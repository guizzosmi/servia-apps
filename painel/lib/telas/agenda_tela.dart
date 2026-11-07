import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/status.dart';
import '../widgets/agenda_simples.dart';
import '../widgets/fila.dart';
import '../widgets/margem.dart';
import '../widgets/montar_dia.dart';
import '../widgets/status_chip.dart';

/// Agenda do modo simples (guia 62): o que falta agendar e os próximos 14
/// dias, numa lista. Substitui o quadro do dia e a fila.
class AgendaTela extends StatefulWidget {
  const AgendaTela({super.key});

  @override
  State<AgendaTela> createState() => _AgendaTelaState();
}

class _AgendaTelaState extends State<AgendaTela> {
  List<Map<String, dynamic>> _fila = [];
  List<Map<String, dynamic>> _agenda = [];
  bool _carregando = true;
  String? _erro;

  static const _dias = 14;

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
      final h = DateTime.now();
      final hoje = DateTime(h.year, h.month, h.day);
      final fila = await carregarFila();
      final agenda = await Supabase.instance.client
          .from('partes_itens')
          .select('id, status, data, ordem, agendamento_id, resultado_motivo, '
              'partes_diarias!inner(equipe_id, status, equipes(nome)), '
              'agendamentos(os_id, tipo, janela_inicio, janela_fim, '
              'ordens_servico(codigo, problema_relatado, clientes(nome), locais(nome, cidade)))')
          .gte('data', dataIso(hoje))
          .lte('data', dataIso(hoje.add(const Duration(days: _dias - 1))))
          .eq('papel_equipe', 'responsavel')
          .neq('status', 'removido')
          .isFilter('excluido_em', null)
          .order('data', ascending: true)
          .order('ordem', ascending: true);
      if (mounted) {
        setState(() {
          _fila = fila;
          _agenda = List<Map<String, dynamic>>.from(agenda);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _novaOs() async {
    final novaOs = await context.push<String>('/os/nova');
    if (!mounted) return;
    if (novaOs != null) await context.push('/os/$novaOs');
    if (mounted) _carregar();
  }

  Future<void> _abrirOs(String? osId) async {
    if (osId == null) return;
    await context.push('/os/$osId');
    if (mounted) _carregar();
  }

  Future<void> _agendar(Map<String, dynamic> ag) async {
    if (await agendarSimples(context, agendamentoId: '${ag['id']}')) _carregar();
  }

  Future<void> _reagendar(Map<String, dynamic> it) async {
    if (await agendarSimples(context, agendamentoId: '${it['agendamento_id']}', parteItemId: '${it['id']}')) _carregar();
  }

  Future<void> _tirar(Map<String, dynamic> it) async {
    if (await tirarDaAgenda(context, '${it['id']}')) _carregar();
  }

  String _tituloDia(String iso) {
    final h = DateTime.now();
    final hoje = dataIso(DateTime(h.year, h.month, h.day));
    final amanha = dataIso(DateTime(h.year, h.month, h.day + 1));
    final d = DateTime.parse(iso);
    const semana = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
    final nome = iso == hoje ? 'Hoje' : iso == amanha ? 'Amanhã' : semana[d.weekday - 1];
    return '$nome · ${dataBr(iso)}';
  }

  @override
  Widget build(BuildContext context) {
    final porDia = <String, List<Map<String, dynamic>>>{};
    for (final it in _agenda) {
      porDia.putIfAbsent('${it['data']}', () => []).add(it);
    }
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          Expanded(
            child: Text('Agenda', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          IconButton(tooltip: 'Atualizar', onPressed: _carregando ? null : _carregar, icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
          // Guia 76: agenda o que está para agendar, distribuído entre as equipes.
          OutlinedButton.icon(
            onPressed: () async {
              if (await montarODia(context, publicar: true)) _carregar();
            },
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: const Text('Montar o dia'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: _novaOs, icon: const Icon(Icons.add), label: const Text('Nova OS')),
        ]),
        const SizedBox(height: 4),
        const Text('Agende cada serviço num dia: o técnico recebe no app. O que não for feito volta para cá sozinho.',
            style: TextStyle(color: Cores.neutro)),
        const SizedBox(height: 12),
        if (_carregando) const LinearProgressIndicator(minHeight: 2),
        if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
        // ---------- para agendar ----------
        const SizedBox(height: 8),
        Text('Para agendar (${_fila.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (!_carregando && _fila.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nada esperando agendamento.', style: TextStyle(color: Cores.neutro)),
          ),
        for (final a in _fila)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CartaoFila(
              ag: a,
              aoTocar: () => _abrirOs(a['os_id'] as String?),
              acoes: FilledButton.tonalIcon(
                onPressed: () => _agendar(a),
                icon: const Icon(Icons.event_available, size: 18),
                label: const Text('Agendar'),
              ),
            ),
          ),
        // ---------- próximos dias ----------
        const SizedBox(height: 16),
        const Text('Próximos dias', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (!_carregando && porDia.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nenhum serviço agendado nos próximos 14 dias.', style: TextStyle(color: Cores.neutro)),
          ),
        for (final dia in porDia.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(_tituloDia(dia.key),
                style: const TextStyle(fontWeight: FontWeight.w700, color: Cores.indigo700)),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              for (final it in dia.value) _linha(it),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _linha(Map<String, dynamic> it) {
    final ag = it['agendamentos'] as Map? ?? const {};
    final os = ag['ordens_servico'] as Map? ?? const {};
    final local = os['locais'] as Map? ?? const {};
    final equipe = ((it['partes_diarias'] as Map?)?['equipes'] as Map?)?['nome'];
    final status = it['status'] as String?;
    final podeMexer = ['programado', 'em_deslocamento'].contains(status);
    final janelaTxt = janela(ag['janela_inicio'], ag['janela_fim']);
    return ListTile(
      onTap: () => _abrirOs(ag['os_id'] as String?),
      title: Text([os['codigo'], (os['clientes'] as Map?)?['nome']].where((x) => x != null).join(' · ')),
      subtitle: Text([
        [local['nome'], local['cidade']].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
        if (janelaTxt.isNotEmpty) janelaTxt,
        if (equipe != null) '$equipe',
        if ('${os['problema_relatado'] ?? ''}'.trim().isNotEmpty) '${os['problema_relatado']}',
      ].where((x) => x.isNotEmpty).join('\n')),
      isThreeLine: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        StatusChip(status, statusItem, compacto: true),
        if (podeMexer)
          PopupMenuButton<String>(
            tooltip: 'Ações',
            onSelected: (op) => op == 'reagendar' ? _reagendar(it) : _tirar(it),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reagendar', child: Text('Reagendar')),
              PopupMenuItem(value: 'tirar', child: Text('Tirar da agenda')),
            ],
          ),
      ]),
    );
  }
}
