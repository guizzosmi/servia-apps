import 'acoes_parte.dart';
import 'banco_local.dart';
import 'estado.dart';
import 'sincronizacao.dart';

/// O gestor encerra a OS pelo app (guia 111), pela fila (os_concluir): a
/// plataforma usa a regra do "Concluir OS" do painel e, se recusar, o motivo
/// aparece em Sincronização.
class AcoesEncerrar {
  AcoesEncerrar._();

  static BancoLocal get _banco => EstadoApp.instancia.banco!;
  static Sincronizador get _sync => EstadoApp.instancia.sync!;

  /// Um encerramento desta OS ainda esperando internet.
  static bool pendente(Object? osId) =>
      _banco.fila.any((o) => o.tipo == 'os_concluir' && o.situacao == 'pendente' && o.dados['os_id'] == osId);

  /// As outras visitas da OS que o celular conhece: as que estão na agenda
  /// (serviço em aberto numa parte) e quantas estão na fila sem serviço.
  static ({List<Map<String, dynamic>> naAgenda, int naFila}) outrasVisitas(Object? osId, {Object? exceto}) {
    final ags = _banco.todos('agendamentos').where((a) => a['os_id'] == osId && a['id'] != exceto).toList();
    final ids = {for (final a in ags) a['id']};
    final itens = _banco.todos('partes_itens').where((i) => ids.contains(i['agendamento_id'])).toList();
    final naAgenda = [
      for (final i in itens)
        if (AcoesParte.statusAbertos.contains(i['status'])) i,
    ];
    final comServico = {
      for (final i in itens)
        if (i['status'] != 'removido' && i['status'] != 'nao_realizado') i['agendamento_id'],
    };
    final naFila = ags
        .where((a) => (a['status'] == 'pendente' || a['status'] == 'suspenso') && !comServico.contains(a['id']))
        .length;
    return (naAgenda: naAgenda, naFila: naFila);
  }

  /// Encerra (conclui) a OS. [laudo]: o laudo final (vazio = fica o que já tinha).
  static Future<void> encerrar(Object? osId, {String laudo = ''}) async {
    await _sync.registrar(
      'os_concluir',
      {'os_id': osId, if (laudo.trim().isNotEmpty) 'laudo_final': laudo.trim()},
      aplicarLocal: () async {
        final os = _banco.um('ordens_servico', osId);
        if (os != null) {
          await _banco.gravar('ordens_servico', [
            {...os, 'status': 'concluida', 'concluida_em': DateTime.now().toUtc().toIso8601String()}
          ], avisar: false);
        }
        // As visitas que estavam na fila deixam de valer (como no painel).
        await _banco.gravar('agendamentos', [
          for (final a in _banco.todos('agendamentos'))
            if (a['os_id'] == osId && (a['status'] == 'pendente' || a['status'] == 'suspenso')) {...a, 'status': 'cancelado'},
        ], avisar: false);
        _banco.avisar();
      },
    );
  }
}
