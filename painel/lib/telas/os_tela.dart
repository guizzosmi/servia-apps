import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cadastros/lista.dart';
import '../servicos/documentos.dart';
import '../servicos/status.dart';
import '../servicos/whatsapp.dart';
import '../widgets/atendimentos_os.dart';
import '../widgets/campos_data_hora.dart';
import '../widgets/escolha_equipamentos.dart';
import '../widgets/itens_os.dart';
import '../widgets/margem.dart';
import '../widgets/orcamentos_os.dart';
import '../widgets/status_chip.dart';
import 'orcamento_tela.dart' show descreverEventoOrcamento;

/// Detalhe da OS: dados, garantia, equipamentos, agendamentos (com as
/// tentativas de cada um) e histórico. Toda mudança passa por os_acao.
class OsTela extends StatefulWidget {
  const OsTela({super.key, required this.id});

  final String id;

  @override
  State<OsTela> createState() => _OsTelaState();
}

class _OsTelaState extends State<OsTela> {
  SupabaseClient get _db => Supabase.instance.client;

  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;
  Map<String, dynamic>? _os;
  String? _codigoOrigemGarantia;
  List<Map<String, dynamic>> _equipamentos = [];
  List<Map<String, dynamic>> _agendamentos = [];
  List<Map<String, dynamic>> _tentativas = [];
  List<Map<String, dynamic>> _log = [];
  int _versao = 0; // muda a cada recarga (recarrega os atendimentos também)

  bool get _encerrada => ['concluida', 'cancelada'].contains(_os?['status']);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _erro = null);
    try {
      final os = await _db
          .from('ordens_servico')
          .select('*, clientes(nome, telefone), locais(nome, logradouro, numero, bairro, cidade, uf, instrucoes_acesso), '
              'contatos(nome, telefone)')
          .eq('id', widget.id)
          .single();
      String? codigoOrigem;
      if (os['garantia_origem_os_id'] != null) {
        final o = await _db
            .from('ordens_servico')
            .select('codigo')
            .eq('id', os['garantia_origem_os_id'] as String)
            .maybeSingle();
        codigoOrigem = o?['codigo'] as String?;
      }
      final equipamentos = await _db
          .from('os_equipamentos')
          .select('equipamento_id, principal, equipamentos(codigo, descricao, marca, modelo)')
          .eq('os_id', widget.id)
          .isFilter('excluido_em', null);
      final agendamentos = await _db
          .from('agendamentos')
          .select('*, equipes(nome, cor)')
          .eq('os_id', widget.id)
          .isFilter('excluido_em', null)
          .order('criado_em', ascending: true);
      final orcamentos = await _db.from('orcamentos').select('id').eq('os_id', widget.id);
      final ids = [widget.id, ...agendamentos.map((a) => a['id'] as String)];
      final tentativas = agendamentos.isEmpty
          ? <Map<String, dynamic>>[]
          : await _db
              .from('partes_itens')
              .select('id, agendamento_id, data, status, papel_equipe, resultado_motivo, partes_diarias(equipes(nome))')
              .inFilter('agendamento_id', ids.skip(1).toList())
              .isFilter('excluido_em', null)
              .order('data', ascending: true);
      final log = await _db
          .from('eventos_log')
          .select('id, entidade, acao, dados, ator_nome, origem, criado_em')
          .inFilter('entidade_id', [...ids, ...orcamentos.map((o) => o['id'] as String)])
          .order('criado_em', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _os = os;
        _codigoOrigemGarantia = codigoOrigem;
        _equipamentos = equipamentos;
        _agendamentos = agendamentos;
        _tentativas = tentativas;
        _log = log;
        _versao++;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _avisar(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));
  }

  /// Executa uma ação da OS e recarrega.
  Future<void> _acao(Map<String, dynamic> p, String sucesso) async {
    setState(() => _ocupado = true);
    try {
      await acaoOs(p);
      _avisar(sucesso);
      await _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ---------------- diálogos ----------------

  /// Pede um texto (motivo, laudo...). Devolve null se cancelou.
  Future<String?> _pedirTexto(String titulo, String rotulo,
      {String? explicacao, bool obrigatorio = true, String botao = 'Confirmar', bool perigo = false}) async {
    final campo = TextEditingController();
    final chave = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: SizedBox(
          width: 460,
          child: Form(
            key: chave,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (explicacao != null) ...[Text(explicacao), const SizedBox(height: 12)],
              TextFormField(
                controller: campo,
                autofocus: true,
                minLines: 2,
                maxLines: 6,
                decoration: InputDecoration(labelText: rotulo),
                validator: (v) => obrigatorio && (v ?? '').trim().isEmpty ? 'Obrigatório' : null,
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Voltar')),
          FilledButton(
            style: perigo ? FilledButton.styleFrom(backgroundColor: Cores.erro) : null,
            onPressed: () {
              if (chave.currentState!.validate()) Navigator.of(ctx).pop(campo.text.trim());
            },
            child: Text(botao),
          ),
        ],
      ),
    );
  }

  // ---------------- WhatsApp ----------------

  /// Link do relatório (o cliente vê e imprime) mandado pelo WhatsApp.
  Future<void> _mandarRelatorio() async {
    final os = _os!;
    setState(() => _ocupado = true);
    Map<String, dynamic> r;
    try {
      r = await acaoLink({'acao': 'gerar_relatorio', 'os_id': widget.id});
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
      if (mounted) setState(() => _ocupado = false);
      return;
    }
    if (!mounted) return;
    setState(() => _ocupado = false);
    final local = os['locais'] as Map? ?? const {};
    final cliente = os['clientes'] as Map? ?? const {};
    final enviou = await mandarWhatsApp(
      context,
      modelo: 'os_relatorio',
      titulo: 'Relatório da ${os['codigo']}',
      osId: widget.id,
      clienteId: os['cliente_id'] as String,
      contatoInicialId: os['solicitante_contato_id'] as String?,
      valores: {
        'os': '${os['codigo'] ?? ''}',
        'cliente': '${cliente['nome'] ?? ''}',
        'local': '${local['nome'] ?? ''}',
        'link': '${Config.linkAceite}/r/${r['token']}',
      },
      linkId: r['link_id'] as String?,
      aviso: 'O link vale 30 dias e mostra o relatório como estiver quando o cliente abrir.',
    );
    if (!mounted) return;
    if (!enviou) {
      // Ninguém recebeu: o link não precisa ficar valendo.
      try {
        await acaoLink({'acao': 'revogar', 'link_id': r['link_id']});
      } catch (_) {}
    }
    await _carregar();
  }

  /// Data da visita: a da parte (programado) ou a desejada.
  String? _dataDaVisita(Map<String, dynamic> a) {
    final programadas = _tentativas
        .where((t) => t['agendamento_id'] == a['id'] && ['programado', 'em_deslocamento'].contains(t['status']))
        .map((t) => '${t['data']}')
        .toList()
      ..sort();
    if (programadas.isNotEmpty) return programadas.last;
    return a['data_prevista'] as String?;
  }

  Future<void> _avisarVisita(Map<String, dynamic> a) async {
    final os = _os!;
    final data = _dataDaVisita(a);
    if (data == null) return;
    final local = os['locais'] as Map? ?? const {};
    final cliente = os['clientes'] as Map? ?? const {};
    final endereco = [
      [local['logradouro'], local['numero']].where((x) => x != null && '$x'.isNotEmpty).join(', '),
      local['bairro'],
      [local['cidade'], local['uf']].where((x) => x != null && '$x'.isNotEmpty).join('/'),
    ].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
    final enviou = await mandarWhatsApp(
      context,
      modelo: 'visita_agendada',
      titulo: 'Avisar a visita',
      osId: widget.id,
      clienteId: os['cliente_id'] as String,
      contatoInicialId: os['solicitante_contato_id'] as String?,
      valores: {
        'os': '${os['codigo'] ?? ''}',
        'cliente': '${cliente['nome'] ?? ''}',
        'local': '${local['nome'] ?? ''}',
        'endereco': endereco,
        'data': dataPorExtenso(data),
        'horario': janela(a['janela_inicio'], a['janela_fim']),
      },
      entidade: 'agendamento',
      entidadeId: a['id'] as String?,
    );
    if (enviou && mounted) await _carregar();
  }

  Future<void> _editarDados() async {
    final os = _os!;
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoDadosOs(os: os),
    );
    if (r == null) return;
    await _acao({'acao': 'alterar', 'os_id': widget.id, ...r}, 'Dados da OS salvos.');
  }

  Future<void> _editarEquipamentos() async {
    final r = await escolherEquipamentos(
      context,
      clienteId: _os!['cliente_id'] as String,
      localId: _os!['local_id'] as String,
      atuais: _equipamentos.map((e) => e['equipamento_id'] as String).toSet(),
    );
    if (r == null) return;
    await _acao({'acao': 'equipamentos', 'os_id': widget.id, 'equipamentos': r.keys.toList()}, 'Equipamentos atualizados.');
  }

  Future<void> _agendamento([Map<String, dynamic>? atual]) async {
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoAgendamento(atual: atual),
    );
    if (r == null) return;
    if (atual == null) {
      await _acao({'acao': 'agendamento_novo', 'os_id': widget.id, ...r}, 'Agendamento criado: já está na fila.');
    } else {
      await _acao({'acao': 'agendamento_alterar', 'agendamento_id': atual['id'], ...r}, 'Agendamento salvo.');
    }
  }

  Future<void> _suspender(Map<String, dynamic> ag) async {
    String motivo = 'falta_peca';
    final obs = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, redesenhar) => AlertDialog(
          title: const Text('Suspender agendamento'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Sai da fila até você liberar. A OS mostra o motivo.'),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Motivo'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: motivo,
                    isDense: true,
                    isExpanded: true,
                    items: [
                      for (final m in motivosSuspensao.entries) DropdownMenuItem(value: m.key, child: Text(m.value)),
                    ],
                    onChanged: (v) => redesenhar(() => motivo = v ?? motivo),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(controller: obs, decoration: const InputDecoration(labelText: 'Observação (opcional)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Suspender')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _acao({'acao': 'agendamento_suspender', 'agendamento_id': ag['id'], 'motivo': motivo, 'observacao': obs.text.trim()},
        'Agendamento suspenso.');
  }

  Future<void> _liberar(Map<String, dynamic> ag) async {
    String tipo = ag['tipo'] as String? ?? 'visita_tecnica';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, redesenhar) => AlertDialog(
          title: const Text('Liberar para a fila'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('A peça chegou ou o orçamento foi aprovado? O agendamento volta para a fila.'),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Tipo da próxima visita'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: tipo,
                    isDense: true,
                    isExpanded: true,
                    items: [
                      for (final t in tiposAgendamento.entries) DropdownMenuItem(value: t.key, child: Text(t.value)),
                    ],
                    onChanged: (v) => redesenhar(() => tipo = v ?? tipo),
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Liberar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _acao({'acao': 'agendamento_liberar', 'agendamento_id': ag['id'], 'tipo': tipo}, 'Liberado: voltou para a fila.');
  }

  Future<void> _cancelarAgendamento(Map<String, dynamic> ag) async {
    final motivo = await _pedirTexto('Cancelar agendamento', 'Motivo', botao: 'Cancelar agendamento', perigo: true);
    if (motivo == null) return;
    await _acao({'acao': 'agendamento_cancelar', 'agendamento_id': ag['id'], 'motivo': motivo}, 'Agendamento cancelado.');
  }

  Future<void> _concluir() async {
    final laudo = await _pedirTexto('Concluir OS', 'Laudo final (opcional)',
        explicacao: 'Agendamentos que ainda estavam na fila ou suspensos serão cancelados. '
            'A garantia começa a contar hoje.',
        obrigatorio: false,
        botao: 'Concluir');
    if (laudo == null) return;
    await _acao({'acao': 'concluir', 'os_id': widget.id, 'laudo_final': laudo}, 'OS concluída.');
  }

  Future<void> _cancelarOs() async {
    final motivo = await _pedirTexto('Cancelar OS', 'Motivo do cancelamento',
        explicacao: 'Os agendamentos na fila ou suspensos serão cancelados junto.',
        botao: 'Cancelar OS',
        perigo: true);
    if (motivo == null) return;
    await _acao({'acao': 'cancelar', 'os_id': widget.id, 'motivo': motivo}, 'OS cancelada.');
  }

  Future<void> _reabrir() async {
    final motivo = await _pedirTexto('Reabrir OS', 'Motivo da reabertura', botao: 'Reabrir');
    if (motivo == null) return;
    await _acao({'acao': 'reabrir', 'os_id': widget.id, 'motivo': motivo}, 'OS reaberta.');
  }

  // ---------------- tela ----------------

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null || _os == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_erro ?? 'OS não encontrada.', style: const TextStyle(color: Cores.erro)),
          TextButton(onPressed: () => context.go('/os'), child: const Text('Voltar')),
        ]),
      );
    }
    final os = _os!;
    final editar = podeEditarCadastros() && !_ocupado;
    // Ajustes do que veio do campo: até a OS ser faturada (cancelada, nunca).
    final ajustar = podeEditarCadastros() && os['status'] != 'cancelada' && os['cobranca_status'] != 'faturada';
    final cliente = os['clientes'] as Map? ?? const {};
    final local = os['locais'] as Map? ?? const {};
    final contato = os['contatos'] as Map?;
    final endereco = [
      [local['logradouro'], local['numero']].where((x) => x != null && '$x'.isNotEmpty).join(', '),
      local['bairro'],
      [local['cidade'], local['uf']].where((x) => x != null && '$x'.isNotEmpty).join('/'),
    ].where((x) => x != null && '$x'.isNotEmpty).join(' · ');

    return RefreshIndicator(
      onRefresh: _carregar,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: margemDaTela(context),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---------- cabeçalho ----------
                Row(children: [
                  IconButton(
                    onPressed: () => context.canPop() ? context.pop(true) : context.go('/os'),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text((os['codigo'] ?? '') as String,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      StatusChip(os['status'] as String?, statusOs),
                      StatusChip(os['prioridade'] as String?, prioridades),
                    ]),
                  ),
                  if (_ocupado) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  IconButton(tooltip: 'Atualizar', onPressed: _carregar, icon: const Icon(Icons.refresh)),
                ]),
                Padding(
                  padding: const EdgeInsets.only(left: 52, top: 4),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    BotaoPdf(tipo: 'os', id: widget.id, nomeArquivo: '${os['codigo']}', rotulo: 'Relatório (PDF)'),
                    if (editar && os['status'] != 'cancelada')
                      OutlinedButton.icon(
                        onPressed: _mandarRelatorio,
                        icon: const Icon(Icons.chat_outlined, size: 18),
                        label: const Text('Relatório pelo WhatsApp'),
                      ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 52),
                  child: Text(
                    '${tiposOs[os['tipo']] ?? ''} · aberta em ${dataHoraBr(os['abertura_em'])}'
                    '${os['concluida_em'] != null ? ' · concluída em ${dataHoraBr(os['concluida_em'])}' : ''}'
                    '${os['garantia_ate'] != null ? ' · garantia até ${dataBr(os['garantia_ate'])}' : ''}',
                    style: const TextStyle(color: Cores.neutro),
                  ),
                ),
                const SizedBox(height: 16),

                // ---------- garantia ----------
                if (os['garantia_status'] == 'sugerida')
                  _Faixa(
                    cor: Cores.alerta,
                    icone: Icons.verified_user_outlined,
                    texto: 'Possível retorno em garantia da ${_codigoOrigemGarantia ?? 'OS anterior'}. '
                        'Confirmando, esta OS não é cobrada.',
                    acoes: editar
                        ? [
                            TextButton(
                                onPressed: () => _acao({'acao': 'garantia', 'os_id': widget.id, 'decisao': 'descartar'},
                                    'Garantia descartada.'),
                                child: const Text('Não é garantia')),
                            FilledButton(
                                onPressed: () => _acao({'acao': 'garantia', 'os_id': widget.id, 'decisao': 'confirmar'},
                                    'Garantia confirmada.'),
                                child: const Text('Confirmar')),
                          ]
                        : const [],
                  ),
                if (os['garantia_status'] == 'confirmada')
                  _Faixa(
                    cor: Cores.alerta,
                    icone: Icons.verified_user,
                    texto: 'Retorno em garantia da ${_codigoOrigemGarantia ?? 'OS anterior'}: sem cobrança.',
                  ),
                if (os['status'] == 'cancelada')
                  _Faixa(cor: Cores.erro, icone: Icons.block, texto: 'Cancelada: ${os['motivo_cancelamento'] ?? ''}'),

                // ---------- dados ----------
                _Secao(
                  titulo: 'Cliente e serviço',
                  acao: editar && !_encerrada
                      ? TextButton.icon(onPressed: _editarDados, icon: const Icon(Icons.edit_outlined), label: const Text('Editar'))
                      : null,
                  children: [
                    _Info('Cliente', '${cliente['nome'] ?? ''}${cliente['telefone'] != null ? ' · ${cliente['telefone']}' : ''}'),
                    _Info('Local', '${local['nome'] ?? ''}${endereco.isEmpty ? '' : ' · $endereco'}'),
                    if (local['instrucoes_acesso'] != null) _Info('Acesso', '${local['instrucoes_acesso']}'),
                    if (contato != null) _Info('Quem pediu', '${contato['nome']}${contato['telefone'] != null ? ' · ${contato['telefone']}' : ''}'),
                    _Info('Problema relatado', (os['problema_relatado'] ?? '—') as String),
                    if (os['prevista_para'] != null) _Info('Prevista para', dataBr(os['prevista_para'])),
                    if (os['requer_orcamento'] == true) const _Info('Orçamento', 'Precisa de orçamento antes de executar'),
                    if (os['observacao_interna'] != null) _Info('Observação interna', '${os['observacao_interna']}'),
                    if (os['laudo_final'] != null) _Info('Laudo final', '${os['laudo_final']}'),
                  ],
                ),
                const SizedBox(height: 16),

                // ---------- equipamentos ----------
                _Secao(
                  titulo: 'Equipamentos',
                  acao: editar && !_encerrada
                      ? TextButton.icon(
                          onPressed: _editarEquipamentos, icon: const Icon(Icons.edit_outlined), label: const Text('Alterar'))
                      : null,
                  children: [
                    if (_equipamentos.isEmpty)
                      const Text('Nenhum equipamento ligado a esta OS.', style: TextStyle(color: Cores.neutro)),
                    for (final e in _equipamentos)
                      Builder(builder: (_) {
                        final eq = e['equipamentos'] as Map? ?? const {};
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.ac_unit, color: Cores.indigo500),
                          title: Text('${eq['codigo']} · ${eq['descricao'] ?? ''}'),
                          subtitle: Text([eq['marca'], eq['modelo']].where((x) => x != null).join(' · ')),
                          onTap: () => context.push('/c/equipamentos/${e['equipamento_id']}'),
                        );
                      }),
                  ],
                ),
                const SizedBox(height: 16),

                // ---------- agendamentos ----------
                _Secao(
                  titulo: 'Agendamentos',
                  acao: editar && !_encerrada
                      ? TextButton.icon(
                          onPressed: () => _agendamento(), icon: const Icon(Icons.add), label: const Text('Novo agendamento'))
                      : null,
                  children: [
                    if (_agendamentos.isEmpty)
                      const Text('Nenhum agendamento.', style: TextStyle(color: Cores.neutro)),
                    for (final a in _agendamentos) _linhaAgendamento(a, editar && !_encerrada),
                  ],
                ),
                const SizedBox(height: 16),

                // ---------- atendimentos (o que aconteceu no campo) ----------
                _Secao(
                  titulo: 'Atendimentos',
                  children: [
                    AtendimentosDaOs(osId: widget.id, editavel: ajustar, versao: _versao, aoMudar: _carregar),
                  ],
                ),
                const SizedBox(height: 16),

                // ---------- orçamentos ----------
                _Secao(
                  titulo: 'Orçamentos',
                  children: [
                    OrcamentosDaOs(
                      osId: widget.id,
                      podeCriar: editar && !_encerrada && os['cobranca_status'] != 'faturada',
                      versao: _versao,
                      aoMudar: _carregar,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ---------- peças e serviços ----------
                _Secao(
                  titulo: 'Peças e serviços',
                  children: [
                    if (os['cobranca_status'] == 'faturada')
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('OS faturada: os itens não mudam mais.', style: TextStyle(color: Cores.neutro)),
                      ),
                    ItensDaOs(osId: widget.id, editavel: ajustar, versao: _versao, aoMudar: _carregar),
                  ],
                ),
                const SizedBox(height: 16),

                // ---------- ações da OS ----------
                if (editar)
                  Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.end, children: [
                    if (!_encerrada)
                      OutlinedButton.icon(
                        onPressed: _cancelarOs,
                        style: OutlinedButton.styleFrom(foregroundColor: Cores.erro),
                        icon: const Icon(Icons.block),
                        label: const Text('Cancelar OS'),
                      ),
                    if (!_encerrada)
                      FilledButton.icon(
                        onPressed: _concluir,
                        icon: const Icon(Icons.task_alt),
                        label: const Text('Concluir OS'),
                      ),
                    if (os['status'] == 'concluida')
                      OutlinedButton.icon(
                        onPressed: _reabrir,
                        icon: const Icon(Icons.undo),
                        label: const Text('Reabrir'),
                      ),
                  ]),
                const SizedBox(height: 24),

                // ---------- histórico ----------
                _Secao(
                  titulo: 'Histórico',
                  children: [
                    if (_log.isEmpty) const Text('Sem eventos.', style: TextStyle(color: Cores.neutro)),
                    for (final l in _log)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                              width: 130,
                              child: Text(dataHoraBr(l['criado_em']),
                                  style: const TextStyle(color: Cores.neutro, fontSize: 13))),
                          Expanded(
                            child: Text('${descreverEvento(l)} · ${l['ator_nome'] ?? ''}',
                                style: const TextStyle(fontSize: 13)),
                          ),
                        ]),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _linhaAgendamento(Map<String, dynamic> a, bool editar) {
    final status = a['status'] as String?;
    final equipe = a['equipes'] as Map?;
    final tentativas = _tentativas.where((t) => t['agendamento_id'] == a['id']).toList();
    final detalhes = [
      tiposAgendamento[a['tipo']] ?? '',
      if (a['data_prevista'] != null) 'desejado para ${dataBr(a['data_prevista'])}',
      if (janela(a['janela_inicio'], a['janela_fim']).isNotEmpty) janela(a['janela_inicio'], a['janela_fim']),
      if (a['duracao_estimada_min'] != null) '${a['duracao_estimada_min']} min',
      if (equipe != null) 'equipe ${equipe['nome']}',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Cores.linha), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          StatusChip(status, statusAgendamento),
          const SizedBox(width: 8),
          Expanded(child: Text(detalhes)),
          if (podeEditarCadastros() && ['pendente', 'programado', 'em_andamento'].contains(status) && _dataDaVisita(a) != null)
            IconButton(
              tooltip: 'Avisar o cliente da visita (WhatsApp)',
              onPressed: () => _avisarVisita(a),
              icon: const Icon(Icons.chat_outlined, color: Cores.sucesso),
            ),
          if (editar && ['pendente', 'suspenso', 'programado'].contains(status))
            PopupMenuButton<String>(
              tooltip: 'Ações',
              onSelected: (op) {
                switch (op) {
                  case 'editar':
                    _agendamento(a);
                  case 'suspender':
                    _suspender(a);
                  case 'liberar':
                    _liberar(a);
                  case 'cancelar':
                    _cancelarAgendamento(a);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'editar', child: Text('Editar')),
                if (status == 'pendente') const PopupMenuItem(value: 'suspender', child: Text('Suspender')),
                if (status == 'suspenso') const PopupMenuItem(value: 'liberar', child: Text('Liberar para a fila')),
                if (status != 'programado') const PopupMenuItem(value: 'cancelar', child: Text('Cancelar')),
              ],
            ),
        ]),
        if (a['orientacoes'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Orientações: ${a['orientacoes']}', style: const TextStyle(fontSize: 13)),
          ),
        if (status == 'suspenso')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Suspenso: ${motivosSuspensao[a['motivo_suspensao']] ?? ''}'
                '${a['ultimo_motivo'] != null && a['ultimo_motivo'] != a['motivo_suspensao'] ? ' · ${a['ultimo_motivo']}' : ''}',
                style: const TextStyle(color: Cores.alerta, fontSize: 13)),
          ),
        for (final t in tentativas)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              const Icon(Icons.subdirectory_arrow_right, size: 16, color: Cores.neutro),
              const SizedBox(width: 4),
              Flexible(
                child: Text('${dataBr(t['data'])} · ${((t['partes_diarias'] as Map?)?['equipes'] as Map?)?['nome'] ?? ''}'
                    '${t['papel_equipe'] == 'apoio' ? ' (apoio)' : ''} · ',
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              ),
              StatusChip(t['status'] as String?, statusItem, compacto: true),
              if (t['resultado_motivo'] != null)
                Text('  ${motivosNaoRealizado[t['resultado_motivo']] ?? t['resultado_motivo']}',
                    style: const TextStyle(fontSize: 13, color: Cores.neutro)),
            ]),
          ),
      ]),
    );
  }
}

/// Frase curta para cada evento do log.
String descreverEvento(Map<String, dynamic> l) {
  final acao = l['acao'] as String? ?? '';
  final dados = (l['dados'] as Map?) ?? const {};
  final entidade = l['entidade'] as String? ?? '';
  if (entidade == 'orcamento') return '${dados['codigo'] ?? 'Orçamento'} · ${descreverEventoOrcamento(l)}';
  const nomes = {
    'os:abrir': 'OS aberta',
    'os:alterar': 'Dados da OS alterados',
    'os:equipamentos': 'Equipamentos alterados',
    'os:garantia_confirmar': 'Garantia confirmada',
    'os:garantia_descartar': 'Garantia descartada',
    'os:concluir': 'OS concluída',
    'os:cancelar': 'OS cancelada',
    'os:reabrir': 'OS reaberta',
    'agendamento:criar': 'Novo agendamento',
    'agendamento:alterar': 'Agendamento alterado',
    'agendamento:suspender': 'Agendamento suspenso',
    'agendamento:liberar': 'Agendamento liberado para a fila',
    'agendamento:cancelar': 'Agendamento cancelado',
    'parte_item:programar': 'Programado na parte',
    'parte_item:encaixar': 'Encaixado na parte',
    'parte_item:remover': 'Retirado da parte',
    'parte_item:mover': 'Trocado de equipe',
    'parte_item:designar': 'Pessoas designadas',
    'parte_item:status': 'Andamento do serviço',
    'os:equipamento_incluido_no_local': 'Equipamento incluído no local',
    'os:item_incluido': 'Item incluído',
    'os:item_alterado': 'Item alterado',
    'os:item_excluido': 'Item excluído',
    'os:atendimento_alterado': 'Relato do atendimento corrigido',
    'os:horas_corrigidas': 'Horas corrigidas',
    'os:horas_incluidas': 'Horas incluídas',
    'os:horas_excluidas': 'Horas excluídas',
    'os:medicao_alterada': 'Medição corrigida',
    'os:fluido_alterado': 'Fluido corrigido',
    'os:foto_excluida': 'Foto excluída',
    'os:link_relatorio': 'Link do relatório gerado',
    'os:link_relatorio_revogado': 'Link do relatório cancelado',
  };
  if (entidade == 'os' && acao == 'mensagem') {
    final titulo = modeloMensagem('${dados['modelo']}')?.titulo ?? '${dados['modelo']}';
    return 'Mensagem "$titulo" ${dados['meio'] == 'copiada' ? 'copiada' : 'pelo WhatsApp'} para ${dados['para'] ?? ''}';
  }
  var texto = nomes['$entidade:$acao'] ?? '$entidade: $acao';
  if (dados['descricao'] != null) texto += ': ${dados['descricao']}';
  if (dados['medicao'] != null) texto += ': ${dados['medicao']}';
  if (dados['motivo'] != null && '${dados['motivo']}'.isNotEmpty) {
    texto += ' (${motivosNaoRealizado[dados['motivo']] ?? motivosSuspensao[dados['motivo']] ?? dados['motivo']})';
  }
  if (acao == 'status' && dados['para'] != null) {
    texto += ': ${statusItem[dados['para']]?.texto ?? dados['para']}';
  }
  return texto;
}

// ---------------- peças de tela ----------------

class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.children, this.acao});

  final String titulo;
  final List<Widget> children;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(titulo,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (acao != null) acao!,
          ]),
          const SizedBox(height: 8),
          ...children,
        ]),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.rotulo, this.valor);

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 150, child: Text(rotulo, style: const TextStyle(color: Cores.neutro))),
        Expanded(child: SelectableText(valor)),
      ]),
    );
  }
}

class _Faixa extends StatelessWidget {
  const _Faixa({required this.cor, required this.icone, required this.texto, this.acoes = const []});

  final Color cor;
  final IconData icone;
  final String texto;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.1),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(icone, color: cor),
        const SizedBox(width: 12),
        Expanded(child: Text(texto)),
        ...acoes.expand((a) => [const SizedBox(width: 8), a]),
      ]),
    );
  }
}

// ---------------- diálogos ----------------

class _DialogoDadosOs extends StatefulWidget {
  const _DialogoDadosOs({required this.os});

  final Map<String, dynamic> os;

  @override
  State<_DialogoDadosOs> createState() => _DialogoDadosOsState();
}

class _DialogoDadosOsState extends State<_DialogoDadosOs> {
  late final _problema = TextEditingController(text: (widget.os['problema_relatado'] ?? '') as String);
  late final _obs = TextEditingController(text: (widget.os['observacao_interna'] ?? '') as String);
  late String _prioridade = (widget.os['prioridade'] ?? 'media') as String;
  late bool _requerOrcamento = widget.os['requer_orcamento'] == true;
  late DateTime? _prevista = DateTime.tryParse('${widget.os['prevista_para'] ?? ''}');

  @override
  void dispose() {
    _problema.dispose();
    _obs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dados da OS'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Prioridade'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _prioridade,
                  isDense: true,
                  isExpanded: true,
                  items: [
                    for (final p in prioridades.entries) DropdownMenuItem(value: p.key, child: Text(p.value.texto)),
                  ],
                  onChanged: (v) => setState(() => _prioridade = v ?? _prioridade),
                ),
              ),
            ),
            const SizedBox(height: 12),
            CampoData(rotulo: 'Prevista para', valor: _prevista, aoMudar: (d) => setState(() => _prevista = d)),
            const SizedBox(height: 12),
            TextField(
              controller: _problema,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Problema relatado'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _obs,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Observação interna'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _requerOrcamento,
              onChanged: (v) => setState(() => _requerOrcamento = v),
              title: const Text('Precisa de orçamento antes de executar'),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'prioridade': _prioridade,
            'prevista_para': _prevista == null ? '' : dataIso(_prevista!),
            'problema_relatado': _problema.text.trim(),
            'observacao_interna': _obs.text.trim(),
            'requer_orcamento': _requerOrcamento,
          }),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _DialogoAgendamento extends StatefulWidget {
  const _DialogoAgendamento({this.atual});

  final Map<String, dynamic>? atual;

  @override
  State<_DialogoAgendamento> createState() => _DialogoAgendamentoState();
}

class _DialogoAgendamentoState extends State<_DialogoAgendamento> {
  late String _tipo = (widget.atual?['tipo'] ?? 'visita_tecnica') as String;
  late String _prioridade = (widget.atual?['prioridade'] ?? 'media') as String;
  late DateTime? _data = DateTime.tryParse('${widget.atual?['data_prevista'] ?? ''}');
  late TimeOfDay? _inicio = horaDoBanco(widget.atual?['janela_inicio']);
  late TimeOfDay? _fim = horaDoBanco(widget.atual?['janela_fim']);
  late final _duracao = TextEditingController(text: '${widget.atual?['duracao_estimada_min'] ?? ''}');
  late final _orientacoes = TextEditingController(text: (widget.atual?['orientacoes'] ?? '') as String);

  @override
  void dispose() {
    _duracao.dispose();
    _orientacoes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.atual == null ? 'Novo agendamento' : 'Editar agendamento'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _tipo,
                      isDense: true,
                      isExpanded: true,
                      items: [
                        for (final t in tiposAgendamento.entries) DropdownMenuItem(value: t.key, child: Text(t.value)),
                      ],
                      onChanged: (v) => setState(() => _tipo = v ?? _tipo),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Prioridade'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _prioridade,
                      isDense: true,
                      isExpanded: true,
                      items: [
                        for (final p in prioridades.entries) DropdownMenuItem(value: p.key, child: Text(p.value.texto)),
                      ],
                      onChanged: (v) => setState(() => _prioridade = v ?? _prioridade),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            CampoData(rotulo: 'Data desejada', valor: _data, aoMudar: (d) => setState(() => _data = d)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: CampoHora(rotulo: 'Janela: das', valor: _inicio, aoMudar: (t) => setState(() => _inicio = t))),
              const SizedBox(width: 12),
              Expanded(child: CampoHora(rotulo: 'até', valor: _fim, aoMudar: (t) => setState(() => _fim = t))),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _duracao,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Duração (min)'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _orientacoes,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Orientações para a equipe'),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'tipo': _tipo,
            'prioridade': _prioridade,
            'data_prevista': _data == null ? '' : dataIso(_data!),
            'janela_inicio': horaParaBanco(_inicio) ?? '',
            'janela_fim': horaParaBanco(_fim) ?? '',
            'duracao_estimada_min': int.tryParse(_duracao.text.trim())?.toString() ?? '',
            'orientacoes': _orientacoes.text.trim(),
          }),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
