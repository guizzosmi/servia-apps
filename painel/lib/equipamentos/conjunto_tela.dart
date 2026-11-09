import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/comercial.dart' show reais;
import '../servicos/etiquetas_pdf.dart';
import '../widgets/itens_os.dart' show lerNumero, numeroBr;
import '../widgets/margem.dart';
import 'servico.dart';
import 'widgets.dart';

/// Conjunto do equipamento (guia 102): componentes com código e QR próprios (equipamentos com "pai") e itens por
/// quantidade, comparados com o padrão do modelo. Componente de conjunto não sai sozinho: vai junto com o conjunto.
class EqpConjuntoTela extends StatefulWidget {
  const EqpConjuntoTela({super.key, required this.id});

  /// Equipamento (núcleo) do conjunto ou de um componente dele.
  final String id;

  @override
  State<EqpConjuntoTela> createState() => _EqpConjuntoTelaState();
}

class _EqpConjuntoTelaState extends State<EqpConjuntoTela> {
  Map<String, dynamic>? _d;
  List<Map<String, dynamic>> _modelos = [];
  String? _erro;
  bool _ocupado = false;

  bool get _gestor => Sessao.atual?.tem(Papel.gestor) ?? false;
  Map<String, dynamic> get _e => Map<String, dynamic>.from((_d?['equipamento'] as Map?) ?? const {});
  String get _id => '${_e['equipamento_id'] ?? widget.id}';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final d = await eqp('eqp_conjunto', {'equipamento_id': widget.id});
      final m = await eqp('eqp_modelos_lista', {});
      if (mounted) {
        setState(() {
          _d = d;
          _modelos = listaDe(m['modelos']);
          _erro = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    }
  }

  Future<void> _rodar(String funcao, Map<String, dynamic> p, String ok) async {
    if (!mounted) return;
    setState(() => _ocupado = true);
    try {
      await eqp(funcao, p);
      if (mounted) avisarEqp(context, ok);
      await _carregar();
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _escolherModelo() async {
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Modelo do equipamento'),
        children: [
          if (_modelos.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Cadastre um modelo em Equipamentos › Modelos.')),
          for (final m in _modelos)
            SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop('${m['modelo_id']}'), child: Text('${m['nome']}')),
        ],
      ),
    );
    if (id == null) return;
    await _rodar('eqp_modelo_acao', {'acao': 'aplicar', 'modelo_id': id, 'equipamentos': [_id]},
        'Modelo ligado (preços e medidor vazios preenchidos)');
  }

  Future<void> _incluirComponente() async {
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _ComponenteNovo());
    if (p == null) return;
    await _rodar('eqp_conjunto_acao', {'acao': 'componente_incluir', 'equipamento_id': _id, ...p}, 'Componente incluído com código e QR');
  }

  Future<void> _vincular() async {
    final codigo = await pedirTextoEqp(context, 'Colocar equipamento no conjunto', 'Código da etiqueta (EQ-0001) ou patrimônio');
    if (codigo == null) return;
    await _rodar('eqp_conjunto_acao', {'acao': 'componente_vincular', 'equipamento_id': _id, 'componente_codigo': codigo},
        'Equipamento colocado no conjunto');
  }

  Future<void> _retirar(Map<String, dynamic> c) async {
    final motivo = await pedirTextoEqp(context, 'Tirar ${c['codigo']} do conjunto', 'Motivo (opcional)', obrigatorio: false);
    if (motivo == null) return;
    await _rodar('eqp_conjunto_acao', {'acao': 'componente_retirar', 'componente_id': c['componente_id'], 'motivo': motivo},
        '${c['codigo']} saiu do conjunto');
  }

  Future<void> _item([Map<String, dynamic>? i]) async {
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _ItemConjunto(item: i));
    if (p == null) return;
    await _rodar('eqp_conjunto_acao', {
      'acao': 'item_salvar',
      'equipamento_id': _id,
      if (i != null) 'item_id': i['item_id'],
      ...p,
    }, 'Item salvo');
  }

  Future<void> _removerItem(Map<String, dynamic> i) async {
    if (!await confirmarEqp(context, 'Remover ${i['descricao']}', 'O item sai do conjunto.')) return;
    await _rodar('eqp_conjunto_acao', {'acao': 'item_remover', 'item_id': i['item_id']}, 'Item removido');
  }

  /// Etiquetas QR do conjunto e dos componentes com código (o app lê e abre o conjunto).
  Future<void> _etiquetas() async {
    final e = _e;
    final etiquetas = [
      Etiqueta(codigo: '${e['codigo']}', qrToken: '${e['qr_token']}', descricao: '${e['descricao'] ?? ''}', local: 'Conjunto'),
      for (final c in listaDe(_d?['componentes']))
        Etiqueta(
          codigo: '${c['codigo']}',
          qrToken: '${c['qr_token']}',
          descricao: '${c['descricao'] ?? ''}',
          local: 'Componente de ${e['codigo']}',
        ),
    ];
    setState(() => _ocupado = true);
    try {
      final bytes = await gerarPdfEtiquetas(
        etiquetas: etiquetas,
        modelo: modelosEtiqueta.first,
        rodape: 'Gestão de Equipamentos · ${e['codigo']}',
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'etiquetas-${e['codigo']}');
    } catch (err) {
      if (mounted) avisarEqp(context, mensagemDeErro(err), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    if (_erro != null && _d == null) return Center(child: Text(_erro!, style: const TextStyle(color: Cores.erro)));
    if (_d == null) return const Center(child: CircularProgressIndicator());
    final e = _e;
    final componentes = listaDe(_d!['componentes']);
    final itens = listaDe(_d!['itens']);
    final faltando = listaDe(_d!['faltando']);
    final emCasa = !const ['em_transito', 'em_uso'].contains(e['status']);
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          IconButton(tooltip: 'Voltar', onPressed: () => context.go('/equipamentos/ativo/$_id'), icon: const Icon(Icons.arrow_back)),
          Expanded(
            child: Text('Conjunto ${e['codigo']} · ${e['descricao']}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          ChipStatusEqp('${e['status']}'),
        ]),
        if (_d!['lido_e_componente'] == true)
          const Text('O código lido é de um componente: este é o conjunto dele.', style: TextStyle(color: Cores.info)),
        if (_ocupado) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(
            avatar: const Icon(Icons.qr_code_2, size: 18),
            label: Text('Etiquetas QR (${componentes.length + 1})'),
            onPressed: _ocupado ? null : _etiquetas,
          ),
          if (_gestor) ...[
            if (e['modelo_id'] != null)
              ActionChip(
                avatar: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('Montar pelo padrão do modelo'),
                onPressed: _ocupado || faltando.isEmpty
                    ? null
                    : () => _rodar('eqp_conjunto_acao', {'acao': 'montar', 'equipamento_id': _id}, 'Conjunto montado pelo padrão'),
              ),
            ActionChip(
              avatar: const Icon(Icons.category_outlined, size: 18),
              label: Text(e['modelo_id'] == null ? 'Escolher o modelo' : 'Trocar o modelo'),
              onPressed: _ocupado ? null : _escolherModelo,
            ),
          ],
        ]),
        const SizedBox(height: 12),
        SecaoEqp(
          titulo: 'Modelo',
          child: e['modelo_id'] == null
              ? const Text('Sem modelo. Escolha o modelo para montar o conjunto pelo padrão e usar os preços de tabela dele.',
                  style: TextStyle(color: Cores.neutro))
              : InkWell(
                  onTap: () => context.go('/equipamentos/modelos/${e['modelo_id']}'),
                  child: Text('${e['modelo']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
        ),
        if (faltando.isNotEmpty)
          SecaoEqp(
            titulo: 'Falta pelo padrão do modelo',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final f in faltando)
                Text('${numeroBr(f['falta'])} × ${f['descricao']}${f['obrigatorio'] == true ? '' : ' (opcional)'}',
                    style: const TextStyle(color: Cores.alerta)),
            ]),
          ),
        SecaoEqp(
          titulo: 'Componentes com código (${componentes.length})',
          acoes: [
            if (_gestor && emCasa) ...[
              TextButton.icon(onPressed: _ocupado ? null : _incluirComponente, icon: const Icon(Icons.add, size: 18), label: const Text('Novo')),
              TextButton.icon(onPressed: _ocupado ? null : _vincular, icon: const Icon(Icons.link, size: 18), label: const Text('Já cadastrado')),
            ],
          ],
          child: Column(children: [
            if (componentes.isEmpty)
              const Text('Nenhum componente com código. Eles saem e voltam junto com o conjunto.', style: TextStyle(color: Cores.neutro)),
            for (final c in componentes)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.qr_code_2),
                title: Text('${c['codigo']} · ${c['descricao']}'),
                subtitle: Text([
                  if (c['numero_serie'] != null) 'Série ${c['numero_serie']}',
                  if (c['ficha'] == true) 'com ficha própria (${statusEquipamento[c['status']] ?? c['status']})',
                  if (c['valor_reposicao'] != null) 'reposição ${reais(c['valor_reposicao'])}',
                ].join(' · ')),
                trailing: _gestor && emCasa
                    ? IconButton(tooltip: 'Tirar do conjunto', onPressed: _ocupado ? null : () => _retirar(c), icon: const Icon(Icons.link_off))
                    : null,
              ),
            if (!emCasa)
              const Text('O conjunto está fora: os componentes só entram ou saem quando ele voltar.', style: TextStyle(color: Cores.neutro)),
          ]),
        ),
        SecaoEqp(
          titulo: 'Itens por quantidade (${itens.length})',
          acoes: [
            if (_gestor) TextButton.icon(onPressed: _ocupado ? null : _item, icon: const Icon(Icons.add, size: 18), label: const Text('Incluir')),
          ],
          child: Column(children: [
            if (itens.isEmpty) const Text('Nenhum item.', style: TextStyle(color: Cores.neutro)),
            for (final i in itens)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text('${numeroBr(i['quantidade'])} × ${i['descricao']}'),
                subtitle: i['valor_reposicao'] == null ? null : Text('Reposição ${reais(i['valor_reposicao'])} cada'),
                trailing: _gestor
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(tooltip: 'Editar', onPressed: _ocupado ? null : () => _item(i), icon: const Icon(Icons.edit_outlined)),
                        IconButton(tooltip: 'Remover', onPressed: _ocupado ? null : () => _removerItem(i), icon: const Icon(Icons.delete_outline)),
                      ])
                    : null,
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Componente novo, com código e QR próprios.
class _ComponenteNovo extends StatefulWidget {
  const _ComponenteNovo();

  @override
  State<_ComponenteNovo> createState() => _ComponenteNovoState();
}

class _ComponenteNovoState extends State<_ComponenteNovo> {
  final _descricao = TextEditingController();
  final _serie = TextEditingController();
  final _marca = TextEditingController();

  @override
  void dispose() {
    _descricao.dispose();
    _serie.dispose();
    _marca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Novo componente'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _descricao, decoration: const InputDecoration(labelText: 'Descrição (ex.: Bomba manual)')),
            TextField(controller: _serie, decoration: const InputDecoration(labelText: 'Número de série')),
            TextField(controller: _marca, decoration: const InputDecoration(labelText: 'Marca (vazio = a do conjunto)')),
            const SizedBox(height: 8),
            const Text('O código (EQ-…) e o QR saem automáticos; imprima a etiqueta na tela do conjunto.',
                style: TextStyle(color: Cores.neutro)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              if (_descricao.text.trim().isEmpty) return;
              Navigator.of(context).pop(<String, dynamic>{
                'descricao': _descricao.text.trim(),
                if (_serie.text.trim().isNotEmpty) 'numero_serie': _serie.text.trim(),
                if (_marca.text.trim().isNotEmpty) 'marca': _marca.text.trim(),
              });
            },
            child: const Text('Incluir'),
          ),
        ],
      );
}

/// Item por quantidade do conjunto.
class _ItemConjunto extends StatefulWidget {
  const _ItemConjunto({this.item});

  final Map<String, dynamic>? item;

  @override
  State<_ItemConjunto> createState() => _ItemConjuntoState();
}

class _ItemConjuntoState extends State<_ItemConjunto> {
  final _descricao = TextEditingController();
  final _quantidade = TextEditingController(text: '1');
  final _reposicao = TextEditingController();

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    if (i != null) {
      _descricao.text = '${i['descricao'] ?? ''}';
      _quantidade.text = numeroBr(i['quantidade']);
      _reposicao.text = i['valor_reposicao'] == null ? '' : numeroBr(i['valor_reposicao']);
    }
  }

  @override
  void dispose() {
    _descricao.dispose();
    _quantidade.dispose();
    _reposicao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.item == null ? 'Item do conjunto' : 'Editar item'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _descricao, decoration: const InputDecoration(labelText: 'Descrição (ex.: Mangueira 3 m)')),
            TextField(
              controller: _quantidade,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantidade'),
            ),
            TextField(
              controller: _reposicao,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor de reposição de cada (R\$)'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              final q = lerNumero(_quantidade.text);
              if (_descricao.text.trim().isEmpty || q == null || q <= 0) return;
              Navigator.of(context).pop(<String, dynamic>{
                'descricao': _descricao.text.trim(),
                'quantidade': q,
                'valor_reposicao': lerNumero(_reposicao.text) ?? '',
              });
            },
            child: const Text('Salvar'),
          ),
        ],
      );
}
