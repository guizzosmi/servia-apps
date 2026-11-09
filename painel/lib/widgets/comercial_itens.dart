import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/comercial.dart';

/// Itens da proposta (guia 97): serviços e produtos da oportunidade, avulsos ou mensais (contrato, PMOC).
/// Com itens, o valor e o valor mensal da oportunidade passam a ser a soma (o banco recalcula).
/// [aoSalvar] avisa a tela para recarregar os valores.
class ItensProposta extends StatefulWidget {
  const ItensProposta({super.key, required this.oportunidadeId, required this.aoSalvar});

  final String oportunidadeId;
  final VoidCallback aoSalvar;

  @override
  State<ItensProposta> createState() => _ItensPropostaState();
}

class _Linha {
  _Linha({this.id, this.produtoId, String descricao = '', num quantidade = 1, num valor = 0, num desconto = 0, this.recorrente = false})
      : descricao = TextEditingController(text: descricao),
        quantidade = TextEditingController(text: _texto(quantidade)),
        valor = TextEditingController(text: _texto(valor)),
        desconto = TextEditingController(text: desconto == 0 ? '' : _texto(desconto));

  final String? id;
  final String? produtoId;
  final TextEditingController descricao;
  final TextEditingController quantidade;
  final TextEditingController valor;
  final TextEditingController desconto;
  bool recorrente;

  static String _texto(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2).replaceAll('.', ',');
  static num _ler(TextEditingController c) => num.tryParse(c.text.trim().replaceAll('.', '').replaceAll(',', '.')) ?? 0;

  num get total => _ler(quantidade) * _ler(valor) - _ler(desconto);

  Map<String, dynamic> paraBanco() => {
        'id': id,
        'produto_id': produtoId,
        'descricao': descricao.text.trim(),
        'quantidade': _ler(quantidade) <= 0 ? 1 : _ler(quantidade),
        'valor_unitario': _ler(valor),
        'desconto': _ler(desconto),
        'recorrente': recorrente,
      };

  void dispose() {
    for (final c in [descricao, quantidade, valor, desconto]) {
      c.dispose();
    }
  }
}

class _ItensPropostaState extends State<ItensProposta> {
  final List<_Linha> _linhas = [];
  bool _carregando = true;
  bool _mudou = false;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final l in _linhas) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final r = await Supabase.instance.client
          .from('com_itens')
          .select('id, produto_id, descricao, quantidade, valor_unitario, desconto, recorrente')
          .eq('oportunidade_id', widget.oportunidadeId)
          .isFilter('excluido_em', null)
          .order('ordem');
      if (!mounted) return;
      final antigas = List<_Linha>.of(_linhas);
      setState(() {
        _linhas
          ..clear()
          ..addAll(listaDeMapas(r).map((i) => _Linha(
                id: i['id'] as String?,
                produtoId: i['produto_id'] as String?,
                descricao: '${i['descricao'] ?? ''}',
                quantidade: num.tryParse('${i['quantidade']}') ?? 1,
                valor: num.tryParse('${i['valor_unitario']}') ?? 0,
                desconto: num.tryParse('${i['desconto']}') ?? 0,
                recorrente: i['recorrente'] == true,
              )));
        _mudou = false;
      });
      // Os campos antigos saem da tela neste quadro: libera depois.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final l in antigas) {
          l.dispose();
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagemDeErro(e)), backgroundColor: Cores.erro));
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _doCadastro() async {
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _EscolherProduto());
    if (p == null) return;
    setState(() {
      _linhas.add(_Linha(
        produtoId: p['id'] as String?,
        descricao: '${p['descricao'] ?? ''}',
        valor: num.tryParse('${p['preco_venda'] ?? 0}') ?? 0,
      ));
      _mudou = true;
    });
  }

  Future<void> _salvar() async {
    if (_linhas.any((l) => l.descricao.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Todo item precisa de descrição.'), backgroundColor: Cores.erro));
      return;
    }
    if (_linhas.any((l) => l.total < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('O desconto é maior que o item.'), backgroundColor: Cores.erro));
      return;
    }
    setState(() => _salvando = true);
    try {
      await acaoComercial({
        'acao': 'itens_salvar',
        'oportunidade_id': widget.oportunidadeId,
        'itens': [for (final l in _linhas) l.paraBanco()],
      });
      await _carregar();
      widget.aoSalvar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagemDeErro(e)), backgroundColor: Cores.erro));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avulso = _linhas.where((l) => !l.recorrente).fold<num>(0, (s, l) => s + l.total);
    final mensal = _linhas.where((l) => l.recorrente).fold<num>(0, (s, l) => s + l.total);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: Text('Itens da proposta', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            TextButton.icon(onPressed: _doCadastro, icon: const Icon(Icons.inventory_2_outlined), label: const Text('Do cadastro')),
            TextButton.icon(
              onPressed: () => setState(() {
                _linhas.add(_Linha());
                _mudou = true;
              }),
              icon: const Icon(Icons.add),
              label: const Text('Item'),
            ),
          ]),
          if (_carregando) const LinearProgressIndicator(minHeight: 2),
          if (!_carregando && _linhas.isEmpty)
            const Text('Sem itens: vale o valor digitado. Com itens, o valor e o mensal são a soma deles.',
                style: TextStyle(color: Cores.neutro)),
          for (final l in _linhas)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: l.descricao,
                  decoration: const InputDecoration(labelText: 'Descrição', isDense: true),
                  onChanged: (_) => setState(() => _mudou = true),
                ),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: l.quantidade,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Qtd', isDense: true),
                      onChanged: (_) => setState(() => _mudou = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: l.valor,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Valor', prefixText: 'R\$ ', isDense: true),
                      onChanged: (_) => setState(() => _mudou = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: l.desconto,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Desconto', isDense: true),
                      onChanged: (_) => setState(() => _mudou = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Mensal (contrato, PMOC)',
                    child: FilterChip(
                      label: const Text('Mensal'),
                      selected: l.recorrente,
                      onSelected: (v) => setState(() {
                        l.recorrente = v;
                        _mudou = true;
                      }),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tirar',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _linhas.remove(l);
                        _mudou = true;
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) => l.dispose());
                    },
                  ),
                ]),
              ]),
            ),
          if (_linhas.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              [if (avulso != 0) 'Avulso ${reais(avulso)}', if (mensal != 0) 'Mensal ${reais(mensal)}/mês'].join(' · '),
              style: const TextStyle(fontWeight: FontWeight.w700, color: Cores.indigo700),
            ),
          ],
          if (_mudou) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _salvando ? null : _salvar,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar itens'),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Busca no cadastro de produtos e serviços.
class _EscolherProduto extends StatefulWidget {
  const _EscolherProduto();

  @override
  State<_EscolherProduto> createState() => _EscolherProdutoState();
}

class _EscolherProdutoState extends State<_EscolherProduto> {
  final _busca = TextEditingController();
  List<Map<String, dynamic>> _lista = [];

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final t = _busca.text.trim().replaceAll(RegExp(r'[%,()]'), ' ');
    var q = Supabase.instance.client.from('produtos').select('id, codigo, descricao, tipo, preco_venda').isFilter('excluido_em', null).eq('ativo', true);
    if (t.isNotEmpty) q = q.or('descricao.ilike.%$t%,codigo.ilike.%$t%');
    try {
      final r = await q.order('descricao').limit(30);
      if (mounted) setState(() => _lista = listaDeMapas(r));
    } catch (_) {
      if (mounted) setState(() => _lista = []);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Produto ou serviço do cadastro'),
        content: SizedBox(
          width: 460,
          height: 420,
          child: Column(children: [
            TextField(
              controller: _busca,
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar'),
              onSubmitted: (_) => _buscar(),
            ),
            Expanded(
              child: ListView(children: [
                for (final p in _lista)
                  ListTile(
                    dense: true,
                    title: Text('${p['descricao']}'),
                    subtitle: Text('${p['codigo'] ?? ''} · ${p['tipo'] ?? ''}'),
                    trailing: Text(reais(p['preco_venda'])),
                    onTap: () => Navigator.of(context).pop(p),
                  ),
                if (_lista.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nada encontrado.', style: TextStyle(color: Cores.neutro))),
              ]),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar'))],
      );
}
