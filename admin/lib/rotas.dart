import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'telas/casca.dart';
import 'telas/conta_tela.dart';
import 'telas/contas_tela.dart';
import 'telas/cupons_tela.dart';
import 'telas/faturas_tela.dart';
import 'telas/login_tela.dart';
import 'telas/precos_tela.dart';
import 'telas/resumo_tela.dart';

class _SessaoMudou extends ChangeNotifier {
  _SessaoMudou() {
    _assinatura = Supabase.instance.client.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
  late final StreamSubscription<AuthState> _assinatura;

  @override
  void dispose() {
    _assinatura.cancel();
    super.dispose();
  }
}

final rotas = GoRouter(
  initialLocation: '/',
  refreshListenable: _SessaoMudou(),
  redirect: (context, state) {
    final sessao = Sessao.atual;
    final local = state.matchedLocation;
    if (sessao == null) return local == '/login' ? null : '/login';
    // Só o dono do ServPilot (usuarios.plataforma_admin). O banco confere de novo.
    if (!sessao.plataformaAdmin) return local == '/sem-acesso' ? null : '/sem-acesso';
    if (local == '/login' || local == '/sem-acesso') return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginTela()),
    GoRoute(path: '/sem-acesso', builder: (_, __) => const SemAcessoTela()),
    ShellRoute(
      builder: (context, state, filho) => Casca(local: state.matchedLocation, child: filho),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const ResumoTela()),
        GoRoute(
          path: '/contas',
          builder: (_, state) => ContasTela(situacao: state.uri.queryParameters['situacao']),
          routes: [
            GoRoute(
              path: ':id',
              builder: (_, state) {
                final id = state.pathParameters['id']!;
                return ContaTela(key: ValueKey('conta-$id'), id: id);
              },
            ),
          ],
        ),
        GoRoute(
          path: '/faturas',
          builder: (_, state) => FaturasTela(situacao: state.uri.queryParameters['situacao']),
        ),
        GoRoute(path: '/cupons', builder: (_, __) => const CuponsTela()),
        GoRoute(path: '/precos', builder: (_, __) => const PrecosTela()),
      ],
    ),
  ],
);
