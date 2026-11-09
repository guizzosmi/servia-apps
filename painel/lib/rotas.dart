import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cadastros/catalogo.dart';
import 'cobranca/rotas_cobranca.dart';
import 'equipamentos/rotas_equipamentos.dart';
import 'erp/rotas_erp.dart';
import 'quadro/quadro_tela.dart';
import 'telas/agenda_tela.dart';
import 'telas/comercial_funil_tela.dart';
import 'telas/comercial_indicadores_tela.dart';
import 'telas/comercial_tarefas_tela.dart';
import 'telas/oauth_consentimento_tela.dart';
import 'telas/oportunidade_tela.dart';
import 'telas/estoque_tela.dart';
import 'telas/lembretes_tela.dart';
import 'telas/whatsapp_tela.dart';
import 'telas/caixa_tela.dart';
import 'telas/fiscal_tela.dart';
import 'telas/notas_tela.dart';
import 'telas/parados_tela.dart';
import 'telas/assistente_tela.dart';
import 'telas/aparelhos_tela.dart';
import 'telas/assinatura_tela.dart';
import 'telas/cadastro_form_tela.dart';
import 'telas/cadastro_lista_tela.dart';
import 'telas/casca.dart';
import 'telas/configuracoes_tela.dart';
import 'telas/contrato_tela.dart';
import 'telas/cobrar_tela.dart';
import 'telas/contratos_tela.dart';
import 'telas/empresa_tela.dart';
import 'telas/etiquetas_tela.dart';
import 'telas/fila_tela.dart';
import 'telas/importar_tela.dart';
import 'telas/indicadores_tela.dart';
import 'telas/integracoes_tela.dart';
import 'telas/inicio_tela.dart';
import 'telas/login_tela.dart';
import 'telas/nova_senha_tela.dart';
import 'telas/orcamento_tela.dart';
import 'telas/orcamentos_tela.dart';
import 'telas/os_lista_tela.dart';
import 'telas/os_nova_tela.dart';
import 'telas/os_tela.dart';
import 'telas/plano_assistente_tela.dart';
import 'telas/plano_tela.dart';
import 'telas/planos_tela.dart';
import 'telas/usuario_tela.dart';
import 'telas/usuarios_tela.dart';

/// Papéis que podem usar o painel (o admin passa em todos).
const papeisDoPainel = [Papel.gestor, Papel.financeiro];

/// Avisa o roteador sempre que a sessão muda (entrou, saiu, trocou empresa).
class _SessaoMudou extends ChangeNotifier {
  _SessaoMudou() {
    _assinatura = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      // Guia 58: entrou pelo link de "Esqueci minha senha" -> tela da senha nova.
      if (s.event == AuthChangeEvent.passwordRecovery) recuperandoSenha = true;
      if (s.event == AuthChangeEvent.signedOut) recuperandoSenha = false;
      notifyListeners();
    });
  }

  /// Veio do link do e-mail e ainda não gravou a senha nova.
  bool recuperandoSenha = false;

  void senhaTrocada() {
    recuperandoSenha = false;
    notifyListeners();
  }

  late final StreamSubscription<AuthState> _assinatura;

  @override
  void dispose() {
    _assinatura.cancel();
    super.dispose();
  }
}

final sessaoMudou = _SessaoMudou();

final rotas = GoRouter(
  initialLocation: '/',
  refreshListenable: sessaoMudou,
  redirect: (context, state) {
    final sessao = Sessao.atual;
    final local = state.matchedLocation;
    // Guia 91: o pedido de acesso do Claude (/oauth/consent) volta para ele depois do login.
    if (sessao == null) {
      if (local == '/login') return null;
      return local.startsWith('/oauth/') ? '/login?voltar=${Uri.encodeComponent(state.uri.toString())}' : '/login';
    }
    if (sessaoMudou.recuperandoSenha) return local == '/nova-senha' ? null : '/nova-senha';
    if (local == '/nova-senha') return null;
    if (local == '/login') {
      final voltar = state.uri.queryParameters['voltar'];
      return voltar != null && voltar.startsWith('/oauth/') ? voltar : '/';
    }
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
    GoRoute(
      path: '/oauth/consent',
      builder: (_, state) => OauthConsentimentoTela(authorizationId: state.uri.queryParameters['authorization_id']),
    ),
    GoRoute(path: '/nova-senha', builder: (_, __) => const NovaSenhaTela()),
    GoRoute(path: '/empresa', builder: (_, __) => const EmpresaTela()),
    ShellRoute(
      builder: (context, state, filho) =>
          Casca(local: state.matchedLocation, child: filho),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const InicioTela()),
        GoRoute(path: '/etiquetas', builder: (_, __) => const EtiquetasTela()),
        GoRoute(path: '/fila', builder: (_, __) => const FilaTela()),
        GoRoute(path: '/agenda', builder: (_, __) => const AgendaTela()),
        GoRoute(path: '/estoque', builder: (_, __) => const EstoqueTela()),
        GoRoute(path: '/lembretes', builder: (_, __) => const LembretesTela()),
        GoRoute(path: '/whatsapp', builder: (_, __) => const WhatsappTela()),
        GoRoute(path: '/caixa', builder: (_, __) => const CaixaTela()),
        // Guia 81: notas fiscais (Focus NFe).
        GoRoute(path: '/notas', builder: (_, __) => const NotasTela()),
        GoRoute(path: '/notas/configuracao', builder: (_, __) => const FiscalTela()),
        GoRoute(path: '/parados', builder: (_, __) => const ParadosTela()),
        GoRoute(path: '/assistente', builder: (_, __) => const AssistenteTela()),
        // Guia 90: módulo Comercial.
        GoRoute(
          path: '/comercial',
          builder: (_, __) => const ComercialFunilTela(),
          routes: [
            GoRoute(path: 'nova', builder: (_, __) => const OportunidadeTela(key: ValueKey('oportunidade-nova'))),
            GoRoute(path: 'tarefas', builder: (_, __) => const ComercialTarefasTela()),
            GoRoute(path: 'indicadores', builder: (_, __) => const ComercialIndicadoresTela()),
            GoRoute(
              path: ':id',
              builder: (_, state) {
                final id = state.pathParameters['id']!;
                return OportunidadeTela(key: ValueKey('oportunidade-$id'), id: id);
              },
            ),
          ],
        ),
        // Guia 98: Gestão de Equipamentos (a aplicação do hub).
        rotaEquipamentos,
        // Guia 100: títulos de cobrança e Configurações › Cobrança.
        rotaTitulos,
        rotaErp, // guia 105: ERP (Protheus) e a fila
        GoRoute(
          path: '/quadro',
          builder: (_, state) {
            final data = state.uri.queryParameters['data'];
            final encerrar = state.uri.queryParameters['encerrar'];
            return QuadroTela(key: ValueKey('quadro-$data-$encerrar'), data: data, encerrar: encerrar);
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
        GoRoute(
          path: '/planos',
          builder: (_, __) => const PlanosTela(),
          routes: [
            GoRoute(path: 'novo', builder: (_, __) => const PlanoTela(key: ValueKey('plano-novo'))),
            GoRoute(path: 'assistente', builder: (_, __) => const PlanoAssistenteTela()),
            GoRoute(
              path: ':id',
              builder: (_, state) {
                final id = state.pathParameters['id']!;
                return PlanoTela(key: ValueKey('plano-$id'), id: id);
              },
            ),
          ],
        ),
        GoRoute(path: '/cobrar', builder: (_, __) => const CobrarTela()),
        GoRoute(
          path: '/contratos',
          builder: (_, __) => const ContratosTela(),
          routes: [
            GoRoute(path: 'novo', builder: (_, __) => const ContratoTela(key: ValueKey('contrato-novo'))),
            GoRoute(
              path: ':id',
              builder: (_, state) {
                final id = state.pathParameters['id']!;
                return ContratoTela(key: ValueKey('contrato-$id'), id: id);
              },
            ),
          ],
        ),
        GoRoute(path: '/aparelhos', builder: (_, __) => const AparelhosTela()),
        GoRoute(path: '/configuracoes', builder: (_, __) => const ConfiguracoesTela()),
        GoRoute(path: '/importar', builder: (_, __) => const ImportarTela()),
        GoRoute(path: '/indicadores', builder: (_, __) => const IndicadoresTela()),
        GoRoute(path: '/integracoes', builder: (_, __) => const IntegracoesTela()),
        GoRoute(
          path: '/assinatura',
          builder: (_, state) => AssinaturaTela(pagamento: state.uri.queryParameters['pagamento']),
        ),
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
