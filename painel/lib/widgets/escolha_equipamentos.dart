import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Abre a janela de escolha dos equipamentos de um local. Feita para locais
/// grandes (a Friella tem mais de 100): busca, filtro por ambiente e tipo,
/// "marcar todos os filtrados" e "Incluir equipamento" (cadastra na hora,
/// já ligado ao cliente e ao local, e volta marcado).
/// Devolve {id: "código · descrição"} dos escolhidos, ou null se cancelou.
Future<Map<String, String>?> escolherEquipamentos(
  BuildContext context, {
  required String clienteId,
  required String localId,
  required Set<String> atuais,
}) async {
  var selecionados = {...atuais};
  final podeIncluir = Sessao.atual?.tem(Papel.gestor) ?? false;
  while (true) {
    final r = await showDialog<_Resultado>(
      context: context,
      builder: (_) => _EscolhaEquipamentos(localId: localId, atuais: selecionados, podeIncluir: podeIncluir),
    );
    if (r == null) return null;
    if (r.incluir == null) return r.escolhidos;
    // Fecha a janela, abre o cadastro e, ao voltar, reabre com o novo marcado.
    selecionados = r.selecionados;
    if (!context.mounted) return null;
    final params = {
      'cliente_id': clienteId,
      'local_id': localId,
      if (r.incluir!.trim().isNotEmpty) 'sugerir_codigo': r.incluir!.trim(),
    };
    final id = await context.push<String>(Uri(path: '/c/equipamentos/novo', queryParameters: params).toString());
    if (id != null) selecionados.add(id);
    if (!context.mounted) return null;
  }
}

class _Resultado {
  const _Resultado({this.escolhidos, this.incluir, this.selecionados = const {}});

  /// Escolha final (botão "Usar").
  final Map<String, String>? escolhidos;

  /// Pedido para incluir um equipamento novo (com o texto buscado).
  final String? incluir;

  /// O que já estava marcado quando pediu para incluir.
  final Set<String> selecionados;
}

/// Texto curto de um equipamento: "004512 · Split sala 3".
String rotuloEquipamento(Map e) =>
    [e['codigo'], e['descricao']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');

class _EscolhaEquipamentos extends StatefulWidget {
  const _EscolhaEquipamentos({required this.localId, required this.atuais, required this.podeIncluir});

  final String localId;
  final Set<String> atuais;
  final bool podeIncluir;

  @override
  State<_EscolhaEquipamentos> createState() => _EscolhaEquipamentosState();
}

class _EscolhaEquipamentosState extends State<_EscolhaEquipamentos> {
  final _busca = TextEditingController();
  late final Set<String> _sel = {...widget.atuais};
  List<Map<String, dynamic>>? _todos;
  String? _erro;
  String? _ambiente;
  String? _tipo;

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
    try {
      final dados = await Supabase.instance.client
          .from('equipamentos')
          .select('id, codigo, descricao, marca, modelo, capacidade_valor, capacidade_unidade, '
              'ambientes(nome), tipos_equipamento(nome)')
          .eq('local_id', widget.localId)
          .eq('situacao', 'ativo')
          .isFilter('excluido_em', null)
          .order('codigo', ascending: true)
          .limit(2000);
      if (mounted) setState(() => _todos = dados);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    }
  }

  static String? _nomeAmbiente(Map e) => (e['ambientes'] as Map?)?['nome'] as String?;
  static String? _nomeTipo(Map e) => (e['tipos_equipamento'] as Map?)?['nome'] as String?;

  List<String> _opcoes(String? Function(Map) campo) {
    final s = <String>{};
    for (final e in _todos ?? const <Map<String, dynamic>>[]) {
      final v = campo(e);
      if (v != null && v.isNotEmpty) s.add(v);
    }
    return s.toList()..sort();
  }

  List<Map<String, dynamic>> get _filtrados {
    final b = _busca.text.trim().toLowerCase();
    return (_todos ?? const <Map<String, dynamic>>[]).where((e) {
      if (_ambiente != null && _nomeAmbiente(e) != _ambiente) return false;
      if (_tipo != null && _nomeTipo(e) != _tipo) return false;
      if (b.isEmpty) return true;
      final texto = [e['codigo'], e['descricao'], e['marca'], e['modelo'], _nomeAmbiente(e), _nomeTipo(e)]
          .where((x) => x != null)
          .join(' ')
          .toLowerCase();
      return texto.contains(b);
    }).toList();
  }

  Widget _filtro(String rotulo, String? valor, List<String> opcoes, ValueChanged<String?> aoMudar) {
    return SizedBox(
      width: 200,
      child: InputDecorator(
        decoration: InputDecoration(labelText: rotulo),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: opcoes.contains(valor) ? valor : null,
            isDense: true,
            isExpanded: true,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
              for (final o in opcoes) DropdownMenuItem<String?>(value: o, child: Text(o, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => aoMudar(v)),
          ),
        ),
      ),
    );
  }

  void _devolver() {
    final todos = _todos ?? const <Map<String, dynamic>>[];
    Navigator.of(context).pop(_Resultado(escolhidos: <String, String>{
      for (final e in todos)
        if (_sel.contains(e['id'])) e['id'] as String: rotuloEquipamento(e),
    }));
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;
    final marcadosNoFiltro = filtrados.where((e) => _sel.contains(e['id'])).length;
    final ambientes = _opcoes(_nomeAmbiente);
    final tipos = _opcoes(_nomeTipo);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text('Equipamentos do local',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Text('${_sel.length} escolhido(s)',
                  style: const TextStyle(color: Cores.indigo500, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 12),
            if (_erro != null)
              Text(_erro!, style: const TextStyle(color: Cores.erro))
            else if (_todos == null)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...[
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _busca,
                    autofocus: true,
                    decoration: const InputDecoration(
                        hintText: 'Código, descrição, marca...', prefixIcon: Icon(Icons.search, size: 20)),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (ambientes.isNotEmpty) _filtro('Ambiente', _ambiente, ambientes, (v) => _ambiente = v),
                if (tipos.isNotEmpty) _filtro('Tipo', _tipo, tipos, (v) => _tipo = v),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Text('${filtrados.length} na lista · $marcadosNoFiltro marcado(s)',
                    style: const TextStyle(color: Cores.neutro)),
                const Spacer(),
                TextButton(
                  onPressed: filtrados.isEmpty
                      ? null
                      : () => setState(() => _sel.addAll(filtrados.map((e) => e['id'] as String))),
                  child: Text('Marcar os ${filtrados.length}'),
                ),
                TextButton(
                  onPressed: marcadosNoFiltro == 0
                      ? null
                      : () => setState(() => _sel.removeAll(filtrados.map((e) => e['id']))),
                  child: const Text('Desmarcar'),
                ),
              ]),
              const Divider(height: 1),
              Expanded(
                child: filtrados.isEmpty
                    ? const Center(child: Text('Nenhum equipamento com esse filtro.', style: TextStyle(color: Cores.neutro)))
                    : ListView.builder(
                        itemCount: filtrados.length,
                        itemBuilder: (_, i) {
                          final e = filtrados[i];
                          final id = e['id'] as String;
                          final detalhe = [
                            _nomeAmbiente(e),
                            _nomeTipo(e),
                            [e['marca'], e['modelo']].where((x) => x != null).join(' '),
                          ].where((x) => x != null && x.isNotEmpty).join(' · ');
                          return CheckboxListTile(
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _sel.contains(id),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _sel.add(id);
                              } else {
                                _sel.remove(id);
                              }
                            }),
                            title: Text(rotuloEquipamento(e)),
                            subtitle: detalhe.isEmpty ? null : Text(detalhe),
                          );
                        },
                      ),
              ),
            ],
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (widget.podeIncluir) ...[
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context)
                      .pop(_Resultado(incluir: _busca.text, selecionados: {..._sel})),
                  icon: const Icon(Icons.add),
                  label: Text(_busca.text.trim().isEmpty
                      ? 'Incluir equipamento'
                      : 'Incluir "${_busca.text.trim()}"'),
                ),
                const Spacer(),
              ],
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _todos == null ? null : _devolver,
                child: Text('Usar ${_sel.length} equipamento(s)'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Resumo dos equipamentos escolhidos: contagem + etiquetas (as primeiras),
/// com botão para escolher/alterar e para tirar um da lista.
class ResumoEquipamentos extends StatelessWidget {
  const ResumoEquipamentos({
    super.key,
    required this.escolhidos,
    required this.aoEscolher,
    required this.aoRemover,
    this.habilitado = true,
  });

  final Map<String, String> escolhidos;
  final VoidCallback aoEscolher;
  final ValueChanged<String> aoRemover;
  final bool habilitado;

  static const _maximoVisivel = 24;

  @override
  Widget build(BuildContext context) {
    final itens = escolhidos.entries.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        FilledButton.tonalIcon(
          onPressed: habilitado ? aoEscolher : null,
          icon: const Icon(Icons.checklist),
          label: Text(escolhidos.isEmpty ? 'Escolher equipamentos' : 'Alterar escolha'),
        ),
        const SizedBox(width: 12),
        Text(escolhidos.isEmpty ? 'Nenhum escolhido (a OS pode ser aberta assim mesmo).' : '${escolhidos.length} escolhido(s)',
            style: const TextStyle(color: Cores.neutro)),
      ]),
      if (itens.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in itens.take(_maximoVisivel))
            InputChip(
              label: Text(e.value),
              onDeleted: habilitado ? () => aoRemover(e.key) : null,
              visualDensity: VisualDensity.compact,
            ),
          if (itens.length > _maximoVisivel)
            Chip(label: Text('+${itens.length - _maximoVisivel}'), visualDensity: VisualDensity.compact),
        ]),
      ],
    ]);
  }
}
