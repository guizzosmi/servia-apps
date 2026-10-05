import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'banco_local.dart';
import 'consultas.dart';
import 'estado.dart';
import 'sincronizacao.dart';

/// Ações do atendimento. Cada uma vira uma operação na fila (a plataforma
/// confere as regras quando ela sobe) e muda o banco do celular na hora,
/// para a tela já mostrar o resultado, com ou sem internet.
class AcoesAtendimento {
  AcoesAtendimento._();

  static const _uuid = Uuid();

  /// Espaço de nomes para os ids "calculados" (UUID v5): o mesmo serviço
  /// gera o mesmo id de atendimento em qualquer celular, mesmo offline.
  static const _espaco = '6ba7b811-9dad-11d1-80b4-00c04fd430c8';

  static String idAtendimento(Object? parteItemId) => _uuid.v5(_espaco, 'servia:atendimento:$parteItemId');
  static String idMedicao(Object? atd, Object? equip, Object? modelo) =>
      _uuid.v5(_espaco, 'servia:medicao:$atd:$equip:$modelo');
  static String idFluido(Object? atd, Object? equip) => _uuid.v5(_espaco, 'servia:fluido:$atd:$equip');
  static String novoId() => _uuid.v4();

  static EstadoApp get _estado => EstadoApp.instancia;
  static BancoLocal get _banco => _estado.banco!;
  static Sincronizador get _sync => _estado.sync!;
  static String get eu => _estado.conta!.colaboradorId;
  static String _agora() => DateTime.now().toUtc().toIso8601String();

  /// Onde a pessoa (eu) está agora: o check-in aberto, se houver.
  static Map<String, dynamic>? meuCheckin() {
    final local = _banco.checkinAberto(eu);
    if (local != null) return local;
    final meta = _banco.meta('meu_checkin');
    if (meta == null) return null;
    try {
      return jsonDecode(meta) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Membros da equipe que estão livres (sem check-in aberto), fora eu.
  static List<String> membrosLivres(String parteId) => [
        for (final c in _banco.presentes(parteId))
          if (c['colaborador_id'] != eu && _banco.checkinAberto(c['colaborador_id']) == null)
            c['colaborador_id'] as String,
      ];

  // ------------------------------------------------------------------
  // Check-in e saída
  // ------------------------------------------------------------------

  /// "Estou neste serviço": cria o atendimento (se for o primeiro) e faz o
  /// check-in de quem pediu. O líder pode levar junto os membros livres.
  /// Com [colaboradorId], o líder faz o check-in de outra pessoa.
  static Future<String> checkin(
    Map<String, dynamic> item, {
    List<String> acompanhantes = const [],
    String? colaboradorId,
  }) async {
    final atdId = idAtendimento(item['id']);
    final quem = colaboradorId ?? eu;
    final participanteId = novoId();
    final acomp = [
      for (final c in acompanhantes) {'colaborador_id': c, 'participante_id': novoId()},
    ];
    final agora = _agora();
    await _sync.registrar(
      'checkin',
      {
        'parte_item_id': item['id'],
        'atendimento_id': atdId,
        'participante_id': participanteId,
        if (colaboradorId != null) 'colaborador_id': colaboradorId,
        if (acomp.isNotEmpty) 'acompanhantes': acomp,
      },
      aplicarLocal: () async {
        final ag = _banco.agendamentoDo(item) ?? const {};
        final parte = _banco.um('partes_diarias', item['parte_id']) ?? const {};
        var atd = _banco.um('atendimentos', atdId);
        if (atd == null) {
          atd = {
            'id': atdId,
            'os_id': ag['os_id'],
            'agendamento_id': item['agendamento_id'],
            'parte_item_id': item['id'],
            'status': 'em_andamento',
            'iniciado_em': agora,
          };
          await _banco.gravar('atendimentos', [atd]);
        } else if (atd['status'] == 'pausado') {
          await _banco.alterar('atendimentos', atdId, {'status': 'em_andamento'});
        }
        for (final p in [
          {'colaborador_id': quem, 'participante_id': participanteId},
          ...acomp,
        ]) {
          await _sairDeOutro(p['colaborador_id']!, atdId, agora);
          await _banco.gravar('atendimento_participantes', [
            {
              'id': p['participante_id'],
              'atendimento_id': atdId,
              'colaborador_id': p['colaborador_id'],
              'equipe_id': parte['equipe_id'],
              'entrada_em': agora,
              'saida_em': null,
              'origem': p['colaborador_id'] == quem
                  ? (colaboradorId == null ? 'checkin' : 'lider_por_outro')
                  : 'auto_lider',
            }
          ]);
        }
        if (quem == eu) {
          await _banco.gravarMeta('meu_checkin', jsonEncode({'id': participanteId, 'atendimento_id': atdId}));
        }
        if (item['status'] != 'em_atendimento') {
          await _banco.alterar('partes_itens', item['id'], {'status': 'em_atendimento'});
        }
        if (parte['status'] == 'publicada') {
          await _banco.alterar('partes_diarias', parte['id'], {'status': 'em_andamento'});
        }
      },
    );
    return atdId;
  }

  /// Fecha o check-in aberto da pessoa em outro serviço (uma pessoa, um
  /// serviço por vez). Se lá ficar sem ninguém, aquele serviço pausa.
  static Future<void> _sairDeOutro(String colaboradorId, String atdId, String agora) async {
    final aberto = _banco.checkinAberto(colaboradorId);
    if (aberto == null || aberto['atendimento_id'] == atdId) return;
    await _banco.alterar('atendimento_participantes', aberto['id'], {'saida_em': agora});
    await _pausarSeVazio(aberto['atendimento_id']);
  }

  static Future<void> _pausarSeVazio(Object? atdId) async {
    if (_banco.participantes(atdId, soAbertos: true).isNotEmpty) return;
    final atd = _banco.um('atendimentos', atdId);
    if (atd == null || atd['status'] != 'em_andamento') return;
    await _banco.alterar('atendimentos', atdId, {'status': 'pausado'});
    final item = _banco.um('partes_itens', atd['parte_item_id']);
    if (item != null && item['status'] == 'em_atendimento') {
      await _banco.alterar('partes_itens', item['id'], {'status': 'pausado'});
    }
  }

  /// "Sair do serviço" (a própria pessoa, ou o líder tirando alguém).
  static Future<void> checkout(Map<String, dynamic> participante) async {
    await _sync.registrar(
      'checkout',
      {'participante_id': participante['id']},
      aplicarLocal: () async {
        await _banco.alterar('atendimento_participantes', participante['id'], {'saida_em': _agora()});
        if (participante['colaborador_id'] == eu) await _banco.gravarMeta('meu_checkin', null);
        await _pausarSeVazio(participante['atendimento_id']);
      },
    );
  }

  // ------------------------------------------------------------------
  // Relato, equipamentos, medições, itens e fotos
  // ------------------------------------------------------------------

  static Future<void> salvarRelato(String atdId, Map<String, dynamic> campos) async {
    await _sync.registrar(
      'atendimento_salvar',
      {'atendimento_id': atdId, 'campos': campos},
      aplicarLocal: () => _banco.alterar('atendimentos', atdId, campos),
    );
  }

  /// Equipamento identificado no local (QR ou lista). Se não estava na OS,
  /// entra nela.
  static Future<void> identificarEquipamento(
    Map<String, dynamic> atd,
    Map<String, dynamic> equipamento, {
    required String leitura,
    String? valorLido,
  }) async {
    await _sync.registrar(
      'equipamento_identificado',
      {
        'atendimento_id': atd['id'],
        'equipamento_id': equipamento['id'],
        'leitura': leitura,
        if (valorLido != null) 'valor_lido': valorLido,
      },
      aplicarLocal: () async {
        if (_banco.identificacao(atd['id'], equipamento['id']) == null) {
          await _banco.gravar('atendimento_equipamentos', [
            {
              'id': novoId(),
              'atendimento_id': atd['id'],
              'equipamento_id': equipamento['id'],
              'leitura': leitura,
              'valor_lido': valorLido,
              'lido_em': _agora(),
            }
          ]);
        }
        final naOs = _banco.todos('os_equipamentos').any((e) => e['os_id'] == atd['os_id'] && e['equipamento_id'] == equipamento['id']);
        if (!naOs) {
          await _banco.gravar('os_equipamentos', [
            {'id': novoId(), 'os_id': atd['os_id'], 'equipamento_id': equipamento['id'], 'principal': false}
          ]);
        }
      },
    );
  }

  /// Grava (ou apaga, com valor vazio) uma medição.
  static Future<void> salvarMedicao(
    Map<String, dynamic> atd,
    Map<String, dynamic> equipamento,
    Map<String, dynamic> modelo, {
    num? numero,
    String? texto,
  }) async {
    final id = idMedicao(atd['id'], equipamento['id'], modelo['id']);
    final apagar = numero == null && (texto == null || texto.isEmpty);
    final min = modelo['faixa_min'] as num?, max = modelo['faixa_max'] as num?;
    final fora = numero != null && ((min != null && numero < min) || (max != null && numero > max));
    await _sync.registrar(
      'medicao_salvar',
      {
        'medicao_id': id,
        'atendimento_id': atd['id'],
        'equipamento_id': equipamento['id'],
        'modelo_medicao_id': modelo['id'],
        if (apagar) 'excluir': true,
        if (numero != null) 'valor_numero': numero,
        if (texto != null && texto.isNotEmpty) 'valor_texto': texto,
      },
      aplicarLocal: () async {
        if (apagar) {
          await _banco.apagarIds('atendimento_medicoes', [id]);
        } else {
          await _banco.gravar('atendimento_medicoes', [
            {
              'id': id,
              'atendimento_id': atd['id'],
              'equipamento_id': equipamento['id'],
              'modelo_medicao_id': modelo['id'],
              'valor_numero': numero,
              'valor_texto': texto,
              'unidade': modelo['unidade'],
              'fora_faixa': fora,
              'medido_em': _agora(),
            }
          ]);
        }
      },
    );
  }

  static Future<void> salvarFluido(
    Map<String, dynamic> atd,
    Map<String, dynamic> equipamento, {
    required String fluido,
    required num adicionadoKg,
    required num recolhidoKg,
  }) async {
    final id = idFluido(atd['id'], equipamento['id']);
    final apagar = adicionadoKg == 0 && recolhidoKg == 0;
    await _sync.registrar(
      'fluido_salvar',
      {
        'fluido_id': id,
        'atendimento_id': atd['id'],
        'equipamento_id': equipamento['id'],
        'fluido': fluido,
        'adicionado_kg': adicionadoKg,
        'recolhido_kg': recolhidoKg,
        if (apagar) 'excluir': true,
      },
      aplicarLocal: () async {
        if (apagar) {
          await _banco.apagarIds('atendimento_fluidos', [id]);
        } else {
          await _banco.gravar('atendimento_fluidos', [
            {
              'id': id,
              'atendimento_id': atd['id'],
              'equipamento_id': equipamento['id'],
              'fluido': fluido,
              'adicionado_kg': adicionadoKg,
              'recolhido_kg': recolhidoKg,
            }
          ]);
        }
      },
    );
  }

  /// Peça ou serviço usado: do cadastro (com preço) ou texto livre.
  static Future<void> salvarItem(
    Map<String, dynamic> atd, {
    Map<String, dynamic>? produto,
    String? descricao,
    String? tipo,
    String? unidade,
    required num quantidade,
    String? itemId,
  }) async {
    final id = itemId ?? novoId();
    // Como na plataforma: o preço e o desconto que o gestor deu ficam; item
    // novo (ou outro produto) usa o preço de venda do cadastro.
    final atual = _banco.um('os_itens', id);
    final num preco;
    if (atual != null && atual['produto_id'] == produto?['id']) {
      preco = num.tryParse('${atual['preco_unitario']}') ?? 0;
    } else {
      preco = (produto?['preco_venda'] as num?) ?? 0;
    }
    final desconto = num.tryParse('${atual?['desconto'] ?? 0}') ?? 0;
    await _sync.registrar(
      'item_os_salvar',
      {
        'item_id': id,
        'atendimento_id': atd['id'],
        if (produto != null) 'produto_id': produto['id'],
        if (descricao != null) 'descricao': descricao,
        if (tipo != null) 'tipo': tipo,
        if (unidade != null) 'unidade': unidade,
        'quantidade': quantidade,
      },
      aplicarLocal: () => _banco.gravar('os_itens', [
        {
          'id': id,
          'os_id': atd['os_id'],
          'atendimento_id': atd['id'],
          'produto_id': produto?['id'],
          'descricao': descricao ?? produto?['descricao'] ?? 'Item',
          'tipo': produto?['tipo'] ?? tipo ?? 'produto',
          'quantidade': quantidade,
          'unidade': produto?['unidade'] ?? unidade ?? 'un',
          'preco_unitario': preco,
          'desconto': desconto,
          'total': (quantidade * preco * 100).round() / 100 - desconto,
          'origem': 'manual',
          'confirmado': true,
        }
      ]),
    );
  }

  static Future<void> apagarItem(Map<String, dynamic> item) async {
    await _sync.registrar(
      'item_os_salvar',
      {'item_id': item['id'], 'atendimento_id': item['atendimento_id'], 'excluir': true},
      aplicarLocal: () => _banco.apagarIds('os_itens', ['${item['id']}']),
    );
  }

  /// Foto tirada no app: o arquivo fica no celular e sobe na sincronização,
  /// antes da operação que a registra.
  static Future<void> registrarFoto(
    Map<String, dynamic> atd, {
    required String fotoId,
    required String arquivoLocal,
    required String sha256,
    String? equipamentoId,
  }) async {
    final conta = _estado.conta!;
    final agora = DateTime.now();
    final mes = agora.month.toString().padLeft(2, '0');
    final caminho = '${conta.contaId}/${conta.empresaId}/${agora.year}/$mes/$fotoId.jpg';
    await _sync.registrar(
      'foto_registrada',
      {
        'foto_id': fotoId,
        'atendimento_id': atd['id'],
        'caminho': caminho,
        'sha256': sha256,
        'tirada_em': agora.toUtc().toIso8601String(),
        if (equipamentoId != null) 'equipamento_id': equipamentoId,
        // Só para o app: onde está o arquivo (a plataforma ignora).
        'arquivo_local': arquivoLocal,
      },
      aplicarLocal: () => _banco.gravar('atendimento_fotos', [
        {
          'id': fotoId,
          'atendimento_id': atd['id'],
          'equipamento_id': equipamentoId,
          'caminho': caminho,
          'sha256': sha256,
          'tirada_em': agora.toUtc().toIso8601String(),
          'arquivo_local': arquivoLocal,
        }
      ]),
    );
  }

  static Future<void> apagarFoto(Map<String, dynamic> foto) async {
    await _sync.registrar(
      'foto_registrada',
      {'foto_id': foto['id'], 'atendimento_id': foto['atendimento_id'], 'excluir': true},
      aplicarLocal: () => _banco.apagarIds('atendimento_fotos', ['${foto['id']}']),
    );
  }

  // ------------------------------------------------------------------
  // Encerrar o atendimento
  // ------------------------------------------------------------------

  /// [semAssinaturaMotivo]: o cliente acompanhou, mas não assinou na tela
  /// (assinatura obrigatória na empresa): o motivo fica no histórico.
  static Future<void> concluir(Map<String, dynamic> atd,
      {bool? clientePresente, String? contatoNome, String? semAssinaturaMotivo}) async {
    await _sync.registrar(
      'atendimento_concluir',
      {
        'atendimento_id': atd['id'],
        if (clientePresente != null) 'cliente_presente': clientePresente,
        if (contatoNome != null && contatoNome.trim().isNotEmpty) 'contato_cliente_nome': contatoNome.trim(),
        if (semAssinaturaMotivo != null && semAssinaturaMotivo.trim().isNotEmpty)
          'sem_assinatura_motivo': semAssinaturaMotivo.trim(),
      },
      aplicarLocal: () => _encerrarLocal(atd, 'concluido', 'concluido'),
    );
  }

  static Future<void> naoRealizado(Map<String, dynamic> atd, {required String motivo, String? observacao}) async {
    await _sync.registrar(
      'atendimento_nao_realizado',
      {
        'atendimento_id': atd['id'],
        'motivo': motivo,
        if (observacao != null && observacao.trim().isNotEmpty) 'observacao': observacao.trim(),
      },
      aplicarLocal: () async {
        await _encerrarLocal(atd, 'nao_realizado', 'nao_realizado');
        await _banco.alterar('atendimentos', atd['id'], {'resultado_motivo': motivo});
        await _banco.alterar('partes_itens', atd['parte_item_id'], {'resultado_motivo': motivo});
      },
    );
  }

  static Future<void> _encerrarLocal(Map<String, dynamic> atd, String statusAtd, String statusItem) async {
    final agora = _agora();
    for (final p in _banco.participantes(atd['id'], soAbertos: true)) {
      await _banco.alterar('atendimento_participantes', p['id'], {'saida_em': agora});
      if (p['colaborador_id'] == eu) await _banco.gravarMeta('meu_checkin', null);
    }
    await _banco.alterar('atendimentos', atd['id'], {'status': statusAtd, 'concluido_em': agora});
    await _banco.alterar('partes_itens', atd['parte_item_id'], {'status': statusItem, 'concluido_em': agora});
  }
}
