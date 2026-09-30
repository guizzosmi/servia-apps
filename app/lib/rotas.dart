import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/estado.dart';
import 'telas/hoje_tela.dart';
import 'telas/login_tela.dart';
import 'telas/revogado_tela.dart';
import 'telas/servico_tela.dart';
import 'telas/sincronizacao_tela.dart';

final rotas = GoRouter(
  initialLocation: '/hoje',
  refreshListenable: EstadoApp.instancia,
  redirect: (context, state) {
    final estado = EstadoApp.instancia;
    final local = state.matchedLocation;
    if (!estado.entrou) return local == '/login' ? null : '/login';
    if (local == '/reentrar') return null;
    if (estado.revogado) return local == '/revogado' ? null : '/revogado';
    if (local == '/login' || local == '/revogado') return '/hoje';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginTela()),
    GoRoute(path: '/reentrar', builder: (_, __) => const LoginTela(reentrar: true)),
    GoRoute(path: '/revogado', builder: (_, __) => const RevogadoTela()),
    GoRoute(path: '/hoje', builder: (_, __) => const HojeTela()),
    GoRoute(path: '/sincronizacao', builder: (_, __) => const SincronizacaoTela()),
    GoRoute(
      path: '/servico/:id',
      builder: (_, state) {
        final id = state.pathParameters['id']!;
        return ServicoTela(key: ValueKey('servico-$id'), itemId: id);
      },
    ),
  ],
);
