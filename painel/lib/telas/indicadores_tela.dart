import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/status.dart';
import '../widgets/itens_os.dart' show dinheiro;
import '../widgets/margem.dart';

/// Indicadores (guia 61): o mês (ou outro período) em números: OS, tempo de
/// atendimento, horas por técnico, medições fora da faixa, IA aceita sem
/// edição, orçamentos e preventivas.
class IndicadoresTela extends StatefulWidget {
  const IndicadoresTela({super.key});

  @override
  State<IndicadoresTela> createState() => _IndicadoresTelaState();
}

const _statusOs = {
  'aberta': 'Abertas', 'agendada': 'Agendadas', 'em_andamento': 'Em andamento',
  'aguardando_aprovacao': 'Aguardando aprovação', 'aguardando_peca': 'Aguardando peça',
  'aguardando_cliente': 'Aguardando cliente', 'concluida': 'Concluídas', 'cancelada': 'Canceladas',
};

class _IndicadoresTelaState extends State<IndicadoresTela> {
  String _periodo = 'mes';
  Map<String, dynamic>? _d;
  String? _erro;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  (DateTime, DateTime) _datas() {
    final h = DateTime.now();
    final hoje = DateTime(h.year, h.month, h.day);
    return switch (_periodo) {
      'anterior' => (DateTime(h.year, h.month - 1, 1), DateTime(h.year, h.month, 0)),
      '90' => (hoje.subtract(const Duration(days: 89)), hoje),
      'ano' => (DateTime(h.year, 1, 1), hoje),
      _ => (DateTime(h.year, h.month, 1), hoje),
    };
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final (de, ate) = _datas();
      final r = await Supabase.instance.client.rpc('indicadores', params: {
        'p': {'de': dataIso(de), 'ate': dataIso(ate)}
      });
      if (mounted) setState(() => _d = Map<String, dynamic>.from(r as Map));
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  static num _n(Object? v) => num.tryParse('${v ?? 0}') ?? 0;

  static String _pct(num parte, num total) => total <= 0 ? '—' : '${(100 * parte / total).round()}%';

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return ListView(padding: margemDaTela(context), children: [
      Text('Indicadores', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        for (final p in const [('mes', 'Este mês'), ('anterior', 'Mês passado'), ('90', 'Últimos 90 dias'), ('ano', 'Este ano')])
          ChoiceChip(
            label: Text(p.$2),
            selected: _periodo == p.$1,
            onSelected: (_) {
              setState(() => _periodo = p.$1);
              _carregar();
            },
          ),
      ]),
      const SizedBox(height: 12),
      if (_carregando) const LinearProgressIndicator(minHeight: 2),
      if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
      if (d != null) ..._conteudo(d),
    ]);
  }

  List<Widget> _conteudo(Map<String, dynamic> d) {
    final os = Map<String, dynamic>.from((d['os'] as Map?) ?? const {});
    final atd = Map<String, dynamic>.from((d['atendimentos'] as Map?) ?? const {});
    final med = Map<String, dynamic>.from((d['medicoes'] as Map?) ?? const {});
    final ia = Map<String, dynamic>.from((d['ia'] as Map?) ?? const {});
    final orc = Map<String, dynamic>.from((d['orcamentos'] as Map?) ?? const {});
    final prev = Map<String, dynamic>.from((d['preventivas'] as Map?) ?? const {});
    final tecnicos = ((d['tecnicos'] as List?) ?? const []).cast<Map>();
    final porStatus = ((os['por_status'] as List?) ?? const []).cast<Map>();
    final tempo = _n(atd['tempo_medio_min']);
    return [
      Text('De ${dataBr(d['de'])} a ${dataBr(d['ate'])}', style: const TextStyle(color: Cores.neutro)),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _Numero('OS abertas', '${_n(os['abertas'])}'),
        _Numero('OS concluídas', '${_n(os['concluidas'])}', detalhe: dinheiro(os['valor_concluidas'])),
        _Numero('Tempo médio no cliente', tempo == 0 ? '—' : '${tempo ~/ 60}h${(tempo % 60).toString().padLeft(2, '0')}',
            detalhe: '${_n(atd['concluidos'])} atendimento(s)'),
        _Numero('Retornos', '${_n(os['retornos'])}', detalhe: 'OS de retorno ou garantia', alerta: _n(os['retornos']) > 0),
        _Numero('Medições fora da faixa', _pct(_n(med['fora_faixa']), _n(med['total'])),
            detalhe: '${_n(med['fora_faixa'])} de ${_n(med['total'])}', alerta: _n(med['fora_faixa']) > 0),
        _Numero('IA aceita sem editar', _pct(_n(ia['aceitos_sem_editar']), _n(ia['campos'])),
            detalhe: '${_n(ia['relatos'])} relato(s) revisado(s)'),
        _Numero('Orçamentos aprovados', '${_n(orc['aprovados'])} de ${_n(orc['enviados'])}',
            detalhe: '${_n(orc['aprovados_link'])} pelo link · ${dinheiro(orc['valor_aprovado'])}'),
        _Numero('Preventivas feitas', '${_n(prev['feitas'])}',
            detalhe: '${_n(prev['pendentes'])} pendente(s) · ${_n(prev['nao_conformes'])} não conforme(s)',
            alerta: _n(prev['pendentes']) > 0),
      ]),
      const SizedBox(height: 20),
      LayoutBuilder(builder: (context, box) {
        final largo = box.maxWidth >= 900;
        final cartoes = [
          _Barras(
            titulo: 'OS abertas no período, por situação',
            linhas: [for (final s in porStatus) (_statusOs[s['status']] ?? '${s['status']}', _n(s['n']), '${_n(s['n'])}')],
          ),
          _Barras(
            titulo: 'Horas no cliente por técnico',
            linhas: [
              for (final t in tecnicos)
                ('${t['nome']}', _n(t['horas']), '${_n(t['horas']).toString().replaceAll('.', ',')} h · ${_n(t['atendimentos'])} atend.')
            ],
          ),
        ];
        return largo
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: cartoes[0]),
                const SizedBox(width: 12),
                Expanded(child: cartoes[1]),
              ])
            : Column(children: [cartoes[0], const SizedBox(height: 12), cartoes[1]]);
      }),
    ];
  }
}

class _Numero extends StatelessWidget {
  const _Numero(this.titulo, this.valor, {this.detalhe, this.alerta = false});

  final String titulo;
  final String valor;
  final String? detalhe;
  final bool alerta;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: const TextStyle(color: Cores.neutro)),
              const SizedBox(height: 6),
              Text(valor,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: alerta ? Cores.alerta : Cores.tinta)),
              if (detalhe != null) Text(detalhe!, style: const TextStyle(fontSize: 12, color: Cores.neutro)),
            ]),
          ),
        ),
      );
}

class _Barras extends StatelessWidget {
  const _Barras({required this.titulo, required this.linhas});

  final String titulo;
  final List<(String, num, String)> linhas;

  @override
  Widget build(BuildContext context) {
    final maior = linhas.fold<num>(0, (m, l) => l.$2 > m ? l.$2 : m);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (linhas.isEmpty) const Text('Nada no período.', style: TextStyle(color: Cores.neutro)),
          for (final l in linhas)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(width: 150, child: Text(l.$1, overflow: TextOverflow.ellipsis)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maior <= 0 ? 0 : (l.$2 / maior).toDouble(),
                      minHeight: 12,
                      backgroundColor: Cores.indigo100,
                      color: Cores.indigo500,
                    ),
                  ),
                ),
                SizedBox(width: 130, child: Text(l.$3, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
              ]),
            ),
        ]),
      ),
    );
  }
}
