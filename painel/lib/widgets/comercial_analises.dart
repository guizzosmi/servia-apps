import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/comercial.dart';
import '../servicos/status.dart';

/// Análises do Comercial (guia 97), abaixo dos indicadores: previsão ponderada dos próximos meses,
/// metas por vendedor, por que perdemos (e o que vale retomar) e de onde vêm as vendas (origem e campanha).
class AnalisesComerciais extends StatefulWidget {
  const AnalisesComerciais({super.key, required this.de, required this.ate});

  final DateTime de;
  final DateTime ate;

  @override
  State<AnalisesComerciais> createState() => _AnalisesComerciaisState();
}

class _AnalisesComerciaisState extends State<AnalisesComerciais> {
  late final Future<List<Map<String, dynamic>>> _dados = _carregar();

  Future<List<Map<String, dynamic>>> _carregar() async {
    final db = Supabase.instance.client;
    final periodo = {'de': dataIso(widget.de), 'ate': dataIso(widget.ate)};
    final r = await Future.wait([
      db.rpc('comercial_previsao', params: {'p': {'meses': 3}}),
      db.rpc('comercial_metas_progresso', params: {'p': {'mes': dataIso(widget.de)}}),
      db.rpc('comercial_analise_perdas', params: {'p': periodo}),
      db.rpc('comercial_origens', params: {'p': periodo}),
    ]);
    return [for (final x in r) Map<String, dynamic>.from(x as Map)];
  }

  static num _n(Object? v) => num.tryParse('${v ?? 0}') ?? 0;

  static const _meses = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  static String _mes(Object? iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? '' : '${_meses[d.month - 1]}/${d.year}';
  }

  Widget _titulo(BuildContext context, String t, [String? ajuda]) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: Theme.of(context).textTheme.titleMedium),
          if (ajuda != null) Text(ajuda, style: const TextStyle(fontSize: 12, color: Cores.neutro)),
        ]),
      );

  Widget _barra(String rotulo, num valor, num maximo, String direita, {Color? cor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 180, child: Text(rotulo, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(
            child: LinearProgressIndicator(
              value: maximo <= 0 ? 0 : (valor / maximo).clamp(0, 1).toDouble(),
              minHeight: 12,
              color: cor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          SizedBox(width: 150, child: Text(direita, textAlign: TextAlign.right)),
        ]),
      );

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _dados,
        builder: (context, s) {
          if (s.hasError) return Text(mensagemDeErro(s.error!), style: const TextStyle(color: Cores.erro));
          if (!s.hasData) return const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator(minHeight: 2));
          final previsao = s.data![0], metas = s.data![1], perdas = s.data![2], origens = s.data![3];
          final meses = listaDeMapas(previsao['meses']);
          final maxMes = meses.fold<num>(1, (m, x) => _n(x['valor']) > m ? _n(x['valor']) : m);
          final pessoas = listaDeMapas(metas['pessoas']);
          final motivos = listaDeMapas(perdas['por_motivo']);
          final maxMotivo = motivos.fold<num>(1, (m, x) => _n(x['quantidade']) > m ? _n(x['quantidade']) : m);
          final retomar = listaDeMapas(perdas['para_retomar']);
          final porOrigem = listaDeMapas(origens['por_origem']);
          final campanhas = listaDeMapas(origens['por_campanha']);
          final vencidas = previsao['vencidas'] is Map ? Map<String, dynamic>.from(previsao['vencidas'] as Map) : const <String, dynamic>{};
          final semPrevisao =
              previsao['sem_previsao'] is Map ? Map<String, dynamic>.from(previsao['sem_previsao'] as Map) : const <String, dynamic>{};
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _titulo(context, 'Previsão de fechamento', 'Pela previsão de cada oportunidade aberta; ponderado = valor x chance da etapa.'),
            for (final m in meses)
              _barra(
                _mes(m['mes']),
                _n(m['valor']),
                maxMes,
                '${reais(m['ponderado'])} de ${reais(m['valor'])}',
              ),
            if (_n(vencidas['quantidade']) > 0)
              Text('${vencidas['quantidade']} com a previsão vencida (${reais(vencidas['valor'])}): atualize a data.',
                  style: const TextStyle(color: Cores.alerta)),
            if (_n(semPrevisao['quantidade']) > 0)
              Text('${semPrevisao['quantidade']} sem previsão de fechamento (${reais(semPrevisao['valor'])}).',
                  style: const TextStyle(color: Cores.neutro)),
            _titulo(context, 'Metas do mês por vendedor', 'Defina a meta de cada um em Meta do mês ou pedindo ao assistente.'),
            for (final p in pessoas)
              _n(p['meta_valor']) > 0
                  ? _barra('${p['nome']}', _n(p['ganho_valor']), _n(p['meta_valor']),
                      '${reais(p['ganho_valor'])} de ${reais(p['meta_valor'])}',
                      cor: _n(p['ganho_valor']) >= _n(p['meta_valor']) ? Cores.sucesso : null)
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text('${p['nome']}: ${reais(p['ganho_valor'])} ganho (${p['ganhas']} negócios), sem meta',
                          style: const TextStyle(color: Cores.neutro)),
                    ),
            _titulo(context, 'Por que perdemos',
                '${perdas['perdidas']} perdidas (${reais(perdas['valor_perdido'])})${perdas['taxa_perda_pct'] != null ? ' · ${perdas['taxa_perda_pct']}% das fechadas' : ''}'),
            if (motivos.isEmpty) const Text('Nenhuma perda no período.', style: TextStyle(color: Cores.neutro)),
            for (final m in motivos) _barra('${m['motivo']}', _n(m['quantidade']), maxMotivo, '${m['quantidade']} · ${reais(m['valor'])}', cor: Cores.erro),
            if (listaDeMapas(perdas['por_etapa']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Onde estavam: ${listaDeMapas(perdas['por_etapa']).map((e) => '${e['etapa']} (${e['quantidade']})').join(', ')}',
                  style: const TextStyle(color: Cores.neutro),
                ),
              ),
            if (retomar.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Vale tentar de novo', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final o in retomar)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.replay, color: Cores.alerta),
                  title: Text('${o['codigo']} · ${o['titulo']}'),
                  subtitle: Text('${o['motivo'] ?? ''} · perdida em ${dataBr(o['fechada_em'])}'),
                  trailing: Text(reais(o['valor'])),
                  onTap: () => context.push('/comercial/${o['id']}'),
                ),
            ],
            _titulo(context, 'De onde vêm', 'Criadas no período por origem e por campanha do site (UTM).'),
            for (final o in porOrigem)
              Text('${origensComercial[o['origem']] ?? o['origem']}: ${o['criadas']} novas, ${o['ganhas']} ganhas'
                  '${o['conversao_pct'] != null ? ' (${o['conversao_pct']}%)' : ''} · ${reais(o['valor_ganho'])}'),
            if (campanhas.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Campanhas', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final c in campanhas)
                Text('${[c['fonte'], c['meio'], c['campanha']].where((x) => x != null).join(' / ')}: '
                    '${c['criadas']} novas, ${c['ganhas']} ganhas · ${reais(c['valor_ganho'])}'),
            ],
          ]);
        },
      );
}
