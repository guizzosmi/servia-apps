import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/comercial.dart';

/// Etapas do funil (guia 90): renomear, mudar a chance, ligar/desligar, nova etapa e ordem.
/// Ganho e Perdido são fixas (só o nome muda). Devolve true se mudou algo.
Future<bool> editarEtapas(BuildContext context, List<Map<String, dynamic>> etapas) async {
  final mudou = await showDialog<bool>(context: context, builder: (_) => _DialogoEtapas(etapas));
  return mudou == true;
}

class _DialogoEtapas extends StatefulWidget {
  const _DialogoEtapas(this.etapas);

  final List<Map<String, dynamic>> etapas;

  @override
  State<_DialogoEtapas> createState() => _DialogoEtapasState();
}

class _DialogoEtapasState extends State<_DialogoEtapas> {
  late final List<Map<String, dynamic>> _abertas =
      widget.etapas.where((e) => e['tipo'] == 'aberta').map((e) => Map<String, dynamic>.from(e)).toList();
  late final List<Map<String, dynamic>> _fixas =
      widget.etapas.where((e) => e['tipo'] != 'aberta').map((e) => Map<String, dynamic>.from(e)).toList();
  bool _mudou = false;
  bool _ocupado = false;

  Future<void> _rodar(Future<void> Function() f) async {
    setState(() => _ocupado = true);
    try {
      await f();
      _mudou = true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagemDeErro(e)), backgroundColor: Cores.erro));
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _editar([Map<String, dynamic>? e]) async {
    final nome = TextEditingController(text: '${e?['nome'] ?? ''}');
    final chance = TextEditingController(text: '${e?['probabilidade'] ?? 50}');
    final aberta = e == null || e['tipo'] == 'aberta';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e == null ? 'Nova etapa' : 'Etapa ${e['nome']}'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome'), autofocus: true),
            if (aberta)
              TextField(
                controller: chance,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Chance de fechar (%)', helperText: 'Usada no valor ponderado do funil.'),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Salvar')),
        ],
      ),
    );
    final n = nome.text.trim();
    final c = int.tryParse(chance.text.trim());
    nome.dispose();
    chance.dispose();
    if (ok != true) return;
    await _rodar(() async {
      final r = await acaoComercial({'acao': 'etapa_salvar', 'id': e?['id'], 'nome': n, 'probabilidade': c});
      setState(() {
        if (e == null) {
          _abertas.add({'id': r['etapa_id'], 'nome': n, 'tipo': 'aberta', 'probabilidade': c ?? 50, 'ativo': true});
        } else {
          e['nome'] = n;
          if (aberta && c != null) e['probabilidade'] = c;
        }
      });
    });
  }

  Future<void> _ligar(Map<String, dynamic> e, bool ativo) => _rodar(() async {
        await acaoComercial({'acao': 'etapa_salvar', 'id': e['id'], 'nome': e['nome'], 'ativo': ativo});
        setState(() => e['ativo'] = ativo);
      });

  /// [para] já vem ajustado pelo onReorderItem (é a posição final, depois de tirar o item de [de]).
  Future<void> _reordenar(int de, int para) async {
    setState(() => _abertas.insert(para, _abertas.removeAt(de)));
    await _rodar(() => acaoComercial({'acao': 'etapas_ordem', 'ids': [for (final e in _abertas) e['id']]}));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Etapas do funil'),
        content: SizedBox(
          width: 480,
          height: 460,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Arraste para mudar a ordem. Desligue a etapa que não usa (ela precisa estar vazia).',
                style: TextStyle(color: Cores.neutro)),
            const SizedBox(height: 8),
            Expanded(
              child: ReorderableListView(
                buildDefaultDragHandles: true,
                onReorderItem: _ocupado ? (_, __) {} : _reordenar,
                children: [
                  for (final e in _abertas)
                    ListTile(
                      key: ValueKey(e['id']),
                      title: Text('${e['nome']}', style: TextStyle(color: e['ativo'] == true ? Cores.tinta : Cores.neutro)),
                      subtitle: Text('${e['probabilidade']}% de chance${e['ativo'] == true ? '' : ' · desligada'}'),
                      leading: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _ocupado ? null : () => _editar(e)),
                      trailing: Switch(value: e['ativo'] == true, onChanged: _ocupado ? null : (v) => _ligar(e, v)),
                    ),
                ],
              ),
            ),
            const Divider(),
            for (final e in _fixas)
              ListTile(
                dense: true,
                title: Text('${e['nome']}'),
                subtitle: Text(e['tipo'] == 'ganho' ? 'Fechou negócio' : 'Não fechou (pede o motivo)'),
                leading: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _ocupado ? null : () => _editar(e)),
              ),
          ]),
        ),
        actions: [
          TextButton.icon(onPressed: _ocupado ? null : () => _editar(), icon: const Icon(Icons.add), label: const Text('Nova etapa')),
          FilledButton(onPressed: () => Navigator.of(context).pop(_mudou), child: const Text('Pronto')),
        ],
      );
}
