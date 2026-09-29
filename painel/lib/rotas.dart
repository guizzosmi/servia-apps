import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cadastros/catalogo.dart';
import 'telas/cadastro_form_tela.dart';
import 'telas/cadastro_lista_tela.dart';
import 'telas/casca.dart';
import 'telas/empresa_tela.dart';
import 'telas/inicio_tela.dart';
import 'telas/login_tela.dart';

/// Papéis que podem usar o painel (o admin passa em todos).
const papeisDoPainel = [Papel.gestor, Papel.financeiro];

/// Avisa o roteador sempre que a sessão muda (entrou, saiu, trocou empresa).
class _SessaoMudou extends ChangeNotifier {
  _SessaoMudou() {
    _assinatura = Supabase.instance.client.auth.onAuthStateChange
        .listen((_) => notifyListeners());
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
    if (local == '/login') return '/';
    if (local == '/empresa') return null;
    // Sem empresa ativa ou sem papel de painel nesta empresa: escolher outra.
    if (!sessao.temEmpresa || !sessao.temAlgum(papeisDoPainel)) {
      return '/empresa';
    }
    return null;
  },
  errorBuilder: (context, state) => const _NaoEncontrada(),
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginTela()),
    GoRoute(path: '/empresa', builder: (_, __) => const EmpresaTela()),
    ShellRoute(
      builder: (context, state, filho) =>
          Casca(local: state.matchedLocation, child: filho),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const InicioTela()),
        GoRoute(
          path: '/c/:cadastro',
          builder: (_, state) {
            final def = cadastroPorChave(state.pathParameters['cadastro']!);
            if (def == null) return const _NaoEncontrada();
            return CadastroListaTela(key: ValueKey(def.chave), def: def);
          },
          routes: [
            GoRoute(
              path: 'novo',
              builder: (_, state) {
                final def = cadastroPorChave(state.pathParameters['cadastro']!);
                if (def == null) return const _NaoEncontrada();
                return CadastroFormTela(
                  key: ValueKey('${def.chave}/novo/${state.uri.query}'),
                  def: def,
                  id: null,
                  herdados: Map.of(state.uri.queryParameters),
                );
              },
            ),
            GoRoute(
              path: ':id',
              builder: (_, state) {
                final def = cadastroPorChave(state.pathParameters['cadastro']!);
                final id = state.pathParameters['id']!;
                if (def == null) return const _NaoEncontrada();
                return CadastroFormTela(
                  key: ValueKey('${def.chave}/$id'),
                  def: def,
                  id: id,
                  herdados: const {},
                );
              },
            ),
          ],
        ),
      ],
    ),
  ],
);

class _NaoEncontrada extends StatelessWidget {
  const _NaoEncontrada();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Página não encontrada.'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go('/'),
              child: const Text('Ir para o início'),
            ),
          ],
        ),
      ),
    );
  }
}
