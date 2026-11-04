import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/status.dart';

/// Montar o dia (guia 76): o sistema distribui o que está para agendar entre
/// as equipes (urgentes e SLA primeiro; quem já vai estar perto; quem atendeu
/// o local da última vez; a mais livre). O gestor confere, desmarca o que não
/// quer e aplica. [publicar]: no modo simples vai direto para o app; no quadro
/// fica em rascunho para conferir e publicar. Devolve true se aplicou.
Future<bool> montarODia(BuildContext context, {required bool publicar}) async =>
    await showDialog<bool>(context: context, builder: (_) => _MontarDia(publicar: publicar)) ?? false;

class _MontarDia extends StatefulWidget {
  const _MontarDia({required this.publicar});

  final bool publicar;

  @override
  State<_MontarDia> createState() => _MontarDiaState();
}

class _MontarDiaState extends State<_MontarDia> {
  late DateTime _data = DateTime.now().add(const Duration(days: 1));
  int _max = 5;
  Map<String, dynamic>? _r;
  final _fora = <String>{};
  bool _ocupado = false;
  String? _erro;

  SupabaseClient get _db => Supabase.instance.client;
  String get _iso => '${_data.year}-${_data.month.toString().padLeft(2, '0')}-${_data.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _sugerir();
  }

  Future<void> _sugerir() async {
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('dia_sugerir', params: {
        'p': {'data': _iso, 'max_por_equipe': _max}
      }) as Map);
      if (mounted) {
        setState(() {
          _r = r;
          _fora.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _aplicar() async {
    final itens = [
      for (final s in ((_r?['sugestao'] as List?) ?? const []).cast<Map>())
        if (!_fora.contains('${s['agendamento_id']}')) {'agendamento_id': s['agendamento_id'], 'equipe_id': s['equipe_id']},
    ];
    if (itens.isEmpty) return;
    setState(() => _ocupado = true);
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('dia_aplicar', params: {
        'p': {'data': _iso, 'publicar': widget.publicar, 'itens': itens}
      }) as Map);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.publicar
              ? '${r['agendados']} serviço(s) agendados para ${dataBr(_iso)}. Os técnicos recebem no app.'
              : '${r['agendados']} serviço(s) no quadro de ${dataBr(_iso)}, em rascunho: confira e publique.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sug = ((_r?['sugestao'] as List?) ?? const []).cast<Map>();
    final sobra = ((_r?['sobra'] as List?) ?? const []).cast<Map>();
    final equipes = <String, List<Map>>{};
    for (final s in sug) {
      equipes.putIfAbsent('${s['equipe']}', () => []).add(s);
    }
    final escolhidos = sug.where((s) => !_fora.contains('${s['agendamento_id']}')).length;
    return AlertDialog(
      title: const Text('Montar o dia'),
      content: SizedBox(
        width: 640,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
              'Distribui o que está para agendar: urgentes e SLA primeiro; vai para a equipe que já estará perto '
              '(mesmo bairro ou região), senão para quem atendeu o local da última vez, senão para a mais livre.',
              style: TextStyle(color: Cores.neutro)),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(
              onPressed: _ocupado
                  ? null
                  : () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _data,
                        firstDate: DateTime.now().subtract(const Duration(hours: 12)),
                        lastDate: DateTime.now().add(const Duration(days: 60)),
                      );
                      if (d != null) {
                        setState(() => _data = d);
                        _sugerir();
                      }
                    },
              icon: const Icon(Icons.event),
              label: Text(dataBr(_iso)),
            ),
            const Text('Até'),
            SizedBox(
              width: 90,
              child: InputDecorator(
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _max,
                  isDense: true,
                  items: [for (final n in [2, 3, 4, 5, 6, 8, 10]) DropdownMenuItem(value: n, child: Text('$n'))],
                  onChanged: _ocupado
                      ? null
                      : (v) {
                          setState(() => _max = v ?? 5);
                          _sugerir();
                        },
                ),
              ),
            ),
            ),
            const Text('serviços por equipe no dia'),
          ]),
          if (_erro != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_erro!, style: const TextStyle(color: Cores.erro))),
          const SizedBox(height: 8),
          if (_ocupado && _r == null) const LinearProgressIndicator(),
          Flexible(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (_r != null && sug.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Nada para agendar nesse dia (a fila está vazia ou as equipes estão cheias).'),
                  ),
                for (final e in equipes.entries) ...[
                  const SizedBox(height: 8),
                  Text('${e.key} · ${e.value.length} novo(s)', style: const TextStyle(fontWeight: FontWeight.w700)),
                  for (final s in e.value)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: !_fora.contains('${s['agendamento_id']}'),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _fora.remove('${s['agendamento_id']}');
                        } else {
                          _fora.add('${s['agendamento_id']}');
                        }
                      }),
                      title: Text('${s['os']} · ${s['cliente']} · ${s['local']}'),
                      subtitle: Text([
                        if (s['prioridade'] == 'urgente' || s['prioridade'] == 'alta') 'prioridade ${s['prioridade']}',
                        if (s['sla_prazo'] != null) 'SLA ${dataHoraBr(s['sla_prazo'])}',
                        if ((s['bairro'] ?? '') != '') '${s['bairro']}',
                        '${s['motivo']}',
                      ].join(' · ')),
                    ),
                ],
                if (sobra.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Não couberam (${sobra.length}): ${sobra.take(8).map((s) => s['os']).join(', ')}'
                      '${sobra.length > 8 ? '...' : ''}', style: const TextStyle(color: Cores.alerta)),
                ],
              ]),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _ocupado || escolhidos == 0 ? null : _aplicar,
          child: Text(widget.publicar ? 'Agendar $escolhidos' : 'Pôr $escolhidos no quadro'),
        ),
      ],
    );
  }
}
