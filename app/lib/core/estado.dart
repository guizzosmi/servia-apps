import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'arquivos.dart';
import 'banco_local.dart';
import 'cofre.dart';
import 'notificacoes.dart';
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

  /// O administrador mandou apagar: os dados já foram apagados e a tela
  /// avisa a pessoa antes de voltar ao login.
  bool apagadoPorOrdem = false;
  bool _apagando = false;
  bool _registrandoAvisos = false;

  /// Notificações conferidas nesta abertura do app (uma vez por sessão:
  /// confere o endereço e passa a ouvir as trocas dele).
  bool _avisosConferidos = false;

  /// Na abertura do app: se já havia alguém usando, abre o banco e
  /// começa a sincronizar (funciona sem internet).
  Future<void> iniciar() async {
    try {
      await Arquivos.iniciar();
    } catch (_) {
      // Sem a pasta do app: as fotos usam o caminho gravado.
    }
    final pendente = _pendente(await Cofre.ler(Cofre.chaveApagado));
    final c = await ContaLocal.carregar();
    if (pendente != null && (c == null || c.usuarioId == pendente.$2)) {
      // Apagou mas a plataforma ainda não recebeu a confirmação. Garante
      // que nada ficou (o app pode ter sido fechado no meio da limpeza).
      await BancoLocal.apagarTudo();
      await Arquivos.apagarFotos();
      await Cofre.apagar(Cofre.chaveConta);
      apagadoPorOrdem = true;
      unawaited(_confirmarApagado());
      return;
    }
    // Pendência de outra pessoa: a plataforma recusa e a marca sai.
    if (pendente != null) unawaited(_confirmarApagado());
    if (c == null) return;
    await _abrir(c);
  }

  Future<void> _abrir(ContaLocal c) async {
    conta = c;
    banco = await BancoLocal.abrir();
    // O app fechou logo depois da ordem de apagar: apaga agora.
    if (banco!.meta('apagar') != null) {
      await apagarPorOrdem(esperarConfirmacao: false);
      return;
    }
    sync = Sincronizador(banco!, c, aoMandarApagar: apagarPorOrdem)
      ..addListener(notifyListeners)
      ..addListener(_aoMudarSync);
    sync!.iniciar();
    notifyListeners();
  }

  /// Depois de uma sincronização que deu certo, registra este aparelho
  /// para as notificações (se ainda não registrou).
  void _aoMudarSync() {
    if (sync?.situacao == SituacaoSync.ok && !_avisosConferidos) {
      unawaited(_registrarAvisos());
    }
  }

  Future<void> _registrarAvisos() async {
    final c = conta, b = banco;
    if (c == null || b == null || !Notificacoes.ligado || _registrandoAvisos) return;
    _registrandoAvisos = true;
    try {
      final token = await Notificacoes.token();
      if (token == null || !identical(banco, b)) return;
      if (token != b.meta('fcm_token')) {
        await Notificacoes.enviarToken(c.dispositivoId, token);
        if (!identical(banco, b)) return;
        await b.gravarMeta('fcm_token', token);
      }
      _avisosConferidos = true;
      Notificacoes.aoRenovar((novo) async {
        try {
          await Notificacoes.enviarToken(c.dispositivoId, novo);
          if (identical(banco, b)) await b.gravarMeta('fcm_token', novo);
        } catch (e) {
          debugPrint('Token novo das notificações: $e');
        }
      });
    } catch (e) {
      debugPrint('Registrar notificações: $e');
    } finally {
      _registrandoAvisos = false;
    }
  }

  /// "dispositivo|usuário" gravado no cofre -> (dispositivo, usuário).
  static (String, String)? _pendente(String? valor) {
    if (valor == null) return null;
    final partes = valor.split('|');
    return (partes.first, partes.length > 1 ? partes[1] : '');
  }

  /// O administrador mandou apagar os dados deste aparelho: apaga o banco,
  /// a fila e as fotos na hora, sem perguntar, e avisa a plataforma.
  Future<void> apagarPorOrdem({bool esperarConfirmacao = true}) async {
    if (_apagando) return;
    _apagando = true;
    try {
      sync?.parar();
      final c = conta;
      if (c != null) await Cofre.gravar(Cofre.chaveApagado, '${c.dispositivoId}|${c.usuarioId}');
      await _fechar(apagarDados: true);
      await Cofre.apagar(Cofre.chaveConta);
      apagadoPorOrdem = true;
      notifyListeners();
    } finally {
      _apagando = false;
    }
    if (esperarConfirmacao) {
      await _confirmarApagado();
    } else {
      unawaited(_confirmarApagado());
    }
  }

  /// Conta para a plataforma que os dados foram apagados (o painel mostra
  /// "Dados apagados"). Sem internet, tenta de novo depois. Recusa
  /// definitiva (ex.: outra pessoa entrou no aparelho): desiste.
  Future<void> _confirmarApagado() async {
    final pendente = _pendente(await Cofre.ler(Cofre.chaveApagado));
    if (pendente == null) return;
    try {
      await Supabase.instance.client.functions.invoke('dispositivo-acao', body: {
        'acao': 'confirmar_apagado',
        'dispositivo_id': pendente.$1,
      });
      await Cofre.apagar(Cofre.chaveApagado);
    } on FunctionException catch (e) {
      if (const [400, 403, 404, 409].contains(e.status)) await Cofre.apagar(Cofre.chaveApagado);
      debugPrint('Confirmar apagado: ${e.status} ${e.details}');
    } catch (e) {
      debugPrint('Confirmar apagado: $e');
    }
  }

  /// Botão da tela de dados apagados: volta ao login. Se a confirmação
  /// ainda não subiu, ela vai no próximo login desta pessoa.
  Future<void> concluirApagado() async {
    await _confirmarApagado();
    if (await Cofre.ler(Cofre.chaveApagado) == null) await _sairSilencioso();
    apagadoPorOrdem = false;
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

    // Apagado por ordem sem confirmação (estava sem internet): a mesma
    // pessoa confirma agora; outra pessoa não consegue, e a marca sai.
    final pendente = _pendente(await Cofre.ler(Cofre.chaveApagado));
    if (pendente != null) {
      if (pendente.$2 == info.usuarioId) {
        await _confirmarApagado();
      } else {
        await Cofre.apagar(Cofre.chaveApagado);
      }
    }

    // Registra o aparelho (ou confere se ele foi revogado).
    try {
      final r = await db.functions.invoke('dispositivo-acao', body: {
        'acao': 'registrar',
        'dispositivo_id': dispositivo,
        'plataforma': defaultTargetPlatform.name,
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
    sync?.removeListener(_aoMudarSync);
    _avisosConferidos = false;
    sync?.parar();
    sync = null;
    banco = null;
    conta = null;
    if (apagarDados) {
      await BancoLocal.apagarTudo();
      await Arquivos.apagarFotos();
      await Notificacoes.desligar();
    }
  }
}
