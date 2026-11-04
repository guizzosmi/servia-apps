import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'erros.dart';
import 'links.dart';
import 'tema.dart';

/// Rota do dia (guia 77): as visitas de uma equipe no dia, na ordem, e o
/// link do Google Maps com as paradas que faltam (sai de onde a pessoa está).
/// Com [podeOrdenar] (gestor), aplica a ordem sugerida (o mesmo bairro junto;
/// com coordenadas, o mais perto primeiro).
Future<bool> abrirRotaDoDia(BuildContext context, {required String parteId, bool podeOrdenar = false}) async =>
    await showDialog<bool>(context: context, builder: (_) => _Rota(parteId: parteId, podeOrdenar: podeOrdenar)) ?? false;

/// O link do Google Maps (sem chave de API) para as paradas, na ordem.
/// Até 10 paradas (o limite do link): a última é o destino.
Uri? linkRotaGoogle(List<Map> paradas) {
  final pontos = <String>[
    for (final p in paradas)
      if (p['latitude'] != null && p['longitude'] != null)
        '${p['latitude']},${p['longitude']}'
      else if ('${p['endereco'] ?? ''}'.trim().isNotEmpty)
        '${p['endereco']}'.trim(),
  ].take(10).toList();
  if (pontos.isEmpty) return null;
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': pontos.last,
    if (pontos.length > 1) 'waypoints': pontos.sublist(0, pontos.length - 1).join('|'),
    'travelmode': 'driving',
  });
}

class _Rota extends StatefulWidget {
  const _Rota({required this.parteId, required this.podeOrdenar});

  final String parteId;
  final bool podeOrdenar;

  @override
  State<_Rota> createState() => _RotaState();
}

class _RotaState extends State<_Rota> {
  Map<String, dynamic>? _r;
  bool _sugerida = false;
  bool _ocupado = false;
  String? _erro;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('rota_do_dia', params: {
        'p': {'parte_id': widget.parteId}
      }) as Map);
      if (mounted) setState(() => _r = r);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    }
  }

  List<Map> get _paradas {
    final todas = ((_r?['paradas'] as List?) ?? const []).cast<Map>();
    if (!_sugerida) return todas;
    final ordem = ((_r?['ordem_sugerida'] as List?) ?? const []).map((e) => '$e').toList();
    final porId = {for (final p in todas) '${p['parte_item_id']}': p};
    return [for (final id in ordem) if (porId[id] != null) porId[id]!];
  }

  Future<void> _aplicar() async {
    setState(() => _ocupado = true);
    try {
      await _db.rpc('rota_ordenar', params: {
        'p': {'parte_id': widget.parteId, 'itens': _r?['ordem_sugerida']}
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ordem do dia atualizada.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paradas = _paradas;
    final faltam = paradas.where((p) => p['status'] == 'programado' || p['status'] == 'em_deslocamento').toList();
    final semEndereco = faltam.where((p) =>
        p['latitude'] == null && '${p['endereco'] ?? ''}'.trim().isEmpty).length;
    final link = linkRotaGoogle(faltam);
    final mudou = _r?['ordem_mudou'] == true;
    return AlertDialog(
      title: Text('Rota do dia${_r?['equipe'] != null ? ' · ${_r!['equipe']}' : ''}'),
      content: SizedBox(
        width: 520,
        child: _r == null && _erro == null
            ? const LinearProgressIndicator()
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
                  if (paradas.isEmpty && _erro == null) const Text('Nenhuma visita neste dia.'),
                  if (mudou)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _sugerida,
                      onChanged: (v) => setState(() => _sugerida = v),
                      title: const Text('Ver na ordem sugerida'),
                      subtitle: Text(_r?['com_coordenadas'] == true
                          ? 'O mais perto primeiro (pelas coordenadas dos locais).'
                          : 'As visitas do mesmo bairro juntas.'),
                    ),
                  for (var i = 0; i < paradas.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor:
                            paradas[i]['status'] == 'programado' ? Cores.indigo100 : Cores.linha,
                        child: Text('${i + 1}', style: const TextStyle(fontSize: 12)),
                      ),
                      title: Text('${paradas[i]['cliente']} · ${paradas[i]['local']}'),
                      subtitle: Text('${paradas[i]['endereco'] ?? 'sem endereço no cadastro do local'}'),
                    ),
                  if (semEndereco > 0)
                    Text('$semEndereco visita(s) sem endereço no local ficam fora do mapa.',
                        style: const TextStyle(color: Cores.alerta, fontSize: 12)),
                ]),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Fechar')),
        if (widget.podeOrdenar && mudou && _sugerida)
          OutlinedButton(onPressed: _ocupado ? null : _aplicar, child: const Text('Usar esta ordem')),
        if (link != null)
          FilledButton.icon(
            onPressed: () => abrirLink(link.toString()),
            icon: const Icon(Icons.map_outlined),
            label: Text('Abrir no mapa (${faltam.length > 10 ? 10 : faltam.length})'),
          ),
      ],
    );
  }
}
