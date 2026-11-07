import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../api.dart';
import '../widgets/comuns.dart';

/// Comissões dos parceiros (guia 89): uma linha por fatura paga de cliente indicado.
/// Estorno de fatura com comissão já paga entra como valor negativo (desconta do próximo Pix).
class ComissoesTela extends StatefulWidget {
  const ComissoesTela({super.key});

  @override
  State<ComissoesTela> createState() => _ComissoesTelaState();
}

class _ComissoesTelaState extends State<ComissoesTela> {
  String? _situacao = 'a_pagar';
  late Future<List<Map<String, dynamic>>> _dados = _carregar();

  Future<List<Map<String, dynamic>>> _carregar() => rpcLista('admin_comissoes', {
        'p': {'situacao': _situacao}
      });

  void _recarregar() => setState(() => _dados = _carregar());

  @override
  Widget build(BuildContext context) => Carregar<List<Map<String, dynamic>>>(
        futuro: _dados,
        recarregar: _recarregar,
        construir: (linhas) {
          final hoje = DateTime.now().toIso8601String().substring(0, 10);
          final total = linhas.fold<num>(0, (s, c) => s + numero(c['valor']));
          return ListView(padding: const EdgeInsets.all(24), children: [
            Row(children: [
              Expanded(child: Text('Comissões', style: Theme.of(context).textTheme.headlineSmall)),
              TextButton.icon(
                onPressed: () => context.go('/parceiros'),
                icon: const Icon(Icons.handshake_outlined),
                label: const Text('Parceiros (para pagar)'),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final e in const {'a_pagar': 'A pagar', 'paga': 'Pagas', 'cancelada': 'Canceladas', '': 'Todas'}.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: (_situacao ?? '') == e.key,
                  onSelected: (_) {
                    _situacao = e.key.isEmpty ? null : e.key;
                    _recarregar();
                  },
                ),
            ]),
            const SizedBox(height: 12),
            Text('${linhas.length} lançamento(s) · total ${moeda(total)}', style: const TextStyle(color: Cores.neutro)),
            const SizedBox(height: 8),
            if (linhas.isEmpty) const Text('Nada aqui.'),
            for (final c in linhas)
              Card(
                child: ListTile(
                  onTap: () => context.go('/contas/${c['conta_id']}'),
                  title: Text('${c['parceiro']} · ${c['cliente']}${c['tipo'] == 'estorno' ? ' (estorno)' : ''}'),
                  subtitle: Text([
                    'fatura nº ${c['fatura']}${c['fatura_tipo'] == 'anual' ? ' (anual)' : ''}',
                    if (c['periodo_inicio'] != null) '${dataBr(c['periodo_inicio'])} a ${dataBr(c['periodo_fim'])}',
                    '${numero(c['pct'])}% de ${moeda(c['base'])}${numero(c['meses']) > 1 ? ' · ${c['meses']} meses na janela' : ''}',
                    if (c['situacao'] == 'a_pagar')
                      (c['liberada_em'] as String? ?? '').compareTo(hoje) <= 0
                          ? 'liberada'
                          : 'libera em ${dataBr(c['liberada_em'])}',
                    if (c['pago_em'] != null) 'paga em ${dataBr(c['pago_em'])}',
                    if (c['pagamento_obs'] != null) '${c['pagamento_obs']}',
                  ].join(' · ')),
                  trailing: Text(moeda(c['valor']),
                      style: TextStyle(fontWeight: FontWeight.w700,
                          color: numero(c['valor']) < 0 ? Cores.erro : Cores.tinta)),
                ),
              ),
          ]);
        },
      );
}
