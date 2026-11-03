import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

/// Moldura do admin: menu lateral + barra com "Sair".
class Casca extends StatelessWidget {
  const Casca({super.key, required this.local, required this.child});

  final String local;
  final Widget child;

  static const _itens = [
    (Icons.dashboard_outlined, 'Resumo', '/'),
    (Icons.business_outlined, 'Clientes', '/contas'),
    (Icons.receipt_long_outlined, 'Faturas', '/faturas'),
    (Icons.local_offer_outlined, 'Cupons', '/cupons'),
    (Icons.sell_outlined, 'Preços e regras', '/precos'),
    (Icons.android, 'Testadores do app', '/testadores'),
  ];

  @override
  Widget build(BuildContext context) {
    final largo = MediaQuery.sizeOf(context).width >= 900;
    var atual = _itens.indexWhere((i) => i.$3 != '/' && local.startsWith(i.$3));
    if (atual < 0) atual = 0;
    final menu = NavigationRail(
      extended: largo,
      selectedIndex: atual,
      onDestinationSelected: (i) => context.go(_itens[i].$3),
      labelType: largo ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      destinations: [
        for (final i in _itens) NavigationRailDestination(icon: Icon(i.$1), label: Text(i.$2)),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Marca(altura: 28),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Cores.coral500, borderRadius: BorderRadius.circular(6)),
            child: const Text('ADMIN', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
        shape: const Border(bottom: BorderSide(color: Cores.linha)),
        actions: [
          Text(Sessao.atual?.email ?? '', style: const TextStyle(color: Cores.neutro)),
          const SizedBox(width: 8),
          TextButton.icon(onPressed: Sessao.sair, icon: const Icon(Icons.logout), label: const Text('Sair')),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        menu,
        const VerticalDivider(width: 1),
        Expanded(child: child),
      ]),
    );
  }
}
