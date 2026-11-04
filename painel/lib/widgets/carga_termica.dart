import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'itens_os.dart' show dinheiro, lerNumero, numeroBr;

/// Carga térmica (guia 69): a capacidade que o ambiente precisa, pela conta
/// prática (600 BTU/h por m², 800 com sol da tarde, +600 por pessoa além da
/// primeira e por aparelho que esquenta). Os ambientes do local já vêm com a
/// área e os ocupantes do levantamento. Devolve as peças e serviços escolhidos
/// para o orçamento: [{produto_id, quantidade}].
Future<List<Map<String, dynamic>>?> calcularCargaTermica(BuildContext context, {String? localId}) =>
    showDialog<List<Map<String, dynamic>>>(context: context, builder: (_) => _CargaTermica(localId: localId));

class _CargaTermica extends StatefulWidget {
  const _CargaTermica({this.localId});

  final String? localId;

  @override
  State<_CargaTermica> createState() => _CargaTermicaState();
}

class _CargaTermicaState extends State<_CargaTermica> {
  final _area = TextEditingController();
  final _pessoas = TextEditingController(text: '1');
  final _eletronicos = TextEditingController(text: '0');
  bool _sol = false;
  String _uso = 'residencial';
  List<Map<String, dynamic>> _ambientes = [];
  String? _ambiente;
  Map<String, dynamic>? _r;
  final Map<String, int> _escolhidos = {};
  String? _erro;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    if (widget.localId != null) {
      _db.rpc('carga_termica_local', params: {
        'p': {'local_id': widget.localId}
      }).then((r) {
        if (mounted) setState(() => _ambientes = List<Map<String, dynamic>>.from(((r as Map)['ambientes'] as List?) ?? const []));
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _area.dispose();
    _pessoas.dispose();
    _eletronicos.dispose();
    super.dispose();
  }

  void _usarAmbiente(String? id) {
    final a = _ambientes.where((x) => x['id'] == id).firstOrNull;
    setState(() {
      _ambiente = id;
      if (a != null) {
        if (a['area_m2'] != null) _area.text = numeroBr(a['area_m2']);
        final o = num.tryParse('${a['ocupantes'] ?? ''}') ?? 0;
        if (o > 0) _pessoas.text = '$o';
      }
    });
  }

  Future<void> _calcular() async {
    setState(() => _erro = null);
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('carga_termica', params: {
        'p': {
          'area_m2': lerNumero(_area.text),
          'ocupantes': lerNumero(_pessoas.text) ?? 1,
          'eletronicos': lerNumero(_eletronicos.text) ?? 0,
          'sol_tarde': _sol,
          'uso': _uso,
        }
      }) as Map);
      if (r['ok'] != true) {
        setState(() => _erro = '${r['mensagem'] ?? 'Confira os dados.'}');
        return;
      }
      setState(() {
        _r = r;
        _escolhidos.clear();
      });
    } catch (e) {
      setState(() => _erro = mensagemDeErro(e));
    }
  }

  Widget _campo(TextEditingController c, String rotulo, {String? sufixo}) => SizedBox(
        width: 140,
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: rotulo, suffixText: sufixo),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final amb = _ambientes.where((x) => x['id'] == _ambiente).firstOrNull;
    final instalado = num.tryParse('${amb?['instalado_btu'] ?? 0}') ?? 0;
    return AlertDialog(
      title: const Text('Carga térmica'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_ambientes.isNotEmpty) ...[
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Ambiente do local (do levantamento)'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _ambiente,
                    isDense: true,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Digitar a área')),
                      for (final a in _ambientes)
                        DropdownMenuItem<String?>(
                          value: '${a['id']}',
                          child: Text([
                            a['nome'],
                            if (a['area_m2'] != null) '${numeroBr(a['area_m2'])} m²',
                            if ((num.tryParse('${a['aparelhos'] ?? 0}') ?? 0) > 0) '${a['aparelhos']} aparelho(s)',
                          ].join(' · ')),
                        ),
                    ],
                    onChanged: _usarAmbiente,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(spacing: 12, runSpacing: 12, children: [
              _campo(_area, 'Área', sufixo: 'm²'),
              _campo(_pessoas, 'Pessoas'),
              _campo(_eletronicos, 'Aparelhos que esquentam'),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilterChip(label: const Text('Sol da tarde'), selected: _sol, onSelected: (v) => setState(() => _sol = v)),
              for (final u in const [('residencial', 'Residencial'), ('comercial', 'Comercial'), ('cozinha', 'Cozinha'), ('servidor', 'Sala de servidor')])
                ChoiceChip(label: Text(u.$2), selected: _uso == u.$1, onSelected: (_) => setState(() => _uso = u.$1)),
            ]),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(onPressed: _calcular, icon: const Icon(Icons.calculate_outlined), label: const Text('Calcular')),
            if (_erro != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_erro!, style: const TextStyle(color: Cores.erro))),
            if (r != null) ...[
              const Divider(height: 24),
              Text('${numeroBr(r['btu_h'])} BTU/h', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text('${r['conta']}', style: const TextStyle(color: Cores.neutro, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                (num.tryParse('${r['quantidade']}') ?? 1) > 1
                    ? 'Sugestão: ${r['quantidade']} aparelhos de ${numeroBr(r['capacidade'])} BTU/h'
                    : 'Sugestão: 1 aparelho de ${numeroBr(r['capacidade'])} BTU/h',
                style: const TextStyle(fontWeight: FontWeight.w700, color: Cores.indigo700),
              ),
              if (instalado > 0)
                Text(
                  'Já instalado no ambiente: ${numeroBr(instalado)} BTU/h'
                  '${instalado < (num.tryParse('${r['btu_h']}') ?? 0) ? ' (falta capacidade)' : ' (dá conta)'}',
                  style: TextStyle(color: instalado < (num.tryParse('${r['btu_h']}') ?? 0) ? Cores.erro : Cores.sucesso),
                ),
              const SizedBox(height: 8),
              const Text('Conta prática para orientar; o técnico confere no local (pé-direito, vidros, uso).',
                  style: TextStyle(color: Cores.neutro, fontSize: 12)),
              const SizedBox(height: 8),
              for (final grupo in [('Aparelhos do catálogo', 'produtos'), ('Instalação', 'servicos')]) ...[
                Text(grupo.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (((r[grupo.$2] as List?) ?? const []).isEmpty)
                  Text(
                      grupo.$2 == 'produtos'
                          ? 'Nenhum produto com "${numeroBr(r['capacidade'])}" na descrição. Adicione pelo "Adicionar item".'
                          : 'Nenhum serviço com "instala" na descrição.',
                      style: const TextStyle(color: Cores.neutro, fontSize: 12)),
                for (final p in ((r[grupo.$2] as List?) ?? const []).cast<Map>())
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _escolhidos.containsKey('${p['id']}'),
                    title: Text('${p['descricao']}'),
                    subtitle: Text(dinheiro(p['preco'])),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _escolhidos['${p['id']}'] = (num.tryParse('${r['quantidade']}') ?? 1).toInt();
                      } else {
                        _escolhidos.remove('${p['id']}');
                      }
                    }),
                  ),
              ],
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        if (_escolhidos.isNotEmpty)
          FilledButton(
            onPressed: () => Navigator.pop(context, [
              for (final e in _escolhidos.entries) {'produto_id': e.key, 'quantidade': e.value},
            ]),
            child: Text('Adicionar ${_escolhidos.length} ao orçamento'),
          ),
      ],
    );
  }
}
