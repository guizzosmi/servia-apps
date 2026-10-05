import 'dart:io';

import 'package:uuid/uuid.dart';

import 'acoes_orcamento.dart';
import 'banco_local.dart';
import 'estado.dart';
import 'sincronizacao.dart';

/// Um relato por áudio do atendimento, como a tela mostra: o que ainda está
/// no aparelho (na fila) ou o que a plataforma já tem (tabela audios).
class RelatoAudio {
  const RelatoAudio({
    required this.id,
    required this.status,
    required this.gravadoEm,
    this.duracaoS,
    this.gravadoPor,
    this.erro,
    this.resultado,
    this.transcricao,
    this.opId,
  });

  final String id;

  /// aguardando_envio | recusado (só no aparelho) | enviado | processando |
  /// pronto | erro | revisado
  final String status;
  final String gravadoEm;
  final num? duracaoS;
  final String? gravadoPor;
  final String? erro;
  final Map<String, dynamic>? resultado;
  final String? transcricao;

  /// Operação da fila (relato que ainda não subiu).
  final String? opId;
}

/// Relato por áudio (guia 16): gravado no atendimento, sobe na
/// sincronização (o arquivo antes da operação "relato_gravado") e, depois de
/// registrado, a plataforma transcreve e organiza (relato-processar). A
/// revisão do que a IA entendeu vem no guia 17.
class AcoesRelato {
  AcoesRelato._();

  static const _uuid = Uuid();

  /// Até 10 minutos por relato (uns 5 MB).
  static const duracaoMaxima = Duration(minutes: 10);

  /// Menos que isso não dá relato.
  static const duracaoMinima = Duration(seconds: 2);

  static EstadoApp get _estado => EstadoApp.instancia;
  static BancoLocal get _banco => _estado.banco!;
  static Sincronizador get _sync => _estado.sync!;

  static bool get ligado => AcoesOrcamento.config.relatoAudio;

  static String novoId() => _uuid.v4();

  /// O relato gravado (arquivo em [arquivoLocal], na pasta de áudios do app)
  /// entra na fila. A IA é chamada assim que ele chegar à plataforma.
  static Future<void> registrar(
    Map<String, dynamic> atd, {
    required String audioId,
    required String arquivoLocal,
    required Duration duracao,
  }) async {
    final conta = _estado.conta!;
    final agora = DateTime.now();
    final mes = agora.month.toString().padLeft(2, '0');
    final caminho = '${conta.contaId}/${conta.empresaId}/${agora.year}/$mes/$audioId.m4a';
    var tamanho = 0;
    try {
      tamanho = await File(arquivoLocal).length();
    } catch (_) {
      // O tamanho é só informativo.
    }
    await _sync.registrar('relato_gravado', {
      'audio_id': audioId,
      'atendimento_id': atd['id'],
      'caminho': caminho,
      'mime': 'audio/mp4',
      'tamanho_bytes': tamanho,
      'duracao_s': (duracao.inMilliseconds / 1000).toStringAsFixed(1),
      'gravado_em': agora.toUtc().toIso8601String(),
      // Só para o app: onde está o arquivo (a plataforma ignora).
      'arquivo_local': arquivoLocal,
    },
        // Depois de entrar na fila: a IA só é chamada quando a operação subir.
        aplicarLocal: () => _banco.gravarMeta('relato_processar:$audioId', '1'));
  }

  /// Pede para a IA processar de novo (relato com erro ou parado).
  static Future<void> processarDeNovo(String audioId) async {
    await _banco.gravarMeta('relato_processar:$audioId', '1', avisar: true);
    await _sync.sincronizar();
  }

  /// Este relato está esperando a IA neste aparelho?
  static bool aguardandoIa(String audioId) => _banco.meta('relato_processar:$audioId') != null;

  /// Os relatos do atendimento, do mais novo para o mais antigo.
  static List<RelatoAudio> doAtendimento(Object? atdId) {
    final naFila = <String, RelatoAudio>{};
    for (final o in _banco.fila) {
      if (o.tipo != 'relato_gravado' || o.dados['atendimento_id'] != atdId) continue;
      final id = '${o.dados['audio_id']}';
      naFila[id] = RelatoAudio(
        id: id,
        status: o.situacao == 'recusada' ? 'recusado' : 'aguardando_envio',
        gravadoEm: '${o.dados['gravado_em'] ?? o.em}',
        duracaoS: num.tryParse('${o.dados['duracao_s']}'),
        gravadoPor: _estado.conta?.colaboradorId,
        erro: o.erro,
        opId: o.opId,
      );
    }
    final lista = [
      ...naFila.values,
      for (final a in _banco.todos('audios'))
        if (a['atendimento_id'] == atdId && !naFila.containsKey('${a['id']}'))
          RelatoAudio(
            id: '${a['id']}',
            status: '${a['status']}',
            gravadoEm: '${a['gravado_em']}',
            duracaoS: num.tryParse('${a['duracao_s']}'),
            gravadoPor: a['gravado_por'] as String?,
            erro: a['erro'] as String?,
            resultado: (a['resultado'] as Map?)?.cast<String, dynamic>(),
            transcricao: a['transcricao'] as String?,
          ),
    ];
    // (a hora da plataforma vem com fuso; a do aparelho, em UTC)
    DateTime quando(RelatoAudio r) => DateTime.tryParse(r.gravadoEm)?.toUtc() ?? DateTime(2000);
    lista.sort((a, b) => quando(b).compareTo(quando(a)));
    return lista;
  }
}
