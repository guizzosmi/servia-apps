import 'banco_local.dart';

/// Leituras prontas para as telas (tudo vem do banco do aparelho).
extension Consultas on BancoLocal {
  /// Partes publicadas do dia, das equipes em que a pessoa está.
  List<Map<String, dynamic>> partesDoDia(String data) {
    final lista = todos('partes_diarias').where((p) => p['data'] == data && p['status'] != 'rascunho').toList()
      ..sort((a, b) => nomeEquipe(a['equipe_id']).compareTo(nomeEquipe(b['equipe_id'])));
    return lista;
  }

  /// Serviços de uma parte, na ordem (sem os retirados).
  List<Map<String, dynamic>> itensDaParte(String parteId) {
    final lista = todos('partes_itens').where((i) => i['parte_id'] == parteId && i['status'] != 'removido').toList()
      ..sort((a, b) => ((a['ordem'] ?? 0) as num).compareTo((b['ordem'] ?? 0) as num));
    return lista;
  }

  /// Quem está na equipe agora (líder primeiro).
  List<Map<String, dynamic>> presentes(String parteId) {
    final lista = todos('partes_composicao')
        .where((c) => c['parte_id'] == parteId && c['saida_em'] == null)
        .toList()
      ..sort((a, b) {
        if (a['papel'] != b['papel']) return a['papel'] == 'lider' ? -1 : 1;
        return nomeColaborador(a['colaborador_id']).compareTo(nomeColaborador(b['colaborador_id']));
      });
    return lista;
  }

  String nomeColaborador(Object? id) => '${um('colaboradores', id)?['nome'] ?? '?'}';
  String nomeEquipe(Object? id) => '${um('equipes', id)?['nome'] ?? 'Equipe'}';

  /// O agendamento e a OS de um serviço da parte.
  Map<String, dynamic>? agendamentoDo(Map<String, dynamic> item) => um('agendamentos', item['agendamento_id']);
  Map<String, dynamic>? osDo(Map<String, dynamic> item) => um('ordens_servico', agendamentoDo(item)?['os_id']);

  /// Equipamentos da OS (os mais importantes primeiro).
  List<Map<String, dynamic>> equipamentosDaOs(Object? osId) {
    final ligacoes = todos('os_equipamentos').where((e) => e['os_id'] == osId).toList()
      ..sort((a, b) => (b['principal'] == true ? 1 : 0).compareTo(a['principal'] == true ? 1 : 0));
    return [
      for (final l in ligacoes)
        if (um('equipamentos', l['equipamento_id']) case final Map<String, dynamic> e) e,
    ];
  }

  /// Atendimento (aberto ou não) de um serviço da parte.
  Map<String, dynamic>? atendimentoDoItem(Object? itemId) {
    for (final a in todos('atendimentos')) {
      if (a['parte_item_id'] == itemId) return a;
    }
    return null;
  }

  /// Check-ins de um atendimento (os abertos primeiro, por horário).
  List<Map<String, dynamic>> participantes(Object? atendimentoId, {bool soAbertos = false}) {
    final lista = todos('atendimento_participantes')
        .where((p) => p['atendimento_id'] == atendimentoId && (!soAbertos || p['saida_em'] == null))
        .toList()
      ..sort((a, b) => '${a['entrada_em']}'.compareTo('${b['entrada_em']}'));
    return lista;
  }

  /// Check-in aberto de uma pessoa (em qualquer serviço baixado).
  Map<String, dynamic>? checkinAberto(Object? colaboradorId) {
    for (final p in todos('atendimento_participantes')) {
      if (p['colaborador_id'] == colaboradorId && p['saida_em'] == null) return p;
    }
    return null;
  }

  /// Equipamentos do atendimento: os da OS mais os identificados no local.
  List<Map<String, dynamic>> equipamentosDoAtendimento(Map<String, dynamic> atd) {
    final ids = <String>{
      for (final e in equipamentosDaOs(atd['os_id'])) '${e['id']}',
      for (final a in todos('atendimento_equipamentos'))
        if (a['atendimento_id'] == atd['id']) '${a['equipamento_id']}',
    };
    return [
      for (final id in ids)
        if (um('equipamentos', id) case final Map<String, dynamic> e) e,
    ]..sort((a, b) => '${a['codigo']}'.compareTo('${b['codigo']}'));
  }

  /// Como o equipamento foi identificado neste atendimento (ou null).
  Map<String, dynamic>? identificacao(Object? atendimentoId, Object? equipamentoId) {
    for (final a in todos('atendimento_equipamentos')) {
      if (a['atendimento_id'] == atendimentoId && a['equipamento_id'] == equipamentoId) return a;
    }
    return null;
  }

  /// Medições do cadastro para o tipo do equipamento, na ordem.
  List<Map<String, dynamic>> modelosDoTipo(Object? tipoId) {
    final lista = todos('modelos_medicao')
        .where((m) => m['tipo_equipamento_id'] == tipoId && m['ativo'] != false)
        .toList()
      ..sort((a, b) => ((a['ordem'] ?? 0) as num).compareTo((b['ordem'] ?? 0) as num));
    return lista;
  }

  /// Registros de um atendimento numa tabela filha (medições, itens, fotos...).
  List<Map<String, dynamic>> doAtendimento(String tabela, Object? atendimentoId) =>
      todos(tabela).where((r) => r['atendimento_id'] == atendimentoId).toList();
}
