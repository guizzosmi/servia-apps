import 'acoes_atendimento.dart';
import 'acoes_parte.dart';
import 'banco_local.dart';
import 'consultas.dart';
import 'estado.dart';
import 'sincronizacao.dart';

/// O líder conduz a parte (guia 28): ordem dos serviços, quem faz cada um,
/// a equipe do dia (tirar, incluir, emprestar) e o pedido de replanejamento
/// ao escritório. Cada ação vira uma operação na fila (a plataforma confere
/// as regras) e muda o celular na hora.
class AcoesLider {
  AcoesLider._();

  static EstadoApp get _estado => EstadoApp.instancia;
  static BancoLocal get _banco => _estado.banco!;
  static Sincronizador get _sync => _estado.sync!;
  static String _agora() => DateTime.now().toUtc().toIso8601String();

  /// O líder mexe na parte publicada ou em andamento (qualquer dia baixado).
  static bool podeConduzir(Map<String, dynamic> parte) =>
      AcoesParte.souLider(parte) && (parte['status'] == 'publicada' || parte['status'] == 'em_andamento');

  // ------------------------------------------------------------------
  // Ordem e quem faz
  // ------------------------------------------------------------------

  static Future<void> reordenar(Map<String, dynamic> parte, List<String> itens) async {
    await _sync.registrar(
      'parte_reordenar',
      {'parte_id': parte['id'], 'itens': itens},
      // Tudo de uma vez: a tela redesenha uma vez só, já na ordem nova.
      aplicarLocal: () => _banco.gravar('partes_itens', [
        for (var i = 0; i < itens.length; i++)
          if (_banco.um('partes_itens', itens[i]) case final Map<String, dynamic> item) {...item, 'ordem': i + 1},
      ]),
    );
  }

  static Future<void> designar(Map<String, dynamic> item, List<String> designados) async {
    await _sync.registrar(
      'parte_designar',
      {'parte_item_id': item['id'], 'designados': designados},
      aplicarLocal: () => _banco.alterar('partes_itens', item['id'], {'designados': designados}),
    );
  }

  // ------------------------------------------------------------------
  // Equipe do dia
  // ------------------------------------------------------------------

  /// Quem pode entrar: ativo e sem equipe neste dia (pelo que o celular sabe;
  /// a plataforma confere de novo).
  static List<Map<String, dynamic>> livresParaIncluir(Map<String, dynamic> parte) {
    final data = parte['data'];
    final ocupados = {
      for (final a in _banco.todos('alocados_do_dia'))
        if (a['data'] == data) '${a['colaborador_id']}',
      for (final c in _banco.presentes('${parte['id']}')) '${c['colaborador_id']}',
    };
    return _banco
        .todos('colaboradores')
        .where((c) => c['ativo'] != false && c['excluido_em'] == null && !ocupados.contains('${c['id']}'))
        .toList()
      ..sort((a, b) => '${a['nome']}'.compareTo('${b['nome']}'));
  }

  /// Outras equipes do mesmo dia, para emprestar alguém.
  static List<Map<String, dynamic>> destinosParaEmprestar(Map<String, dynamic> parte) => _banco
      .todos('equipes_do_dia')
      .where((p) => p['data'] == parte['data'] && p['id'] != parte['id'] && p['status'] != 'encerrada')
      .toList()
    ..sort((a, b) => _banco.nomeEquipe(a['equipe_id']).compareTo(_banco.nomeEquipe(b['equipe_id'])));

  static Future<void> incluir(Map<String, dynamic> parte, String colaboradorId) async {
    await _sync.registrar(
      'parte_composicao',
      {'parte_id': parte['id'], 'movimento': 'entrar', 'colaborador_id': colaboradorId},
      aplicarLocal: () async {
        final id = AcoesAtendimento.novoId();
        final linha = {
          'id': id,
          'parte_id': parte['id'],
          'colaborador_id': colaboradorId,
          'papel': 'membro',
          'data': parte['data'],
          'entrada_em': _agora(),
          'saida_em': null,
          'origem': 'incluido_lider',
        };
        await _banco.gravar('partes_composicao', [linha]);
        await _banco.gravar('alocados_do_dia', [
          {'id': id, 'parte_id': parte['id'], 'colaborador_id': colaboradorId, 'data': parte['data'], 'papel': 'membro'},
        ]);
      },
    );
  }

  /// Tira do dia; com [destinoParteId], empresta para aquela equipe.
  static Future<void> tirar(Map<String, dynamic> parte, String colaboradorId, {String? destinoParteId}) async {
    await _sync.registrar(
      'parte_composicao',
      {
        'parte_id': parte['id'],
        'movimento': destinoParteId == null ? 'sair' : 'emprestar',
        'colaborador_id': colaboradorId,
        if (destinoParteId != null) 'destino_parte_id': destinoParteId,
      },
      aplicarLocal: () async {
        final agora = _agora();
        final parteId = '${parte['id']}';
        // Sai do serviço em que estava (o serviço pausa se ficar sem ninguém).
        for (final item in _banco.itensDaParte(parteId)) {
          final atd = _banco.atendimentoDoItem(item['id']);
          if (atd == null) continue;
          var saiu = false;
          for (final p in _banco.participantes(atd['id'], soAbertos: true)) {
            if (p['colaborador_id'] != colaboradorId) continue;
            await _banco.alterar('atendimento_participantes', p['id'], {'saida_em': agora});
            saiu = true;
          }
          if (saiu && atd['status'] == 'em_andamento' && _banco.participantes(atd['id'], soAbertos: true).isEmpty) {
            await _banco.alterar('atendimentos', atd['id'], {'status': 'pausado'});
            if (item['status'] == 'em_atendimento') {
              await _banco.alterar('partes_itens', item['id'], {'status': 'pausado'});
            }
          }
          // Sai dos serviços que ainda não começaram.
          final designados = ((item['designados'] as List?) ?? const []).cast<String>();
          if ((item['status'] == 'programado' || item['status'] == 'em_deslocamento') &&
              designados.contains(colaboradorId)) {
            await _banco.alterar('partes_itens', item['id'],
                {'designados': designados.where((d) => d != colaboradorId).toList()});
          }
        }
        for (final c in _banco.presentes(parteId)) {
          if (c['colaborador_id'] == colaboradorId) {
            await _banco.alterar('partes_composicao', c['id'], {'saida_em': agora});
          }
        }
        final alocacoes = [
          for (final a in _banco.todos('alocados_do_dia'))
            if (a['parte_id'] == parteId && a['colaborador_id'] == colaboradorId) '${a['id']}',
        ];
        if (alocacoes.isNotEmpty) await _banco.apagarIds('alocados_do_dia', alocacoes);
        if (destinoParteId != null) {
          await _banco.gravar('alocados_do_dia', [
            {
              'id': AcoesAtendimento.novoId(),
              'parte_id': destinoParteId,
              'colaborador_id': colaboradorId,
              'data': parte['data'],
              'papel': 'membro',
            },
          ]);
        }
      },
    );
  }

  // ------------------------------------------------------------------
  // Pedido de replanejamento
  // ------------------------------------------------------------------

  /// O pedido mais recente do serviço (ou null).
  static Map<String, dynamic>? pedidoDo(Object? itemId) {
    final lista = _banco
        .todos('replanejamentos')
        .where((r) => r['parte_item_id'] == itemId && r['excluido_em'] == null)
        .toList()
      ..sort((a, b) => '${b['criado_em']}'.compareTo('${a['criado_em']}'));
    return lista.isEmpty ? null : lista.first;
  }

  /// Só para serviço que ainda não começou.
  static bool podePedir(Map<String, dynamic> item) =>
      item['status'] == 'programado' || item['status'] == 'em_deslocamento';

  static Future<void> pedirReplanejamento(
    Map<String, dynamic> item, {
    required String motivo,
    String? dataSugerida,
    String? observacao,
  }) async {
    final id = AcoesAtendimento.novoId();
    final obs = observacao?.trim() ?? '';
    await _sync.registrar(
      'replanejamento_pedir',
      {
        'pedido_id': id,
        'parte_item_id': item['id'],
        'motivo': motivo,
        if (dataSugerida != null) 'data_sugerida': dataSugerida,
        if (obs.isNotEmpty) 'observacao': obs,
      },
      aplicarLocal: () async {
        final agora = _agora();
        for (final r in _banco.todos('replanejamentos')) {
          if (r['parte_item_id'] == item['id'] && r['status'] == 'pendente' && r['excluido_em'] == null) {
            await _banco.alterar('replanejamentos', r['id'], {'excluido_em': agora});
          }
        }
        await _banco.gravar('replanejamentos', [
          {
            'id': id,
            'parte_item_id': item['id'],
            'parte_id': item['parte_id'],
            'motivo': motivo,
            'data_sugerida': dataSugerida,
            'observacao': obs.isEmpty ? null : obs,
            'status': 'pendente',
            'pedido_por': AcoesAtendimento.eu,
            'criado_em': agora,
            'excluido_em': null,
          },
        ]);
      },
    );
  }
}

/// Motivos do pedido de replanejamento (os mesmos códigos da plataforma).
const motivosReplanejamento = {
  'cliente_pediu': 'Cliente pediu outro dia',
  'falta_peca': 'Falta de peça',
  'tempo': 'Não vai dar tempo',
  'clima': 'Clima',
  'outra_equipe': 'Precisa de outra equipe',
  'outro': 'Outro',
};
