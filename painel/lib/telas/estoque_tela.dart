import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cadastros/lista.dart';
import '../servicos/status.dart';
import '../widgets/itens_os.dart' show lerNumero, numeroBr;
import '../widgets/margem.dart';

/// Estoque (guia 63): saldos por estoque (almoxarifado e carro de cada
/// equipe), cilindros de gás e os movimentos. Entrada de compra,
/// transferência e inventário. A peça usada na OS sai sozinha do carro da
/// equipe que atendeu; o gás adicionado sai do cilindro do carro.
class EstoqueTela extends StatefulWidget {
  const EstoqueTela({super.key});

  @override
  State<EstoqueTela> createState() => _EstoqueTelaState();
}

const _tiposMov = {
  'entrada': 'Entrada',
  'transferencia': 'Transferência',
  'inventario': 'Inventário',
  'os': 'OS',
  'gas_os': 'Gás na OS',
  'recolhido_os': 'Recolhido na OS',
  'cilindro': 'Cilindro',
};

const _statusCil = {
  'cheio': Rotulo('Cheio', Cores.sucesso),
  'em_uso': Rotulo('Em uso', Cores.info),
  'vazio': Rotulo('Vazio', Cores.alerta),
  'devolvido': Rotulo('Devolvido', Cores.neutro),
};

SupabaseClient get _db => Supabase.instance.client;

Future<Map<String, dynamic>> acaoEstoque(Map<String, dynamic> p) async {
  final r = await _db.rpc('estoque_acao', params: {'p': p});
  return Map<String, dynamic>.from(r as Map);
}

class _EstoqueTelaState extends State<EstoqueTela> {
  List<Map<String, dynamic>> _estoques = [];
  List<Map<String, dynamic>> _saldos = [];
  List<Map<String, dynamic>> _cilindros = [];
  List<Map<String, dynamic>> _movimentos = [];
  Map<String, String> _codigosOs = {};
  bool _carregando = true;
  bool _soAbaixo = false;
  String _busca = '';
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final estoques = await _db
          .from('estoques')
          .select('id, nome, tipo, padrao, equipe_id')
          .eq('ativo', true)
          .isFilter('excluido_em', null)
          .order('padrao', ascending: false)
          .order('tipo', ascending: true)
          .order('nome', ascending: true);
      final saldos = await _db
          .from('estoque_saldos')
          .select('estoque_id, produto_id, quantidade, minimo, produtos(descricao, codigo, unidade)')
          .limit(5000);
      final cil = await _db
          .from('cilindros')
          .select('id, identificacao, fluido, tipo, capacidade_kg, saldo_kg, status, estoque_id, estoques(nome)')
          .isFilter('excluido_em', null)
          .order('fluido', ascending: true)
          .order('identificacao', ascending: true);
      final mov = await _db
          .from('estoque_movimentos')
          .select('criado_em, tipo, quantidade, documento, observacao, os_id, custo_unitario, '
              'estoques(nome), produtos(descricao, unidade), cilindros(identificacao, fluido)')
          .order('criado_em', ascending: false)
          .limit(300);
      final idsOs = {for (final m in mov) if (m['os_id'] != null) '${m['os_id']}'}.toList();
      final codigos = <String, String>{};
      if (idsOs.isNotEmpty) {
        final os = await _db.from('ordens_servico').select('id, codigo').inFilter('id', idsOs);
        for (final o in os) {
          codigos['${o['id']}'] = '${o['codigo']}';
        }
      }
      if (mounted) {
        setState(() {
          _estoques = List<Map<String, dynamic>>.from(estoques);
          _saldos = List<Map<String, dynamic>>.from(saldos);
          _cilindros = List<Map<String, dynamic>>.from(cil);
          _movimentos = List<Map<String, dynamic>>.from(mov);
          _codigosOs = codigos;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _avisar(String t, {bool erro = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Cores.erro : null));

  Future<void> _executar(Future<Map<String, dynamic>> Function() f, String ok) async {
    try {
      await f();
      _avisar(ok);
      await _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _criarCarros() => _executar(() => acaoEstoque({'acao': 'criar_carros'}),
      'Pronto: almoxarifado e o estoque do carro de cada equipe.');

  Future<void> _movimento(String tipo) async {
    if (_estoques.isEmpty) {
      await _criarCarros();
      if (_estoques.isEmpty) return;
    }
    if (!mounted) return;
    final p = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoMovimento(tipo: tipo, estoques: _estoques),
    );
    if (p == null) return;
    await _executar(() => acaoEstoque(p), switch (tipo) {
      'entrada' => 'Entrada registrada.',
      'transferir' => 'Transferência registrada.',
      _ => 'Inventário registrado: saldos acertados.',
    });
  }

  Future<void> _minimo(Map<String, dynamic> estoque, Map<String, dynamic> produto, String produtoId, Object? atual) async {
    final c = TextEditingController(text: numeroBr(atual));
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mínimo · ${produto['descricao']}'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Mínimo em ${estoque['nome']}', helperText: 'Vazio = sem mínimo'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Salvar')),
        ],
      ),
    );
    if (r == null) return;
    await _executar(
        () => acaoEstoque({'acao': 'minimo', 'estoque_id': estoque['id'], 'produto_id': produtoId, 'minimo': lerNumero(r)}),
        'Mínimo salvo.');
  }

  Future<void> _novoCilindro() async {
    if (_estoques.isEmpty) await _criarCarros();
    if (!mounted || _estoques.isEmpty) return;
    final p = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoCilindro(estoques: _estoques),
    );
    if (p == null) return;
    await _executar(() => acaoEstoque({'acao': 'cilindro_novo', ...p}), 'Cilindro cadastrado.');
  }

  Future<void> _acaoCilindro(Map<String, dynamic> c, String op) async {
    if (op == 'mover') {
      final destino = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('Levar ${c['identificacao']} para'),
          children: [
            for (final e in _estoques.where((e) => e['id'] != c['estoque_id']))
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, '${e['id']}'), child: Text('${e['nome']}')),
          ],
        ),
      );
      if (destino == null) return;
      await _executar(() => acaoEstoque({'acao': 'cilindro_mover', 'cilindro_id': c['id'], 'estoque_id': destino}),
          'Cilindro movido.');
    } else {
      await _executar(() => acaoEstoque({'acao': 'cilindro_status', 'cilindro_id': c['id'], 'status': op}),
          op == 'devolvido' ? 'Cilindro devolvido.' : 'Cilindro marcado como vazio.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final editar = podeEditarCadastros();
    return DefaultTabController(
      length: 3,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: margemDaTela(context).copyWith(bottom: 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text('Estoque',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              IconButton(tooltip: 'Atualizar', onPressed: _carregando ? null : _carregar, icon: const Icon(Icons.refresh)),
            ]),
            const Text('A peça usada na OS sai sozinha do carro da equipe que atendeu (sem atendimento, do almoxarifado). '
                'O gás adicionado sai do cilindro do carro; o recolhido entra no cilindro de recolhimento.',
                style: TextStyle(color: Cores.neutro)),
            const SizedBox(height: 12),
            if (editar)
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                    onPressed: () => _movimento('entrada'), icon: const Icon(Icons.add), label: const Text('Entrada (compra)')),
                OutlinedButton.icon(
                    onPressed: () => _movimento('transferir'),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Transferir')),
                OutlinedButton.icon(
                    onPressed: () => _movimento('inventario'),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Inventário')),
                OutlinedButton.icon(
                    onPressed: _novoCilindro, icon: const Icon(Icons.propane_tank_outlined), label: const Text('Cilindro')),
                TextButton.icon(
                    onPressed: _criarCarros,
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: const Text('Criar o estoque do carro de cada equipe')),
                TextButton.icon(
                    onPressed: () => context.push('/c/estoques').then((_) => _carregar()),
                    icon: const Icon(Icons.warehouse_outlined),
                    label: const Text('Locais de estoque')),
              ]),
            const SizedBox(height: 8),
            if (_carregando) const LinearProgressIndicator(minHeight: 2),
            if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
            const TabBar(isScrollable: true, tabs: [Tab(text: 'Saldos'), Tab(text: 'Cilindros (gás)'), Tab(text: 'Movimentos')]),
          ]),
        ),
        Expanded(
          child: TabBarView(children: [
            _abaSaldos(editar),
            _abaCilindros(editar),
            _abaMovimentos(),
          ]),
        ),
      ]),
    );
  }

  Widget _abaSaldos(bool editar) {
    // produto -> estoque -> saldo
    final porProduto = <String, Map<String, Map<String, dynamic>>>{};
    final produtos = <String, Map<String, dynamic>>{};
    for (final s in _saldos) {
      final pid = '${s['produto_id']}';
      produtos[pid] = Map<String, dynamic>.from((s['produtos'] as Map?) ?? const {});
      porProduto.putIfAbsent(pid, () => {})['${s['estoque_id']}'] = s;
    }
    bool abaixo(String pid) => porProduto[pid]!.values.any((s) {
          final m = num.tryParse('${s['minimo'] ?? ''}');
          return m != null && (num.tryParse('${s['quantidade']}') ?? 0) < m;
        });
    final b = _busca.toLowerCase();
    final ids = produtos.keys
        .where((pid) => b.isEmpty || '${produtos[pid]!['descricao']} ${produtos[pid]!['codigo'] ?? ''}'.toLowerCase().contains(b))
        .where((pid) => !_soAbaixo || abaixo(pid))
        .toList()
      ..sort((a, c) => '${produtos[a]!['descricao']}'.compareTo('${produtos[c]!['descricao']}'));
    final qtdAbaixo = produtos.keys.where(abaixo).length;
    return ListView(padding: margemDaTela(context), children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 260,
          child: TextField(
            decoration: const InputDecoration(hintText: 'Peça ou código', prefixIcon: Icon(Icons.search, size: 20)),
            onChanged: (v) => setState(() => _busca = v),
          ),
        ),
        FilterChip(
          label: Text('Abaixo do mínimo ($qtdAbaixo)'),
          selected: _soAbaixo,
          onSelected: (v) => setState(() => _soAbaixo = v),
        ),
      ]),
      const SizedBox(height: 12),
      if (_estoques.isEmpty && !_carregando)
        const Text('Nenhum estoque ainda: toque em "Criar o estoque do carro de cada equipe" (o almoxarifado vem junto).',
            style: TextStyle(color: Cores.neutro))
      else if (ids.isEmpty && !_carregando)
        const Text('Nenhuma peça com saldo. Registre uma entrada (compra) ou um inventário.',
            style: TextStyle(color: Cores.neutro))
      else
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 40,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 44,
            columns: [
              const DataColumn(label: Text('Peça')),
              for (final e in _estoques) DataColumn(label: Text('${e['nome']}'), numeric: true),
              const DataColumn(label: Text('Total'), numeric: true),
            ],
            rows: [
              for (final pid in ids)
                DataRow(cells: [
                  DataCell(Text('${produtos[pid]!['descricao']}', overflow: TextOverflow.ellipsis)),
                  for (final e in _estoques) _celula(e, pid, produtos[pid]!, editar),
                  DataCell(Text(
                      '${numeroBr(porProduto[pid]!.values.fold<num>(0, (t, s) => t + (num.tryParse('${s['quantidade']}') ?? 0)))} '
                      '${produtos[pid]!['unidade'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
            ],
          ),
        ),
      if (editar && ids.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Toque num saldo para definir o mínimo daquele estoque.', style: TextStyle(color: Cores.neutro, fontSize: 12)),
        ),
    ]);
  }

  DataCell _celula(Map<String, dynamic> e, String pid, Map<String, dynamic> produto, bool editar) {
    final s = _saldos.where((x) => x['estoque_id'] == e['id'] && x['produto_id'] == pid).firstOrNull;
    final q = num.tryParse('${s?['quantidade'] ?? ''}');
    final m = num.tryParse('${s?['minimo'] ?? ''}');
    final baixo = m != null && (q ?? 0) < m;
    return DataCell(
      Text(
        q == null ? '—' : '${numeroBr(q)}${m != null ? ' / mín. ${numeroBr(m)}' : ''}',
        style: TextStyle(color: baixo ? Cores.erro : (q != null && q < 0 ? Cores.alerta : null),
            fontWeight: baixo ? FontWeight.w700 : null),
      ),
      onTap: editar ? () => _minimo(e, produto, pid, s?['minimo']) : null,
    );
  }

  Widget _abaCilindros(bool editar) {
    if (!_carregando && _cilindros.isEmpty) {
      return Padding(
        padding: margemDaTela(context),
        child: const Text('Nenhum cilindro. Toque em "Cilindro" para cadastrar o gás (kg) que está no carro ou no '
            'almoxarifado, e um cilindro de recolhimento se a equipe recolhe gás.',
            style: TextStyle(color: Cores.neutro)),
      );
    }
    return ListView(padding: margemDaTela(context), children: [
      for (final c in _cilindros)
        Card(
          child: ListTile(
            leading: Icon(c['tipo'] == 'recolhimento' ? Icons.recycling : Icons.propane_tank_outlined),
            title: Text('${c['identificacao']} · ${c['fluido']}${c['tipo'] == 'recolhimento' ? ' (recolhimento)' : ''}'),
            subtitle: Text('${(c['estoques'] as Map?)?['nome'] ?? ''} · '
                '${numeroBr(c['saldo_kg'])} de ${numeroBr(c['capacidade_kg'])} kg'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _chip(c['status'] as String?),
              if (editar && c['status'] != 'devolvido')
                PopupMenuButton<String>(
                  tooltip: 'Ações',
                  onSelected: (op) => _acaoCilindro(c, op),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'mover', child: Text('Levar para outro estoque')),
                    if (c['status'] != 'vazio') const PopupMenuItem(value: 'vazio', child: Text('Marcar como vazio')),
                    const PopupMenuItem(value: 'devolvido', child: Text('Devolvido ao fornecedor')),
                  ],
                ),
            ]),
          ),
        ),
    ]);
  }

  Widget _chip(String? s) {
    final r = _statusCil[s];
    if (r == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: r.cor.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
      child: Text(r.texto, style: TextStyle(color: r.cor, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  Widget _abaMovimentos() {
    if (!_carregando && _movimentos.isEmpty) {
      return Padding(
        padding: margemDaTela(context),
        child: const Text('Nenhum movimento ainda.', style: TextStyle(color: Cores.neutro)),
      );
    }
    return ListView(padding: margemDaTela(context), children: [
      for (final m in _movimentos) _linhaMov(m),
    ]);
  }

  Widget _linhaMov(Map<String, dynamic> m) {
    final q = num.tryParse('${m['quantidade']}') ?? 0;
    final prod = m['produtos'] as Map?;
    final cil = m['cilindros'] as Map?;
    final oque = prod != null ? '${prod['descricao']}' : '${cil?['identificacao'] ?? ''} · ${cil?['fluido'] ?? ''}';
    final un = prod != null ? '${prod['unidade'] ?? ''}' : 'kg';
    final os = _codigosOs['${m['os_id']}'];
    return ListTile(
      dense: true,
      leading: Icon(q > 0 ? Icons.south_west : Icons.north_east, color: q > 0 ? Cores.sucesso : Cores.alerta, size: 20),
      title: Text('$oque · ${q > 0 ? '+' : ''}${numeroBr(q)} $un'),
      subtitle: Text([
        dataHoraBr(m['criado_em']),
        _tiposMov[m['tipo']] ?? '${m['tipo']}',
        '${(m['estoques'] as Map?)?['nome'] ?? ''}',
        if (os != null) os,
        if (m['documento'] != null) '${m['documento']}',
        if (m['observacao'] != null) '${m['observacao']}',
      ].where((x) => x.isNotEmpty).join(' · ')),
      onTap: m['os_id'] == null ? null : () => context.push('/os/${m['os_id']}'),
    );
  }
}

// ---------------------------------------------------------------------------
// Entrada, transferência e inventário: estoque(s) e a lista de peças.
// ---------------------------------------------------------------------------
class _Linha {
  String? produtoId;
  String rotulo = '';
  final qtd = TextEditingController();
  final custo = TextEditingController();
}

class _DialogoMovimento extends StatefulWidget {
  const _DialogoMovimento({required this.tipo, required this.estoques});

  final String tipo; // entrada | transferir | inventario
  final List<Map<String, dynamic>> estoques;

  @override
  State<_DialogoMovimento> createState() => _DialogoMovimentoState();
}

class _DialogoMovimentoState extends State<_DialogoMovimento> {
  late String _estoque;
  String? _para;
  final _linhas = <_Linha>[_Linha()];
  final _doc = TextEditingController();
  List<Map<String, dynamic>> _produtos = [];
  String? _erro;

  @override
  void initState() {
    super.initState();
    _estoque = '${widget.estoques.first['id']}';
    final outros = widget.estoques.where((e) => '${e['id']}' != _estoque);
    _para = outros.isEmpty ? null : '${outros.first['id']}';
    _db
        .from('produtos')
        .select('id, descricao, codigo, unidade')
        .eq('tipo', 'produto')
        .eq('ativo', true)
        .isFilter('excluido_em', null)
        .order('descricao', ascending: true)
        .limit(3000)
        .then((r) {
      if (mounted) setState(() => _produtos = List<Map<String, dynamic>>.from(r));
    });
  }

  String get _titulo => switch (widget.tipo) {
        'entrada' => 'Entrada (compra)',
        'transferir' => 'Transferir entre estoques',
        _ => 'Inventário (contagem)',
      };

  Widget _escolhaEstoque(String rotulo, String? valor, ValueChanged<String?> mudou, {String? sem}) => InputDecorator(
        decoration: InputDecoration(labelText: rotulo),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: valor,
            isDense: true,
            isExpanded: true,
            items: [
              for (final e in widget.estoques.where((e) => '${e['id']}' != sem))
                DropdownMenuItem(value: '${e['id']}', child: Text('${e['nome']}')),
            ],
            onChanged: mudou,
          ),
        ),
      );

  void _confirmar() {
    final itens = <Map<String, dynamic>>[];
    for (final l in _linhas) {
      if (l.produtoId == null) continue;
      final q = lerNumero(l.qtd.text);
      if (q == null || (widget.tipo != 'inventario' && q <= 0) || q < 0) {
        setState(() => _erro = 'Confira a quantidade de "${l.rotulo}".');
        return;
      }
      itens.add({
        'produto_id': l.produtoId,
        if (widget.tipo == 'inventario') 'contado': q else 'quantidade': q,
        if (widget.tipo == 'entrada' && lerNumero(l.custo.text) != null) 'custo_unitario': lerNumero(l.custo.text),
      });
    }
    if (itens.isEmpty) {
      setState(() => _erro = 'Escolha ao menos uma peça.');
      return;
    }
    if (widget.tipo == 'transferir' && _para == null) {
      setState(() => _erro = 'Escolha o estoque de destino.');
      return;
    }
    Navigator.pop(context, {
      'acao': widget.tipo,
      'estoque_id': _estoque,
      if (widget.tipo == 'transferir') 'para_estoque_id': _para,
      if (widget.tipo == 'entrada' && _doc.text.trim().isNotEmpty) 'documento': _doc.text.trim(),
      'itens': itens,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_titulo),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _escolhaEstoque(widget.tipo == 'transferir' ? 'De' : 'Estoque', _estoque, (v) {
              setState(() {
                _estoque = v ?? _estoque;
                if (_para == _estoque) {
                  final outros = widget.estoques.where((e) => '${e['id']}' != _estoque);
                  _para = outros.isEmpty ? null : '${outros.first['id']}';
                }
              });
            }),
            if (widget.tipo == 'transferir') ...[
              const SizedBox(height: 12),
              _escolhaEstoque('Para', _para, (v) => setState(() => _para = v), sem: _estoque),
            ],
            if (widget.tipo == 'entrada') ...[
              const SizedBox(height: 12),
              TextField(controller: _doc, decoration: const InputDecoration(labelText: 'Nota fiscal ou fornecedor (opcional)')),
            ],
            if (widget.tipo == 'inventario')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Informe quanto foi contado: o saldo é acertado para esse número.',
                    style: TextStyle(color: Cores.neutro)),
              ),
            const SizedBox(height: 12),
            for (final l in _linhas)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    flex: 5,
                    child: Autocomplete<Map<String, dynamic>>(
                      displayStringForOption: (p) => '${p['descricao']}',
                      optionsBuilder: (v) {
                        final t = v.text.trim().toLowerCase();
                        if (t.isEmpty) return const Iterable<Map<String, dynamic>>.empty();
                        return _produtos
                            .where((p) => '${p['descricao']} ${p['codigo'] ?? ''}'.toLowerCase().contains(t))
                            .take(30);
                      },
                      onSelected: (p) => setState(() {
                        l.produtoId = '${p['id']}';
                        l.rotulo = '${p['descricao']}';
                      }),
                      fieldViewBuilder: (context, ctrl, foco, aoEnviar) => TextField(
                        controller: ctrl,
                        focusNode: foco,
                        decoration: InputDecoration(
                          labelText: 'Peça',
                          suffixIcon: l.produtoId == null ? null : const Icon(Icons.check, color: Cores.sucesso, size: 18),
                        ),
                        onChanged: (_) {
                          if (l.produtoId != null) setState(() => l.produtoId = null);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: l.qtd,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: widget.tipo == 'inventario' ? 'Contado' : 'Quantidade'),
                    ),
                  ),
                  if (widget.tipo == 'entrada') ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: l.custo,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Custo un. (R\$)'),
                      ),
                    ),
                  ],
                  IconButton(
                    tooltip: 'Tirar',
                    onPressed: _linhas.length == 1 ? null : () => setState(() => _linhas.remove(l)),
                    icon: const Icon(Icons.close),
                  ),
                ]),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _linhas.add(_Linha())),
                icon: const Icon(Icons.add),
                label: const Text('Outra peça'),
              ),
            ),
            if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _confirmar, child: const Text('Registrar')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cilindro novo
// ---------------------------------------------------------------------------
class _DialogoCilindro extends StatefulWidget {
  const _DialogoCilindro({required this.estoques});

  final List<Map<String, dynamic>> estoques;

  @override
  State<_DialogoCilindro> createState() => _DialogoCilindroState();
}

class _DialogoCilindroState extends State<_DialogoCilindro> {
  final _ident = TextEditingController();
  final _fluido = TextEditingController(text: 'R-410A');
  final _cap = TextEditingController(text: '11,3');
  final _doc = TextEditingController();
  final _custo = TextEditingController();
  String _tipo = 'gas';
  late String _estoque = '${widget.estoques.first['id']}';
  String? _erro;

  void _ok() {
    final cap = lerNumero(_cap.text);
    if (_fluido.text.trim().isEmpty || cap == null || cap <= 0) {
      setState(() => _erro = 'Informe o fluido e a capacidade em kg.');
      return;
    }
    Navigator.pop(context, {
      'identificacao': _ident.text.trim(),
      'fluido': _fluido.text.trim(),
      'tipo': _tipo,
      'capacidade_kg': cap,
      'estoque_id': _estoque,
      if (_doc.text.trim().isNotEmpty) 'documento': _doc.text.trim(),
      if (lerNumero(_custo.text) != null) 'custo_kg': lerNumero(_custo.text),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cilindro'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'gas', label: Text('Gás (cheio)')),
                ButtonSegment(value: 'recolhimento', label: Text('Recolhimento')),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => setState(() => _tipo = s.first),
            ),
            const SizedBox(height: 12),
            TextField(controller: _fluido, decoration: const InputDecoration(labelText: 'Fluido *', hintText: 'R-410A, R-32, R-22...')),
            TextField(
              controller: _cap,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Capacidade (kg) *'),
            ),
            TextField(controller: _ident, decoration: const InputDecoration(labelText: 'Identificação', hintText: 'Ex.: nº do lote ou do cilindro')),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Onde está'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _estoque,
                  isDense: true,
                  isExpanded: true,
                  items: [
                    for (final e in widget.estoques) DropdownMenuItem(value: '${e['id']}', child: Text('${e['nome']}')),
                  ],
                  onChanged: (v) => setState(() => _estoque = v ?? _estoque),
                ),
              ),
            ),
            if (_tipo == 'gas') ...[
              TextField(controller: _doc, decoration: const InputDecoration(labelText: 'Nota fiscal (opcional)')),
              TextField(
                controller: _custo,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Custo por kg (R\$, opcional)'),
              ),
            ],
            if (_erro != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_erro!, style: const TextStyle(color: Cores.erro)),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _ok, child: const Text('Cadastrar')),
      ],
    );
  }
}
