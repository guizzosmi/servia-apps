import 'package:go_router/go_router.dart';

import 'cobranca_config_tela.dart';
import 'titulos_tela.dart';

/// Rotas da cobrança parametrizável (guia 100), dentro da casca do painel: a lista de títulos e
/// Configurações › Cobrança (gestor e financeiro veem; só o gestor muda, o banco confere de novo).
final rotaTitulos = GoRoute(
  path: '/titulos',
  builder: (_, __) => const TitulosTela(),
  routes: [
    GoRoute(path: 'configuracao', builder: (_, __) => const CobrancaConfigTela()),
  ],
);
