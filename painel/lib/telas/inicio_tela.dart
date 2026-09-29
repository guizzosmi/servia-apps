import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cadastros/catalogo.dart';

/// Tela inicial: atalhos e contadores dos cadastros.
/// (O quadro do dia entra aqui na etapa de agendamentos.)
class InicioTela extends StatefulWidget {
  const InicioTela({super.key});

  @override
  State<InicioTela> createState() => _InicioTelaState();
}

class _InicioTelaState extends State<InicioTela> {
  // Contagens feitas uma vez ao abrir (e não a cada redesenho da tela).
  late final Map<String, Future<int>> _contagens = {
    for (final def in cadastrosDoMenu) def.tabela: _contar(def.tabela),
  };

  Future<int> _contar(String tabela) async {
    final r = await Supabase.instance.client
        .from(tabela)
        .select('id')
        .isFilter('excluido_em', null)
        .limit(1)
        .count(CountOption.exact);
    return r.count;
  }

  @override
  Widget build(BuildContext context) {
    final sessao = Sessao.atual;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Olá!',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          Text('${sessao?.email ?? ''} · ${sessao?.papeis.join(', ') ?? ''}',
              style: const TextStyle(color: Cores.neutro)),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final def in cadastrosDoMenu)
                SizedBox(
                  width: 220,
                  child: Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.go('/c/${def.chave}'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Cores.indigo100,
                              foregroundColor: Cores.indigo700,
                              child: Icon(def.icone),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FutureBuilder<int>(
                                    future: _contagens[def.tabela],
                                    builder: (_, s) => Text(
                                      s.hasData ? '${s.data}' : (s.hasError ? '–' : '…'),
                                      style: const TextStyle(
                                          fontSize: 22, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  Text(def.titulo,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Cores.neutro)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
