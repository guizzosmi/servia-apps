import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/status.dart';

String dinheiro(Object? v) => 'R\$ ${(num.tryParse('${v ?? 0}') ?? 0).toStringAsFixed(2).replaceAll('.', ',')}';

/// 2 -> "2"; 2.5 -> "2,5"
String numeroBr(Object? v) {
  final n = num.tryParse('${v ?? ''}');
  if (n == null) return '';
  return (n == n.roundToDouble() ? n.toInt().toString() : n.toString()).replaceAll('.', ',');
}

/// "5,50" -> 5.5 (vazio ou inválido = null)
num? lerNumero(String texto) => num.tryParse(texto.trim().replaceAll(',', '.'));

/// Peças e serviços da OS: os do campo (app) e os do gestor. O gestor
/// inclui, muda quantidade, preço e desconto, e exclui.
class ItensDaOs extends StatefulWidget {
  const ItensDaOs({super.key, required this.osId, required this.editavel, this.versao = 0, this.aoMudar});

  final String osId;
  final bool editavel;

  /// Muda quando a tela da OS recarrega: recarrega sem piscar.
  final int versao;
  final VoidCallback? aoMudar;

  @override
  State<ItensDaOs> createState() => _ItensDaOsState();
}

class _ItensDaOsState extends State<ItensDaOs> {
  SupabaseClient get _db => Supabase.instance.client;

  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;
  List<Map<String, dynamic>> _itens = [];
  List<Map<String, dynamic>> _equipamentos = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(ItensDaOs antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.versao != widget.versao) _carregar();
  }

  /// Só a resposta do pedido mais recente vale (duas recargas seguidas).
  int _pedido = 0;

  Future<void> _carregar() async {
    final meu = ++_pedido;
    try {
      final r = await Future.wait<List<Map<String, dynamic>>>([
        _db
            .from('os_itens')
            .select('*, equipamentos(codigo), atendimentos(partes_itens(data, partes_diarias(equipes(nome))))')
            .eq('os_id', widget.osId)
            .isFilter('excluido_em', null)
            .order('criado_em', ascending: true),
        _db
            .from('os_equipamentos')
            .select('equipamento_id, equipamentos(codigo, descricao)')
            .eq('os_id', widget.osId)
            .isFilter('excluido_em', null),
      ]);
      if (!mounted || meu != _pedido) return;
      setState(() {
        _erro = null;
        _itens = r[0];
        _equipamentos = r[1];
      });
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _avisar(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));
  }

  Future<void> _executar(Map<String, dynamic> p, String sucesso) async {
    if (!mounted) return;
    setState(() => _ocupado = true);
    try {
      await acaoAtendimento(p);
      _avisar(sucesso);
      widget.aoMudar?.call();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _editar([Map<String, dynamic>? item]) async {
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoItem(item: item, equipamentos: _equipamentos),
    );
    if (r == null) return;
    await _executar({
      'acao': 'item_salvar',
      'os_id': widget.osId,
      if (item != null) 'item_id': item['id'],
      ...r,
    }, item == null ? 'Item incluído.' : 'Item salvo.');
  }

  Future<void> _excluir(Map<String, dynamic> item) async {
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir item'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${item['descricao']} · ${dinheiro(item['total'])}'),
            const SizedBox(height: 12),
            TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo (opcional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Cores.erro),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    final texto = motivo.text.trim();
    // O diálogo ainda anima a saída usando o campo: libera depois.
    Future.delayed(const Duration(seconds: 1), motivo.dispose);
    if (ok != true) return;
    await _executar({'acao': 'item_excluir', 'item_id': item['id'], 'motivo': texto}, 'Item excluído.');
  }

  String _origem(Map<String, dynamic> i) {
    final item = (i['atendimentos'] as Map?)?['partes_itens'] as Map?;
    if (item == null) return 'Painel';
    final equipe = ((item['partes_diarias'] as Map?)?['equipes'] as Map?)?['nome'];
    return [equipe, dataBr(item['data'])].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const LinearProgressIndicator(minHeight: 2);
    if (_erro != null) return Text(_erro!, style: const TextStyle(color: Cores.erro));
    final total = _itens.fold<num>(0, (s, i) => s + (num.tryParse('${i['total']}') ?? 0));
    const cabecalho = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Cores.neutro);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_itens.isEmpty)
        const Text('Nenhuma peça ou serviço lançado.', style: TextStyle(color: Cores.neutro))
      else
        Table(
          columnWidths: const {
            0: FlexColumnWidth(4),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(1.2),
            3: FlexColumnWidth(1.6),
            4: FlexColumnWidth(1.4),
            5: FlexColumnWidth(1.6),
            6: FixedColumnWidth(100),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            const TableRow(children: [
              Text('DESCRIÇÃO', style: cabecalho),
              Text('ORIGEM', style: cabecalho),
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
                          i['tipo'] == 'servico' ? 'Serviço' : 'Peça',
                          if (i['produto_id'] == null) 'sem cadastro',
                          if ((i['equipamentos'] as Map?)?['codigo'] != null) 'equip. ${(i['equipamentos'] as Map)['codigo']}',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12, color: Cores.neutro),
                      ),
                    ]),
                  ),
                  Text(_origem(i), style: const TextStyle(fontSize: 13)),
                  Text('${numeroBr(i['quantidade'])} ${i['unidade'] ?? ''}'),
                  Text(
                    (num.tryParse('${i['preco_unitario']}') ?? 0) == 0 ? 'sem preço' : dinheiro(i['preco_unitario']),
                    style: TextStyle(
                        color: (num.tryParse('${i['preco_unitario']}') ?? 0) == 0 ? Cores.alerta : null,
                        fontWeight: (num.tryParse('${i['preco_unitario']}') ?? 0) == 0 ? FontWeight.w700 : null),
                  ),
                  Text((num.tryParse('${i['desconto']}') ?? 0) == 0 ? '—' : dinheiro(i['desconto'])),
                  Text(dinheiro(i['total']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (widget.editavel)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Editar',
                        visualDensity: VisualDensity.compact,
                        onPressed: _ocupado ? null : () => _editar(i),
                        icon: const Icon(Icons.edit_outlined, size: 20),
                      ),
                      IconButton(
                        tooltip: 'Excluir',
                        visualDensity: VisualDensity.compact,
                        onPressed: _ocupado ? null : () => _excluir(i),
                        icon: const Icon(Icons.delete_outline, size: 20, color: Cores.erro),
                      ),
                    ])
                  else
                    const SizedBox(),
                ],
              ),
          ],
        ),
      const SizedBox(height: 8),
      Row(children: [
        if (widget.editavel)
          TextButton.icon(
            onPressed: _ocupado ? null : () => _editar(),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar peça ou serviço'),
          ),
        const Spacer(),
        Text('Total: ${dinheiro(total)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ]),
    ]);
  }
}

/// Incluir ou editar um item. Devolve os campos para item_salvar.
class _DialogoItem extends StatefulWidget {
  const _DialogoItem({this.item, required this.equipamentos});

  final Map<String, dynamic>? item;
  final List<Map<String, dynamic>> equipamentos;

  @override
  State<_DialogoItem> createState() => _DialogoItemState();
}

class _DialogoItemState extends State<_DialogoItem> {
  final _chave = GlobalKey<FormState>();
  late final _descricao = TextEditingController(text: '${widget.item?['descricao'] ?? ''}');
  late final _quantidade = TextEditingController(text: numeroBr(widget.item?['quantidade'] ?? 1));
  late final _unidade = TextEditingController(text: '${widget.item?['unidade'] ?? 'un'}');
  late final _preco = TextEditingController(
      text: widget.item == null ? '' : (num.tryParse('${widget.item!['preco_unitario']}') ?? 0).toStringAsFixed(2).replaceAll('.', ','));
  late final _desconto = TextEditingController(
      text: (num.tryParse('${widget.item?['desconto'] ?? 0}') ?? 0) == 0
          ? ''
          : (num.tryParse('${widget.item!['desconto']}') ?? 0).toStringAsFixed(2).replaceAll('.', ','));
  late String _tipo = '${widget.item?['tipo'] ?? 'produto'}';
  // Equipamento que saiu da OS: o item fica sem (é o que a tela mostra).
  late String? _equipamento = _equipamentoInicial();

  String? _equipamentoInicial() {
    final atual = widget.item == null ? null : widget.item!['equipamento_id'] as String?;
    return widget.equipamentos.any((e) => e['equipamento_id'] == atual) ? atual : null;
  }

  /// Produto do cadastro escolhido (null = item sem cadastro).
  late Map<String, dynamic>? _produto = widget.item?['produto_id'] == null
      ? null
      : {'id': widget.item!['produto_id'], 'descricao': widget.item!['descricao']};
  List<Map<String, dynamic>> _produtos = [];

  @override
  void initState() {
    super.initState();
    _carregarProdutos();
  }

  Future<void> _carregarProdutos() async {
    try {
      final r = await Supabase.instance.client
          .from('produtos')
          .select('id, codigo, descricao, tipo, unidade, preco_venda')
          .eq('ativo', true)
          .isFilter('excluido_em', null)
          .order('descricao')
          .limit(2000);
      if (mounted) setState(() => _produtos = r);
    } catch (_) {
      // Sem a lista, o item entra sem cadastro.
    }
  }

  @override
  void dispose() {
    _descricao.dispose();
    _quantidade.dispose();
    _unidade.dispose();
    _preco.dispose();
    _desconto.dispose();
    super.dispose();
  }

  void _escolher(Map<String, dynamic> p) {
    setState(() {
      _produto = p;
      _descricao.text = '${p['descricao']}';
      _tipo = '${p['tipo'] ?? 'produto'}';
      _unidade.text = '${p['unidade'] ?? 'un'}';
      _preco.text = (num.tryParse('${p['preco_venda']}') ?? 0).toStringAsFixed(2).replaceAll('.', ',');
    });
  }

  String _rotulo(Map<String, dynamic> p) =>
      [p['codigo'], p['descricao']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');

  num get _total {
    final q = lerNumero(_quantidade.text) ?? 0, p = lerNumero(_preco.text) ?? 0, d = lerNumero(_desconto.text) ?? 0;
    return (q * p * 100).round() / 100 - d;
  }

  String? _numeroValido(String? v, {bool obrigatorio = false, bool positivo = false}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return obrigatorio ? 'Obrigatório' : null;
    final n = lerNumero(t);
    if (n == null) return 'Número inválido';
    if (positivo ? n <= 0 : n < 0) return positivo ? 'Maior que zero' : 'Não pode ser negativo';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Adicionar peça ou serviço' : 'Editar item'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _chave,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Autocomplete<Map<String, dynamic>>(
                initialValue: TextEditingValue(text: _descricao.text),
                displayStringForOption: (p) => '${p['descricao']}',
                optionsBuilder: (v) {
                  final b = v.text.trim().toLowerCase();
                  if (b.isEmpty) return const Iterable.empty();
                  return _produtos.where((p) => _rotulo(p).toLowerCase().contains(b)).take(30);
                },
                optionsViewBuilder: (context, escolher, opcoes) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 280),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final p in opcoes)
                            ListTile(
                              dense: true,
                              title: Text(_rotulo(p)),
                              trailing: Text(dinheiro(p['preco_venda'])),
                              onTap: () => escolher(p),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                onSelected: _escolher,
                fieldViewBuilder: (context, texto, foco, enviar) => TextFormField(
                  controller: texto,
                  focusNode: foco,
                  onFieldSubmitted: (_) => enviar(),
                  autofocus: widget.item == null,
                  decoration: InputDecoration(
                    labelText: 'Produto ou serviço',
                    helperText: _produto == null ? 'Sem cadastro: digite a descrição' : 'Do cadastro',
                    prefixIcon: Icon(_produto == null ? Icons.edit_note : Icons.inventory_2_outlined),
                  ),
                  onChanged: (t) {
                    _descricao.text = t;
                    // Mudou o texto do produto escolhido: vira item sem cadastro.
                    if (_produto != null && t.trim() != '${_produto!['descricao']}') setState(() => _produto = null);
                  },
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Obrigatório' : null,
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _tipo,
                        isDense: true,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'produto', child: Text('Peça / produto')),
                          DropdownMenuItem(value: 'servico', child: Text('Serviço')),
                        ],
                        onChanged: _produto != null ? null : (v) => setState(() => _tipo = v ?? _tipo),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _quantidade,
                    decoration: const InputDecoration(labelText: 'Quantidade'),
                    validator: (v) => _numeroValido(v, obrigatorio: true, positivo: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    controller: _unidade,
                    enabled: _produto == null,
                    decoration: const InputDecoration(labelText: 'Unidade'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _preco,
                    decoration: const InputDecoration(labelText: 'Preço unitário (R\$)'),
                    validator: (v) => _numeroValido(v, obrigatorio: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _desconto,
                    decoration: const InputDecoration(labelText: 'Desconto (R\$)'),
                    validator: (v) {
                      final e = _numeroValido(v);
                      if (e != null) return e;
                      return _total < 0 ? 'Maior que o valor' : null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Equipamento (opcional)'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _equipamento,
                    isDense: true,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Nenhum (item da OS)')),
                      for (final e in widget.equipamentos)
                        DropdownMenuItem<String?>(
                          value: e['equipamento_id'] as String,
                          child: Text([(e['equipamentos'] as Map?)?['codigo'], (e['equipamentos'] as Map?)?['descricao']]
                              .where((x) => x != null)
                              .join(' · ')),
                        ),
                    ],
                    onChanged: (v) => setState(() => _equipamento = v),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: Text('Total do item: ${dinheiro(_total < 0 ? 0 : _total)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
        FilledButton(
          onPressed: () {
            if (!_chave.currentState!.validate()) return;
            Navigator.of(context).pop(<String, dynamic>{
              'produto_id': _produto?['id'] ?? '',
              'descricao': _descricao.text.trim(),
              'tipo': _tipo,
              'quantidade': _quantidade.text.trim(),
              'unidade': _unidade.text.trim(),
              'preco_unitario': _preco.text.trim(),
              'desconto': _desconto.text.trim().isEmpty ? '0' : _desconto.text.trim(),
              'equipamento_id': _equipamento ?? '',
            });
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
