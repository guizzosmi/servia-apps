import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/estado.dart';
import 'telas/atendimento_tela.dart';
import 'telas/hoje_tela.dart';
import 'telas/leitor_qr_tela.dart';
import 'telas/login_tela.dart';
import 'telas/nova_os_tela.dart';
import 'telas/orcamento_tela.dart';
import 'telas/revogado_tela.dart';
import 'telas/servico_tela.dart';
import 'telas/sincronizacao_tela.dart';

final rotas = GoRouter(
  initialLocation: '/hoje',
  refreshListenable: EstadoApp.instancia,
  redirect: (context, state) {
    final estado = EstadoApp.instancia;
    final local = state.matchedLocation;
    if (estado.apagadoPorOrdem) return local == '/apagado' ? null : '/apagado';
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
    GoRoute(path: '/apagado', builder: (_, __) => const ApagadoTela()),
    GoRoute(path: '/hoje', builder: (_, __) => const HojeTela()),
    GoRoute(path: '/sincronizacao', builder: (_, __) => const SincronizacaoTela()),
    GoRoute(path: '/ler-codigo', builder: (_, __) => const LeitorQrTela()),
    GoRoute(
      path: '/nova-os',
      builder: (_, state) => NovaOsTela(
        clienteId: state.uri.queryParameters['cliente'],
        localId: state.uri.queryParameters['local'],
        audioId: state.uri.queryParameters['audio'],
      ),
    ),
    GoRoute(
      path: '/atendimento/:id',
      builder: (_, state) {
        final id = state.pathParameters['id']!;
        return AtendimentoTela(key: ValueKey('atendimento-$id'), atendimentoId: id);
      },
    ),
    GoRoute(
      path: '/orcamento/:id',
      builder: (_, state) {
        final id = state.pathParameters['id']!;
        return OrcamentoTela(key: ValueKey('orcamento-$id'), atendimentoId: id);
      },
    ),
    GoRoute(
      path: '/servico/:id',
      builder: (_, state) {
        final id = state.pathParameters['id']!;
        return ServicoTela(key: ValueKey('servico-$id'), itemId: id);
      },
    ),
  ],
);
