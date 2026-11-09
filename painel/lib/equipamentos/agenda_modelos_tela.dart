import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/comercial.dart' show reais;
import '../servicos/status.dart';
import '../widgets/margem.dart';
import 'servico.dart';
import 'widgets.dart';

/// Agenda por modelo (guia 102): "quantos livres do modelo X de tal a tal data", no período inteiro e dia a dia.
class EqpAgendaModelosTela extends StatefulWidget {
  const EqpAgendaModelosTela({super.key});

  @override
  State<EqpAgendaModelosTela> createState() => _EqpAgendaModelosTelaState();
}

class _EqpAgendaModelosTelaState extends State<EqpAgendaModelosTela> {
  final _busca = TextEditingController();
  DateTime _inicio = DateTime.now();
  DateTime _fim = DateTime.now().add(const Duration(days: 13));
  Map<String, dynamic>? _d;
  bool _carregando = true;
  String? _erro;

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
    if (_fim.isBefore(_inicio)) {
      setState(() => _erro = 'O fim é antes do início.');
      return;
    }
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final d = await eqp('eqp_agenda_modelos', {
        'inicio': iso(_inicio),
        'fim': iso(_fim),
        if (_busca.text.trim().isNotEmpty) 'busca': _busca.text.trim(),
      });
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// "08/11" de uma data do banco.
  String _diaCurto(Object? v) {
    final t = dataBr(v);
    return t.length >= 5 ? t.substring(0, 5) : t;
  }

  Color _cor(int livres, int total) {
    if (livres <= 0) return Cores.erro;
    if (livres * 3 <= total) return Cores.alerta;
    return Cores.sucesso;
  }

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    final modelos = listaDe(_d?['modelos']);
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Text('Livres por modelo', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const Text('Quantos equipamentos de cada modelo estão livres no período e em cada dia (reservados, fora, bloqueados e, '
            'até hoje, em manutenção não contam).', style: TextStyle(color: Cores.neutro)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          CampoDataEqp(rotulo: 'De', data: _inicio, aoMudar: (d) => setState(() => _inicio = d)),
          CampoDataEqp(rotulo: 'Até', data: _fim, aoMudar: (d) => setState(() => _fim = d)),
          SizedBox(
            width: 260,
            child: TextField(
              controller: _busca,
              decoration: const InputDecoration(hintText: 'Modelo ou família', prefixIcon: Icon(Icons.search)),
              onSubmitted: (_) => _carregar(),
            ),
          ),
          FilledButton(onPressed: _carregando ? null : _carregar, child: const Text('Ver')),
        ]),
        const SizedBox(height: 8),
        if (_carregando) const LinearProgressIndicator(minHeight: 2),
        if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
        if (!_carregando && _d != null && modelos.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nenhum modelo com equipamentos. Cadastre os modelos em Equipamentos › Modelos.', style: TextStyle(color: Cores.neutro)),
          ),
        if ((_d?['sem_modelo'] as num? ?? 0) > 0)
          Text('${_d!['sem_modelo']} equipamento(s) sem modelo não entram aqui (veja Agenda e disponibilidade).',
              style: const TextStyle(color: Cores.neutro)),
        for (final m in modelos) _modelo(m),
      ]),
    );
  }

  Widget _modelo(Map<String, dynamic> m) {
    final total = (m['total'] as num? ?? 0).toInt();
    final livres = (m['livres_no_periodo'] as num? ?? 0).toInt();
    final dias = listaDe(m['por_dia']);
    return SecaoEqp(
      titulo: '${m['modelo']}',
      acoes: [
        TextButton(onPressed: () => context.go('/equipamentos/modelos/${m['modelo_id']}'), child: const Text('Modelo')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$livres de $total livres no período inteiro'
            '${m['preco_diaria'] != null ? ' · ${reais(m['preco_diaria'])}/dia' : ''}',
            style: TextStyle(color: _cor(livres, total), fontWeight: FontWeight.w700)),
        if (listaDe(m['livres']).isNotEmpty)
          Text(listaDe(m['livres']).map((e) => '${e['codigo']}').join(', '), style: const TextStyle(color: Cores.neutro)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final d in dias)
              Container(
                width: 46,
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: _cor((d['livres'] as num? ?? 0).toInt(), total).withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(children: [
                  Text(_diaCurto(d['dia']), style: const TextStyle(fontSize: 11, color: Cores.neutro)),
                  Text('${d['livres']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}
