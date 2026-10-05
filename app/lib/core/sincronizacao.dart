import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'arquivos.dart';
import 'banco_local.dart';
import 'cofre.dart';
import 'formatos.dart';

/// Versão do app enviada à plataforma (aparece na tela de aparelhos).
const versaoApp = '0.10.0';

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
  Sincronizador(this.banco, this.conta, {this.aoMandarApagar});

  final BancoLocal banco;
  final ContaLocal conta;

  /// O administrador mandou apagar os dados deste aparelho.
  final Future<void> Function()? aoMandarApagar;

  SituacaoSync situacao = SituacaoSync.parado;

  /// Detalhe da última falha (para mostrar na tela de sincronização).
  String? mensagem;

  Timer? _relogio;
  Timer? _espera;
  bool _rodando = false;
  bool _deNovo = false;

  /// Parado ao sair do app (ou trocar de usuário): não sincroniza nem avisa mais.
  bool _parado = false;

  /// Chamando a IA para os relatos registrados (não trava a sincronização).
  bool _processandoRelatos = false;
  bool _relatosDeNovo = false;

  static const _uuid = Uuid();
  SupabaseClient get _db => Supabase.instance.client;

  DateTime? get ultimaSync => DateTime.tryParse(banco.meta('ultima_sync') ?? '')?.toLocal();

  /// Data de hoje segundo a plataforma (fuso da empresa); sem ela, a do
  /// aparelho. Se a meia-noite passou sem internet, anda os mesmos dias que
  /// o calendário do aparelho andou desde a última sincronização.
  String get hoje {
    final plataforma = banco.meta('hoje');
    final naqueleDia = banco.meta('hoje_aparelho');
    final agora = _hojeDoAparelho();
    if (plataforma == null || naqueleDia == null) return plataforma ?? agora;
    final dias = DateTime.parse('${agora}T00:00:00Z').difference(DateTime.parse('${naqueleDia}T00:00:00Z')).inDays;
    return dias <= 0 ? plataforma : somarDias(plataforma, dias);
  }

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
      unawaited(_processarRelatos());
      await _limparDeVezEmQuando();
    } on _SemConexao catch (e) {
      _mudar(SituacaoSync.semConexao, e.motivo);
    } on _PrecisaEntrar {
      _mudar(SituacaoSync.precisaEntrar, 'Sua sessão venceu. Entre de novo para sincronizar (nada se perde).');
    } on PostgrestException catch (e) {
      if (e.hint == 'dispositivo_apagar' && aoMandarApagar != null) {
        // Mandado apagar: marca (se o app fechar agora, apaga ao abrir), para
        // de sincronizar na hora e apaga tudo logo depois desta volta.
        try {
          await banco.gravarMeta('apagar', '1');
        } catch (_) {}
        parar();
        unawaited(Future(aoMandarApagar!));
      } else if (e.hint == 'dispositivo_revogado' || e.hint == 'dispositivo_apagar') {
        await banco.gravarMeta('revogado', e.hint);
        _mudar(SituacaoSync.revogado, e.message);
      } else {
        _mudar(SituacaoSync.erro, e.message);
      }
    } on AuthException catch (e) {
      _mudar(SituacaoSync.erro, e.message);
    } on StorageException catch (e) {
      if (int.tryParse(e.statusCode ?? '') == null) {
        // Sem resposta do servidor: é falta de conexão.
        _mudar(SituacaoSync.semConexao, 'Sem conexão com a plataforma.');
      } else {
        // O servidor recusou o arquivo (ex.: permissão do bucket).
        _mudar(SituacaoSync.erro, 'Arquivo não enviado: ${e.message}');
      }
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
      // Os arquivos sobem antes das operações que os registram. A foto
      // cujo arquivo sumiu já ficou recusada aqui e não vai no lote.
      final semArquivo = {...await _subirFotos(lote), ...await _subirAnexos(lote), ...await _subirAudios(lote)};
      final envio = lote.where((o) => !semArquivo.contains(o.opId)).toList();
      if (envio.isEmpty) continue;
      final r = await _rpc('sync_enviar', {..._base(), 'operacoes': envio.map((o) => o.paraEnvio()).toList()});
      final aceitas = <String>[];
      final respondidas = <String>{};
      var parar = false;
      for (final res in (r['resultados'] as List? ?? const [])) {
        final m = res as Map;
        final opId = m['op_id'] as String;
        respondidas.add(opId);
        if (m['ok'] == true) {
          aceitas.add(opId);
          await _depoisDeAceita(lote.firstWhere((o) => o.opId == opId, orElse: () => lote.first), m);
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
      if (parar || envio.any((o) => !respondidas.contains(o.opId))) return;
    }
  }

  /// O que a plataforma respondeu e o técnico precisa saber.
  Future<void> _depoisDeAceita(Operacao op, Map m) async {
    if (op.opId != m['op_id']) return;
    if (op.tipo == 'relato_vincular') {
      // O áudio já é da OS (a OS falada sai da lista; o relato aparece no atendimento).
      final d = op.dados;
      await banco.alterar('audios', d['audio_id'], {
        'os_id': d['os_id'],
        if (d['como_relato'] == true) 'finalidade': 'relato' else 'status': 'revisado',
      });
      return;
    }
    if (op.tipo == 'relato_gravado') {
      // O relato continua na tela até o dia chegar de novo com ele.
      final d = op.dados;
      if (banco.um('audios', d['audio_id']) == null) {
        await banco.gravar('audios', [
          {
            'id': d['audio_id'],
            'atendimento_id': d['atendimento_id'],
            'finalidade': d['finalidade'] ?? 'relato',
            'status': '${m['status'] ?? 'enviado'}',
            'gravado_em': d['gravado_em'] ?? op.em,
            'duracao_s': d['duracao_s'],
            'gravado_por': conta.colaboradorId,
          }
        ], avisar: false);
      }
      return;
    }
    if (op.tipo != 'os_abrir' && op.tipo != 'cadastro_app') return;
    // CPF/CNPJ que já existia: a OS ficou no cliente cadastrado; o cliente
    // criado no aparelho sai da lista (senão aparece duplicado).
    final novo = (op.dados['cliente_novo'] as Map?)?['id'];
    if (novo != null && m['cliente_id'] != null && m['cliente_id'] != novo) {
      await banco.apagarIds('clientes', ['$novo']);
    }
    final aviso = m['aviso'];
    if (aviso is Map && (aviso['tipo'] == 'ficou_na_fila' || aviso['tipo'] == 'codigo_repetido')) {
      final quem = op.tipo == 'os_abrir' ? '${m['codigo'] ?? 'OS'}: ' : '';
      await banco.gravarMeta('aviso:${op.opId}', '$quem${aviso['mensagem']}', avisar: true);
    }
  }

  /// Avisos da plataforma ainda não vistos (chave, texto).
  List<(String, String)> get avisos => [
        for (final k in banco.chavesMeta('aviso:'))
          if (banco.meta(k) case final String t) (k, t),
      ];

  Future<void> dispensarAviso(String chave) => banco.gravarMeta(chave, null, avisar: true);

  /// Sobe para o bucket "fotos" os arquivos das fotos do lote que ainda
  /// não subiram. Sem internet, a falha interrompe a sincronização (tenta
  /// de novo depois); arquivo que sumiu do aparelho recusa a operação
  /// (devolve os op_id recusados, que não devem ser enviados).
  Future<Set<String>> _subirFotos(List<Operacao> lote) async {
    final recusadas = <String>{};
    for (final op in lote.where((o) => o.tipo == 'foto_registrada')) {
      final fotoId = '${op.dados['foto_id']}';
      final local = op.dados['arquivo_local'] as String?;
      if (local == null || op.dados['excluir'] == true || banco.meta('foto_subiu:$fotoId') != null) continue;
      final arquivo = Arquivos.foto(local)!;
      if (!await arquivo.exists()) {
        await banco.marcarRecusada(op.opId, 'O arquivo desta foto não está mais no aparelho.');
        recusadas.add(op.opId);
        continue;
      }
      try {
        await _db.storage.from('fotos').uploadBinary(
              '${op.dados['caminho']}',
              await arquivo.readAsBytes(),
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            );
      } on StorageException catch (e) {
        // Já estava lá (subiu antes e a resposta se perdeu): segue.
        final jaExiste = e.statusCode == '409' || e.message.toLowerCase().contains('exist') ||
            e.message.toLowerCase().contains('duplicate');
        if (!jaExiste) rethrow;
      }
      await banco.gravarMeta('foto_subiu:$fotoId', '1');
    }
    return recusadas;
  }

  /// Sobe os arquivos anexados a uma operação (assinatura e resumo em PDF):
  /// dados['arquivos'] = [{bucket, caminho, local, tipo}]. Como nas fotos:
  /// sem internet, tenta depois; arquivo que sumiu recusa a operação.
  Future<Set<String>> _subirAnexos(List<Operacao> lote) async {
    final recusadas = <String>{};
    for (final op in lote) {
      final anexos = op.dados['arquivos'];
      if (anexos is! List) continue;
      for (final a in anexos.cast<Map>()) {
        final caminho = '${a['caminho']}';
        if (banco.meta('arquivo_subiu:$caminho') != null) continue;
        final arquivo = Arquivos.assinatura(a['local']);
        if (arquivo == null || !await arquivo.exists()) {
          await banco.marcarRecusada(op.opId, 'O arquivo da assinatura não está mais no aparelho.');
          recusadas.add(op.opId);
          break;
        }
        try {
          await _db.storage.from('${a['bucket']}').uploadBinary(
                caminho,
                await arquivo.readAsBytes(),
                fileOptions: FileOptions(contentType: '${a['tipo']}'),
              );
        } on StorageException catch (e) {
          final jaExiste = e.statusCode == '409' || e.message.toLowerCase().contains('exist') ||
              e.message.toLowerCase().contains('duplicate');
          if (!jaExiste) rethrow;
        }
        await banco.gravarMeta('arquivo_subiu:$caminho', '1');
      }
    }
    return recusadas;
  }

  /// Sobe para o bucket "audios" os relatos gravados do lote (como as
  /// fotos: sem internet, tenta depois; arquivo que sumiu recusa a operação).
  Future<Set<String>> _subirAudios(List<Operacao> lote) async {
    final recusadas = <String>{};
    for (final op in lote.where((o) => o.tipo == 'relato_gravado')) {
      final audioId = '${op.dados['audio_id']}';
      if (banco.meta('audio_subiu:$audioId') != null) continue;
      final arquivo = Arquivos.audio(op.dados['arquivo_local']);
      if (arquivo == null || !await arquivo.exists()) {
        await banco.marcarRecusada(op.opId, 'O arquivo deste relato não está mais no aparelho.');
        recusadas.add(op.opId);
        continue;
      }
      try {
        await _db.storage.from('audios').uploadBinary(
              '${op.dados['caminho']}',
              await arquivo.readAsBytes(),
              fileOptions: FileOptions(contentType: '${op.dados['mime'] ?? 'audio/mp4'}'),
            );
      } on StorageException catch (e) {
        final jaExiste = e.statusCode == '409' || e.message.toLowerCase().contains('exist') ||
            e.message.toLowerCase().contains('duplicate');
        if (!jaExiste) rethrow;
      }
      await banco.gravarMeta('audio_subiu:$audioId', '1');
    }
    return recusadas;
  }

  /// Relatos já registrados na plataforma e ainda não processados: chama a
  /// função relato-processar (transcreve e organiza) e, se mudou algo, pede
  /// outra sincronização para baixar o resultado. Cada relato a processar
  /// fica marcado no aparelho (`relato_processar:<id>`) até a função responder.
  Future<void> _processarRelatos() async {
    if (_parado) return;
    if (_processandoRelatos) {
      _relatosDeNovo = true;
      return;
    }
    final chaves = banco.chavesMeta('relato_processar:');
    if (chaves.isEmpty) return;
    _processandoRelatos = true;
    var mudou = false;
    try {
      final naFila = {
        for (final o in banco.fila)
          if (o.tipo == 'relato_gravado') '${o.dados['audio_id']}': o.situacao,
      };
      for (final chave in chaves) {
        if (_parado) return;
        final id = chave.substring('relato_processar:'.length);
        final situacao = naFila[id];
        if (situacao == 'pendente') continue; // ainda não chegou à plataforma
        if (situacao == 'recusada') {
          await banco.gravarMeta(chave, null);
          continue;
        }
        try {
          await _db.functions
              .invoke('relato-processar', body: {'audio_id': id})
              .timeout(const Duration(seconds: 120));
          await banco.gravarMeta(chave, null);
          mudou = true;
        } on FunctionException catch (e) {
          final codigo = e.details is Map ? '${(e.details as Map)['code']}' : '';
          // Outro pedido já está processando: confere de novo na próxima.
          if (codigo == 'audio_processando') continue;
          // Sessão ou servidor fora: tenta tudo de novo depois.
          if (e.status == 401 || (e.status >= 500 && codigo != 'ia_falhou')) break;
          // A IA falhou (o relato fica "Erro", com o motivo) ou o relato não
          // pode mais ser processado: não insiste sozinho.
          await banco.gravarMeta(chave, null);
          mudou = true;
          debugPrint('Relato $id: ${e.status} ${e.details}');
        }
      }
    } catch (e) {
      // Sem internet ou tempo esgotado: tenta na próxima sincronização.
      debugPrint('Processar relatos: $e');
    } finally {
      _processandoRelatos = false;
      if (mudou || _relatosDeNovo) pedir();
      _relatosDeNovo = false;
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
      // Configuração da empresa (orçamento, assinatura) e dados do cabeçalho
      // do resumo que o cliente assina.
      if (r['config'] is Map) await banco.gravarMeta('config', jsonEncode(r['config']));
      if (r['empresa'] is Map) await banco.gravarMeta('empresa', jsonEncode(r['empresa']));
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
        // A foto que está no celular continua apontando para o arquivo local.
        final arquivos = {
          for (final f in banco.todos('atendimento_fotos'))
            if (f['arquivo_local'] != null) '${f['id']}': f['arquivo_local'],
        };
        await banco.substituir({
          for (final t in tabelasDoDia)
            t: [
              for (final l in ((dia[t] as List?) ?? const []).cast<Map<String, dynamic>>())
                if (t == 'atendimento_fotos' && arquivos.containsKey('${l['id']}'))
                  {...l, 'arquivo_local': arquivos['${l['id']}']}
                else
                  l,
            ],
        });
        await banco.gravarMeta('hoje', dia['hoje'] as String?);
        await banco.gravarMeta('hoje_aparelho', _hojeDoAparelho());
        await banco.gravarMeta('meu_checkin', dia['meu_checkin'] == null ? null : jsonEncode(dia['meu_checkin']));
      }
      querDia = false;
      paginas++;
      if (r['mais'] != true || paginas > 200) break;
    }
    banco.avisar();
  }

  /// Limpeza das fotos que já não são usadas, no máximo a cada 6 horas.
  Future<void> _limparDeVezEmQuando() async {
    final ultima = DateTime.tryParse(banco.meta('limpeza_fotos') ?? '');
    if (ultima != null && DateTime.now().toUtc().difference(ultima) < const Duration(hours: 6)) return;
    try {
      final n = await Arquivos.limparFotos(banco);
      if (n > 0) debugPrint('Limpeza: $n foto(s) apagada(s) do aparelho.');
      await banco.gravarMeta('limpeza_fotos', DateTime.now().toUtc().toIso8601String());
    } catch (e) {
      debugPrint('Limpeza das fotos: $e');
    }
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
