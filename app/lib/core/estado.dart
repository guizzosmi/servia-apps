import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'banco_local.dart';
import 'cofre.dart';
import 'sincronizacao.dart';

/// Erro de login com frase pronta para a tela.
class ErroLogin implements Exception {
  const ErroLogin(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// Estado geral do app: quem está usando, o banco local e a sincronização.
/// As rotas escutam este objeto (entrar, sair, aparelho revogado).
class EstadoApp extends ChangeNotifier {
  EstadoApp._();
  static final instancia = EstadoApp._();

  ContaLocal? conta;
  BancoLocal? banco;
  Sincronizador? sync;

  bool get entrou => conta != null && banco != null && sync != null;
  bool get revogado => banco?.meta('revogado') != null || sync?.situacao == SituacaoSync.revogado;

  /// Na abertura do app: se já havia alguém usando, abre o banco e
  /// começa a sincronizar (funciona sem internet).
  Future<void> iniciar() async {
    final c = await ContaLocal.carregar();
    if (c == null) return;
    await _abrir(c);
  }

  Future<void> _abrir(ContaLocal c) async {
    conta = c;
    banco = await BancoLocal.abrir();
    sync = Sincronizador(banco!, c)..addListener(notifyListeners);
    sync!.iniciar();
    notifyListeners();
  }

  /// Login por e-mail e senha, ou por código da empresa + matrícula + PIN.
  Future<void> entrar({required String email, required String senha}) async {
    final db = Supabase.instance.client;
    try {
      await Sessao.entrar(email, senha);
    } catch (e) {
      throw ErroLogin(mensagemDeErro(e));
    }
    final info = Sessao.atual;
    if (info == null || !info.temEmpresa) {
      await _sairSilencioso();
      throw const ErroLogin('Usuário sem empresa ativa. Fale com o administrador.');
    }
    if (info.colaboradorId == null) {
      await _sairSilencioso();
      throw const ErroLogin('Seu usuário não está ligado a um colaborador. Fale com o gestor.');
    }

    // Id do aparelho: criado uma vez por pessoa neste celular e guardado no
    // cofre (se duas pessoas usam o mesmo celular, cada uma tem o seu registro).
    final chaveDispositivo = '${Cofre.chaveDispositivo}_${info.usuarioId}';
    var dispositivo = await Cofre.ler(chaveDispositivo);
    if (dispositivo == null) {
      dispositivo = const Uuid().v4();
      await Cofre.gravar(chaveDispositivo, dispositivo);
    }

    // Registra o aparelho (ou confere se ele foi revogado).
    try {
      final r = await db.functions.invoke('dispositivo-acao', body: {
        'acao': 'registrar',
        'dispositivo_id': dispositivo,
        'plataforma': Platform.operatingSystem,
        'versao_app': versaoApp,
      });
      final status = ((r.data as Map?)?['dispositivo'] as Map?)?['status'];
      if (status == 'revogado' || status == 'apagar') {
        await _sairSilencioso();
        throw const ErroLogin('Este aparelho foi desconectado pelo administrador.');
      }
    } on ErroLogin {
      rethrow;
    } catch (e) {
      await _sairSilencioso();
      throw ErroLogin(mensagemDeErro(e));
    }

    final nova = ContaLocal(
      usuarioId: info.usuarioId,
      email: info.email,
      contaId: info.contaId!,
      empresaId: info.empresaId!,
      colaboradorId: info.colaboradorId!,
      dispositivoId: dispositivo,
    );

    // Outra pessoa (ou outra empresa) no mesmo aparelho: começa do zero.
    final anterior = conta ?? await ContaLocal.carregar();
    final mesmaPessoa = anterior != null &&
        anterior.usuarioId == nova.usuarioId &&
        anterior.empresaId == nova.empresaId;
    if (!mesmaPessoa) await _fechar(apagarDados: true);

    await nova.salvar();
    if (entrou && mesmaPessoa) {
      // Voltou a entrar (sessão vencida): mantém o banco e a fila.
      conta = nova;
      await sync!.sincronizar();
      notifyListeners();
      return;
    }
    await _abrir(nova);
  }

  /// Desfaz um login pela metade sem esconder a mensagem de erro.
  Future<void> _sairSilencioso() async {
    try {
      await Sessao.sair();
    } catch (_) {
      await const ArmazenamentoSessao().removePersistedSession();
    }
  }

  /// Quantas ações ainda não subiram (para avisar antes de sair).
  int get pendentes => banco?.pendentes ?? 0;

  /// Sai do app neste aparelho: apaga o banco local, a fila e a sessão.
  Future<void> sair() async {
    await _fechar(apagarDados: true);
    await Cofre.apagar(Cofre.chaveConta);
    try {
      await Sessao.sair();
    } catch (_) {
      // Sem internet: a sessão local é apagada mesmo assim.
      await const ArmazenamentoSessao().removePersistedSession();
    }
    notifyListeners();
  }

  Future<void> _fechar({required bool apagarDados}) async {
    sync?.removeListener(notifyListeners);
    sync?.parar();
    sync = null;
    banco = null;
    conta = null;
    if (apagarDados) await BancoLocal.apagarTudo();
  }
}
