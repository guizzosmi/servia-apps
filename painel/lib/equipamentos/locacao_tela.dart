import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/comercial.dart' show reais;
import '../servicos/status.dart';
import '../widgets/itens_os.dart' show numeroBr;
import '../widgets/margem.dart';
import 'servico.dart';
import 'widgets.dart';

/// Um contrato de locação: equipamentos (com a agenda conferida pelo banco), confirmar, retirada e devolução
/// com checklist, fotos, horímetro e quem recebeu, avaria na devolução, prorrogar, cancelar e encerrar.
class EqpLocacaoTela extends StatefulWidget {
  const EqpLocacaoTela({super.key, required this.id});

  final String id;

  @override
  State<EqpLocacaoTela> createState() => _EqpLocacaoTelaState();
}

class _EqpLocacaoTelaState extends State<EqpLocacaoTela> {
  Map<String, dynamic>? _d;
  String? _erro;
  bool _ocupado = false;

  bool get _gestor => Sessao.atual?.tem(Papel.gestor) ?? false;
  Map<String, dynamic> get _l => Map<String, dynamic>.from((_d?['locacao'] as Map?) ?? const {});

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final d = await eqp('eqp_locacao_ver', {'locacao_id': widget.id});
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

  Future<void> _acao(Map<String, dynamic> p, String ok) async {
    setState(() => _ocupado = true);
    try {
      await eqp('eqp_locacao_acao', {'locacao_id': widget.id, ...p});
      if (mounted) avisarEqp(context, ok);
      await _carregar();
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _incluir() async {
    Map<String, dynamic> livres;
    try {
      livres = await eqp('eqp_disponibilidade', {'inicio': _l['inicio'], 'fim': _l['fim_previsto']});
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
      return;
    }
    if (!mounted) return;
    final ja = listaDe(_d?['itens']).where((i) => i['situacao'] != 'cancelado').map((i) => '${i['equipamento_id']}').toSet();
    final p = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _IncluirItem(
        livres: listaDe(livres['livres']).where((e) => !ja.contains('${e['equipamento_id']}')).toList(),
        ocupados: listaDe(livres['ocupados']),
        dias: (_l['dias'] as num?)?.toInt() ?? 1,
      ),
    );
    if (p == null) return;
    await _acao({'acao': 'item_salvar', ...p}, 'Equipamento incluído');
  }

  Future<void> _retirar([Map<String, dynamic>? item]) async {
    final p = await dialogoConferencia(
      context,
      titulo: item == null ? 'Retirada de todos os reservados' : 'Retirada · ${item['codigo']}',
      devolucao: false,
      medidor: item?['medidor'] as String?,
    );
    if (p == null) return;
    await _acao({'acao': 'retirar', if (item != null) 'item_id': item['item_id'], ...p}, 'Retirada registrada');
  }

  Future<void> _devolver(Map<String, dynamic> item) async {
    final p = await dialogoConferencia(context, titulo: 'Devolução · ${item['codigo']}', devolucao: true, medidor: item['medidor'] as String?);
    if (p == null) return;
    await _acao({'acao': 'devolver', 'item_id': item['item_id'], ...p}, 'Devolução registrada');
  }

  Future<void> _remover(Map<String, dynamic> item) async {
    if (!await confirmarEqp(context, 'Remover ${item['codigo']}', 'Tira o equipamento do contrato (e cancela a reserva dele).')) return;
    await _acao({'acao': 'item_remover', 'item_id': item['item_id']}, 'Equipamento removido');
  }

  Future<void> _prorrogar() async {
    final atual = DateTime.tryParse('${_l['fim_previsto']}') ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime.tryParse('${_l['inicio']}') ?? DateTime(2020),
      lastDate: DateTime(atual.year + 3),
      helpText: 'Novo fim previsto',
    );
    if (d == null) return;
    await _acao({'acao': 'alterar', 'fim_previsto': iso(d)}, 'Fim previsto alterado');
  }

  Future<void> _cancelar() async {
    final motivo = await pedirTextoEqp(context, 'Cancelar ${_l['codigo']}', 'Motivo');
    if (motivo == null) return;
    await _acao({'acao': 'cancelar', 'motivo': motivo}, 'Contrato cancelado');
  }

  Future<void> _confirmar() async {
    if (!await confirmarEqp(context, 'Confirmar ${_l['codigo']}',
        'Reserva todos os equipamentos de ${dataBr(_l['inicio'])} a ${dataBr(_l['fim_previsto'])}. Se algum estiver ocupado, '
            'nada é reservado.')) {
      return;
    }
    await _acao({'acao': 'confirmar'}, 'Contrato confirmado: equipamentos reservados');
  }

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    if (_erro != null && _d == null) return Center(child: Text(_erro!, style: const TextStyle(color: Cores.erro)));
    if (_d == null) return const Center(child: CircularProgressIndicator());
    final l = _l;
    final sit = '${l['situacao']}';
    final itens = listaDe(_d!['itens']);
    final aberta = sit == 'rascunho' || sit == 'confirmada' || sit == 'em_andamento';
    final reservados = itens.where((i) => i['situacao'] == 'reservado').length;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          IconButton(tooltip: 'Voltar', onPressed: () => context.go('/equipamentos/locacoes'), icon: const Icon(Icons.arrow_back)),
          Expanded(
            child: Text('${l['codigo']} · ${l['cliente']}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text(situacoesLocacao[sit] ?? sit, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        if (_ocupado) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 8),
        // Guia 102: forma de cobrança, franquia e medições do contrato.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go('/equipamentos/cobranca/${widget.id}'),
            icon: const Icon(Icons.request_quote_outlined, size: 18),
            label: const Text('Cobrança e medições'),
          ),
        ),
        if (_gestor && aberta)
          Wrap(spacing: 8, runSpacing: 8, children: [
            ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Incluir equipamento'), onPressed: _ocupado ? null : _incluir),
            if (sit == 'rascunho')
              ActionChip(avatar: const Icon(Icons.check, size: 18), label: const Text('Confirmar (reservar)'), onPressed: _ocupado ? null : _confirmar),
            if (reservados > 0)
              ActionChip(
                avatar: const Icon(Icons.logout, size: 18),
                label: Text('Retirar todos ($reservados)'),
                onPressed: _ocupado ? null : () => _retirar(),
              ),
            if (sit != 'rascunho')
              ActionChip(avatar: const Icon(Icons.update, size: 18), label: const Text('Prorrogar / antecipar'), onPressed: _ocupado ? null : _prorrogar),
            if (sit == 'rascunho' || sit == 'confirmada')
              ActionChip(avatar: const Icon(Icons.close, size: 18), label: const Text('Cancelar'), onPressed: _ocupado ? null : _cancelar),
            if (sit == 'em_andamento' && !itens.any((i) => i['situacao'] == 'em_campo'))
              ActionChip(
                avatar: const Icon(Icons.done_all, size: 18),
                label: const Text('Encerrar'),
                onPressed: _ocupado ? null : () => _acao({'acao': 'encerrar'}, 'Contrato encerrado'),
              ),
          ]),
        const SizedBox(height: 12),
        SecaoEqp(
          titulo: 'Contrato',
          child: Text([
            '${dataBr(l['inicio'])} a ${dataBr(l['fim_previsto'])} (${l['dias']} dias)',
            'Entrega: ${l['local'] ?? ''}${'${l['endereco'] ?? ''}'.isNotEmpty ? ' · ${l['endereco']}' : ''}',
            if (l['obra'] != null) 'Obra: ${l['obra']}',
            if (l['contato'] != null) 'Contato: ${l['contato']}${l['telefone'] != null ? ' · ${l['telefone']}' : ''}',
            'Valor previsto: ${reais(l['valor_previsto'])}',
            if (l['condicoes'] != null) 'Condições: ${l['condicoes']}',
            if (l['motivo_cancelamento'] != null) 'Cancelado: ${l['motivo_cancelamento']}',
          ].join('\n')),
        ),
        SecaoEqp(
          titulo: 'Equipamentos (${itens.where((i) => i['situacao'] != 'cancelado').length})',
          child: itens.isEmpty
              ? const Text('Inclua os equipamentos (a lista mostra só os livres no período).', style: TextStyle(color: Cores.neutro))
              : Column(children: [
                  for (final i in itens)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => context.go('/equipamentos/ativo/${i['equipamento_id']}'),
                      title: Text('${i['codigo']} · ${i['descricao']}'),
                      subtitle: Text(
                        [
                          '${situacoesItem[i['situacao']] ?? i['situacao']} · ${reais(i['preco'])} ${periodicidades[i['periodicidade']] ?? ''}'
                              ' = ${reais(i['valor_previsto'])}',
                          if (i['saida_em'] != null)
                            'saiu ${dataHoraBr(i['saida_em'])}${i['condicao_saida'] != null ? ' (${condicoes[i['condicao_saida']]})' : ''}',
                          if (i['retorno_em'] != null)
                            'voltou ${dataHoraBr(i['retorno_em'])}${i['condicao_retorno'] != null ? ' (${condicoes[i['condicao_retorno']]})' : ''}',
                          if (i['avaria_descricao'] != null)
                            'avaria: ${i['avaria_descricao']}${i['avaria_valor'] != null ? ' · ${reais(i['avaria_valor'])}' : ''}',
                          if (i['atrasado'] == true) 'ATRASADO',
                        ].join('\n'),
                        style: TextStyle(color: i['atrasado'] == true || i['avaria_descricao'] != null ? Cores.erro : Cores.neutro),
                      ),
                      trailing: !_gestor
                          ? null
                          : switch ('${i['situacao']}') {
                              'reservado' => TextButton(onPressed: _ocupado ? null : () => _retirar(i), child: const Text('Retirar')),
                              'em_campo' => FilledButton.tonal(onPressed: _ocupado ? null : () => _devolver(i), child: const Text('Devolver')),
                              'previsto' => IconButton(tooltip: 'Remover', onPressed: _ocupado ? null : () => _remover(i), icon: const Icon(Icons.close)),
                              _ => null,
                            },
                    ),
                ]),
        ),
        SecaoEqp(
          titulo: 'Retiradas e devoluções',
          child: listaDe(_d!['movimentos']).isEmpty
              ? const Text('Nada ainda.', style: TextStyle(color: Cores.neutro))
              : Column(children: [
                  for (final m in listaDe(_d!['movimentos']))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${m['codigo']} · ${nomesEvento[m['evento']] ?? m['evento']} · ${dataHoraBr(m['ocorrido_em'])}'),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text([
                          if (m['condicao'] != null) condicoes[m['condicao']] ?? '${m['condicao']}',
                          if (m['leitura'] != null) 'leitura ${numeroBr(m['leitura'])}',
                          if (m['recebido_por'] != null) 'recebido por ${m['recebido_por']}',
                          if (m['quem'] != null) 'por ${m['quem']}',
                          for (final c in listaDe(m['checklist']))
                            if (c['ok'] != true) 'não ok: ${c['item']}',
                        ].join(' · ')),
                        if ((m['fotos'] as List?)?.isNotEmpty ?? false) FotosEqp(m['fotos'] as List),
                      ]),
                    ),
                ]),
        ),
      ]),
    );
  }
}

/// Escolhe um equipamento livre no período e o preço (o da tabela vem sugerido).
class _IncluirItem extends StatefulWidget {
  const _IncluirItem({required this.livres, required this.ocupados, required this.dias});

  final List<Map<String, dynamic>> livres;
  final List<Map<String, dynamic>> ocupados;
  final int dias;

  @override
  State<_IncluirItem> createState() => _IncluirItemState();
}

class _IncluirItemState extends State<_IncluirItem> {
  Map<String, dynamic>? _eq;
  String _per = 'dia';
  final _preco = TextEditingController();
  final _filtro = TextEditingController();

  @override
  void dispose() {
    _preco.dispose();
    _filtro.dispose();
    super.dispose();
  }

  void _escolher(Map<String, dynamic> e) {
    final per = e['preco_diaria'] != null ? 'dia' : (e['preco_semana'] != null ? 'semana' : (e['preco_mes'] != null ? 'mes' : 'dia'));
    setState(() {
      _eq = e;
      _per = per;
      _preco.text = numeroBr(e[switch (per) { 'semana' => 'preco_semana', 'mes' => 'preco_mes', _ => 'preco_diaria' }]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = _filtro.text.trim().toLowerCase();
    final livres = widget.livres
        .where((e) => f.isEmpty || '${e['codigo']} ${e['descricao']} ${e['tipo'] ?? ''}'.toLowerCase().contains(f))
        .toList();
    return AlertDialog(
      title: const Text('Incluir equipamento'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _filtro,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Filtrar os livres no período'),
              onChanged: (_) => setState(() {}),
            ),
            if (livres.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Nenhum livre no período.')),
            for (final e in livres.take(30))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                selected: _eq?['equipamento_id'] == e['equipamento_id'],
                leading: Icon(_eq?['equipamento_id'] == e['equipamento_id'] ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 20),
                title: Text('${e['codigo']} · ${e['descricao']}'),
                subtitle: Text([
                  '${e['local'] ?? ''}',
                  if (e['preco_diaria'] != null) '${reais(e['preco_diaria'])}/dia',
                  if (e['preco_semana'] != null) '${reais(e['preco_semana'])}/semana',
                  if (e['preco_mes'] != null) '${reais(e['preco_mes'])}/mês',
                  if (e['aviso'] != null) '${e['aviso']}',
                ].join(' · ')),
                onTap: () => _escolher(e),
              ),
            if (widget.ocupados.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Ocupados no período: ${widget.ocupados.map((o) => '${o['codigo']} (${o['motivo']})').join(', ')}',
                  style: const TextStyle(color: Cores.neutro, fontSize: 12),
                ),
              ),
            if (_eq != null) ...[
              const Divider(),
              Wrap(spacing: 8, children: [
                for (final p in periodicidades.entries)
                  ChoiceChip(label: Text(p.value), selected: _per == p.key, onSelected: (_) => setState(() => _per = p.key)),
              ]),
              TextField(
                controller: _preco,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Preço ${periodicidades[_per]} (R\$)', helperText: '${widget.dias} dia(s) no contrato'),
              ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
        FilledButton(
          onPressed: _eq == null
              ? null
              : () {
                  final preco = num.tryParse(_preco.text.trim().replaceAll(',', '.'));
                  if (preco == null || preco < 0) return;
                  Navigator.of(context).pop(<String, dynamic>{
                    'equipamento_id': _eq!['equipamento_id'],
                    'preco': preco,
                    'periodicidade': _per,
                  });
                },
          child: const Text('Incluir'),
        ),
      ],
    );
  }
}
