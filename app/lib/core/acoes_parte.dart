import 'banco_local.dart';
import 'consultas.dart';
import 'estado.dart';
import 'sincronizacao.dart';

/// Encerrar o dia (guia 30): o líder fecha a parte da equipe pelo app.
/// O que não foi feito volta para a fila com o motivo; quem ainda estava
/// num serviço sai dele; a equipe do dia é fechada.
class AcoesParte {
  AcoesParte._();

  static EstadoApp get _estado => EstadoApp.instancia;
  static BancoLocal get _banco => _estado.banco!;
  static Sincronizador get _sync => _estado.sync!;
  static String get eu => _estado.conta!.colaboradorId;

  static const statusAbertos = {'programado', 'em_deslocamento', 'em_atendimento', 'pausado'};

  static bool souLider(Map<String, dynamic> parte) => parte['lider_colaborador_id'] == eu;

  /// Publicada ou em andamento, de hoje ou de antes (dia futuro não).
  static bool podeEncerrar(Map<String, dynamic> parte) {
    final status = parte['status'];
    return souLider(parte) &&
        (status == 'publicada' || status == 'em_andamento') &&
        '${parte['data']}'.compareTo(_sync.hoje) <= 0;
  }

  /// Os dias anteriores que eu (líder) ainda não encerrei.
  static List<Map<String, dynamic>> diasSemFechar() => [
        for (final p in _banco.todos('partes_diarias'))
          if ('${p['data']}'.compareTo(_sync.hoje) < 0 && podeEncerrar(p)) p,
      ]..sort((a, b) => '${a['data']}'.compareTo('${b['data']}'));

  /// Serviços da parte ainda sem resultado (não concluídos nem "não realizado").
  static List<Map<String, dynamic>> abertos(String parteId) =>
      _banco.itensDaParte(parteId).where((i) => statusAbertos.contains(i['status'])).toList();

  /// Quem ainda está em algum serviço da parte (check-in aberto).
  static List<String> noServico(String parteId) => [
        for (final i in abertos(parteId))
          if (_banco.atendimentoDoItem(i['id']) case final Map<String, dynamic> atd)
            for (final p in _banco.participantes(atd['id'], soAbertos: true)) '${p['colaborador_id']}',
      ];

  /// [motivos]: parte_item_id -> motivo (os códigos de motivosNaoRealizado).
  static Future<void> encerrar(Map<String, dynamic> parte,
      {required Map<String, String> motivos, String? resumo}) async {
    final parteId = '${parte['id']}';
    final texto = resumo?.trim() ?? '';
    await _sync.registrar(
      'parte_encerrar',
      {
        'parte_id': parteId,
        'motivos': motivos,
        // Serviço encaixado depois da última sincronização (o app não conhecia).
        'motivo_padrao': 'outro',
        if (texto.isNotEmpty) 'resumo_texto': texto,
      },
      aplicarLocal: () async {
        final agora = DateTime.now().toUtc().toIso8601String();
        for (final item in abertos(parteId)) {
          final motivo = motivos['${item['id']}'] ?? 'outro';
          final atd = _banco.atendimentoDoItem(item['id']);
          if (atd != null && (atd['status'] == 'em_andamento' || atd['status'] == 'pausado')) {
            for (final p in _banco.participantes(atd['id'], soAbertos: true)) {
              await _banco.alterar('atendimento_participantes', p['id'], {'saida_em': agora});
              if (p['colaborador_id'] == eu) await _banco.gravarMeta('meu_checkin', null);
            }
            await _banco.alterar('atendimentos', atd['id'],
                {'status': 'nao_realizado', 'concluido_em': agora, 'resultado_motivo': motivo});
          }
          await _banco.alterar('partes_itens', item['id'],
              {'status': 'nao_realizado', 'concluido_em': agora, 'resultado_motivo': motivo});
        }
        for (final c in _banco.presentes(parteId)) {
          await _banco.alterar('partes_composicao', c['id'], {'saida_em': agora});
        }
        await _banco.alterar('partes_diarias', parteId, {
          'status': 'encerrada',
          'encerrada_em': agora,
          if (texto.isNotEmpty) 'resumo_texto': texto,
        });
      },
    );
  }
}
