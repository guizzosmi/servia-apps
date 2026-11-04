import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_cadastro.dart';
import '../core/acoes_levantamento.dart';
import '../core/acoes_os.dart';
import '../core/estado.dart';
import '../widgets/cadastros_rapidos.dart';

const _unidades = {'btu_h': 'BTU/h', 'tr': 'TR', 'kw': 'kW'};

String _num(Object? v) {
  final n = num.tryParse('${v ?? ''}');
  if (n == null) return '';
  final t = n == n.roundToDouble() ? n.toInt().toString() : n.toString().replaceAll('.', ',');
  return n >= 1000 && n == n.roundToDouble()
      ? t.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')
      : t;
}

/// Levantamento do local (guia 57): o técnico escolhe o cliente e o local e
/// cadastra os ambientes (andar, área, ocupantes) e os aparelhos de cada um,
/// com a foto da plaqueta (a IA preenche) e a etiqueta QR colada na hora.
/// Sem OS e sem internet: tudo sobe na sincronização.
class LevantamentoTela extends StatefulWidget {
  const LevantamentoTela({super.key});

  @override
  State<LevantamentoTela> createState() => _LevantamentoTelaState();
}

class _LevantamentoTelaState extends State<LevantamentoTela> {
  Map<String, dynamic>? _cliente;
  Map<String, dynamic>? _local;
  final Set<String> _abertos = {};

  void _aviso(String texto) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _escolherCliente() async {
    final c = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _BuscaCliente(),
    );
    if (c == null || !mounted) return;
    final locais = AcoesOs.locaisDo(c['id']);
    setState(() {
      _cliente = c;
      _local = locais.length == 1 ? locais.first : null;
      _abertos.clear();
    });
    if (locais.isEmpty) _aviso('Este cliente ainda não tem local: cadastre no painel ou abra uma OS para ele.');
  }

  Future<void> _ambiente([Map<String, dynamic>? a]) async {
    final r = await showDialog<_DadosAmbiente>(context: context, builder: (_) => _DialogoAmbiente(atual: a));
    if (r == null || !mounted) return;
    final id = await AcoesLevantamento.salvarAmbiente(
      clienteId: '${_cliente!['id']}',
      localId: '${_local!['id']}',
      id: a?['id'] as String?,
      nome: r.nome,
      setorAndar: r.setor,
      areaM2: r.area,
      ocupantesFixos: r.fixos,
      ocupantesVariaveis: r.variaveis,
    );
    if (mounted) setState(() => _abertos.add(id));
  }

  Future<void> _aparelho(String? ambienteId) async {
    final e = await cadastrarEquipamento(
      context,
      localId: '${_local!['id']}',
      ambienteId: ambienteId,
      codigosUsados: AcoesCadastro.codigosDoCliente(_cliente!['id']),
    );
    if (e == null || !mounted) return;
    await AcoesLevantamento.aparelhoNoLocal(clienteId: '${_cliente!['id']}', localId: '${_local!['id']}', e: e);
    if (mounted) _aviso('${e.rotulo} cadastrado. Sobe na próxima sincronização.');
  }

  @override
  Widget build(BuildContext context) {
    final banco = EstadoApp.instancia.banco!;
    return Scaffold(
      appBar: AppBar(title: const Text('Levantamento do local', style: TextStyle(fontWeight: FontWeight.w800))),
      floatingActionButton: _local == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('novoAmbiente'),
              onPressed: () => _ambiente(),
              icon: const Icon(Icons.add),
              label: const Text('Ambiente'),
            ),
      body: !AcoesOs.possoAbrir
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('O levantamento é de quem tem "Pode abrir OS pelo app". Fale com o gestor.',
                    textAlign: TextAlign.center),
              ),
            )
          : ListenableBuilder(
              listenable: banco,
              builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
                _cabecalho(),
                if (_local != null) ..._ambientes(),
              ]),
            ),
    );
  }

  Widget _cabecalho() {
    final c = _cliente;
    if (c == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Percorra o cliente e cadastre cada ambiente e os aparelhos dele. A foto da plaqueta preenche '
                'marca, modelo, série e capacidade; a etiqueta QR em branco fica no aparelho.',
                style: TextStyle(color: Cores.neutro)),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('escolherCliente'),
              onPressed: _escolherCliente,
              icon: const Icon(Icons.person_search_outlined),
              label: const Text('Escolher o cliente'),
            ),
          ]),
        ),
      );
    }
    final locais = AcoesOs.locaisDo(c['id']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('${c['nome']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            TextButton(onPressed: _escolherCliente, child: const Text('Trocar')),
          ]),
          if (locais.length > 1)
            DropdownButton<String>(
              value: _local?['id'] as String?,
              hint: const Text('Escolha o local'),
              isExpanded: true,
              items: [
                for (final l in locais)
                  DropdownMenuItem(
                      value: '${l['id']}',
                      child: Text([l['nome'], l['cidade']].where((x) => x != null).join(' · '),
                          overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() {
                _local = locais.firstWhere((l) => l['id'] == v);
                _abertos.clear();
              }),
            )
          else if (_local != null)
            Text([_local!['nome'], _local!['cidade']].where((x) => x != null).join(' · '),
                style: const TextStyle(color: Cores.neutro)),
        ]),
      ),
    );
  }

  List<Widget> _ambientes() {
    final localId = _local!['id'];
    final ambientes = AcoesLevantamento.ambientesDo(localId);
    final todos = AcoesLevantamento.aparelhosDo(localId);
    final semAmbiente = todos.where((e) => e['ambiente_id'] == null || ambientes.every((a) => a['id'] != e['ambiente_id'])).toList();
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Text('${ambientes.length} ambiente(s) · ${todos.length} aparelho(s)',
            style: const TextStyle(color: Cores.neutro, fontWeight: FontWeight.w600)),
      ),
      if (ambientes.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nenhum ambiente ainda: toque em "+ Ambiente" (ex.: Recepção, Sala de reuniões).',
              style: TextStyle(color: Cores.neutro)),
        ),
      for (final a in ambientes) _cartaoAmbiente(a, todos.where((e) => e['ambiente_id'] == a['id']).toList()),
      if (semAmbiente.isNotEmpty) _cartaoAmbiente(null, semAmbiente),
    ];
  }

  Widget _cartaoAmbiente(Map<String, dynamic>? a, List<Map<String, dynamic>> aparelhos) {
    final id = '${a?['id'] ?? ''}';
    final aberto = _abertos.contains(id);
    final detalhe = a == null
        ? 'Aparelhos sem ambiente'
        : [
            a['setor_andar'],
            if (a['area_m2'] != null) '${_num(a['area_m2'])} m²',
            if (a['ocupantes_fixos'] != null || a['ocupantes_variaveis'] != null)
              '${a['ocupantes_fixos'] ?? 0}${a['ocupantes_variaveis'] != null ? ' + ${a['ocupantes_variaveis']}' : ''} ocupante(s)',
          ].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
    return Card(
      child: Column(children: [
        ListTile(
          onTap: () => setState(() => aberto ? _abertos.remove(id) : _abertos.add(id)),
          title: Text(a == null ? 'Sem ambiente' : '${a['nome']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text([if (detalhe.isNotEmpty) detalhe, '${aparelhos.length} aparelho(s)'].join('\n')),
          isThreeLine: detalhe.isNotEmpty,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (a != null)
              IconButton(tooltip: 'Área e ocupantes', onPressed: () => _ambiente(a), icon: const Icon(Icons.edit_outlined)),
            Icon(aberto ? Icons.expand_less : Icons.expand_more),
          ]),
        ),
        if (aberto) ...[
          for (final e in aparelhos)
            ListTile(
              dense: true,
              leading: const Icon(Icons.ac_unit, size: 20),
              title: Text([e['codigo'], e['descricao']].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
              subtitle: Text([
                [e['marca'], e['modelo']].where((x) => x != null).join(' '),
                if (e['capacidade_valor'] != null)
                  '${_num(e['capacidade_valor'])} ${_unidades[e['capacidade_unidade']] ?? ''}'.trim(),
                e['fluido_refrigerante'],
              ].where((x) => x != null && '$x'.trim().isNotEmpty).join(' · ')),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _aparelho(a?['id'] as String?),
                icon: const Icon(Icons.add),
                label: Text(a == null ? 'Aparelho' : 'Aparelho em ${a['nome']}'),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _DadosAmbiente {
  const _DadosAmbiente(this.nome, this.setor, this.area, this.fixos, this.variaveis);
  final String nome;
  final String setor;
  final num? area;
  final int? fixos;
  final int? variaveis;
}

class _DialogoAmbiente extends StatefulWidget {
  const _DialogoAmbiente({this.atual});

  final Map<String, dynamic>? atual;

  @override
  State<_DialogoAmbiente> createState() => _DialogoAmbienteState();
}

class _DialogoAmbienteState extends State<_DialogoAmbiente> {
  final _form = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: '${widget.atual?['nome'] ?? ''}');
  late final _setor = TextEditingController(text: '${widget.atual?['setor_andar'] ?? ''}');
  late final _area = TextEditingController(text: _num(widget.atual?['area_m2']));
  late final _fixos = TextEditingController(text: '${widget.atual?['ocupantes_fixos'] ?? ''}');
  late final _variaveis = TextEditingController(text: '${widget.atual?['ocupantes_variaveis'] ?? ''}');

  @override
  void dispose() {
    for (final c in [_nome, _setor, _area, _fixos, _variaveis]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _inteiro(String? v) => (v ?? '').trim().isEmpty || int.tryParse(v!.trim()) != null ? null : 'Só números';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.atual == null ? 'Novo ambiente' : 'Ambiente'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _nome,
              autofocus: widget.atual == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nome *', hintText: 'Ex.: Recepção, Sala 3'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o nome' : null,
            ),
            TextFormField(
              controller: _setor,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Andar ou setor', hintText: 'Ex.: Térreo, Bloco B'),
            ),
            TextFormField(
              controller: _area,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Área (m²)', helperText: 'Vai para o documento do PMOC'),
              validator: (v) => (v ?? '').trim().isEmpty || lerNumero(v!) != null ? null : 'Só números',
            ),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _fixos,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Ocupantes fixos'),
                  validator: _inteiro,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _variaveis,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Flutuantes'),
                  validator: _inteiro,
                ),
              ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!(_form.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(_DadosAmbiente(
              _nome.text.trim(),
              _setor.text.trim(),
              lerNumero(_area.text),
              int.tryParse(_fixos.text.trim()),
              int.tryParse(_variaveis.text.trim()),
            ));
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

/// Busca do cliente (pelo nome, fantasia ou cidade).
class _BuscaCliente extends StatefulWidget {
  const _BuscaCliente();

  @override
  State<_BuscaCliente> createState() => _BuscaClienteState();
}

class _BuscaClienteState extends State<_BuscaCliente> {
  final _busca = TextEditingController();

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lista = AcoesOs.clientes(_busca.text);
    final mostrar = lista.take(100).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _busca,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Nome do cliente ou cidade', prefixIcon: Icon(Icons.search)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: mostrar.isEmpty
                ? const Center(child: Text('Nenhum cliente encontrado.', style: TextStyle(color: Cores.neutro)))
                : ListView.builder(
                    itemCount: mostrar.length,
                    itemBuilder: (_, i) {
                      final c = mostrar[i];
                      final cidades = AcoesOs.locaisDo(c['id'])
                          .map((l) => l['cidade'])
                          .where((x) => x != null && '$x'.isNotEmpty)
                          .toSet()
                          .join(', ');
                      return ListTile(
                        title: Text('${c['nome']}'),
                        subtitle: cidades.isEmpty ? null : Text(cidades),
                        onTap: () => Navigator.of(context).pop(c),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
