import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/status.dart';

/// Alerta da Início (guia 30): dias anteriores com parte sem fechar, cada
/// um com o atalho para o quadro daquele dia. Só para o gestor; nunca hoje
/// nem dias futuros. Sem pendência, não aparece.
class DiasSemFechar extends StatefulWidget {
  const DiasSemFechar({super.key});

  @override
  State<DiasSemFechar> createState() => _DiasSemFecharState();
}

class _DiasSemFecharState extends State<DiasSemFechar> {
  late final Future<Map<String, dynamic>> _dados = _carregar();

  static const _diasDaSemana = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

  Future<Map<String, dynamic>> _carregar() async {
    final r = await Supabase.instance.client.rpc('partes_pendentes', params: {'p': <String, dynamic>{}});
    return r is Map<String, dynamic> ? r : <String, dynamic>{};
  }

  static String _dia(Object? iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? '' : '${_diasDaSemana[d.weekday - 1]}, ${dataBr(iso)}';
  }

  static String _situacao(Map<String, dynamic> p) {
    final abertos = (p['abertos'] as num?)?.toInt() ?? 0;
    final noServico = (p['no_servico'] as num?)?.toInt() ?? 0;
    if (p['status'] == 'rascunho') {
      return 'rascunho não publicado com ${p['servicos']} serviço(s) fora da fila';
    }
    return [
      abertos == 0 ? 'todos os serviços com resultado' : '$abertos serviço(s) sem resultado',
      if (noServico > 0) '$noServico pessoa(s) ainda no serviço',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _dados,
      builder: (context, snap) {
        final lista = ((snap.data?['partes'] as List?) ?? const []).cast<Map<String, dynamic>>();
        if (lista.isEmpty) return const SizedBox.shrink();
        final total = (snap.data?['total'] as num?)?.toInt() ?? lista.length;
        return Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Card(
            margin: EdgeInsets.zero,
            color: Cores.alerta.withValues(alpha: .08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.nightlight_outlined, color: Cores.alerta),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      total == 1 ? '1 dia sem fechar' : '$total dias sem fechar',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    'Enquanto o dia não fecha, o que não foi feito não volta para a fila.',
                    style: TextStyle(color: Cores.neutro),
                  ),
                ),
                for (final p in lista)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.circle, size: 12, color: _cor(p['cor'])),
                    title: Text('${_dia(p['data'])} · ${p['equipe'] ?? ''}'),
                    subtitle: Text(_situacao(p)),
                    trailing: FilledButton.tonal(
                      onPressed: () => context.go(Uri(path: '/quadro', queryParameters: {
                        'data': '${p['data']}',
                        // Publicada ou em andamento: já abre o encerramento daquela equipe.
                        if (p['status'] != 'rascunho') 'encerrar': '${p['parte_id']}',
                      }).toString()),
                      child: const Text('Fechar'),
                    ),
                  ),
                if (total > lista.length)
                  Text('E mais ${total - lista.length} (os mais antigos).', style: const TextStyle(color: Cores.neutro)),
              ]),
            ),
          ),
        );
      },
    );
  }

  static Color _cor(Object? hex) {
    final s = '${hex ?? ''}'.replaceAll('#', '');
    final n = int.tryParse(s, radix: 16);
    return s.length == 6 && n != null ? Color(0xFF000000 | n) : Cores.indigo500;
  }
}
