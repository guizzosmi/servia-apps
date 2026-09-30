import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'banco_local.dart';
import 'cofre.dart';

/// Versão do app enviada à plataforma (aparece na tela de aparelhos).
const versaoApp = '0.1.0';

/// Tabelas de cadastro que descem por cursor (só o que mudou).
const tabelasDeCadastro = [
  'clientes',
  'locais',
  'contatos',
  'ambientes',
  'equipamentos',
  'produtos',
  'tipos_equipamento',
  'modelos_medicao',
  'colaboradores',
  'equipes',
  'equipe_membros',
];

enum SituacaoSync { parado, sincronizando, ok, semConexao, precisaEntrar, revogado, erro }

class _SemConexao implements Exception {
  const _SemConexao(this.motivo);
  final String motivo;
}

class _PrecisaEntrar implements Exception {
  const _PrecisaEntrar();
}

/// Sincronização: envia a fila de operações e baixa o que mudou.
///
/// Roda ao abrir o app, ao voltar para ele, a cada 2 minutos com o app
/// aberto, logo depois de cada ação (com 1 segundo de espera, para juntar
/// várias) e pelo botão "Sincronizar agora".
class Sincronizador extends ChangeNotifier with WidgetsBindingObserver {
  Sincronizador(this.banco, this.conta);

  final BancoLocal banco;
  final ContaLocal conta;

  SituacaoSync situacao = SituacaoSync.parado;

  /// Detalhe da última falha (para mostrar na tela de sincronização).
  String? mensagem;

  Timer? _relogio;
  Timer? _espera;
  bool _rodando = false;
  bool _deNovo = false;

  /// Parado ao sair do app (ou trocar de usuário): não sincroniza nem avisa mais.
  bool _parado = false;

  static const _uuid = Uuid();
  SupabaseClient get _db => Supabase.instance.client;

  DateTime? get ultimaSync => DateTime.tryParse(banco.meta('ultima_sync') ?? '')?.toLocal();

  /// Data de hoje segundo a plataforma (fuso da empresa); sem ela, a do aparelho.
  String get hoje => banco.meta('hoje') ?? _hojeDoAparelho();

  static String _hojeDoAparelho() {
    final a = DateTime.now();
    return '${a.year}-${a.month.toString().padLeft(2, '0')}-${a.day.toString().padLeft(2, '0')}';
  }

  void iniciar() {
    WidgetsBinding.instance.addObserver(this);
    _relogio = Timer.periodic(const Duration(minutes: 2), (_) => sincronizar());
    sincronizar();
  }

  void parar() {
    _parado = true;
    WidgetsBinding.instance.removeObserver(this);
    _relogio?.cancel();
    _espera?.cancel();
  }

  @override
  void dispose() {
    parar();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) sincronizar();
  }

  /// Pede uma sincronização daqui a pouco (junta ações feitas em sequência).
  void pedir() {
    if (_parado) return;
    _espera?.cancel();
    _espera = Timer(const Duration(seconds: 1), sincronizar);
  }

  /// Registra uma ação: entra na fila, muda o banco local na hora
  /// (a tela já mostra o novo estado) e pede a sincronização.
  Future<void> registrar(String tipo, Map<String, dynamic> dados, {Future<void> Function()? aplicarLocal}) async {
    await banco.enfileirar(Operacao(
      opId: _uuid.v4(),
      tipo: tipo,
      em: DateTime.now().toUtc().toIso8601String(),
      dados: dados,
    ));
    if (aplicarLocal != null) await aplicarLocal();
    pedir();
  }

  /// Tira da fila uma operação recusada (o técnico já viu o motivo).
  Future<void> descartar(String opId) => banco.removerDaFila([opId]);

  void _mudar(SituacaoSync s, [String? msg]) {
    if (_parado) return;
    situacao = s;
    mensagem = msg;
    notifyListeners();
  }

  Future<void> sincronizar() async {
    if (_parado) return;
    if (_rodando) {
      _deNovo = true;
      return;
    }
    _rodando = true;
    _mudar(SituacaoSync.sincronizando);
    try {
      await _garantirSessao();
      await _enviar();
      await _baixar();
      await banco.gravarMeta('ultima_sync', DateTime.now().toUtc().toIso8601String());
      _mudar(SituacaoSync.ok);
    } on _SemConexao catch (e) {
      _mudar(SituacaoSync.semConexao, e.motivo);
    } on _PrecisaEntrar {
      _mudar(SituacaoSync.precisaEntrar, 'Sua sessão venceu. Entre de novo para sincronizar (nada se perde).');
    } on PostgrestException catch (e) {
      if (e.hint == 'dispositivo_revogado' || e.hint == 'dispositivo_apagar') {
        await banco.gravarMeta('revogado', e.hint);
        _mudar(SituacaoSync.revogado, e.message);
      } else {
        _mudar(SituacaoSync.erro, e.message);
      }
    } on AuthException catch (e) {
      _mudar(SituacaoSync.erro, e.message);
    } catch (e) {
      // Sem internet, servidor fora do ar, tempo esgotado...
      _mudar(SituacaoSync.semConexao, 'Sem conexão com a plataforma.');
      debugPrint('Sincronização: $e');
    } finally {
      _rodando = false;
      if (_deNovo) {
        _deNovo = false;
        pedir();
      }
    }
  }

  /// A sessão de login dura 1 hora e se renova sozinha. Se o app ficou
  /// fechado ou sem internet, renova aqui, a partir da sessão guardada.
  Future<void> _garantirSessao() async {
    final atual = _db.auth.currentSession;
    if (atual != null && !atual.isExpired && atual.user.id == conta.usuarioId) return;
    final guardada = await const ArmazenamentoSessao().accessToken();
    if (guardada == null) throw const _PrecisaEntrar();
    try {
      await _db.auth.recoverSession(guardada);
    } on AuthRetryableFetchException {
      throw const _SemConexao('Sem conexão com a plataforma.');
    } on AuthException {
      throw const _PrecisaEntrar();
    }
    final nova = _db.auth.currentSession;
    if (nova == null || nova.user.id != conta.usuarioId) throw const _PrecisaEntrar();
  }

  Map<String, dynamic> _base() => {'dispositivo_id': conta.dispositivoId, 'versao_app': versaoApp};

  Future<Map<String, dynamic>> _rpc(String funcao, Map<String, dynamic> p) async {
    final r = await _db.rpc(funcao, params: {'p': p}).timeout(const Duration(seconds: 60));
    return r is Map<String, dynamic> ? r : <String, dynamic>{};
  }

  /// Envia a fila em lotes de 50, na ordem em que as ações foram feitas.
  Future<void> _enviar() async {
    while (true) {
      final lote = banco.proximas(50);
      if (lote.isEmpty) return;
      final r = await _rpc('sync_enviar', {..._base(), 'operacoes': lote.map((o) => o.paraEnvio()).toList()});
      final aceitas = <String>[];
      final respondidas = <String>{};
      var parar = false;
      for (final res in (r['resultados'] as List? ?? const [])) {
        final m = res as Map;
        final opId = m['op_id'] as String;
        respondidas.add(opId);
        if (m['ok'] == true) {
          aceitas.add(opId);
        } else if (m['temporario'] == true) {
          await banco.marcarTentativa(opId, '${m['mensagem'] ?? 'Tentar de novo'}');
          parar = true; // tenta de novo na próxima sincronização
        } else {
          await banco.marcarRecusada(opId, '${m['mensagem'] ?? m['codigo'] ?? 'Recusada'}');
        }
      }
      await banco.removerDaFila(aceitas);
      // Alguma operação do lote ficou sem resposta: tenta na próxima
      // sincronização (sem isso, o mesmo lote seria reenviado sem parar).
      if (parar || lote.any((o) => !respondidas.contains(o.opId))) return;
    }
  }

  /// Baixa os cadastros (por cursor, em páginas) e o dia.
  Future<void> _baixar() async {
    // Começa 1 minuto antes do último cursor: gravações que terminaram
    // fora de ordem não se perdem (o que vier repetido só é regravado).
    final cursores = <String, dynamic>{};
    for (final t in tabelasDeCadastro) {
      final c = _cursor(t);
      if (c != null) {
        final em = DateTime.tryParse('${c['em']}');
        cursores[t] = {
          'em': em?.subtract(const Duration(minutes: 1)).toIso8601String(),
          'id': '00000000-0000-0000-0000-000000000000',
        };
      }
    }
    // O dia só é trocado se a fila estiver vazia: ações ainda não enviadas
    // continuam valendo na tela.
    var querDia = banco.pendentes == 0;
    var paginas = 0;
    while (true) {
      final r = await _rpc('sync_baixar', {..._base(), 'cursores': cursores, 'dia': querDia});
      final cadastros = (r['cadastros'] as Map?) ?? const {};
      for (final e in cadastros.entries) {
        final tabela = e.key as String;
        final bloco = e.value as Map;
        final linhas = ((bloco['linhas'] as List?) ?? const []).cast<Map<String, dynamic>>();
        final excluidos = linhas.where((l) => l['excluido_em'] != null).map((l) => '${l['id']}');
        final ativos = linhas.where((l) => l['excluido_em'] == null);
        if (excluidos.isNotEmpty) await banco.apagarIds(tabela, excluidos, avisar: false);
        if (ativos.isNotEmpty) await banco.gravar(tabela, ativos, avisar: false);
        if (bloco['cursor'] != null) {
          cursores[tabela] = bloco['cursor'];
          await banco.gravarMeta('cursor:$tabela', jsonEncode(bloco['cursor']));
        }
      }
      final dia = r['dia'];
      // Confere de novo: uma ação feita durante o download não pode ser
      // desfeita na tela pelo dia que acabou de chegar.
      if (dia is Map && banco.pendentes == 0) {
        await banco.substituir({
          for (final t in tabelasDoDia) t: ((dia[t] as List?) ?? const []).cast<Map<String, dynamic>>(),
        });
        await banco.gravarMeta('hoje', dia['hoje'] as String?);
        await banco.gravarMeta('meu_checkin', dia['meu_checkin'] == null ? null : jsonEncode(dia['meu_checkin']));
      }
      querDia = false;
      paginas++;
      if (r['mais'] != true || paginas > 200) break;
    }
    banco.avisar();
  }

  Map<String, dynamic>? _cursor(String tabela) {
    final t = banco.meta('cursor:$tabela');
    if (t == null) return null;
    try {
      return jsonDecode(t) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
