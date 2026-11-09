import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/estado.dart';
import 'telas/aparelho_tela.dart';
import 'telas/assistente_tela.dart';
import 'telas/atendimento_tela.dart';
import 'telas/conduzir_parte_tela.dart';
import 'telas/encerrar_dia_tela.dart';
import 'telas/eqp_ficha_tela.dart';
import 'telas/eqp_inicio_tela.dart';
import 'telas/eqp_registro_tela.dart';
import 'telas/hoje_tela.dart';
import 'telas/leitor_qr_tela.dart';
import 'telas/levantamento_tela.dart';
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
    // Guia 93: o assistente com o Claude (texto e voz, só com internet).
    GoRoute(
      path: '/assistente',
      builder: (_, state) => AssistenteTela(falarAoAbrir: state.uri.queryParameters['falar'] == '1'),
    ),
    GoRoute(path: '/sincronizacao', builder: (_, __) => const SincronizacaoTela()),
    GoRoute(path: '/ler-codigo', builder: (_, __) => const LeitorQrTela()),
    // Guia 108: a ficha do aparelho da etiqueta lida fora da OS.
    GoRoute(
      path: '/aparelho/:id',
      builder: (_, state) => AparelhoTela(
        key: ValueKey('aparelho-${state.pathParameters['id']}'),
        equipamentoId: state.pathParameters['id']!,
        lido: state.uri.queryParameters['lido'],
      ),
    ),
    GoRoute(path: '/levantamento', builder: (_, __) => const LevantamentoTela()),
    // Guia 104: Gestão de Equipamentos (entrega, chegada, retorno pelo app).
    GoRoute(path: '/equipamentos', builder: (_, __) => const EqpInicioTela()),
    GoRoute(
      path: '/equipamentos/:id',
      builder: (_, state) {
        final id = state.pathParameters['id']!;
        return EqpFichaTela(key: ValueKey('eqp-$id'), equipamentoId: id);
      },
    ),
    GoRoute(
      path: '/equipamentos/:id/registrar/:evento',
      builder: (_, state) => EqpRegistroTela(
        equipamentoId: state.pathParameters['id']!,
        evento: state.pathParameters['evento']!,
      ),
    ),
    GoRoute(
      path: '/nova-os',
      builder: (_, state) => NovaOsTela(
        clienteId: state.uri.queryParameters['cliente'],
        localId: state.uri.queryParameters['local'],
        equipamentoId: state.uri.queryParameters['equipamento'],
        audioId: state.uri.queryParameters['audio'],
        falarAoAbrir: state.uri.queryParameters['falar'] == '1',
      ),
    ),
    GoRoute(
      path: '/atendimento/:id',
      builder: (_, state) {
        final id = state.pathParameters['id']!;
        return AtendimentoTela(
            key: ValueKey('atendimento-$id'), atendimentoId: id, aparelhoId: state.uri.queryParameters['aparelho']);
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
      path: '/conduzir/:id',
      builder: (_, state) {
        final id = state.pathParameters['id']!;
        return ConduzirParteTela(key: ValueKey('conduzir-$id'), parteId: id);
      },
    ),
    GoRoute(
      path: '/encerrar-dia/:id',
      builder: (_, state) {
        final id = state.pathParameters['id']!;
        return EncerrarDiaTela(key: ValueKey('encerrar-$id'), parteId: id);
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
