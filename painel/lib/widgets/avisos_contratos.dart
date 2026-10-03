import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/contratos.dart';
import '../servicos/status.dart';
import 'itens_os.dart' show dinheiro, numeroBr;

/// Avisos dos contratos na Início: reajuste perto (ou vencido), franquia
/// passada no mês e OS do aparelho sem preço. Sem aviso, não aparece.
class AvisosContratos extends StatefulWidget {
  const AvisosContratos({super.key});

  @override
  State<AvisosContratos> createState() => _AvisosContratosState();
}

class _AvisosContratosState extends State<AvisosContratos> {
  late final Future<List<Map<String, dynamic>>> _avisos = avisosContratos();

  static String _texto(Map<String, dynamic> a) => switch (a['tipo']) {
        'reajuste' => '${'${a['data']}'.compareTo(dataIso(DateTime.now())) < 0 ? 'reajuste atrasado' : 'reajuste'} '
            '${indicesReajuste[a['indice']] ?? ''} em ${dataBr(a['data'])}',
        'franquia' => 'franquia passou no mês: ${a['visitas']}'
            '${a['franquia_visitas'] != null ? ' de ${a['franquia_visitas']}' : ''} visita(s), '
            '${numeroBr(a['horas'])}${a['franquia_horas'] != null ? ' de ${numeroBr(a['franquia_horas'])}' : ''} h '
            '(excedente ${dinheiro(a['excedente_valor'])})',
        'sem_preco' => '${a['os']} OS do aparelho sem preço',
        _ => '${a['tipo']}',
      };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _avisos,
      builder: (context, snap) {
        final lista = snap.data ?? const [];
        if (lista.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.handshake_outlined, color: Cores.alerta),
                  SizedBox(width: 8),
                  Text('Contratos: atenção', style: TextStyle(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 4),
                for (final c in lista)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onTap: () => context.push('/contratos/${c['contrato_id']}'),
                    title: Text('${c['codigo']} · ${c['cliente'] ?? ''}${c['local'] != null ? ' (${c['local']})' : ''}'),
                    subtitle: Text([
                      for (final a in ((c['avisos'] as List?) ?? const []).cast<Map<String, dynamic>>()) _texto(a),
                    ].join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
