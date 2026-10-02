import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cadastros/catalogo.dart';
import 'quadro/quadro_tela.dart';
import 'telas/aparelhos_tela.dart';
import 'telas/cadastro_form_tela.dart';
import 'telas/cadastro_lista_tela.dart';
import 'telas/casca.dart';
import 'telas/configuracoes_tela.dart';
import 'telas/empresa_tela.dart';
import 'telas/etiquetas_tela.dart';
import 'telas/fila_tela.dart';
import 'telas/inicio_tela.dart';
import 'telas/login_tela.dart';
import 'telas/orcamento_tela.dart';
import 'telas/orcamentos_tela.dart';
import 'telas/os_lista_tela.dart';
import 'telas/os_nova_tela.dart';
import 'telas/os_tela.dart';
import 'telas/usuario_tela.dart';
import 'telas/usuarios_tela.dart';

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
    // Usuários, aparelhos e configurações: só o admin (o servidor confere de novo).
    final soAdmin = local.startsWith('/usuarios') || local.startsWith('/aparelhos') ||
        local.startsWith('/configuracoes');
    if (soAdmin && !sessao.tem(Papel.admin)) return '/';
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
        GoRoute(path: '/etiquetas', builder: (_, __) => const EtiquetasTela()),
        GoRoute(path: '/fila', builder: (_, __) => const FilaTela()),
        GoRoute(
          path: '/quadro',
          builder: (_, state) {
            final data = state.uri.queryParameters['data'];
            return QuadroTela(key: ValueKey('quadro-$data'), data: data);
          },
        ),
        GoRoute(
          path: '/os',
          builder: (_, __) => const OsListaTela(),
          routes: [
            GoRoute(path: 'nova', builder: (_, __) => const OsNovaTela()),
            GoRoute(
              path: ':id',
              builder: (_, state) {
                final id = state.pathParameters['id']!;
                return OsTela(key: ValueKey('os-$id'), id: id);
              },
            ),
          ],
        ),
        GoRoute(
          path: '/orcamentos',
          builder: (_, __) => const OrcamentosTela(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (_, state) {
                final id = state.pathParameters['id']!;
                return OrcamentoTela(key: ValueKey('orcamento-$id'), id: id);
              },
            ),
          ],
        ),
        GoRoute(path: '/aparelhos', builder: (_, __) => const AparelhosTela()),
        GoRoute(path: '/configuracoes', builder: (_, __) => const ConfiguracoesTela()),
        GoRoute(
          path: '/usuarios',
          builder: (_, __) => const UsuariosTela(),
          routes: [
            GoRoute(
              path: 'novo',
              builder: (_, __) => const UsuarioTela(key: ValueKey('usuario-novo'), id: null),
            ),
            GoRoute(
              path: ':id',
              builder: (_, state) {
                final id = state.pathParameters['id']!;
                return UsuarioTela(key: ValueKey('usuario-$id'), id: id);
              },
            ),
          ],
        ),
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
                  // ?cliente_id=... vem travado (herdado do pai);
                  // ?sugerir_nome=... só preenche (dá para mudar).
                  herdados: {
                    for (final e in state.uri.queryParameters.entries)
                      if (!e.key.startsWith('sugerir_')) e.key: e.value,
                  },
                  sugestoes: {
                    for (final e in state.uri.queryParameters.entries)
                      if (e.key.startsWith('sugerir_')) e.key.substring(8): e.value,
                  },
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
