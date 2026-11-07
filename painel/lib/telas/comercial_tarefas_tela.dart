import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/arquivo_web.dart';
import '../servicos/comercial.dart';
import '../servicos/status.dart';
import '../widgets/margem.dart';

/// Tarefas do Comercial (guia 90): atrasadas, de hoje e dos próximos 7 dias.
class ComercialTarefasTela extends StatefulWidget {
  const ComercialTarefasTela({super.key});

  @override
  State<ComercialTarefasTela> createState() => _ComercialTarefasTelaState();
}

class _ComercialTarefasTelaState extends State<ComercialTarefasTela> {
  bool _todas = false;
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _itens = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await Supabase.instance.client.rpc('comercial_tarefas', params: {
        'p': {'todas': _todas}
      });
      if (mounted) setState(() => _itens = (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _concluir(Map<String, dynamic> t) async {
    try {
      await Supabase.instance.client
          .from('com_atividades')
          .update({'concluida_em': DateTime.now().toUtc().toIso8601String()})
          .eq('id', t['id'] as String);
      if (mounted) _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagemDeErro(e)), backgroundColor: Cores.erro));
      }
    }
  }

  String _grupo(Map<String, dynamic> t) {
    final d = DateTime.tryParse('${t['previsto_para'] ?? ''}')?.toLocal();
    if (d == null) return 'Sem data';
    final hoje = DateTime.now();
    if (t['atrasada'] == true) return 'Atrasadas';
    if (d.year == hoje.year && d.month == hoje.month && d.day == hoje.day) return 'Hoje';
    return 'Próximos dias';
  }

  @override
  Widget build(BuildContext context) {
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final t in _itens) {
      grupos.putIfAbsent(_grupo(t), () => []).add(t);
    }
    return ListView(padding: margemDaTela(context), children: [
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        IconButton(onPressed: () => context.go('/comercial'), icon: const Icon(Icons.arrow_back), tooltip: 'Funil'),
        Text('Tarefas do comercial', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        FilterChip(
          label: const Text('De todos'),
          selected: _todas,
          onSelected: (v) {
            setState(() => _todas = v);
            _carregar();
          },
        ),
        IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
      ]),
      const SizedBox(height: 4),
      const Text('As suas e as sem responsável. Concluiu? A oportunidade precisa de uma próxima tarefa.',
          style: TextStyle(color: Cores.neutro)),
      const SizedBox(height: 12),
      if (_carregando) const LinearProgressIndicator(minHeight: 2),
      if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
      if (!_carregando && _itens.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Nenhuma tarefa pendente.')),
      for (final g in const ['Atrasadas', 'Hoje', 'Próximos dias', 'Sem data'])
        if (grupos[g] != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(g, style: TextStyle(fontWeight: FontWeight.w800, color: g == 'Atrasadas' ? Cores.erro : Cores.indigo700)),
          ),
          for (final t in grupos[g]!)
            Card(
              child: ListTile(
                leading: Text(tiposAtividade[t['tipo']] ?? '', style: const TextStyle(fontSize: 12, color: Cores.neutro)),
                title: Text('${t['titulo']}'),
                subtitle: Text([
                  if (t['previsto_para'] != null) dataHoraBr(t['previsto_para']),
                  if (t['oportunidade'] != null) '${t['oportunidade']}',
                  if (t['cliente'] != null) '${t['cliente']}',
                  if (t['responsavel'] != null) '${t['responsavel']}',
                ].join(' · ')),
                onTap: t['oportunidade_id'] == null ? null : () => context.push('/comercial/${t['oportunidade_id']}'),
                trailing: Wrap(spacing: 4, children: [
                  if (linkWhatsapp(t['telefone']) != null)
                    IconButton(
                      tooltip: 'WhatsApp',
                      icon: const Icon(Icons.chat_outlined),
                      onPressed: () => abrirEmNovaAba(linkWhatsapp(t['telefone'])!),
                    ),
                  TextButton(onPressed: () => _concluir(t), child: const Text('Concluir')),
                ]),
              ),
            ),
        ],
    ]);
  }
}
