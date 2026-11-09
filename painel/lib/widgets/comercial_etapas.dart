import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/comercial.dart';

/// Etapas do funil (guia 90): renomear, mudar a chance, ligar/desligar, nova etapa e ordem.
/// Guia 97: dias para ficar parada e a tarefa automática ao entrar na etapa.
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
    final auto = e?['tarefa_auto'] is Map ? Map<String, dynamic>.from(e!['tarefa_auto'] as Map) : null;
    final parada = TextEditingController(text: e == null ? '7' : '${e['dias_parada'] ?? ''}');
    final autoTitulo = TextEditingController(text: '${auto?['titulo'] ?? ''}');
    final autoDias = TextEditingController(text: '${auto?['dias'] ?? 1}');
    var autoLigada = auto != null;
    var autoTipo = tiposTarefa.containsKey(auto?['tipo']) ? '${auto!['tipo']}' : 'tarefa';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, definir) => AlertDialog(
          title: Text(e == null ? 'Nova etapa' : 'Etapa ${e['nome']}'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome'), autofocus: true),
                if (aberta) ...[
                  TextField(
                    controller: chance,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Chance de fechar (%)', helperText: 'Usada no valor ponderado e na previsão.'),
                  ),
                  TextField(
                    controller: parada,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Fica parada depois de quantos dias sem movimento',
                        helperText: 'O cartão fica vermelho no funil. Vazio ou 0: não vale nesta etapa.'),
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: autoLigada,
                  onChanged: (v) => definir(() => autoLigada = v),
                  title: const Text('Criar uma tarefa quando entrar nesta etapa'),
                ),
                if (autoLigada) ...[
                  DropdownButtonFormField<String>(
                    initialValue: autoTipo,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: [for (final t in tiposTarefa.entries) DropdownMenuItem(value: t.key, child: Text(t.value))],
                    onChanged: (v) => definir(() => autoTipo = v ?? 'tarefa'),
                  ),
                  TextField(
                    controller: autoTitulo,
                    decoration: const InputDecoration(labelText: 'Tarefa', hintText: 'Ex.: Cobrar o retorno da proposta'),
                  ),
                  TextField(
                    controller: autoDias,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Para daqui a quantos dias (às 9h)', helperText: '0 = em 1 hora.'),
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    final n = nome.text.trim();
    final c = int.tryParse(chance.text.trim());
    final dp = int.tryParse(parada.text.trim()) ?? 0;
    final at = autoTitulo.text.trim();
    final ad = int.tryParse(autoDias.text.trim()) ?? 1;
    for (final x in [nome, chance, parada, autoTitulo, autoDias]) {
      x.dispose();
    }
    if (ok != true) return;
    final tarefaAuto = autoLigada && at.isNotEmpty ? {'tipo': autoTipo, 'titulo': at, 'dias': ad < 0 ? 0 : ad} : null;
    await _rodar(() async {
      final r = await acaoComercial({
        'acao': 'etapa_salvar',
        'id': e?['id'],
        'nome': n,
        'probabilidade': c,
        if (aberta) 'dias_parada': dp < 0 ? 0 : dp,
        'tarefa_auto': tarefaAuto,
      });
      setState(() {
        if (e == null) {
          _abertas.add({
            'id': r['etapa_id'],
            'nome': n,
            'tipo': 'aberta',
            'probabilidade': c ?? 50,
            'ativo': true,
            'dias_parada': dp > 0 ? dp : null,
            'tarefa_auto': tarefaAuto,
          });
        } else {
          e['nome'] = n;
          if (aberta && c != null) e['probabilidade'] = c;
          if (aberta) e['dias_parada'] = dp > 0 ? dp : null;
          e['tarefa_auto'] = tarefaAuto;
        }
      });
    });
  }

  /// "60% de chance · parada em 5 dias · tarefa: Cobrar o retorno"
  String _resumo(Map<String, dynamic> e) => [
        if (e['tipo'] == 'aberta') '${e['probabilidade']}% de chance',
        if (e['tipo'] == 'ganho') 'Fechou negócio',
        if (e['tipo'] == 'perdido') 'Não fechou (pede o motivo)',
        if (e['dias_parada'] != null) 'parada em ${e['dias_parada']} dias',
        if (e['tarefa_auto'] is Map) 'tarefa: ${(e['tarefa_auto'] as Map)['titulo']}',
        if (e['tipo'] == 'aberta' && e['ativo'] != true) 'desligada',
      ].join(' · ');

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
          // Cabe em telas baixas: o resto do diálogo (título, margens e botões) ocupa uns 240 px.
          height: (MediaQuery.sizeOf(context).height - 240).clamp(280.0, 460.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Arraste para mudar a ordem. Desligue a etapa que não usa (ela precisa estar vazia).',
                style: TextStyle(color: Cores.neutro)),
            const SizedBox(height: 8),
            Expanded(
              child: ReorderableListView(
                // A alça de arrastar fica à esquerda (a padrão, à direita, ficava por cima do Switch).
                buildDefaultDragHandles: false,
                onReorderItem: _ocupado ? (_, __) {} : _reordenar,
                children: [
                  for (var i = 0; i < _abertas.length; i++)
                    ListTile(
                      key: ValueKey(_abertas[i]['id']),
                      title: Text('${_abertas[i]['nome']}',
                          style: TextStyle(color: _abertas[i]['ativo'] == true ? Cores.tinta : Cores.neutro)),
                      subtitle: Text(_resumo(_abertas[i])),
                      leading: Row(mainAxisSize: MainAxisSize.min, children: [
                        ReorderableDragStartListener(
                          index: i,
                          enabled: !_ocupado,
                          child: const MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.drag_indicator)),
                          ),
                        ),
                        IconButton(
                            icon: const Icon(Icons.edit_outlined), onPressed: _ocupado ? null : () => _editar(_abertas[i])),
                      ]),
                      trailing: Switch(
                          value: _abertas[i]['ativo'] == true, onChanged: _ocupado ? null : (v) => _ligar(_abertas[i], v)),
                    ),
                ],
              ),
            ),
            const Divider(),
            for (final e in _fixas)
              ListTile(
                dense: true,
                title: Text('${e['nome']}'),
                subtitle: Text(_resumo(e)),
                // O espaço da alça, para alinhar com as etapas de cima (Ganho e Perdido não mudam de lugar).
                leading: Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 32),
                  IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _ocupado ? null : () => _editar(e)),
                ]),
              ),
          ]),
        ),
        actions: [
          TextButton.icon(onPressed: _ocupado ? null : () => _editar(), icon: const Icon(Icons.add), label: const Text('Nova etapa')),
          FilledButton(onPressed: () => Navigator.of(context).pop(_mudou), child: const Text('Pronto')),
        ],
      );
}
