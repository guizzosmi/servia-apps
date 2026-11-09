import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/comercial.dart';
import '../servicos/status.dart';
import '../widgets/comercial_analises.dart';
import '../widgets/margem.dart';

/// Indicadores do Comercial (guia 90): conversão, valor ganho, funil, origens, perdas e meta do mês.
/// Guia 97: previsão ponderada, metas por vendedor, perdas em detalhe e campanhas (AnalisesComerciais).
class ComercialIndicadoresTela extends StatefulWidget {
  const ComercialIndicadoresTela({super.key});

  @override
  State<ComercialIndicadoresTela> createState() => _ComercialIndicadoresTelaState();
}

class _ComercialIndicadoresTelaState extends State<ComercialIndicadoresTela> {
  late DateTime _de = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _ate = DateTime.now();
  late Future<Map<String, dynamic>> _dados = _carregar();

  Future<Map<String, dynamic>> _carregar() async {
    final r = await Supabase.instance.client.rpc('comercial_indicadores', params: {
      'p': {'de': dataIso(_de), 'ate': dataIso(_ate)}
    });
    return Map<String, dynamic>.from(r as Map);
  }

  void _recarregar() => setState(() => _dados = _carregar());

  Future<void> _meta(Map<String, dynamic>? atual) async {
    final valor = TextEditingController(text: '${atual?['valor_meta'] ?? ''}');
    final qtd = TextEditingController(text: '${atual?['quantidade_meta'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Meta de ${_de.month.toString().padLeft(2, '0')}/${_de.year}'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: valor,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Valor ganho no mês (R\$)', helperText: 'Valor + 12 x o mensal dos contratos.'),
            ),
            TextField(controller: qtd, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Negócios ganhos no mês')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Salvar')),
        ],
      ),
    );
    final v = num.tryParse(valor.text.trim().replaceAll('.', '').replaceAll(',', '.')) ?? 0;
    final q = int.tryParse(qtd.text.trim()) ?? 0;
    valor.dispose();
    qtd.dispose();
    if (ok != true) return;
    try {
      final db = Supabase.instance.client;
      final mes = dataIso(DateTime(_de.year, _de.month));
      final existente = await db.from('com_metas').select('id').eq('mes', mes).isFilter('responsavel_id', null)
          .isFilter('excluido_em', null).maybeSingle();
      if (existente == null) {
        await db.from('com_metas').insert({'mes': mes, 'valor_meta': v, 'quantidade_meta': q});
      } else {
        await db.from('com_metas').update({'valor_meta': v, 'quantidade_meta': q}).eq('id', existente['id'] as String);
      }
      _recarregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagemDeErro(e)), backgroundColor: Cores.erro));
      }
    }
  }

  Widget _numero(String rotulo, String valor, {Color? cor, String? ajuda}) => SizedBox(
        width: 200,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rotulo, style: const TextStyle(color: Cores.neutro)),
              const SizedBox(height: 4),
              Text(valor, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cor ?? Cores.tinta)),
              if (ajuda != null) Text(ajuda, style: const TextStyle(fontSize: 11, color: Cores.neutro)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _dados,
        builder: (context, s) {
          final d = s.data;
          final meta = d?['meta'] is Map ? Map<String, dynamic>.from(d!['meta'] as Map) : null;
          final aberto = d?['aberto'] is Map ? Map<String, dynamic>.from(d!['aberto'] as Map) : const <String, dynamic>{};
          final funil = (d?['funil'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final maxFunil = funil.fold<num>(1, (m, f) => (num.tryParse('${f['chegaram']}') ?? 0) > m ? num.parse('${f['chegaram']}') : m);
          num n(Object? v) => num.tryParse('${v ?? 0}') ?? 0;
          return ListView(padding: margemDaTela(context), children: [
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              IconButton(onPressed: () => context.go('/comercial'), icon: const Icon(Icons.arrow_back), tooltip: 'Funil'),
              Text('Indicadores do comercial', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text('${dataBr(dataIso(_de))} a ${dataBr(dataIso(_ate))}'),
                onPressed: () async {
                  final r = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    initialDateRange: DateTimeRange(start: _de, end: _ate),
                  );
                  if (r == null) return;
                  _de = r.start;
                  _ate = r.end;
                  _recarregar();
                },
              ),
              TextButton.icon(onPressed: () => _meta(meta), icon: const Icon(Icons.flag_outlined), label: const Text('Meta do mês')),
            ]),
            const SizedBox(height: 12),
            if (s.connectionState != ConnectionState.done) const LinearProgressIndicator(minHeight: 2),
            if (s.hasError) Text(mensagemDeErro(s.error!), style: const TextStyle(color: Cores.erro)),
            if (d != null) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                _numero('Novas oportunidades', '${d['criadas']}'),
                _numero('Ganhas', '${d['ganhas']}', cor: Cores.sucesso),
                _numero('Perdidas', '${d['perdidas']}', cor: Cores.erro),
                _numero('Conversão', d['conversao_pct'] == null ? '–' : '${d['conversao_pct']}%', ajuda: 'ganhas ÷ fechadas no período'),
                _numero('Valor ganho', reais(d['valor_ganho']), cor: Cores.sucesso, ajuda: 'valor + 12 x mensal'),
                _numero('Mensal ganho', reais(d['mensal_ganho']), ajuda: 'contratos novos por mês'),
                _numero('Ticket médio', d['ticket_medio'] == null ? '–' : reais(d['ticket_medio'])),
                _numero('Ciclo de venda', d['ciclo_medio_dias'] == null ? '–' : '${d['ciclo_medio_dias']} dias', ajuda: 'da criação ao ganho'),
                _numero('Em aberto', reais(aberto['valor']), ajuda: '${aberto['quantidade'] ?? 0} oportunidades · ${reais(aberto['ponderado'])} ponderado'),
              ]),
              if (meta != null) ...[
                const SizedBox(height: 16),
                Text('Meta do mês', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                if (n(meta['valor_meta']) > 0) ...[
                  Text('Valor: ${reais(d['valor_ganho'])} de ${reais(meta['valor_meta'])}'),
                  LinearProgressIndicator(
                      value: (n(d['valor_ganho']) / n(meta['valor_meta'])).clamp(0, 1).toDouble(),
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(5)),
                ],
                if (n(meta['quantidade_meta']) > 0) ...[
                  const SizedBox(height: 8),
                  Text('Negócios: ${d['ganhas']} de ${meta['quantidade_meta']}'),
                  LinearProgressIndicator(
                      value: (n(d['ganhas']) / n(meta['quantidade_meta'])).clamp(0, 1).toDouble(),
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(5)),
                ],
              ],
              const SizedBox(height: 16),
              Text('Funil das oportunidades criadas no período', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              for (final f in funil)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(width: 200, child: Text('${f['etapa']}')),
                    Expanded(
                      child: LinearProgressIndicator(
                          value: (n(f['chegaram']) / maxFunil).toDouble(), minHeight: 14, borderRadius: BorderRadius.circular(4)),
                    ),
                    SizedBox(width: 48, child: Text('${f['chegaram']}', textAlign: TextAlign.right)),
                  ]),
                ),
              // Origens e perdas ficam em AnalisesComerciais (com campanhas, valores e o que vale tentar de novo).
              const SizedBox(height: 16),
              AnalisesComerciais(key: ValueKey('analises-${dataIso(_de)}-${dataIso(_ate)}'), de: _de, ate: _ate),
            ],
          ]);
        },
      );
}
