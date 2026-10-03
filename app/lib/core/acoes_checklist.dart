import 'acoes_atendimento.dart';
import 'banco_local.dart';
import 'estado.dart';
import 'sincronizacao.dart';

/// Resultado de um item do checklist da preventiva (mesmos códigos do banco).
const resultadosChecklist = {
  'feito': 'Feito',
  'nao_se_aplica': 'Não se aplica',
  'nao_conforme': 'Não conforme',
};

/// Andamento do checklist de um lote. "Unidade" = um aparelho, ou uma
/// atividade geral do plano (ex.: avaliação do ar).
class AndamentoChecklist {
  const AndamentoChecklist({required this.total, required this.prontas, required this.naoConformes, this.prazo});

  final int total;
  final int prontas;
  final int naoConformes;

  /// Fim do lote (o mês ou a quinzena).
  final String? prazo;

  int get faltam => total - prontas;
  double get fracao => total == 0 ? 0 : prontas / total;
}

/// O checklist do lote da preventiva (plano_execucoes), marcado pela equipe
/// no atendimento. Quando todos os itens de um aparelho estão marcados, a
/// plataforma fecha o ciclo e cria a OS do aparelho. Cada marcação vira uma operação na fila e muda o banco do
/// celular na hora, com ou sem internet.
class AcoesChecklist {
  AcoesChecklist._();

  static BancoLocal get _banco => EstadoApp.instancia.banco!;
  static Sincronizador get _sync => EstadoApp.instancia.sync!;

  static bool feito(Map<String, dynamic> x) =>
      x['status'] == 'feito' || x['status'] == 'nao_conforme' || x['status'] == 'nao_se_aplica';

  /// Itens do checklist da OS (sem os que saíram do plano), na ordem.
  static List<Map<String, dynamic>> daOs(Object? osId) {
    final lista = _banco
        .todos('plano_execucoes')
        .where((x) => x['os_id'] == osId && x['status'] != 'cancelada')
        .toList()
      ..sort((a, b) {
        final o = ((a['ordem'] ?? 0) as num).compareTo((b['ordem'] ?? 0) as num);
        return o != 0 ? o : '${a['descricao']}'.compareTo('${b['descricao']}');
      });
    return lista;
  }

  static bool temChecklist(Object? osId) => _banco.todos('plano_execucoes').any((x) => x['os_id'] == osId);

  /// Itens agrupados: chave = id do aparelho, ou '' para as atividades gerais.
  static Map<String, List<Map<String, dynamic>>> porAparelho(Object? osId) {
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final x in daOs(osId)) {
      grupos.putIfAbsent('${x['equipamento_id'] ?? ''}', () => []).add(x);
    }
    return grupos;
  }

  static AndamentoChecklist andamento(Object? osId) {
    final itens = daOs(osId);
    final unidades = <String, List<Map<String, dynamic>>>{};
    for (final x in itens) {
      unidades.putIfAbsent('${x['unidade_id'] ?? x['equipamento_id'] ?? 'g:${x['plano_atividade_id']}'}', () => []).add(x);
    }
    final os = _banco.um('ordens_servico', osId);
    return AndamentoChecklist(
      total: unidades.length,
      prontas: unidades.values.where((l) => l.every(feito)).length,
      naoConformes: unidades.values.where((l) => l.any((x) => x['status'] == 'nao_conforme')).length,
      prazo: os?['plano_janela_fim'] as String? ?? (itens.isEmpty ? null : '${itens.first['prazo']}'),
    );
  }

  /// O ciclo deste aparelho já fechou neste lote (a plataforma criou a OS dele).
  static bool cicloFechado(List<Map<String, dynamic>> itens) =>
      itens.isNotEmpty && itens.every(feito) && itens.any((x) => x['ciclo_os_id'] != null);

  /// Vencimento do aparelho (o menor prazo dos itens dele).
  static String? vencimento(List<Map<String, dynamic>> itens) {
    final prazos = [for (final x in itens) if (x['prazo'] != null) '${x['prazo']}']..sort();
    return prazos.isEmpty ? null : prazos.first;
  }

  /// Marca (ou desmarca, com resultado null) itens do checklist.
  /// [marcas]: execucao_id -> (resultado, observação, foto_id).
  static Future<void> marcar(Map<String, dynamic> atd, Map<String, (String?, String?, String?)> marcas) async {
    if (marcas.isEmpty) return;
    final agora = DateTime.now().toUtc().toIso8601String();
    // O aparelho em que algo foi marcado entra como identificado (lista) no
    // atendimento: o relatório mostra os aparelhos atendidos nesta visita.
    final aparelhos = <String>{
      for (final e in marcas.entries)
        if (e.value.$1 != null)
          if (_banco.um('plano_execucoes', e.key)?['equipamento_id'] case final Object id) '$id',
    };
    await _sync.registrar(
      'checklist_marcar',
      {
        'atendimento_id': atd['id'],
        'itens': [
          for (final e in marcas.entries)
            {
              'execucao_id': e.key,
              'resultado': e.value.$1,
              if (e.value.$2 != null && e.value.$2!.trim().isNotEmpty) 'observacao': e.value.$2!.trim(),
              'foto_id': ?e.value.$3,
            }
        ],
      },
      aplicarLocal: () async {
        final linhas = <Map<String, dynamic>>[];
        for (final e in marcas.entries) {
          final atual = _banco.um('plano_execucoes', e.key);
          if (atual == null || atual['status'] == 'cancelada' || atual['status'] == 'nao_feito') continue;
          final r = e.value.$1;
          linhas.add({
            ...atual,
            'status': r ?? 'pendente',
            'observacao': r == null ? null : (e.value.$2?.trim().isEmpty ?? true ? null : e.value.$2!.trim()),
            'atendimento_id': r == null ? null : atd['id'],
            'executado_por': r == null ? null : AcoesAtendimento.eu,
            'executado_em': r == null ? null : agora,
            'foto_id': r == null ? null : (e.value.$3 ?? atual['foto_id']),
            if (r == null) 'ciclo_os_id': null, // desmarcado: o ciclo reabre
          });
        }
        await _banco.gravar('plano_execucoes', linhas);
      },
    );
    for (final id in aparelhos) {
      final equip = _banco.um('equipamentos', id);
      if (equip != null && _banco.todos('atendimento_equipamentos')
          .every((a) => a['atendimento_id'] != atd['id'] || a['equipamento_id'] != id)) {
        await AcoesAtendimento.identificarEquipamento(atd, equip, leitura: 'lista');
      }
    }
  }
}
