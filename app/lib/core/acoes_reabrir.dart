import 'package:supabase_flutter/supabase_flutter.dart';

import 'acoes_atendimento.dart';
import 'acoes_os.dart';
import 'acoes_parte.dart';
import 'banco_local.dart';
import 'consultas.dart';
import 'estado.dart';
import 'regras_reabrir.dart';
import 'sincronizacao.dart';

/// Reabrir OS pelo app (guia 109): o gestor ou o líder da equipe que fez o
/// serviço. Como as outras ações: entra na fila (os_reabrir), muda o celular
/// na hora e sobe quando houver internet; a plataforma confere as mesmas
/// regras do painel e, se recusar, o motivo aparece em Sincronização.
class AcoesReabrir {
  AcoesReabrir._();

  static EstadoApp get _estado => EstadoApp.instancia;
  static BancoLocal get _banco => _estado.banco!;
  static Sincronizador get _sync => _estado.sync!;

  /// Gestor (papel no token da sessão; sem sessão no celular, não).
  static bool get souGestor {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return token != null && ehGestor(papeisDoToken(token));
  }

  /// Uma reabertura desta OS ainda esperando internet.
  static bool pendente(Object? osId) =>
      _banco.fila.any((o) => o.tipo == 'os_reabrir' && o.situacao == 'pendente' && o.dados['os_id'] == osId);

  /// O botão aparece para este serviço?
  static bool podeReabrir(Map<String, dynamic> item) {
    final os = _banco.osDo(item);
    if (os == null || pendente(os['id'])) return false;
    final parte = _banco.um('partes_diarias', item['parte_id']) ?? const {};
    return podeReabrirServico(
      itemStatus: item['status'],
      osStatus: os['status'],
      planoPapel: os['plano_papel'],
      gestor: souGestor,
      lider: AcoesParte.souLider(parte),
    );
  }

  /// A parte de hoje para onde o serviço volta: a do próprio serviço, se é de
  /// hoje, está aberta e eu estou nela. null = vai para a fila do escritório.
  static Map<String, dynamic>? parteParaRefazer(Map<String, dynamic> item) {
    for (final p in AcoesOs.partesParaAtender()) {
      if (p['id'] == item['parte_id']) return p;
    }
    return null;
  }

  /// Reabre. Devolve o id do serviço novo, quando ele volta para a parte de
  /// hoje (para abrir a tela dele); null quando a visita vai para a fila.
  static Future<String?> reabrir(Map<String, dynamic> item, String motivo) async {
    final os = _banco.osDo(item);
    if (os == null) return null;
    final parte = parteParaRefazer(item);
    final novoItem = parte == null ? null : AcoesAtendimento.novoId();
    final texto = motivo.trim();
    await _sync.registrar(
      'os_reabrir',
      {
        'os_id': os['id'],
        'motivo': texto,
        'parte_item_origem_id': item['id'],
        if (parte != null) ...{'parte_id': parte['id'], 'parte_item_id': novoItem},
      },
      aplicarLocal: () async {
        if (os['status'] == 'concluida') {
          await _banco.gravar('ordens_servico', [
            {...os, 'status': 'em_andamento', 'concluida_em': null, 'garantia_ate': null}
          ], avisar: false);
        }
        if (parte != null) {
          // A visita nova no fim da parte (a plataforma dá o id dela ao subir:
          // aqui ela existe só para a tela, até o dia chegar de novo).
          final agId = AcoesAtendimento.novoId();
          await _banco.gravar('agendamentos', [
            {
              'id': agId,
              'os_id': os['id'],
              'tipo': os['tipo'] == 'preventiva' ? 'preventiva' : 'retorno',
              'status': 'programado',
              'prioridade': os['prioridade'],
              'data_prevista': parte['data'],
              'orientacoes': 'Reaberta: $texto',
            }
          ], avisar: false);
          final ultima = _banco
              .itensDaParte('${parte['id']}')
              .fold<num>(0, (m, i) => (i['ordem'] ?? 0) as num > m ? (i['ordem'] as num) : m);
          await _banco.gravar('partes_itens', [
            {
              'id': novoItem,
              'parte_id': parte['id'],
              'agendamento_id': agId,
              'data': parte['data'],
              'ordem': ultima + 1,
              'papel_equipe': 'responsavel',
              'status': 'programado',
              'designados': const <String>[],
              'incluido_apos_publicacao': true,
              'alterado_apos_publicacao': false,
            }
          ], avisar: false);
        }
        _banco.avisar();
      },
    );
    return novoItem;
  }
}
