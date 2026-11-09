import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/comercial.dart' show reais;
import '../servicos/status.dart';
import '../widgets/itens_os.dart' show numeroBr;
import '../widgets/margem.dart';
import 'entregas_tela.dart' show verRegistroEqp;
import 'servico.dart';
import 'widgets.dart';

/// Ficha do equipamento: status, onde está, reservas, linha do tempo (com fotos e checklist), manutenções,
/// locações, receita e custo. As ações mostram só os eventos que o status atual permite.
class EqpFichaTela extends StatefulWidget {
  const EqpFichaTela({super.key, required this.id});

  final String id;

  @override
  State<EqpFichaTela> createState() => _EqpFichaTelaState();
}

class _EqpFichaTelaState extends State<EqpFichaTela> {
  Map<String, dynamic>? _d;
  String? _erro;
  bool _ocupado = false;

  bool get _gestor => Sessao.atual?.tem(Papel.gestor) ?? false;
  bool get _custos => _gestor || (Sessao.atual?.tem(Papel.financeiro) ?? false);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final d = await eqp('eqp_ficha', {'equipamento_id': widget.id});
      if (mounted) {
        setState(() {
          _d = d;
          _erro = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    }
  }

  Map<String, dynamic> get _ficha => Map<String, dynamic>.from((_d?['ficha'] as Map?) ?? const {});
  Map<String, dynamic> get _bem => Map<String, dynamic>.from((_d?['equipamento'] as Map?) ?? const {});

  /// Roda uma ação, avisa e recarrega.
  Future<void> _rodar(String funcao, Map<String, dynamic> p, String ok) async {
    setState(() => _ocupado = true);
    try {
      final r = await eqp(funcao, p);
      if (mounted) avisarEqp(context, r['codigo'] != null ? '$ok · ${r['codigo']}' : ok);
      await _carregar();
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _movimentar(String evento) async {
    final apoio = await _apoioOuAviso();
    if (apoio == null || !mounted) return;
    final reservadas = listaDe(_d?['alocacoes']).where((a) => a['situacao'] == 'reservada').toList();
    final p = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _Movimentar(
        evento: evento,
        medidor: '${_ficha['medidor']}',
        locais: listaDe(apoio['locais_empresa']),
        reservadas: reservadas,
      ),
    );
    if (p == null) return;
    await _rodar('eqp_movimentar', {'equipamento_id': widget.id, 'evento': evento, ...p}, nomesEvento[evento] ?? evento);
  }

  Future<Map<String, dynamic>?> _apoioOuAviso() async {
    try {
      return await eqpApoio();
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
      return null;
    }
  }

  Future<void> _manutencao() async {
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _Manutencao());
    if (p == null) return;
    await _rodar('eqp_manutencao_acao', {'acao': 'abrir', 'equipamento_id': widget.id, ...p}, 'OS de manutenção aberta');
  }

  Future<void> _reservar() async {
    final apoio = await _apoioOuAviso();
    if (apoio == null || !mounted) return;
    final p = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _Reservar(obras: listaDe(apoio['obras']), setores: listaDe(apoio['setores'])),
    );
    if (p == null) return;
    await _rodar('eqp_alocacao_acao', {'acao': 'reservar', 'equipamento_id': widget.id, ...p}, 'Reserva feita');
  }

  Future<void> _cancelarReserva(Map<String, dynamic> a) async {
    final motivo = await pedirTextoEqp(context, 'Cancelar reserva', 'Motivo');
    if (motivo == null) return;
    await _rodar('eqp_alocacao_acao', {'acao': 'cancelar', 'alocacao_id': a['alocacao_id'], 'motivo': motivo}, 'Reserva cancelada');
  }

  Future<void> _leitura() async {
    final t = await pedirTextoEqp(context, 'Registrar leitura', 'Leitura atual (${_ficha['medidor']})');
    final v = num.tryParse((t ?? '').replaceAll(',', '.'));
    if (v == null) return;
    await _rodar('eqp_leitura', {'equipamento_id': widget.id, 'valor': v}, 'Leitura registrada');
  }

  Future<void> _custo() async {
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _Custo());
    if (p == null) return;
    await _rodar('eqp_custo_acao', {'acao': 'lancar', 'equipamento_id': widget.id, ...p}, 'Custo lançado');
  }

  Future<void> _estornar(Map<String, dynamic> c) async {
    final motivo = await pedirTextoEqp(context, 'Estornar ${reais(c['valor'])}', 'Motivo do estorno');
    if (motivo == null) return;
    await _rodar('eqp_custo_acao', {'acao': 'estornar', 'custo_id': c['custo_id'], 'motivo': motivo}, 'Custo estornado');
  }

  Future<void> _editar() async {
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _Editar(ficha: _ficha, bem: _bem));
    if (p == null) return;
    await _rodar('eqp_ficha_acao', {'acao': 'alterar', 'equipamento_id': widget.id, ...p}, 'Ficha salva');
  }

  Widget _info(String rotulo, Object? valor) {
    final v = '${valor ?? ''}';
    if (v.isEmpty || v == 'null') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '$rotulo: ', style: const TextStyle(color: Cores.neutro)),
        TextSpan(text: v),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    if (_erro != null && _d == null) {
      return Center(child: Text(_erro!, style: const TextStyle(color: Cores.erro)));
    }
    if (_d == null) return const Center(child: CircularProgressIndicator());
    final f = _ficha;
    final b = _bem;
    final status = '${f['status']}';
    final res = Map<String, dynamic>.from((_d!['resultado'] as Map?) ?? const {});
    final medidor = '${f['medidor']}';
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          IconButton(tooltip: 'Voltar', onPressed: () => context.go('/equipamentos/lista'), icon: const Icon(Icons.arrow_back)),
          Expanded(
            child: Text('${b['codigo']} · ${b['descricao']}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          ChipStatusEqp(status),
        ]),
        if (_ocupado) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 8),
        if (_gestor)
          Wrap(spacing: 8, runSpacing: 8, children: [
            PopupMenuButton<String>(
              enabled: !_ocupado && (eventosPorStatus[status] ?? const []).isNotEmpty,
              onSelected: _movimentar,
              itemBuilder: (_) => [
                for (final ev in eventosPorStatus[status] ?? const <String>[])
                  PopupMenuItem(value: ev, child: Text(nomesEvento[ev] ?? ev)),
              ],
              child: const Chip(avatar: Icon(Icons.swap_horiz, size: 18), label: Text('Movimentar')),
            ),
            ActionChip(
              avatar: const Icon(Icons.event_available_outlined, size: 18),
              label: const Text('Reservar (obra própria / uso próprio)'),
              onPressed: _ocupado || status == 'baixado' ? null : _reservar,
            ),
            ActionChip(
              avatar: const Icon(Icons.build_outlined, size: 18),
              label: const Text('Abrir manutenção'),
              onPressed: _ocupado || status == 'baixado' ? null : _manutencao,
            ),
            if (medidor != 'nenhum')
              ActionChip(avatar: const Icon(Icons.speed_outlined, size: 18), label: const Text('Leitura'), onPressed: _ocupado ? null : _leitura),
            ActionChip(avatar: const Icon(Icons.edit_outlined, size: 18), label: const Text('Editar'), onPressed: _ocupado ? null : _editar),
            // Guia 102: conjunto (componentes com QR e itens) e modelo.
            ActionChip(
              avatar: const Icon(Icons.account_tree_outlined, size: 18),
              label: const Text('Conjunto e modelo'),
              onPressed: () => context.go('/equipamentos/conjunto/${b['id']}'),
            ),
          ]),
        const SizedBox(height: 12),
        SecaoEqp(
          titulo: 'Agora',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _info('Onde está', f['local_atual']),
            _info('Com', f['com']),
            _info('Destino', destinos[f['destino_atual']]),
            _info('Desde', dataHoraBr(f['status_desde'])),
            _info('Depósito (base)', f['local_base']),
            _info('Patrimônio', f['patrimonio']),
            _info('Categoria', b['tipo']),
            _info('Marca / modelo', [b['marca'], b['modelo']].where((x) => x != null).join(' ')),
            _info('Série', b['numero_serie']),
            if (medidor != 'nenhum')
              _info(switch (medidor) { 'km' => 'Km', 'ciclos' => 'Ciclos', _ => 'Horímetro' },
                  f['leitura_atual'] == null ? null : '${numeroBr(f['leitura_atual'])} (uso acumulado ${numeroBr(f['uso_total'])})'),
            _info('Preços', [
              if (f['preco_diaria'] != null) '${reais(f['preco_diaria'])}/dia',
              if (f['preco_semana'] != null) '${reais(f['preco_semana'])}/semana',
              if (f['preco_mes'] != null) '${reais(f['preco_mes'])}/mês',
            ].join(' · ')),
            _info('Centro de custo', f['centro_custo']),
          ]),
        ),
        SecaoEqp(
          titulo: 'Resultado',
          acoes: [
            if (_custos)
              TextButton.icon(onPressed: _ocupado ? null : _custo, icon: const Icon(Icons.add, size: 18), label: const Text('Lançar custo')),
          ],
          child: Wrap(spacing: 24, runSpacing: 8, children: [
            _info('Receita estimada no mês', reais(res['receita_estimada_mes'])),
            _info('Receita estimada total', reais(res['receita_estimada_total'])),
            if (res['custo_mes'] != null) _info('Custo no mês', reais(res['custo_mes'])),
            if (res['custo_total'] != null) _info('Custo total', reais(res['custo_total'])),
          ]),
        ),
        SecaoEqp(
          titulo: 'Reservas e usos',
          child: listaDe(_d!['alocacoes']).isEmpty
              ? const Text('Nenhuma reserva.', style: TextStyle(color: Cores.neutro))
              : Column(children: [
                  for (final a in listaDe(_d!['alocacoes']))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${destinos[a['destino']] ?? a['destino']} · ${quemSemObra(a)}'),
                      subtitle: Text(
                        '${dataBr(a['inicio'])} a ${a['fim_previsto'] == null ? 'sem data' : dataBr(a['fim_previsto'])} · ${situacoesAlocacao[a['situacao']] ?? a['situacao']}'
                        '${a['atrasado'] == true ? ' · ATRASADO' : ''}',
                        style: TextStyle(color: a['atrasado'] == true ? Cores.erro : Cores.neutro),
                      ),
                      trailing: a['locacao_id'] != null
                          ? TextButton(onPressed: () => context.go('/equipamentos/locacoes/${a['locacao_id']}'), child: Text('${a['locacao']}'))
                          : (a['situacao'] == 'reservada' && _gestor
                              ? IconButton(tooltip: 'Cancelar reserva', onPressed: () => _cancelarReserva(a), icon: const Icon(Icons.close))
                              : null),
                    ),
                ]),
        ),
        SecaoEqp(
          titulo: 'Linha do tempo',
          child: Column(children: [
            for (final m in listaDe(_d!['linha_do_tempo']))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.circle, size: 12, color: corDoStatus('${m['status_para']}')),
                title: Text('${nomesEvento[m['evento']] ?? m['evento']} · ${statusEquipamento[m['status_para']] ?? ''}'
                    '${m['os'] != null ? ' · ${m['os']}' : ''}'),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text([
                    dataHoraBr(m['ocorrido_em']),
                    if (m['para'] != null) '${m['de'] != null && m['de'] != m['para'] ? '${m['de']} → ' : ''}${m['para']}',
                    if (m['condicao'] != null) condicoes[m['condicao']] ?? '${m['condicao']}',
                    if (m['leitura'] != null) 'leitura ${numeroBr(m['leitura'])}',
                    if (m['recebido_por'] != null) 'recebido por ${m['recebido_por']}',
                    if (m['quem'] != null) 'por ${m['quem']}',
                    if (m['motivo'] != null) '${m['motivo']}',
                    if (m['observacao'] != null) '${m['observacao']}',
                  ].join(' · ')),
                  if ((m['fotos'] as List?)?.isNotEmpty ?? false) FotosEqp(m['fotos'] as List),
                  if (m['origem'] == 'app')
                    TextButton(
                      onPressed: () => verRegistroEqp(context, '${m['movimento_id']}'),
                      child: const Text('Ver o registro do app (GPS, checklist, assinatura)'),
                    ),
                ]),
              ),
          ]),
        ),
        SecaoEqp(
          titulo: 'Manutenções',
          child: listaDe(_d!['manutencoes']).isEmpty
              ? const Text('Nenhuma OS de manutenção.', style: TextStyle(color: Cores.neutro))
              : Column(children: [
                  for (final o in listaDe(_d!['manutencoes']))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${o['codigo']} · ${naturezasManutencao[o['natureza']] ?? o['natureza']} · ${o['status']}'),
                      subtitle: Text('${dataBr(o['abertura_em'])} · ${o['problema'] ?? ''}'),
                      onTap: () => context.go('/os/${o['os_id']}'),
                    ),
                ]),
        ),
        SecaoEqp(
          titulo: 'Locações',
          child: listaDe(_d!['locacoes']).isEmpty
              ? const Text('Nenhuma locação.', style: TextStyle(color: Cores.neutro))
              : Column(children: [
                  for (final l in listaDe(_d!['locacoes']))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${l['codigo']} · ${l['cliente']}'),
                      subtitle: Text('${dataBr(l['inicio'])} a ${dataBr(l['fim_previsto'])} · ${situacoesItem[l['situacao_item']] ?? ''}'
                          ' · ${reais(l['preco'])} ${periodicidades[l['periodicidade']] ?? ''}'
                          '${l['avaria_descricao'] != null ? ' · avaria: ${l['avaria_descricao']}' : ''}'),
                      onTap: () => context.go('/equipamentos/locacoes/${l['locacao_id']}'),
                    ),
                ]),
        ),
        if (_d!['custos'] is List)
          SecaoEqp(
            titulo: 'Custos',
            child: listaDe(_d!['custos']).isEmpty
                ? const Text('Nenhum custo lançado.', style: TextStyle(color: Cores.neutro))
                : Column(children: [
                    for (final c in listaDe(_d!['custos']))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${reais(c['valor'])} · ${naturezasCusto[c['natureza']] ?? c['natureza']} · ${c['descricao']}'),
                        subtitle: Text('${dataBr(c['data_custo'])}${c['documento'] != null ? ' · ${c['documento']}' : ''}'
                            '${c['estornado'] == true ? ' · estornado' : ''}'),
                        trailing: c['estornado'] == true || c['estorno'] == true || !_custos
                            ? null
                            : IconButton(tooltip: 'Estornar', onPressed: () => _estornar(c), icon: const Icon(Icons.undo)),
                      ),
                  ]),
          ),
      ]),
    );
  }
}

/// Campos do evento: local, reserva, motivo, leitura e observação (o banco confere tudo de novo).
class _Movimentar extends StatefulWidget {
  const _Movimentar({required this.evento, required this.medidor, required this.locais, required this.reservadas});

  final String evento;
  final String medidor;
  final List<Map<String, dynamic>> locais;
  final List<Map<String, dynamic>> reservadas;

  @override
  State<_Movimentar> createState() => _MovimentarState();
}

class _MovimentarState extends State<_Movimentar> {
  final _motivo = TextEditingController();
  final _obs = TextEditingController();
  final _leitura = TextEditingController();
  String? _local;
  String? _alocacao;
  bool _direto = true;

  bool get _pedeLocal => const ['mover', 'retorno', 'recolher', 'chegada'].contains(widget.evento);
  bool get _pedeReserva => const ['saida', 'reservar', 'transferencia'].contains(widget.evento);
  bool get _pedeMotivo => const ['bloquear', 'baixar'].contains(widget.evento);

  @override
  void dispose() {
    _motivo.dispose();
    _obs.dispose();
    _leitura.dispose();
    super.dispose();
  }

  void _ok() {
    if (widget.evento == 'mover' && _local == null) return;
    if (widget.evento == 'transferencia' && _alocacao == null) return;
    if (_pedeMotivo && _motivo.text.trim().isEmpty) return;
    final leitura = num.tryParse(_leitura.text.trim().replaceAll(',', '.'));
    Navigator.of(context).pop(<String, dynamic>{
      if (_local != null) 'local_id': _local,
      if (_alocacao != null) 'alocacao_id': _alocacao,
      if (widget.evento == 'saida') 'direto': _direto,
      if (_motivo.text.trim().isNotEmpty) 'motivo': _motivo.text.trim(),
      if (_obs.text.trim().isNotEmpty) 'observacao': _obs.text.trim(),
      if (leitura != null) 'leitura': leitura,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(nomesEvento[widget.evento] ?? widget.evento),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_pedeReserva)
                widget.reservadas.isEmpty
                    ? const Text('Não há reserva para este equipamento. Faça a reserva (ou o contrato de locação) antes.',
                        style: TextStyle(color: Cores.alerta))
                    : DropdownButtonFormField<String?>(
                        initialValue: _alocacao,
                        decoration: InputDecoration(
                            labelText: widget.evento == 'transferencia' ? 'Novo destino (reserva)' : 'Reserva (padrão: a próxima)'),
                        items: [
                          if (widget.evento != 'transferencia') const DropdownMenuItem<String?>(value: null, child: Text('A próxima')),
                          for (final a in widget.reservadas)
                            DropdownMenuItem<String?>(
                              value: '${a['alocacao_id']}',
                              child: Text('${a['com'] ?? ''} · ${dataBr(a['inicio'])}'),
                            ),
                        ],
                        onChanged: (v) => setState(() => _alocacao = v),
                      ),
              if (widget.evento == 'saida')
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _direto,
                  title: const Text('Já chegou ao destino (sem trânsito)'),
                  onChanged: (v) => setState(() => _direto = v),
                ),
              if (_pedeLocal)
                DropdownButtonFormField<String?>(
                  initialValue: _local,
                  decoration: InputDecoration(labelText: widget.evento == 'mover' ? 'Para qual local da empresa' : 'Local (padrão: o depósito base)'),
                  items: [
                    if (widget.evento != 'mover') const DropdownMenuItem<String?>(value: null, child: Text('Padrão')),
                    for (final l in widget.locais) DropdownMenuItem<String?>(value: '${l['id']}', child: Text('${l['nome']}')),
                  ],
                  onChanged: (v) => setState(() => _local = v),
                ),
              if (_pedeMotivo) TextField(controller: _motivo, decoration: const InputDecoration(labelText: 'Motivo (obrigatório)')),
              if (widget.medidor != 'nenhum')
                TextField(
                  controller: _leitura,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Leitura do medidor (opcional)'),
                ),
              TextField(controller: _obs, decoration: const InputDecoration(labelText: 'Observação')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(onPressed: _ok, child: const Text('Registrar')),
        ],
      );
}

class _Manutencao extends StatefulWidget {
  const _Manutencao();

  @override
  State<_Manutencao> createState() => _ManutencaoState();
}

class _ManutencaoState extends State<_Manutencao> {
  final _problema = TextEditingController();
  String _natureza = 'corretiva';
  String _prioridade = 'media';

  @override
  void dispose() {
    _problema.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Abrir manutenção'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: _natureza,
              decoration: const InputDecoration(labelText: 'Natureza'),
              items: [for (final n in naturezasManutencao.entries) DropdownMenuItem(value: n.key, child: Text(n.value))],
              onChanged: (v) => setState(() => _natureza = v ?? 'corretiva'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _prioridade,
              decoration: const InputDecoration(labelText: 'Prioridade'),
              items: const [
                DropdownMenuItem(value: 'baixa', child: Text('Baixa')),
                DropdownMenuItem(value: 'media', child: Text('Média')),
                DropdownMenuItem(value: 'alta', child: Text('Alta')),
                DropdownMenuItem(value: 'urgente', child: Text('Urgente')),
              ],
              onChanged: (v) => setState(() => _prioridade = v ?? 'media'),
            ),
            TextField(controller: _problema, maxLines: 3, decoration: const InputDecoration(labelText: 'O que fazer / problema')),
            const SizedBox(height: 8),
            const Text('Abre a OS do ServPilot (sem cobrança) e o equipamento fica "em manutenção" até você liberar.',
                style: TextStyle(color: Cores.neutro, fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              if (_problema.text.trim().isEmpty) return;
              Navigator.of(context).pop(<String, dynamic>{
                'natureza': _natureza,
                'prioridade': _prioridade,
                'problema': _problema.text.trim(),
              });
            },
            child: const Text('Abrir OS'),
          ),
        ],
      );
}

class _Reservar extends StatefulWidget {
  const _Reservar({required this.obras, required this.setores});

  final List<Map<String, dynamic>> obras;
  final List<Map<String, dynamic>> setores;

  @override
  State<_Reservar> createState() => _ReservarState();
}

class _ReservarState extends State<_Reservar> {
  String _destino = 'obra_propria';
  String? _obra;
  String? _setor;
  DateTime _inicio = DateTime.now();
  DateTime? _fim;

  @override
  Widget build(BuildContext context) {
    final obras = widget.obras.where((o) => o['propria'] == true && o['situacao'] != 'encerrada').toList();
    final setores = widget.setores.where((s) => s['ativo'] == true).toList();
    return AlertDialog(
      title: const Text('Reservar'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('Obra própria'), selected: _destino == 'obra_propria', onSelected: (_) => setState(() => _destino = 'obra_propria')),
            ChoiceChip(label: const Text('Uso próprio'), selected: _destino == 'uso_proprio', onSelected: (_) => setState(() => _destino = 'uso_proprio')),
          ]),
          if (_destino == 'obra_propria')
            DropdownButtonFormField<String?>(
              initialValue: _obra,
              decoration: const InputDecoration(labelText: 'Obra'),
              items: [for (final o in obras) DropdownMenuItem<String?>(value: '${o['id']}', child: Text('${o['codigo']} · ${o['nome']}'))],
              onChanged: (v) => setState(() => _obra = v),
            )
          else
            DropdownButtonFormField<String?>(
              initialValue: _setor,
              decoration: const InputDecoration(labelText: 'Setor / filial'),
              items: [for (final s in setores) DropdownMenuItem<String?>(value: '${s['id']}', child: Text('${s['nome']}'))],
              onChanged: (v) => setState(() => _setor = v),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            CampoDataEqp(rotulo: 'Início', data: _inicio, aoMudar: (d) => setState(() => _inicio = d)),
            CampoDataEqp(rotulo: 'Fim previsto', data: _fim, aoMudar: (d) => setState(() => _fim = d)),
          ]),
          const SizedBox(height: 8),
          const Text('Para cliente, use Locações (contrato com preço, retirada e devolução).',
              style: TextStyle(color: Cores.neutro, fontSize: 12)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
        FilledButton(
          onPressed: () {
            if (_destino == 'obra_propria' && _obra == null) return;
            if (_destino == 'uso_proprio' && _setor == null) return;
            Navigator.of(context).pop(<String, dynamic>{
              'destino': _destino,
              if (_obra != null && _destino == 'obra_propria') 'obra_id': _obra,
              if (_setor != null && _destino == 'uso_proprio') 'setor_id': _setor,
              'inicio': iso(_inicio),
              if (_fim != null) 'fim_previsto': iso(_fim!),
            });
          },
          child: const Text('Reservar'),
        ),
      ],
    );
  }
}

class _Custo extends StatefulWidget {
  const _Custo();

  @override
  State<_Custo> createState() => _CustoState();
}

class _CustoState extends State<_Custo> {
  final _valor = TextEditingController();
  final _descricao = TextEditingController();
  final _motivo = TextEditingController();
  final _documento = TextEditingController();
  final _fornecedor = TextEditingController();
  String _natureza = 'reparo';
  DateTime _data = DateTime.now();

  @override
  void dispose() {
    for (final c in [_valor, _descricao, _motivo, _documento, _fornecedor]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Lançar custo'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                initialValue: _natureza,
                decoration: const InputDecoration(labelText: 'Natureza'),
                items: [for (final n in naturezasCusto.entries) DropdownMenuItem(value: n.key, child: Text(n.value))],
                onChanged: (v) => setState(() => _natureza = v ?? 'reparo'),
              ),
              TextField(
                controller: _valor,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Valor (R\$)'),
              ),
              TextField(controller: _descricao, decoration: const InputDecoration(labelText: 'Descrição')),
              TextField(controller: _motivo, decoration: const InputDecoration(labelText: 'Motivo (por que à mão)')),
              TextField(controller: _documento, decoration: const InputDecoration(labelText: 'Documento (nota, pedido no ERP)')),
              TextField(controller: _fornecedor, decoration: const InputDecoration(labelText: 'Fornecedor')),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: CampoDataEqp(rotulo: 'Data', data: _data, aoMudar: (d) => setState(() => _data = d)),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              final v = num.tryParse(_valor.text.trim().replaceAll(',', '.'));
              if (v == null || v <= 0 || _descricao.text.trim().isEmpty || _motivo.text.trim().isEmpty) return;
              Navigator.of(context).pop(<String, dynamic>{
                'natureza': _natureza,
                'valor': v,
                'descricao': _descricao.text.trim(),
                'motivo': _motivo.text.trim(),
                'data_custo': iso(_data),
                if (_documento.text.trim().isNotEmpty) 'documento': _documento.text.trim(),
                if (_fornecedor.text.trim().isNotEmpty) 'fornecedor': _fornecedor.text.trim(),
              });
            },
            child: const Text('Lançar'),
          ),
        ],
      );
}

class _Editar extends StatefulWidget {
  const _Editar({required this.ficha, required this.bem});

  final Map<String, dynamic> ficha;
  final Map<String, dynamic> bem;

  @override
  State<_Editar> createState() => _EditarState();
}

class _EditarState extends State<_Editar> {
  late final Map<String, TextEditingController> _c = {
    'descricao': TextEditingController(text: '${widget.bem['descricao'] ?? ''}'),
    'marca': TextEditingController(text: '${widget.bem['marca'] ?? ''}'),
    'modelo': TextEditingController(text: '${widget.bem['modelo'] ?? ''}'),
    'numero_serie': TextEditingController(text: '${widget.bem['numero_serie'] ?? ''}'),
    for (final k in ['patrimonio', 'preco_diaria', 'preco_semana', 'preco_mes', 'valor_aquisicao', 'centro_custo', 'observacoes'])
      k: TextEditingController(text: '${widget.ficha[k] ?? ''}'),
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _campo(String k, String rotulo, {bool numero = false}) => TextField(
        controller: _c[k],
        keyboardType: numero ? const TextInputType.numberWithOptions(decimal: true) : null,
        decoration: InputDecoration(labelText: rotulo),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Editar ficha'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _campo('descricao', 'Descrição'),
              _campo('patrimonio', 'Patrimônio'),
              Row(children: [
                Expanded(child: _campo('marca', 'Marca')),
                const SizedBox(width: 8),
                Expanded(child: _campo('modelo', 'Modelo')),
              ]),
              _campo('numero_serie', 'Número de série'),
              Row(children: [
                Expanded(child: _campo('preco_diaria', 'R\$ por dia', numero: true)),
                const SizedBox(width: 8),
                Expanded(child: _campo('preco_semana', 'R\$ por semana', numero: true)),
                const SizedBox(width: 8),
                Expanded(child: _campo('preco_mes', 'R\$ por mês', numero: true)),
              ]),
              _campo('valor_aquisicao', 'Valor de aquisição', numero: true),
              _campo('centro_custo', 'Centro de custo (ERP)'),
              _campo('observacoes', 'Observações'),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              final p = <String, dynamic>{};
              for (final e in _c.entries) {
                final t = e.value.text.trim();
                p[e.key] = const ['preco_diaria', 'preco_semana', 'preco_mes', 'valor_aquisicao'].contains(e.key)
                    ? (t.isEmpty ? null : num.tryParse(t.replaceAll(',', '.')))
                    : t;
              }
              Navigator.of(context).pop(p);
            },
            child: const Text('Salvar'),
          ),
        ],
      );
}
