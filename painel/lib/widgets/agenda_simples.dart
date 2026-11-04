import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/status.dart';

/// Modo simples (guia 62): agendar, reagendar e tirar da agenda sem o quadro.
/// Por baixo é a parte do dia de sempre (a função agenda_simples abre o dia
/// da equipe, programa e publica), então o app do técnico recebe igual.

Future<Map<String, dynamic>> acaoAgendaSimples(Map<String, dynamic> p) async {
  final r = await Supabase.instance.client.rpc('agenda_simples', params: {'p': p});
  return Map<String, dynamic>.from(r as Map);
}

/// Equipes ativas (no modo simples, "quem vai fazer").
Future<List<Map<String, dynamic>>> equipesAtivas() async {
  final r = await Supabase.instance.client
      .from('equipes')
      .select('id, nome')
      .eq('ativa', true)
      .isFilter('excluido_em', null)
      .order('nome');
  return List<Map<String, dynamic>>.from(r);
}

/// Pergunta o dia e quem vai fazer e agenda (ou reagenda, com [parteItemId]).
/// Devolve true se agendou.
Future<bool> agendarSimples(BuildContext context,
    {required String agendamentoId, String? parteItemId, String? titulo}) async {
  List<Map<String, dynamic>> equipes;
  try {
    equipes = await equipesAtivas();
  } catch (e) {
    if (context.mounted) _avisar(context, mensagemDeErro(e), erro: true);
    return false;
  }
  if (!context.mounted) return false;
  if (equipes.isEmpty) {
    _avisar(context, 'Cadastre o técnico e a equipe dele (Cadastros > Equipes) antes de agendar.', erro: true);
    return false;
  }
  final escolha = await showDialog<(DateTime, String)>(
    context: context,
    builder: (_) => _DialogoAgendar(equipes: equipes, titulo: titulo ?? (parteItemId == null ? 'Agendar' : 'Reagendar')),
  );
  if (escolha == null || !context.mounted) return false;
  try {
    await acaoAgendaSimples({
      'acao': parteItemId == null ? 'agendar' : 'reagendar',
      if (parteItemId == null) 'agendamento_id': agendamentoId else 'parte_item_id': parteItemId,
      'data': dataIso(escolha.$1),
      'equipe_id': escolha.$2,
    });
    if (context.mounted) _avisar(context, 'Agendado para ${dataBr(dataIso(escolha.$1))}. O técnico já recebe no app.');
    return true;
  } catch (e) {
    if (context.mounted) _avisar(context, mensagemDeErro(e), erro: true);
    return false;
  }
}

/// Tira o serviço da agenda: ele volta para "Para agendar".
Future<bool> tirarDaAgenda(BuildContext context, String parteItemId) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Tirar da agenda?'),
      content: const Text('O serviço volta para "Para agendar" e some do app do técnico.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Tirar da agenda')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await acaoAgendaSimples({'acao': 'tirar', 'parte_item_id': parteItemId});
    if (context.mounted) _avisar(context, 'Tirado da agenda: voltou para agendar.');
    return true;
  } catch (e) {
    if (context.mounted) _avisar(context, mensagemDeErro(e), erro: true);
    return false;
  }
}

void _avisar(BuildContext context, String texto, {bool erro = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null),
  );
}

class _DialogoAgendar extends StatefulWidget {
  const _DialogoAgendar({required this.equipes, required this.titulo});

  final List<Map<String, dynamic>> equipes;
  final String titulo;

  @override
  State<_DialogoAgendar> createState() => _DialogoAgendarState();
}

class _DialogoAgendarState extends State<_DialogoAgendar> {
  late DateTime _dia;
  late String _equipe;

  DateTime get _hoje {
    final h = DateTime.now();
    return DateTime(h.year, h.month, h.day);
  }

  @override
  void initState() {
    super.initState();
    _dia = _hoje;
    _equipe = '${widget.equipes.first['id']}';
  }

  Future<void> _outroDia() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dia,
      firstDate: _hoje,
      lastDate: _hoje.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _dia = d);
  }

  @override
  Widget build(BuildContext context) {
    final amanha = _hoje.add(const Duration(days: 1));
    final outro = _dia != _hoje && _dia != amanha;
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Quando?', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('Hoje'), selected: _dia == _hoje, onSelected: (_) => setState(() => _dia = _hoje)),
            ChoiceChip(label: const Text('Amanhã'), selected: _dia == amanha, onSelected: (_) => setState(() => _dia = amanha)),
            ChoiceChip(
              label: Text(outro ? dataBr(dataIso(_dia)) : 'Outro dia...'),
              selected: outro,
              onSelected: (_) => _outroDia(),
            ),
          ]),
          if (widget.equipes.length > 1) ...[
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Quem vai fazer'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _equipe,
                  isDense: true,
                  isExpanded: true,
                  items: [
                    for (final e in widget.equipes) DropdownMenuItem(value: '${e['id']}', child: Text('${e['nome']}')),
                  ],
                  onChanged: (v) => setState(() => _equipe = v ?? _equipe),
                ),
              ),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, (_dia, _equipe)), child: const Text('Agendar')),
      ],
    );
  }
}
