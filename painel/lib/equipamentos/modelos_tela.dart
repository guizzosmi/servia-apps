import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/comercial.dart' show reais;
import '../widgets/itens_os.dart' show lerNumero, numeroBr;
import '../widgets/margem.dart';
import 'servico.dart';
import 'widgets.dart';

/// Medidores do modelo (o mesmo da ficha).
const medidoresModelo = {'nenhum': 'Sem medidor', 'horas': 'Horímetro (h)', 'km': 'Km', 'ciclos': 'Ciclos'};

/// Modelos (famílias) da Gestão de Equipamentos (guia 102): preços de tabela, diária interna da obra própria,
/// franquia e excedente sugeridos e os componentes padrão do conjunto.
class EqpModelosTela extends StatefulWidget {
  const EqpModelosTela({super.key});

  @override
  State<EqpModelosTela> createState() => _EqpModelosTelaState();
}

class _EqpModelosTelaState extends State<EqpModelosTela> {
  final _busca = TextEditingController();
  List<Map<String, dynamic>> _lista = [];
  bool _inativos = false;
  bool _carregando = true;
  String? _erro;

  bool get _gestor => Sessao.atual?.tem(Papel.gestor) ?? false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await eqp('eqp_modelos_lista', {
        if (_busca.text.trim().isNotEmpty) 'busca': _busca.text.trim(),
        'inativos': _inativos,
      });
      if (mounted) setState(() => _lista = listaDe(r['modelos']));
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _novo() async {
    Map<String, dynamic> apoio;
    try {
      apoio = await eqpApoio();
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
      return;
    }
    if (!mounted) return;
    final p = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => DialogoModelo(tipos: listaDe(apoio['tipos_equipamento'])),
    );
    if (p == null || !mounted) return;
    try {
      final r = await eqp('eqp_modelo_acao', {'acao': 'salvar', ...p});
      if (mounted) context.go('/equipamentos/modelos/${r['modelo_id']}');
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          Expanded(
            child: Text('Modelos', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (_gestor) FilledButton.icon(onPressed: _novo, icon: const Icon(Icons.add), label: const Text('Novo modelo')),
        ]),
        const Text('O modelo guarda os preços de tabela, a diária interna da obra própria e os componentes padrão. '
            'Equipamento novo do modelo já vem com os preços e o conjunto montado.', style: TextStyle(color: Cores.neutro)),
        const SizedBox(height: 8),
        TextField(
          controller: _busca,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Nome, família ou fabricante',
            suffixIcon: IconButton(onPressed: _carregar, icon: const Icon(Icons.arrow_forward)),
          ),
          onSubmitted: (_) => _carregar(),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _inativos,
          title: const Text('Mostrar inativos'),
          onChanged: (v) {
            setState(() => _inativos = v);
            _carregar();
          },
        ),
        if (_carregando) const LinearProgressIndicator(minHeight: 2),
        if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
        if (!_carregando && _lista.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('Nenhum modelo.', style: TextStyle(color: Cores.neutro))),
        for (final m in _lista)
          Card(
            child: ListTile(
              onTap: () => context.go('/equipamentos/modelos/${m['modelo_id']}'),
              title: Text('${m['nome']}${m['ativo'] == true ? '' : ' (inativo)'}'),
              subtitle: Text([
                if (m['familia'] != null) '${m['familia']}',
                if (m['fabricante'] != null) '${m['fabricante']}',
                '${m['equipamentos']} equipamento(s), ${m['disponiveis']} disponível(is)',
                '${m['componentes']} componente(s) padrão',
              ].join(' · ')),
              trailing: Text([
                if (m['preco_diaria'] != null) '${reais(m['preco_diaria'])}/dia',
                if (m['preco_mes'] != null) '${reais(m['preco_mes'])}/mês',
              ].join('\n'), textAlign: TextAlign.end),
            ),
          ),
      ]),
    );
  }
}

/// Ficha do modelo: dados, componentes padrão e os equipamentos dele.
class EqpModeloTela extends StatefulWidget {
  const EqpModeloTela({super.key, required this.id});

  final String id;

  @override
  State<EqpModeloTela> createState() => _EqpModeloTelaState();
}

class _EqpModeloTelaState extends State<EqpModeloTela> {
  Map<String, dynamic>? _d;
  Map<String, dynamic> _apoio = const {};
  String? _erro;
  bool _ocupado = false;

  bool get _gestor => Sessao.atual?.tem(Papel.gestor) ?? false;
  Map<String, dynamic> get _m => Map<String, dynamic>.from((_d?['modelo'] as Map?) ?? const {});

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final d = await eqp('eqp_modelo_ver', {'modelo_id': widget.id});
      final apoio = await eqpApoio();
      if (mounted) {
        setState(() {
          _d = d;
          _apoio = apoio;
          _erro = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    }
  }

  Future<void> _acao(Map<String, dynamic> p, String ok) async {
    if (!mounted) return;
    setState(() => _ocupado = true);
    try {
      await eqp('eqp_modelo_acao', p);
      if (mounted) avisarEqp(context, ok);
      await _carregar();
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _editar() async {
    final p = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => DialogoModelo(tipos: listaDe(_apoio['tipos_equipamento']), modelo: _m),
    );
    if (p == null) return;
    await _acao({'acao': 'salvar', 'modelo_id': widget.id, ...p}, 'Modelo salvo');
  }

  Future<void> _componente([Map<String, dynamic>? c]) async {
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _Componente(componente: c));
    if (p == null) return;
    await _acao({
      'acao': 'componente_salvar',
      'modelo_id': widget.id,
      if (c != null) 'componente_id': c['componente_id'],
      ...p,
    }, 'Componente salvo');
  }

  Future<void> _removerComponente(Map<String, dynamic> c) async {
    if (!await confirmarEqp(context, 'Remover ${c['descricao']}', 'Sai do padrão do modelo. Os conjuntos já montados não mudam.')) {
      return;
    }
    await _acao({'acao': 'componente_remover', 'componente_id': c['componente_id']}, 'Componente removido');
  }

  Future<void> _novoEquipamento() async {
    final locais = listaDe(_apoio['locais_empresa']);
    if (locais.isEmpty) {
      avisarEqp(context, 'Cadastre antes um depósito em Equipamentos › Depósitos e obras.', erro: true);
      return;
    }
    final p = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _NovoEquipamento(locais: locais, medidor: '${_m['medidor_padrao']}'),
    );
    if (p == null || !mounted) return;
    setState(() => _ocupado = true);
    try {
      final r = await eqp('eqp_modelo_acao', {'acao': 'novo_equipamento', 'modelo_id': widget.id, ...p});
      if (!mounted) return;
      avisarEqp(context, '${r['codigo']} cadastrado (${r['componentes_criados']} componente(s) com QR, ${r['itens_criados']} item(ns))');
      context.go('/equipamentos/conjunto/${r['equipamento_id']}');
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _aplicar() async {
    List<Map<String, dynamic>> lista;
    try {
      lista = listaDe((await eqp('eqp_lista', {}))['equipamentos']);
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
      return;
    }
    if (!mounted) return;
    final ids = await showDialog<List<String>>(context: context, builder: (_) => _EscolherEquipamentos(lista: lista));
    if (ids == null || ids.isEmpty) return;
    await _acao({'acao': 'aplicar', 'modelo_id': widget.id, 'equipamentos': ids},
        'Modelo aplicado a ${ids.length} equipamento(s): preços e medidor vazios preenchidos');
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
    if (_erro != null && _d == null) return Center(child: Text(_erro!, style: const TextStyle(color: Cores.erro)));
    if (_d == null) return const Center(child: CircularProgressIndicator());
    final m = _m;
    final componentes = listaDe(_d!['componentes']);
    final equipamentos = listaDe(_d!['equipamentos']);
    final medidor = '${m['medidor_padrao']}';
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          IconButton(tooltip: 'Voltar', onPressed: () => context.go('/equipamentos/modelos'), icon: const Icon(Icons.arrow_back)),
          Expanded(
            child: Text('${m['nome']}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (m['ativo'] != true) const Text('Inativo', style: TextStyle(color: Cores.erro, fontWeight: FontWeight.w700)),
        ]),
        if (_ocupado) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 8),
        if (_gestor)
          Wrap(spacing: 8, runSpacing: 8, children: [
            ActionChip(
              avatar: const Icon(Icons.add_box_outlined, size: 18),
              label: const Text('Novo equipamento deste modelo'),
              onPressed: _ocupado || m['ativo'] != true ? null : _novoEquipamento,
            ),
            ActionChip(
              avatar: const Icon(Icons.playlist_add_check, size: 18),
              label: const Text('Aplicar a equipamentos já cadastrados'),
              onPressed: _ocupado || m['ativo'] != true ? null : _aplicar,
            ),
            ActionChip(avatar: const Icon(Icons.edit_outlined, size: 18), label: const Text('Editar'), onPressed: _ocupado ? null : _editar),
            if (m['ativo'] == true)
              ActionChip(
                avatar: const Icon(Icons.block, size: 18),
                label: const Text('Inativar'),
                onPressed: _ocupado ? null : () => _acao({'acao': 'inativar', 'modelo_id': widget.id}, 'Modelo inativado'),
              ),
          ]),
        const SizedBox(height: 12),
        SecaoEqp(
          titulo: 'Dados e preços de tabela',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _info('Família', m['familia']),
            _info('Fabricante', m['fabricante']),
            _info('Categoria', m['tipo']),
            _info('Medidor padrão', medidoresModelo[medidor]),
            _info('Por dia', m['preco_diaria'] == null ? null : reais(m['preco_diaria'])),
            _info('Por semana', m['preco_semana'] == null ? null : reais(m['preco_semana'])),
            _info('Por mês', m['preco_mes'] == null ? null : reais(m['preco_mes'])),
            _info('Diária interna (obra própria)', m['diaria_interna'] == null ? null : reais(m['diaria_interna'])),
            _info('Franquia sugerida por mês', m['franquia_uso_mes'] == null ? null : numeroBr(m['franquia_uso_mes'])),
            _info('Excedente sugerido', m['preco_excedente'] == null ? null : '${reais(m['preco_excedente'])} por unidade'),
            _info('Observações', m['observacoes']),
          ]),
        ),
        SecaoEqp(
          titulo: 'Componentes padrão (conjunto)',
          acoes: [
            if (_gestor)
              TextButton.icon(onPressed: _ocupado ? null : _componente, icon: const Icon(Icons.add, size: 18), label: const Text('Incluir')),
          ],
          child: Column(children: [
            if (componentes.isEmpty)
              const Text('Sem componentes padrão. Com código próprio (QR) para o que tem número de série; por quantidade para '
                  'mangueiras, cabos e acessórios.', style: TextStyle(color: Cores.neutro)),
            for (final c in componentes)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(c['serializado'] == true ? Icons.qr_code_2 : Icons.inventory_2_outlined),
                title: Text('${numeroBr(c['quantidade'])} × ${c['descricao']}'),
                subtitle: Text([
                  if (c['serializado'] == true) 'Com código e QR próprios' else 'Por quantidade',
                  if (c['obrigatorio'] != true) 'opcional',
                  if (c['valor_reposicao'] != null) 'reposição ${reais(c['valor_reposicao'])}',
                ].join(' · ')),
                trailing: _gestor
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(tooltip: 'Editar', onPressed: _ocupado ? null : () => _componente(c), icon: const Icon(Icons.edit_outlined)),
                        IconButton(
                          tooltip: 'Remover',
                          onPressed: _ocupado ? null : () => _removerComponente(c),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ])
                    : null,
              ),
          ]),
        ),
        SecaoEqp(
          titulo: 'Equipamentos deste modelo (${equipamentos.length})',
          child: Column(children: [
            if (equipamentos.isEmpty) const Text('Nenhum equipamento.', style: TextStyle(color: Cores.neutro)),
            for (final e in equipamentos)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                onTap: () => context.go('/equipamentos/ativo/${e['equipamento_id']}'),
                title: Text('${e['codigo']} · ${e['descricao']}'),
                subtitle: Text([if (e['patrimonio'] != null) 'Patrimônio ${e['patrimonio']}', '${e['local'] ?? ''}'].join(' · ')),
                trailing: ChipStatusEqp('${e['status']}'),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Incluir ou alterar um modelo. Devolve só os campos (vazio = sem valor).
class DialogoModelo extends StatefulWidget {
  const DialogoModelo({super.key, required this.tipos, this.modelo});

  final List<Map<String, dynamic>> tipos;
  final Map<String, dynamic>? modelo;

  @override
  State<DialogoModelo> createState() => _DialogoModeloState();
}

class _DialogoModeloState extends State<DialogoModelo> {
  late final Map<String, TextEditingController> _c;
  String _medidor = 'nenhum';
  String? _tipo;

  static const _campos = [
    'nome', 'familia', 'fabricante', 'preco_diaria', 'preco_semana', 'preco_mes', 'diaria_interna', 'franquia_uso_mes',
    'preco_excedente', 'observacoes',
  ];
  static const _numeros = {'preco_diaria', 'preco_semana', 'preco_mes', 'diaria_interna', 'franquia_uso_mes', 'preco_excedente'};

  @override
  void initState() {
    super.initState();
    final m = widget.modelo ?? const <String, dynamic>{};
    _c = {
      for (final k in _campos)
        k: TextEditingController(text: m[k] == null ? '' : (_numeros.contains(k) ? numeroBr(m[k]) : '${m[k]}')),
    };
    _medidor = '${m['medidor_padrao'] ?? 'nenhum'}';
    final tipo = m['tipo_equipamento_id'];
    _tipo = tipo == null || !widget.tipos.any((t) => '${t['id']}' == '$tipo') ? null : '$tipo';
  }

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

  void _ok() {
    if (_c['nome']!.text.trim().isEmpty) return;
    final p = <String, dynamic>{'medidor_padrao': _medidor, 'tipo_equipamento_id': _tipo ?? ''};
    for (final k in _campos) {
      final t = _c[k]!.text.trim();
      p[k] = _numeros.contains(k) ? (lerNumero(t) ?? '') : t;
    }
    Navigator.of(context).pop(p);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.modelo == null ? 'Novo modelo' : 'Editar modelo'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _campo('nome', 'Nome (ex.: Macaco hidráulico 200 t)'),
              _campo('familia', 'Família (ex.: Macacos hidráulicos)'),
              _campo('fabricante', 'Fabricante'),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(labelText: 'Categoria (tipo de equipamento)'),
                items: [
                  const DropdownMenuItem<String>(child: Text('Sem categoria')),
                  for (final t in widget.tipos) DropdownMenuItem<String>(value: '${t['id']}', child: Text('${t['nome']}')),
                ],
                onChanged: (v) => setState(() => _tipo = v),
              ),
              DropdownButtonFormField<String>(
                initialValue: _medidor,
                decoration: const InputDecoration(labelText: 'Medidor padrão'),
                items: [for (final e in medidoresModelo.entries) DropdownMenuItem<String>(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _medidor = v ?? 'nenhum'),
              ),
              const SizedBox(height: 8),
              const Text('Preços de tabela da locação', style: TextStyle(fontWeight: FontWeight.w600)),
              _campo('preco_diaria', 'Por dia (R\$)', numero: true),
              _campo('preco_semana', 'Por semana (R\$)', numero: true),
              _campo('preco_mes', 'Por mês (R\$)', numero: true),
              _campo('diaria_interna', 'Diária interna da obra própria (R\$)', numero: true),
              _campo('franquia_uso_mes', 'Franquia de uso sugerida por mês (horas, km ou ciclos)', numero: true),
              _campo('preco_excedente', 'Preço do excedente por unidade (R\$)', numero: true),
              _campo('observacoes', 'Observações'),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(onPressed: _ok, child: const Text('Salvar')),
        ],
      );
}

/// Componente padrão do modelo.
class _Componente extends StatefulWidget {
  const _Componente({this.componente});

  final Map<String, dynamic>? componente;

  @override
  State<_Componente> createState() => _ComponenteState();
}

class _ComponenteState extends State<_Componente> {
  final _descricao = TextEditingController();
  final _quantidade = TextEditingController(text: '1');
  final _reposicao = TextEditingController();
  bool _serializado = false;
  bool _obrigatorio = true;

  @override
  void initState() {
    super.initState();
    final c = widget.componente;
    if (c != null) {
      _descricao.text = '${c['descricao'] ?? ''}';
      _quantidade.text = numeroBr(c['quantidade']);
      _reposicao.text = c['valor_reposicao'] == null ? '' : numeroBr(c['valor_reposicao']);
      _serializado = c['serializado'] == true;
      _obrigatorio = c['obrigatorio'] != false;
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
        title: Text(widget.componente == null ? 'Componente padrão' : 'Editar componente'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _descricao, decoration: const InputDecoration(labelText: 'Descrição (ex.: Bomba manual, Mangueira 3 m)')),
            TextField(
              controller: _quantidade,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantidade'),
            ),
            TextField(
              controller: _reposicao,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor de reposição (R\$, base para cobrar a falta)'),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _serializado,
              title: const Text('Tem código e QR próprios (número de série)'),
              onChanged: (v) => setState(() => _serializado = v),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _obrigatorio,
              title: const Text('Obrigatório no conjunto'),
              onChanged: (v) => setState(() => _obrigatorio = v),
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
                'serializado': _serializado,
                'obrigatorio': _obrigatorio,
              });
            },
            child: const Text('Salvar'),
          ),
        ],
      );
}

/// Novo equipamento do modelo: depósito, patrimônio, série e leitura inicial.
class _NovoEquipamento extends StatefulWidget {
  const _NovoEquipamento({required this.locais, required this.medidor});

  final List<Map<String, dynamic>> locais;
  final String medidor;

  @override
  State<_NovoEquipamento> createState() => _NovoEquipamentoState();
}

class _NovoEquipamentoState extends State<_NovoEquipamento> {
  final _patrimonio = TextEditingController();
  final _serie = TextEditingController();
  final _leitura = TextEditingController();
  String? _local;
  bool _montar = true;

  @override
  void initState() {
    super.initState();
    final deposito = widget.locais.where((l) => l['categoria'] == 'deposito');
    _local = '${(deposito.isEmpty ? widget.locais.first : deposito.first)['id']}';
  }

  @override
  void dispose() {
    _patrimonio.dispose();
    _serie.dispose();
    _leitura.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Novo equipamento do modelo'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<String>(
              initialValue: _local,
              decoration: const InputDecoration(labelText: 'Depósito (base)'),
              items: [for (final l in widget.locais) DropdownMenuItem<String>(value: '${l['id']}', child: Text('${l['nome']}'))],
              onChanged: (v) => setState(() => _local = v),
            ),
            TextField(controller: _patrimonio, decoration: const InputDecoration(labelText: 'Patrimônio')),
            TextField(controller: _serie, decoration: const InputDecoration(labelText: 'Número de série')),
            if (widget.medidor != 'nenhum')
              TextField(
                controller: _leitura,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Leitura inicial (${medidoresModelo[widget.medidor] ?? widget.medidor})'),
              ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _montar,
              title: const Text('Montar o conjunto pelo padrão do modelo'),
              onChanged: (v) => setState(() => _montar = v),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              if (_local == null) return;
              final leitura = lerNumero(_leitura.text);
              Navigator.of(context).pop(<String, dynamic>{
                'local_base_id': _local,
                if (_patrimonio.text.trim().isNotEmpty) 'patrimonio': _patrimonio.text.trim(),
                if (_serie.text.trim().isNotEmpty) 'numero_serie': _serie.text.trim(),
                if (leitura != null) 'leitura_inicial': leitura,
                'montar_conjunto': _montar,
              });
            },
            child: const Text('Cadastrar'),
          ),
        ],
      );
}

/// Escolher equipamentos (para aplicar o modelo).
class _EscolherEquipamentos extends StatefulWidget {
  const _EscolherEquipamentos({required this.lista});

  final List<Map<String, dynamic>> lista;

  @override
  State<_EscolherEquipamentos> createState() => _EscolherEquipamentosState();
}

class _EscolherEquipamentosState extends State<_EscolherEquipamentos> {
  final Set<String> _marcados = {};

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Aplicar o modelo'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: widget.lista.isEmpty
              ? const Text('Nenhum equipamento cadastrado.', style: TextStyle(color: Cores.neutro))
              : ListView(children: [
                  const Text('Liga o modelo e preenche os preços e o medidor que estiverem vazios (os preços próprios ficam).',
                      style: TextStyle(color: Cores.neutro)),
                  for (final e in widget.lista)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _marcados.contains('${e['equipamento_id']}'),
                      title: Text('${e['codigo']} · ${e['descricao']}'),
                      subtitle: Text('${e['modelo'] ?? 'sem modelo'}'),
                      onChanged: (v) => setState(() {
                        final id = '${e['equipamento_id']}';
                        if (v == true) {
                          _marcados.add(id);
                        } else {
                          _marcados.remove(id);
                        }
                      }),
                    ),
                ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(_marcados.toList()), child: Text('Aplicar (${_marcados.length})')),
        ],
      );
}
