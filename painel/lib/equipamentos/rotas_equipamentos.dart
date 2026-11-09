import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'agenda_modelos_tela.dart';
import 'agenda_tela.dart';
import 'cadastros_tela.dart';
import 'custos_config_tela.dart';
import 'fechamento_tela.dart';
import 'manutencao_tela.dart';
import 'entregas_tela.dart';
import 'cobranca_tela.dart';
import 'conjunto_tela.dart';
import 'ficha_tela.dart';
import 'inicio_tela.dart';
import 'lista_tela.dart';
import 'locacao_tela.dart';
import 'locacoes_tela.dart';
import 'medicoes_tela.dart';
import 'modelos_tela.dart';
import 'parametros_tela.dart';
import 'planos_manutencao_tela.dart';
import 'servico.dart';

/// Rotas da Gestão de Equipamentos (guia 98), dentro da casca do painel.
final rotaEquipamentos = GoRoute(
  path: '/equipamentos',
  builder: (_, __) => const EqpInicioTela(),
  routes: [
    GoRoute(path: 'visao', builder: (_, __) => const EqpInicioTela()),
    GoRoute(path: 'lista', builder: (_, __) => const EqpListaTela()),
    GoRoute(path: 'agenda', builder: (_, __) => const EqpAgendaTela()),
    GoRoute(path: 'cadastros', builder: (_, __) => const EqpCadastrosTela()),
    // Guia 103: manutenção, planos de preventiva, indicadores e fechamento, custos da manutenção.
    GoRoute(path: 'manutencao', builder: (_, __) => const EqpManutencaoTela()),
    GoRoute(path: 'planos', builder: (_, __) => const EqpPlanosTela()),
    GoRoute(path: 'fechamento', builder: (_, __) => const EqpFechamentoTela()),
    GoRoute(path: 'custos', builder: (_, __) => const EqpCustosConfigTela()),
    GoRoute(path: 'entregas', builder: (_, __) => const EqpEntregasTela()),
    // Guia 102: modelos, conjunto, cobrança e medição da locação, livres por modelo e parâmetros.
    GoRoute(
      path: 'modelos',
      builder: (_, __) => const EqpModelosTela(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (_, state) {
            final id = state.pathParameters['id']!;
            return EqpModeloTela(key: ValueKey('modelo-$id'), id: id);
          },
        ),
      ],
    ),
    GoRoute(
      path: 'conjunto/:id',
      builder: (_, state) {
        final id = state.pathParameters['id']!;
        return EqpConjuntoTela(key: ValueKey('conjunto-$id'), id: id);
      },
    ),
    GoRoute(
      path: 'cobranca/:id',
      builder: (_, state) {
        final id = state.pathParameters['id']!;
        return EqpCobrancaTela(key: ValueKey('cobranca-$id'), id: id);
      },
    ),
    GoRoute(
      path: 'medicoes',
      builder: (_, __) => const EqpMedicoesTela(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (_, state) {
            final id = state.pathParameters['id']!;
            return EqpMedicaoTela(key: ValueKey('medicao-$id'), id: id);
          },
        ),
      ],
    ),
    GoRoute(path: 'livres-por-modelo', builder: (_, __) => const EqpAgendaModelosTela()),
    GoRoute(path: 'parametros', builder: (_, __) => const EqpParametrosTela()),
    GoRoute(
      path: 'ativo/:id',
      builder: (_, state) {
        final id = state.pathParameters['id']!;
        return EqpFichaTela(key: ValueKey('eqp-$id'), id: id);
      },
    ),
    GoRoute(
      path: 'locacoes',
      builder: (_, __) => const EqpLocacoesTela(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (_, state) {
            final id = state.pathParameters['id']!;
            return EqpLocacaoTela(key: ValueKey('locacao-$id'), id: id);
          },
        ),
      ],
    ),
  ],
);

/// Itens do menu lateral da aplicação: só para quem tem "equipamentos" no token.
/// [item] e [grupo] são os construtores do próprio menu (casca), para ficar igual aos outros.
List<Widget> menuEquipamentos(
  Widget Function(IconData icone, String rotulo, String destino) item,
  Widget Function(String titulo) grupo,
) {
  if (!temEquipamentos()) return const [];
  return [
    grupo('Equipamentos'),
    item(Icons.precision_manufacturing_outlined, 'Visão geral', '/equipamentos/visao'),
    item(Icons.construction_outlined, 'Equipamentos', '/equipamentos/lista'),
    item(Icons.description_outlined, 'Locações', '/equipamentos/locacoes'),
    item(Icons.date_range_outlined, 'Agenda e disponibilidade', '/equipamentos/agenda'),
    item(Icons.warehouse_outlined, 'Depósitos e obras', '/equipamentos/cadastros'),
    item(Icons.fact_check_outlined, 'Entregas e divergências', '/equipamentos/entregas'),
    item(Icons.category_outlined, 'Modelos', '/equipamentos/modelos'),
    item(Icons.request_quote_outlined, 'Medições', '/equipamentos/medicoes'),
    item(Icons.event_note_outlined, 'Livres por modelo', '/equipamentos/livres-por-modelo'),
    item(Icons.build_circle_outlined, 'Manutenção', '/equipamentos/manutencao'),
    item(Icons.insights_outlined, 'Indicadores e fechamento', '/equipamentos/fechamento'),
    item(Icons.payments_outlined, 'Custos e plano', '/equipamentos/custos'),
    item(Icons.tune, 'Parâmetros', '/equipamentos/parametros'),
  ];
}
