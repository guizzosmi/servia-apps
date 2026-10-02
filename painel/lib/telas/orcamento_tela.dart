import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cadastros/lista.dart';
import '../servicos/documentos.dart';
import '../servicos/status.dart';
import '../widgets/assinatura_cliente.dart';
import '../widgets/campos_data_hora.dart';
import '../widgets/itens_os.dart';
import '../widgets/status_chip.dart';

/// Um orçamento: dados, itens, respostas do cliente, versões e histórico.
/// Rascunho é editável; depois de enviado, só com nova versão.
/// Toda mudança passa por orcamento_acao.
class OrcamentoTela extends StatefulWidget {
  const OrcamentoTela({super.key, required this.id});

  final String id;

  @override
  State<OrcamentoTela> createState() => _OrcamentoTelaState();
}

class _OrcamentoTelaState extends State<OrcamentoTela> {
  SupabaseClient get _db => Supabase.instance.client;

  /// Orçamento mostrado. Trocar de versão troca aqui, na mesma tela (assim
  /// quem abriu esta tela recarrega quando o usuário voltar).
  late String _id = widget.id;

  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;
  Map<String, dynamic>? _orc;
  List<Map<String, dynamic>> _itens = [];
  List<Map<String, dynamic>> _versoes = [];
  List<Map<String, dynamic>> _aceites = [];
  List<Map<String, dynamic>> _contatos = [];
  List<Map<String, dynamic>> _equipamentos = [];
  List<Map<String, dynamic>> _log = [];
  List<Map<String, dynamic>> _links = [];

  // Dados do rascunho (editados na tela e salvos de uma vez).
  final _diagnostico = TextEditingController();
  final _prazo = TextEditingController();
  final _condicoes = TextEditingController();
  final _observacoes = TextEditingController();
  DateTime? _validade;
  String? _contatoId;
  bool _alterado = false;

  bool get _rascunho => _orc?['status'] == 'rascunho';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _diagnostico.dispose();
    _prazo.dispose();
    _condicoes.dispose();
    _observacoes.dispose();
    super.dispose();
  }

  Future<void> _carregar({bool manterEdicao = false}) async {
    setState(() => _erro = null);
    final id = _id; // trocou de versão no meio: a resposta antiga não vale
    try {
      final orc = await _db
          .from('orcamentos')
          .select('*, contatos(nome, telefone, email), '
              'ordens_servico(id, codigo, status, cliente_id, local_id, clientes(nome), locais(nome))')
          .eq('id', _id)
          .single();
      final os = orc['ordens_servico'] as Map<String, dynamic>;
      final r = await Future.wait<List<Map<String, dynamic>>>([
        _db
            .from('orcamento_itens')
            .select('*, equipamentos(codigo)')
            .eq('orcamento_id', _id)
            .isFilter('excluido_em', null)
            .order('ordem')
            .order('criado_em'),
        _db
            .from('orcamentos')
            .select('id, versao_orcamento, status, total, validade_ate, criado_em')
            .eq('numero', orc['numero'] as int)
            .order('versao_orcamento'),
        _db
            .from('aceites')
            .select('*')
            .eq('entidade', 'orcamento')
            .eq('entidade_id', _id)
            .order('criado_em'),
        _db
            .from('contatos')
            .select('id, nome, telefone, funcoes')
            .eq('cliente_id', os['cliente_id'] as String)
            .eq('ativo', true)
            .isFilter('excluido_em', null)
            .order('nome'),
        _db
            .from('os_equipamentos')
            .select('equipamento_id, equipamentos(codigo, descricao)')
            .eq('os_id', os['id'] as String)
            .isFilter('excluido_em', null),
        _db
            .from('eventos_log')
            .select('id, entidade, acao, dados, ator_nome, criado_em')
            .eq('entidade_id', _id)
            .order('criado_em', ascending: false)
            .limit(50),
        _db
            .from('links_publicos')
            .select('id, destino, expira_em, usado_em, revogado_em, acessos, ultimo_acesso_em, criado_em, contatos(nome)')
            .eq('entidade', 'orcamento')
            .eq('entidade_id', _id)
            .order('criado_em', ascending: false),
      ]);
      if (!mounted || id != _id) return;
      setState(() {
        _orc = orc;
        _itens = r[0];
        _versoes = r[1];
        _aceites = r[2];
        _contatos = r[3];
        _equipamentos = r[4];
        _log = r[5];
        _links = r[6];
        if (!manterEdicao || !_alterado) _preencherDados(orc);
      });
    } catch (e) {
      if (mounted && id == _id) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted && id == _id) setState(() => _carregando = false);
    }
  }

  void _preencherDados(Map<String, dynamic> o) {
    _diagnostico.text = '${o['diagnostico'] ?? ''}';
    _prazo.text = '${o['prazo_execucao_dias'] ?? ''}';
    _condicoes.text = '${o['condicoes_pagamento'] ?? ''}';
    _observacoes.text = '${o['observacoes'] ?? ''}';
    _validade = DateTime.tryParse('${o['validade_ate'] ?? ''}');
    _contatoId = o['contato_id'] as String?;
    // Contato que saiu do cadastro: fica sem (é o que a tela mostra).
    if (!_contatos.any((c) => c['id'] == _contatoId)) _contatoId = null;
    _alterado = false;
  }

  /// Voltar: o que foi digitado e não salvo é salvo antes de sair.
  Future<void> _voltar() async {
    if (_alterado && !await _salvarDados(avisar: false)) return;
    if (!mounted) return;
    if (context.canPop()) {
      context.pop(true);
    } else {
      context.go('/orcamentos');
    }
  }

  void _trocarPara(String id) {
    setState(() {
      _id = id;
      _carregando = true;
      _alterado = false;
    });
    _carregar();
  }

  void _avisar(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));
  }

  /// Executa uma ação do orçamento e recarrega. Devolve a resposta (ou null).
  Future<Map<String, dynamic>?> _acao(Map<String, dynamic> p, String sucesso, {bool manterEdicao = false}) async {
    if (!mounted) return null;
    setState(() => _ocupado = true);
    try {
      final r = await acaoOrcamento({'orcamento_id': _id, ...p});
      _avisar(sucesso);
      await _carregar(manterEdicao: manterEdicao);
      return r;
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
      return null;
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ---------------- ações ----------------

  Future<bool> _salvarDados({bool avisar = true}) async {
    final prazo = _prazo.text.trim();
    if (prazo.isNotEmpty && (int.tryParse(prazo) ?? 0) <= 0) {
      _avisar('Prazo de execução: um número de dias maior que zero.', erro: true);
      return false;
    }
    final r = await _acao({
      'acao': 'salvar',
      'contato_id': _contatoId ?? '',
      'validade_ate': _validade == null ? '' : dataIso(_validade!),
      'prazo_execucao_dias': prazo,
      'condicoes_pagamento': _condicoes.text.trim(),
      'observacoes': _observacoes.text.trim(),
      'diagnostico': _diagnostico.text.trim(),
    }, avisar ? 'Dados salvos.' : 'Salvo.', manterEdicao: true);
    if (r == null) return false;
    setState(() => _alterado = false);
    return true;
  }

  Future<void> _editarItem([Map<String, dynamic>? item]) async {
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => DialogoItem(item: item, equipamentos: _equipamentos, tipos: tiposItemOrcamento),
    );
    if (r == null) return;
    await _acao({'acao': 'item_salvar', if (item != null) 'item_id': item['id'], ...r},
        item == null ? 'Item incluído.' : 'Item salvo.',
        manterEdicao: true);
  }

  Future<void> _excluirItem(Map<String, dynamic> item) async {
    final ok = await _confirmar('Excluir item', '${item['descricao']} · ${dinheiro(item['total'])}',
        botao: 'Excluir', perigo: true);
    if (ok != true) return;
    await _acao({'acao': 'item_excluir', 'item_id': item['id']}, 'Item excluído.', manterEdicao: true);
  }

  Future<void> _enviar() async {
    if (_alterado && !await _salvarDados(avisar: false)) return;
    if (!mounted) return;
    final ok = await _confirmar(
      'Marcar como enviado',
      'O orçamento fica congelado: para mudar depois, só com uma nova versão.\n\n'
          'Enquanto o cliente não responde, o serviço sai da fila (fica suspenso, aguardando orçamento) '
          'e a OS fica "Aguardando aprovação".\n\n'
          'O PDF fica pronto no botão PDF (no alto): baixe e mande ao cliente pelo seu canal de sempre. '
          'O link para ele aprovar sozinho chega no próximo passo.',
      botao: 'Marcar como enviado',
    );
    if (ok != true) return;
    final r = await _acao({'acao': 'enviar'}, 'Orçamento enviado: o PDF está pronto no botão PDF.');
    if (r != null) _congelarPdf();
  }

  /// Saiu do rascunho: o PDF definitivo é gerado e guardado já (nunca mais muda).
  void _congelarPdf() {
    unawaited(pdfDoServidor('orcamento', _id).then((_) {}, onError: (Object e) => debugPrint('PDF do orçamento: $e')));
  }

  Future<void> _aprovar() async {
    if (_alterado && !await _salvarDados(avisar: false)) return;
    if (!mounted) return;
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoResposta(
        aprovar: true,
        contatos: _contatos,
        contatoId: _orc!['contato_id'] as String?,
        total: _orc!['total'],
      ),
    );
    if (r == null) return;
    final resp = await _acao({'acao': 'aprovar', ...r}, 'Aprovação registrada: itens na OS e serviço na fila.');
    if (resp != null) _congelarPdf();
    if (resp != null && resp['agendamento_criado'] != null) {
      _avisar('Aprovação registrada. A OS não tinha agendamento: um novo (reparo) foi para a fila.');
    }
  }

  Future<void> _reprovar() async {
    if (_alterado && !await _salvarDados(avisar: false)) return;
    if (!mounted) return;
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoResposta(
        aprovar: false,
        contatos: _contatos,
        contatoId: _orc!['contato_id'] as String?,
        total: _orc!['total'],
      ),
    );
    if (r == null) return;
    final resp = await _acao({'acao': 'reprovar', ...r},
        'Reprovação registrada. Na OS: conclua só com o diagnóstico ou cancele.');
    if (resp != null) _congelarPdf();
  }

  Future<void> _novaVersao() async {
    final ok = await _confirmar(
      'Nova versão',
      'Cria a versão ${(_versoes.isEmpty ? 1 : _versoes.last['versao_orcamento'] as int) + 1} em rascunho, '
          'com os mesmos dados e itens, para você corrigir.'
          '${_orc!['status'] == 'reprovado' ? '' : '\n\nEsta versão deixa de valer: o cliente não pode mais aprová-la.'}',
      botao: 'Criar nova versão',
    );
    if (ok != true) return;
    final r = await _acao({'acao': 'nova_versao'}, 'Nova versão criada.');
    if (r != null && mounted) _trocarPara(r['orcamento_id'] as String);
  }

  Future<void> _cancelar() async {
    final motivo = await _pedirTexto('Cancelar orçamento', 'Motivo',
        explicacao: 'Use quando a empresa desistiu do orçamento (ex.: o cliente resolveu por outro caminho). '
            'Se o serviço estiver suspenso esperando o orçamento, ele continua assim: libere ou cancele na OS.');
    if (motivo == null) return;
    await _acao({'acao': 'cancelar', 'motivo': motivo}, 'Orçamento cancelado.');
  }

  Future<bool?> _confirmar(String titulo, String texto, {String botao = 'Confirmar', bool perigo = false}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: SizedBox(width: 460, child: Text(texto)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(
            style: perigo ? FilledButton.styleFrom(backgroundColor: Cores.erro) : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(botao),
          ),
        ],
      ),
    );
  }

  Future<String?> _pedirTexto(String titulo, String rotulo, {String? explicacao}) async {
    final campo = TextEditingController();
    final chave = GlobalKey<FormState>();
    final r = await showDialog<String>(
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
                maxLines: 5,
                decoration: InputDecoration(labelText: rotulo),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Obrigatório' : null,
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Cores.erro),
            onPressed: () {
              if (chave.currentState!.validate()) Navigator.of(ctx).pop(campo.text.trim());
            },
            child: const Text('Cancelar orçamento'),
          ),
        ],
      ),
    );
    // O diálogo ainda anima a saída usando o campo: libera depois.
    Future.delayed(const Duration(seconds: 1), campo.dispose);
    return r;
  }

  // ---------------- tela ----------------

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null || _orc == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_erro ?? 'Orçamento não encontrado.', style: const TextStyle(color: Cores.erro)),
          TextButton(onPressed: () => context.go('/orcamentos'), child: const Text('Voltar')),
        ]),
      );
    }
    final o = _orc!;
    final os = o['ordens_servico'] as Map? ?? const {};
    final status = o['status'] as String?;
    final visivel = statusOrcamentoVisivel(o);
    final gestor = podeEditarCadastros() && !_ocupado;
    final editar = gestor && _rascunho;
    final semVersaoNova = o['substituido_por_id'] == null;
    final aceite = _aceites.isEmpty ? null : _aceites.last;

    return RefreshIndicator(
      onRefresh: _carregar,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // ---------- cabeçalho ----------
              Row(children: [
                IconButton(
                  onPressed: _voltar,
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 4),
                Text('${o['codigo']} v${o['versao_orcamento']}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(width: 12),
                StatusChip(visivel, statusOrcamento),
                const Spacer(),
                if (_ocupado) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                BotaoPdf(
                  key: ValueKey('pdf-$_id-$status'),
                  tipo: 'orcamento',
                  id: _id,
                  nomeArquivo: '${o['codigo']}-v${o['versao_orcamento']}',
                  rotulo: status == 'rascunho' ? 'Prévia do PDF' : 'PDF',
                ),
                const SizedBox(width: 8),
                IconButton(tooltip: 'Atualizar', onPressed: _carregar, icon: const Icon(Icons.refresh)),
              ]),
              Padding(
                padding: const EdgeInsets.only(left: 52),
                child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    onPressed: () => context.push('/os/${os['id']}'),
                    child: Text('${os['codigo'] ?? ''}'),
                  ),
                  Text(' · ${(os['clientes'] as Map?)?['nome'] ?? ''} · ${(os['locais'] as Map?)?['nome'] ?? ''}'
                      ' · criado em ${dataHoraBr(o['criado_em'])}'
                      '${o['enviado_em'] != null ? ' · enviado em ${dataHoraBr(o['enviado_em'])}' : ''}',
                      style: const TextStyle(color: Cores.neutro)),
                ]),
              ),
              const SizedBox(height: 16),

              // ---------- faixas ----------
              if (status == 'substituido' || (status == 'reprovado' && !semVersaoNova))
                _Faixa(
                  cor: Cores.neutro,
                  icone: Icons.history,
                  texto: 'Existe uma versão mais nova deste orçamento.',
                  acoes: [
                    FilledButton(
                      onPressed: () => _trocarPara(o['substituido_por_id'] as String),
                      child: const Text('Abrir a versão nova'),
                    ),
                  ],
                ),
              if (visivel == 'vencido' || status == 'expirado')
                _Faixa(
                  cor: Cores.alerta,
                  icone: Icons.event_busy,
                  texto: 'Venceu em ${dataBr(o['validade_ate'])}. Para o cliente aprovar, crie uma nova versão '
                      '(com validade nova).',
                ),
              if (status == 'aprovado')
                _Faixa(
                  cor: Cores.sucesso,
                  icone: Icons.task_alt,
                  texto: 'Aprovado em ${dataHoraBr(o['aprovado_em'])}'
                      '${aceite?['nome'] != null ? ' por ${aceite!['nome']}' : ''}'
                      ' (${(formasAceite[o['aprovacao_forma']] ?? '').toLowerCase()}). '
                      'Os itens estão na OS e o serviço está na fila.',
                ),
              if (status == 'reprovado')
                _Faixa(
                  cor: Cores.erro,
                  icone: Icons.cancel_outlined,
                  texto: 'Reprovado em ${dataHoraBr(o['reprovado_em'])}'
                      '${o['motivo_reprovacao'] != null ? ': ${o['motivo_reprovacao']}' : ''}. '
                      'Na OS: conclua só com o diagnóstico, cancele, ou faça uma nova versão.',
                ),
              if (status == 'cancelado')
                _Faixa(cor: Cores.neutro, icone: Icons.block, texto: 'Cancelado: ${o['motivo_cancelamento'] ?? ''}'),
              if (status == 'rascunho')
                const _Faixa(
                  cor: Cores.neutro,
                  icone: Icons.edit_note,
                  texto: 'Rascunho: o cliente ainda não viu. Os itens são gravados na hora; os dados, no botão Salvar. '
                      'Quando estiver pronto, use Marcar como enviado (ou registre a resposta, se o cliente já decidiu).',
                ),
              if (status == 'enviado' && visivel != 'vencido')
                const _Faixa(
                  cor: Cores.info,
                  icone: Icons.hourglass_top,
                  texto: 'Aguardando o cliente. Quando ele responder, registre a aprovação ou a reprovação.',
                ),

              // ---------- dados ----------
              _Secao(
                titulo: 'Dados do orçamento',
                acao: editar
                    ? (_alterado
                        ? FilledButton.icon(
                            onPressed: () => _salvarDados(),
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Salvar'))
                        : const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.cloud_done_outlined, size: 18, color: Cores.sucesso),
                            SizedBox(width: 6),
                            Text('Tudo salvo', style: TextStyle(color: Cores.sucesso, fontWeight: FontWeight.w600)),
                          ]))
                    : null,
                children: editar ? [_formDados()] : _dadosLeitura(o),
              ),
              const SizedBox(height: 16),

              // ---------- itens ----------
              _Secao(
                titulo: 'Itens',
                children: [
                  _tabelaItens(editar),
                  const SizedBox(height: 8),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (editar)
                      TextButton.icon(
                        onPressed: () => _editarItem(),
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar item'),
                      ),
                    const Spacer(),
                    _totais(o),
                  ]),
                ],
              ),
              const SizedBox(height: 16),

              // ---------- ações ----------
              if (gestor)
                Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.end, children: [
                  if (['rascunho', 'enviado', 'expirado'].contains(status))
                    OutlinedButton.icon(
                      onPressed: _cancelar,
                      style: OutlinedButton.styleFrom(foregroundColor: Cores.erro),
                      icon: const Icon(Icons.block),
                      label: const Text('Cancelar orçamento'),
                    ),
                  if (['enviado', 'expirado', 'reprovado'].contains(status) && semVersaoNova)
                    OutlinedButton.icon(
                      onPressed: _novaVersao,
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Nova versão'),
                    ),
                  if (['rascunho', 'enviado'].contains(status))
                    OutlinedButton.icon(
                      onPressed: _reprovar,
                      icon: const Icon(Icons.thumb_down_alt_outlined),
                      label: const Text('Registrar reprovação'),
                    ),
                  if (status == 'rascunho' || (status == 'enviado' && visivel != 'vencido'))
                    OutlinedButton.icon(
                      onPressed: _itens.isEmpty ? null : _aprovar,
                      icon: const Icon(Icons.thumb_up_alt_outlined),
                      label: const Text('Registrar aprovação'),
                    ),
                  if (status == 'rascunho')
                    FilledButton.icon(
                      onPressed: _itens.isEmpty ? null : _enviar,
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Marcar como enviado'),
                    ),
                ]),
              const SizedBox(height: 24),

              // ---------- link para o cliente ----------
              if (status != 'rascunho' || _links.isNotEmpty) ...[
                _Secao(
                  titulo: 'Link para o cliente aprovar',
                  acao: gestor && status == 'enviado' && visivel != 'vencido'
                      ? FilledButton.icon(
                          onPressed: _gerarLink,
                          icon: const Icon(Icons.link),
                          label: Text(_links.any(_linkAtivo) ? 'Gerar novo link' : 'Gerar link'),
                        )
                      : null,
                  children: [
                    if (_links.isEmpty)
                      Text(
                        status == 'enviado'
                            ? 'O cliente abre o link no celular, vê o orçamento e aprova ou recusa sozinho.'
                            : 'Nenhum link foi gerado.',
                        style: const TextStyle(color: Cores.neutro),
                      ),
                    for (final l in _links) _linhaLink(l, gestor),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // ---------- respostas do cliente ----------
              if (_aceites.isNotEmpty) ...[
                _Secao(titulo: 'Resposta do cliente', children: [for (final a in _aceites) _linhaAceite(a)]),
                const SizedBox(height: 16),
              ],

              // ---------- versões ----------
              if (_versoes.length > 1) ...[
                _Secao(titulo: 'Versões', children: [
                  for (final v in _versoes)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      selected: v['id'] == _id,
                      leading: Text('v${v['versao_orcamento']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      title: Text('${dinheiro(v['total'])} · criada em ${dataBr(v['criado_em'])}'),
                      trailing: StatusChip(statusOrcamentoVisivel(v), statusOrcamento, compacto: true),
                      onTap: v['id'] == _id ? null : () => _trocarPara(v['id'] as String),
                    ),
                ]),
                const SizedBox(height: 16),
              ],

              // ---------- histórico ----------
              _Secao(titulo: 'Histórico', children: [
                if (_log.isEmpty) const Text('Sem eventos.', style: TextStyle(color: Cores.neutro)),
                for (final l in _log)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                          width: 130,
                          child: Text(dataHoraBr(l['criado_em']), style: const TextStyle(color: Cores.neutro, fontSize: 13))),
                      Expanded(
                        child: Text('${descreverEventoOrcamento(l)} · ${l['ator_nome'] ?? ''}',
                            style: const TextStyle(fontSize: 13)),
                      ),
                    ]),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _formDados() {
    void mudou() {
      if (!_alterado) setState(() => _alterado = true);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          flex: 3,
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Quem aprova (contato do cliente)'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _contatoId,
                isDense: true,
                isExpanded: true,
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Ninguém escolhido')),
                  for (final c in _contatos)
                    DropdownMenuItem<String?>(
                      value: c['id'] as String,
                      child: Text([
                        c['nome'],
                        if ((c['funcoes'] as List?)?.contains('aprovador') ?? false) 'aprovador',
                        c['telefone'],
                      ].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _contatoId = v;
                  _alterado = true;
                }),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: CampoData(
            rotulo: 'Válido até',
            valor: _validade,
            aoMudar: (d) => setState(() {
              _validade = d;
              _alterado = true;
            }),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _prazo,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Prazo de execução (dias)'),
            onChanged: (_) => mudou(),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _diagnostico,
        minLines: 2,
        maxLines: 8,
        decoration: const InputDecoration(labelText: 'Diagnóstico (o que foi encontrado)'),
        onChanged: (_) => mudou(),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _condicoes,
        minLines: 1,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Condições de pagamento', hintText: 'Ex.: 50% na aprovação e 50% na conclusão'),
        onChanged: (_) => mudou(),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _observacoes,
        minLines: 1,
        maxLines: 4,
        decoration: const InputDecoration(labelText: 'Observações para o cliente'),
        onChanged: (_) => mudou(),
      ),
    ]);
  }

  List<Widget> _dadosLeitura(Map<String, dynamic> o) {
    final contato = o['contatos'] as Map?;
    return [
      _Info('Quem aprova',
          contato == null ? '—' : [contato['nome'], contato['telefone']].where((x) => x != null).join(' · ')),
      _Info('Válido até', o['validade_ate'] == null ? '—' : dataBr(o['validade_ate'])),
      if (o['prazo_execucao_dias'] != null) _Info('Prazo de execução', '${o['prazo_execucao_dias']} dia(s)'),
      _Info('Diagnóstico', '${o['diagnostico'] ?? '—'}'),
      if (o['condicoes_pagamento'] != null) _Info('Condições de pagamento', '${o['condicoes_pagamento']}'),
      if (o['observacoes'] != null) _Info('Observações', '${o['observacoes']}'),
    ];
  }

  Widget _tabelaItens(bool editar) {
    if (_itens.isEmpty) {
      return Text(editar ? 'Nenhum item ainda. Adicione peças, serviços, mão de obra e deslocamento.' : 'Sem itens.',
          style: const TextStyle(color: Cores.neutro));
    }
    const cabecalho = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Cores.neutro);
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(4.5),
        1: FlexColumnWidth(1.3),
        2: FlexColumnWidth(1.6),
        3: FlexColumnWidth(1.4),
        4: FlexColumnWidth(1.6),
        5: FixedColumnWidth(100),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        const TableRow(children: [
          Text('DESCRIÇÃO', style: cabecalho),
          Text('QTD.', style: cabecalho),
          Text('PREÇO', style: cabecalho),
          Text('DESC.', style: cabecalho),
          Text('TOTAL', style: cabecalho),
          SizedBox(),
        ]),
        for (final i in _itens)
          TableRow(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Cores.linha))),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i['descricao']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    [
                      tiposItemOrcamento[i['tipo']] ?? '',
                      if (i['produto_id'] == null) 'sem cadastro',
                      if ((i['equipamentos'] as Map?)?['codigo'] != null) 'equip. ${(i['equipamentos'] as Map)['codigo']}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: Cores.neutro),
                  ),
                ]),
              ),
              Text('${numeroBr(i['quantidade'])} ${i['unidade'] ?? ''}'),
              Text(
                (num.tryParse('${i['preco_unitario']}') ?? 0) == 0 ? 'sem preço' : dinheiro(i['preco_unitario']),
                style: TextStyle(
                    color: (num.tryParse('${i['preco_unitario']}') ?? 0) == 0 ? Cores.alerta : null,
                    fontWeight: (num.tryParse('${i['preco_unitario']}') ?? 0) == 0 ? FontWeight.w700 : null),
              ),
              Text((num.tryParse('${i['desconto']}') ?? 0) == 0 ? '—' : dinheiro(i['desconto'])),
              Text(dinheiro(i['total']), style: const TextStyle(fontWeight: FontWeight.w700)),
              if (editar)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Editar',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _editarItem(i),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Excluir',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _excluirItem(i),
                    icon: const Icon(Icons.delete_outline, size: 20, color: Cores.erro),
                  ),
                ])
              else
                const SizedBox(),
            ],
          ),
      ],
    );
  }

  Widget _totais(Map<String, dynamic> o) {
    Widget linha(String rotulo, Object? valor, {bool negativo = false, bool forte = false}) {
      final n = num.tryParse('${valor ?? 0}') ?? 0;
      if (n == 0 && !forte) return const SizedBox.shrink();
      final estilo = TextStyle(fontSize: forte ? 16 : 14, fontWeight: forte ? FontWeight.w800 : FontWeight.w500);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 170, child: Text(rotulo, textAlign: TextAlign.right, style: estilo)),
          SizedBox(width: 120, child: Text('${negativo ? '- ' : ''}${dinheiro(valor)}', textAlign: TextAlign.right, style: estilo)),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      linha('Peças e produtos', o['subtotal_produtos']),
      linha('Serviços e mão de obra', o['subtotal_servicos']),
      linha('Deslocamento', o['deslocamento']),
      linha('Descontos', o['desconto'], negativo: true),
      linha('Total', o['total'], forte: true),
    ]);
  }

  // ---------------- link ----------------

  bool _linkAtivo(Map<String, dynamic> l) =>
      l['usado_em'] == null &&
      l['revogado_em'] == null &&
      (DateTime.tryParse('${l['expira_em']}')?.isAfter(DateTime.now()) ?? false);

  Future<void> _gerarLink() async {
    final o = _orc!;
    if (_links.any(_linkAtivo)) {
      final ok = await _confirmar('Gerar novo link',
          'O link enviado antes deixa de valer (quem abrir verá "link substituído"). Continuar?',
          botao: 'Gerar novo link');
      if (ok != true) return;
    }
    final r = await _acaoLink({'acao': 'gerar', 'orcamento_id': _id}, 'Link gerado.');
    if (r == null || !mounted) return;
    final url = '${Config.linkAceite}/a/${r['token']}';
    final contato = '${r['contato'] ?? ''}'.trim();
    final primeiro = contato.split(' ').first;
    final msg = '${primeiro.isEmpty ? 'Olá!' : 'Olá, $primeiro!'} Segue o orçamento ${o['codigo']} '
        '(${dinheiro(o['total'])}, válido até ${dataBr(o['validade_ate'])}). '
        'Para ver e aprovar: $url';
    await showDialog<void>(
      context: context,
      builder: (ctx) => _DialogoLink(url: url, mensagem: msg, contato: contato, telefone: '${r['telefone'] ?? ''}'),
    );
  }

  Future<void> _revogarLink(Map<String, dynamic> l) async {
    final ok = await _confirmar('Cancelar link', 'Quem abrir este link verá que ele foi substituído e não conseguirá aprovar.',
        botao: 'Cancelar link', perigo: true);
    if (ok != true) return;
    await _acaoLink({'acao': 'revogar', 'link_id': l['id']}, 'Link cancelado.');
  }

  Future<Map<String, dynamic>?> _acaoLink(Map<String, dynamic> p, String sucesso) async {
    if (!mounted) return null;
    setState(() => _ocupado = true);
    try {
      final r = await acaoLink(p);
      _avisar(sucesso);
      await _carregar(manterEdicao: true);
      return r;
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
      return null;
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Widget _linhaLink(Map<String, dynamic> l, bool gestor) {
    final ativo = _linkAtivo(l);
    final contato = (l['contatos'] as Map?)?['nome'];
    final String situacao;
    final Color cor;
    if (l['usado_em'] != null) {
      situacao = 'Respondido em ${dataHoraBr(l['usado_em'])}';
      cor = Cores.sucesso;
    } else if (l['revogado_em'] != null) {
      situacao = 'Cancelado (substituído)';
      cor = Cores.neutro;
    } else if (!ativo) {
      situacao = 'Vencido';
      cor = Cores.alerta;
    } else {
      situacao = 'Ativo até ${dataHoraBr(l['expira_em'])}';
      cor = Cores.info;
    }
    final acessos = (l['acessos'] as int?) ?? 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.link, color: cor),
      title: Text('Gerado em ${dataHoraBr(l['criado_em'])}${contato != null ? ' para $contato' : ''}'),
      subtitle: Text([
        situacao,
        acessos == 0
            ? 'ainda não foi aberto'
            : 'aberto $acessos vez(es), a última em ${dataHoraBr(l['ultimo_acesso_em'])}',
      ].join(' · ')),
      trailing: gestor && ativo
          ? TextButton(onPressed: () => _revogarLink(l), child: const Text('Cancelar link'))
          : null,
    );
  }

  Widget _linhaAceite(Map<String, dynamic> a) {
    final aprovado = a['decisao'] == 'aprovado';
    const forca = {'forte': 'evidência forte', 'media': 'evidência média', 'fraca': 'evidência fraca'};
    final hash = '${a['documento_sha256'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Cores.linha), borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(aprovado ? Icons.thumb_up_alt_outlined : Icons.thumb_down_alt_outlined,
            color: aprovado ? Cores.sucesso : Cores.erro),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${aprovado ? 'Aprovado' : 'Reprovado'} ${(formasAceite[a['forma']] ?? '').toLowerCase()}'
              '${a['nome'] != null ? ' por ${a['nome']}' : ''} · ${dataHoraBr(a['criado_em'])}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (a['observacao'] != null) Text('${a['observacao']}'),
            if (a['forma'] == 'link')
              Text(
                [
                  if (a['documento_pessoa'] != null) 'documento ${a['documento_pessoa']}',
                  if (a['ip'] != null) 'IP ${a['ip']}',
                  if (a['user_agent'] != null) _navegador('${a['user_agent']}'),
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: Cores.neutro),
              ),
            Text(
              [
                forca[a['forca_evidencia']] ?? '',
                if (a['assinatura_caminho'] != null) 'assinatura na tela do app'
                else if (hash.length >= 12) 'conteúdo ${hash.substring(0, 12)}…',
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: Cores.neutro),
            ),
            if (a['assinatura_caminho'] != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: AssinaturaCliente(aceite: a)),
          ]),
        ),
      ]),
    );
  }
}

/// Frase curta para cada evento do orçamento.
String descreverEventoOrcamento(Map<String, dynamic> l) {
  final dados = (l['dados'] as Map?) ?? const {};
  final v = dados['versao'] != null ? ' v${dados['versao']}' : '';
  final texto = switch (l['acao']) {
    'criar' => 'Orçamento criado$v${dados['origem'] == 'app' ? ' no app, no local' : ''}'
        '${dados['precos_divergentes'] != null ? ' (preço diferente do catálogo atual)' : ''}',
    'enviar' => 'Marcado como enviado$v',
    'substituir' => 'Substituído pela v${dados['nova_versao'] ?? '?'}',
    'aprovar' => 'Aprovado$v ${(formasAceite[dados['forma']] ?? '').toLowerCase()}'
        '${dados['nome'] != null ? ' por ${dados['nome']}' : ''}',
    'reprovar' => 'Reprovado$v${dados['nome'] != null ? ' por ${dados['nome']}' : ''}',
    'cancelar' => 'Cancelado$v',
    'link_gerado' => 'Link para o cliente gerado${dados['contato'] != null ? ' (para ${dados['contato']})' : ''}',
    'link_revogado' => 'Link para o cliente cancelado',
    _ => 'Orçamento: ${l['acao']}',
  };
  final motivo = dados['motivo'];
  return motivo == null || '$motivo'.isEmpty ? texto : '$texto ($motivo)';
}

// ---------------- diálogos ----------------

/// Registrar a resposta do cliente: aprovação ou reprovação.
class _DialogoResposta extends StatefulWidget {
  const _DialogoResposta({required this.aprovar, required this.contatos, this.contatoId, this.total});

  final bool aprovar;
  final List<Map<String, dynamic>> contatos;
  final String? contatoId;
  final Object? total;

  @override
  State<_DialogoResposta> createState() => _DialogoRespostaState();
}

class _DialogoRespostaState extends State<_DialogoResposta> {
  final _chave = GlobalKey<FormState>();
  String _forma = 'telefone';
  late String? _contatoId = widget.contatos.any((c) => c['id'] == widget.contatoId) ? widget.contatoId : null;
  late final _nome = TextEditingController(text: _nomeDoContato(_contatoId));
  final _documento = TextEditingController();
  final _texto = TextEditingController();

  String _nomeDoContato(String? id) =>
      '${widget.contatos.where((c) => c['id'] == id).firstOrNull?['nome'] ?? ''}';

  @override
  void dispose() {
    _nome.dispose();
    _documento.dispose();
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aprovar = widget.aprovar;
    return AlertDialog(
      title: Text(aprovar ? 'Registrar aprovação' : 'Registrar reprovação'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _chave,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(aprovar
                  ? 'Total de ${dinheiro(widget.total)}. Os itens vão para a OS e o serviço volta para a fila '
                      '(como reparo). O registro não pode ser desfeito.'
                  : 'O serviço que esperava este orçamento é cancelado. Depois, na OS, você conclui só com o '
                      'diagnóstico, cancela, ou faz uma nova versão.'),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'telefone', label: Text('Por telefone'), icon: Icon(Icons.call_outlined)),
                  ButtonSegment(value: 'presencial', label: Text('Pessoalmente'), icon: Icon(Icons.person_outline)),
                ],
                selected: {_forma},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _forma = s.first),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Contato do cliente'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _contatoId,
                    isDense: true,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Outra pessoa (digite o nome)')),
                      for (final c in widget.contatos)
                        DropdownMenuItem<String?>(value: c['id'] as String, child: Text('${c['nome']}')),
                    ],
                    onChanged: (v) => setState(() {
                      _contatoId = v;
                      if (v != null) _nome.text = _nomeDoContato(v);
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nome,
                decoration: InputDecoration(labelText: aprovar ? 'Nome de quem aprovou' : 'Nome de quem reprovou (opcional)'),
                validator: (v) => aprovar && (v ?? '').trim().isEmpty ? 'Obrigatório' : null,
              ),
              if (aprovar) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _documento,
                  decoration: const InputDecoration(labelText: 'CPF ou documento (opcional)'),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _texto,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(labelText: aprovar ? 'Observação (opcional)' : 'Motivo (opcional)'),
              ),
              if (_forma == 'telefone')
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Aprovação por telefone fica registrada como evidência fraca (só a sua palavra). '
                    'Para valores altos, prefira o link (próximo passo) ou a assinatura no app.',
                    style: TextStyle(fontSize: 12, color: Cores.neutro),
                  ),
                ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
        FilledButton(
          style: aprovar ? null : FilledButton.styleFrom(backgroundColor: Cores.erro),
          onPressed: () {
            if (!_chave.currentState!.validate()) return;
            Navigator.of(context).pop(<String, dynamic>{
              'forma': _forma,
              'contato_id': _contatoId ?? '',
              'nome': _nome.text.trim(),
              if (aprovar) 'documento_pessoa': _documento.text.trim(),
              if (aprovar) 'observacao': _texto.text.trim() else 'motivo': _texto.text.trim(),
            });
          },
          child: Text(aprovar ? 'Registrar aprovação' : 'Registrar reprovação'),
        ),
      ],
    );
  }
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
              child: Text(titulo, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
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
        SizedBox(width: 170, child: Text(rotulo, style: const TextStyle(color: Cores.neutro))),
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

/// "Chrome no Android" a partir do user-agent (só para leitura do gestor).
String _navegador(String ua) {
  final so = ua.contains('Android')
      ? 'Android'
      : (ua.contains('iPhone') || ua.contains('iPad'))
          ? 'iPhone'
          : ua.contains('Windows')
              ? 'Windows'
              : ua.contains('Mac OS')
                  ? 'Mac'
                  : null;
  final nav = ua.contains('SamsungBrowser')
      ? 'Samsung Internet'
      : ua.contains('Edg/')
          ? 'Edge'
          : ua.contains('Firefox')
              ? 'Firefox'
              : (ua.contains('Chrome') || ua.contains('CriOS'))
                  ? 'Chrome'
                  : ua.contains('Safari')
                      ? 'Safari'
                      : null;
  if (nav == null && so == null) return 'navegador não identificado';
  return [nav ?? 'navegador', if (so != null) 'no $so'].join(' ');
}

/// O link gerado: aparece só agora (o banco guarda só o "carimbo" dele).
class _DialogoLink extends StatelessWidget {
  const _DialogoLink({required this.url, required this.mensagem, required this.contato, required this.telefone});

  final String url;
  final String mensagem;
  final String contato;
  final String telefone;

  void _copiar(BuildContext context, String texto, String aviso) {
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(aviso)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Link para o cliente'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(contato.isEmpty
              ? 'Mande para quem vai aprovar, pelo WhatsApp ou e-mail.'
              : 'Mande para $contato${telefone.isEmpty ? '' : ' ($telefone)'}, pelo WhatsApp ou e-mail.'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Cores.fundo, borderRadius: BorderRadius.circular(10)),
            child: SelectableText(mensagem),
          ),
          const SizedBox(height: 12),
          const Text(
            'Guarde agora: por segurança, o link aparece só nesta tela. Se perder, gere outro '
            '(o anterior deixa de valer).',
            style: TextStyle(fontSize: 12, color: Cores.neutro),
          ),
        ]),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _copiar(context, url, 'Link copiado.'),
          icon: const Icon(Icons.link),
          label: const Text('Copiar só o link'),
        ),
        FilledButton.icon(
          onPressed: () => _copiar(context, mensagem, 'Mensagem copiada: é só colar no WhatsApp.'),
          icon: const Icon(Icons.copy),
          label: const Text('Copiar mensagem'),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fechar')),
      ],
    );
  }
}
