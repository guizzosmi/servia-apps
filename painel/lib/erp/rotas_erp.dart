import 'package:go_router/go_router.dart';

import 'configuracao_tela.dart';
import 'fila_tela.dart';

/// Rotas da integração com o Protheus (guia 105), dentro da casca do painel.
/// O menu fica em Administração › ERP (Protheus); o banco confere o papel
/// (gestor ou financeiro) em todas as funções.
final rotaErp = GoRoute(
  path: '/erp',
  builder: (_, __) => const ErpConfiguracaoTela(),
  routes: [
    GoRoute(path: 'fila', builder: (_, __) => const ErpFilaTela()),
  ],
);
