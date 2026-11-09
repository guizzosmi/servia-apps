import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../widgets/margem.dart';
import 'servico.dart';
import 'widgets.dart';

/// Cadastros da aplicação: locais da própria empresa (depósito, oficina, filial), obras e setores.
/// Clientes e os endereços deles são os do núcleo (Cadastros › Clientes).
class EqpCadastrosTela extends StatefulWidget {
  const EqpCadastrosTela({super.key});

  @override
  State<EqpCadastrosTela> createState() => _EqpCadastrosTelaState();
}

class _EqpCadastrosTelaState extends State<EqpCadastrosTela> {
  Map<String, dynamic>? _d;
  String? _erro;

  bool get _gestor => Sessao.atual?.tem(Papel.gestor) ?? false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final d = await eqpApoio();
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

  Future<void> _salvar(String funcao, Map<String, dynamic> p, String ok) async {
    try {
      await eqp(funcao, p);
      if (mounted) avisarEqp(context, ok);
      await _carregar();
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _local([Map<String, dynamic>? l]) async {
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _LocalEmpresa(local: l));
    if (p == null) return;
    await _salvar('eqp_local_acao', {'acao': 'salvar', if (l != null) 'local_id': l['id'], ...p}, 'Local salvo');
  }

  Future<void> _obra() async {
    final locais = listaDe(_d?['locais_empresa']);
    if (locais.isEmpty) {
      avisarEqp(context, 'Cadastre antes o endereço da obra como local da empresa (categoria Obra).', erro: true);
      return;
    }
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _ObraPropria(locais: locais));
    if (p == null) return;
    await _salvar('eqp_obra_acao', {'acao': 'salvar', ...p}, 'Obra salva');
  }

  Future<void> _encerrarObra(Map<String, dynamic> o) async {
    if (!await confirmarEqp(context, 'Encerrar ${o['codigo']}', 'A obra não pode ter equipamento reservado ou nela.')) return;
    await _salvar('eqp_obra_acao', {'acao': 'encerrar', 'obra_id': o['id']}, 'Obra encerrada');
  }

  Future<void> _setor() async {
    final nome = await pedirTextoEqp(context, 'Novo setor', 'Nome (ex.: Almoxarifado, Filial Toledo)');
    if (nome == null) return;
    await _salvar('eqp_setor_acao', {'acao': 'salvar', 'nome': nome}, 'Setor salvo');
  }

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    if (_erro != null && _d == null) return Center(child: Text(_erro!, style: const TextStyle(color: Cores.erro)));
    if (_d == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Text('Cadastros dos equipamentos', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const Text('Os clientes e os endereços deles são os mesmos do ServPilot (Cadastros › Clientes). Aqui ficam os '
            'locais da própria empresa, as obras próprias e os setores do uso próprio.', style: TextStyle(color: Cores.neutro)),
        const SizedBox(height: 12),
        SecaoEqp(
          titulo: 'Locais da empresa',
          acoes: [if (_gestor) TextButton.icon(onPressed: _local, icon: const Icon(Icons.add, size: 18), label: const Text('Novo'))],
          child: Column(children: [
            if (listaDe(_d!['locais_empresa']).isEmpty)
              const Text('Cadastre ao menos um depósito: é de onde os equipamentos saem e para onde voltam.',
                  style: TextStyle(color: Cores.alerta)),
            for (final l in listaDe(_d!['locais_empresa']))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${l['nome']}'),
                subtitle: Text([
                  categoriasLocal[l['categoria']] ?? 'Local',
                  if (l['cidade'] != null) '${l['cidade']}${l['uf'] != null ? '/${l['uf']}' : ''}',
                ].join(' · ')),
                trailing: _gestor ? IconButton(tooltip: 'Editar', onPressed: () => _local(l), icon: const Icon(Icons.edit_outlined)) : null,
              ),
          ]),
        ),
        SecaoEqp(
          titulo: 'Obras',
          acoes: [if (_gestor) TextButton.icon(onPressed: _obra, icon: const Icon(Icons.add, size: 18), label: const Text('Obra própria'))],
          child: Column(children: [
            if (listaDe(_d!['obras']).isEmpty) const Text('Nenhuma obra.', style: TextStyle(color: Cores.neutro)),
            for (final o in listaDe(_d!['obras']))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${o['codigo']} · ${o['nome']}'),
                subtitle: Text('${o['propria'] == true ? 'Própria' : 'Do cliente ${o['cliente']}'} · ${o['local']} · ${situacoesObra[o['situacao']] ?? o['situacao']}'),
                trailing: _gestor && o['situacao'] != 'encerrada'
                    ? IconButton(tooltip: 'Encerrar', onPressed: () => _encerrarObra(o), icon: const Icon(Icons.flag_outlined))
                    : null,
              ),
          ]),
        ),
        SecaoEqp(
          titulo: 'Setores (uso próprio)',
          acoes: [if (_gestor) TextButton.icon(onPressed: _setor, icon: const Icon(Icons.add, size: 18), label: const Text('Novo'))],
          child: Column(children: [
            if (listaDe(_d!['setores']).isEmpty) const Text('Nenhum setor.', style: TextStyle(color: Cores.neutro)),
            for (final s in listaDe(_d!['setores']))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${s['nome']}'),
                subtitle: Text(s['ativo'] == true ? 'Ativo' : 'Inativo'),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _LocalEmpresa extends StatefulWidget {
  const _LocalEmpresa({this.local});

  final Map<String, dynamic>? local;

  @override
  State<_LocalEmpresa> createState() => _LocalEmpresaState();
}

class _LocalEmpresaState extends State<_LocalEmpresa> {
  late final Map<String, TextEditingController> _c = {
    for (final k in ['nome', 'logradouro', 'numero', 'bairro', 'cidade', 'uf']) k: TextEditingController(text: '${widget.local?[k] ?? ''}'),
  };
  late String _categoria = '${widget.local?['categoria'] ?? 'deposito'}';

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.local == null ? 'Novo local da empresa' : 'Local da empresa'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: _c['nome'], decoration: const InputDecoration(labelText: 'Nome (ex.: Depósito Central)')),
              DropdownButtonFormField<String>(
                initialValue: categoriasLocal.containsKey(_categoria) ? _categoria : 'deposito',
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: [for (final c in categoriasLocal.entries) DropdownMenuItem(value: c.key, child: Text(c.value))],
                onChanged: (v) => setState(() => _categoria = v ?? 'deposito'),
              ),
              TextField(controller: _c['logradouro'], decoration: const InputDecoration(labelText: 'Endereço')),
              Row(children: [
                SizedBox(width: 100, child: TextField(controller: _c['numero'], decoration: const InputDecoration(labelText: 'Número'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _c['bairro'], decoration: const InputDecoration(labelText: 'Bairro'))),
              ]),
              Row(children: [
                Expanded(child: TextField(controller: _c['cidade'], decoration: const InputDecoration(labelText: 'Cidade'))),
                const SizedBox(width: 8),
                SizedBox(width: 70, child: TextField(controller: _c['uf'], decoration: const InputDecoration(labelText: 'UF'))),
              ]),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              if (_c['nome']!.text.trim().isEmpty) return;
              Navigator.of(context).pop(<String, dynamic>{
                for (final e in _c.entries) e.key: e.value.text.trim(),
                'categoria': _categoria,
              });
            },
            child: const Text('Salvar'),
          ),
        ],
      );
}

class _ObraPropria extends StatefulWidget {
  const _ObraPropria({required this.locais});

  final List<Map<String, dynamic>> locais;

  @override
  State<_ObraPropria> createState() => _ObraPropriaState();
}

class _ObraPropriaState extends State<_ObraPropria> {
  final _nome = TextEditingController();
  final _cc = TextEditingController();
  late String _local = '${(widget.locais.firstWhere((l) => l['categoria'] == 'obra', orElse: () => widget.locais.first))['id']}';
  DateTime? _inicio;
  DateTime? _fim;

  @override
  void dispose() {
    _nome.dispose();
    _cc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Obra própria'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _nome, decoration: const InputDecoration(labelText: 'Nome da obra')),
            DropdownButtonFormField<String>(
              initialValue: _local,
              decoration: const InputDecoration(labelText: 'Endereço (local da empresa)'),
              items: [for (final l in widget.locais) DropdownMenuItem(value: '${l['id']}', child: Text('${l['nome']}'))],
              onChanged: (v) => setState(() => _local = v ?? _local),
            ),
            TextField(controller: _cc, decoration: const InputDecoration(labelText: 'Centro de custo (ERP)')),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              CampoDataEqp(rotulo: 'Início', data: _inicio, aoMudar: (d) => setState(() => _inicio = d)),
              CampoDataEqp(rotulo: 'Fim previsto', data: _fim, aoMudar: (d) => setState(() => _fim = d)),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              if (_nome.text.trim().isEmpty) return;
              Navigator.of(context).pop(<String, dynamic>{
                'nome': _nome.text.trim(),
                'local_id': _local,
                if (_cc.text.trim().isNotEmpty) 'centro_custo': _cc.text.trim(),
                if (_inicio != null) 'inicio': iso(_inicio!),
                if (_fim != null) 'fim_previsto': iso(_fim!),
              });
            },
            child: const Text('Salvar'),
          ),
        ],
      );
}
