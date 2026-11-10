import 'package:supabase_flutter/supabase_flutter.dart';

import 'acoes_os.dart';
import 'acoes_parte.dart';
import 'banco_local.dart';
import 'consultas.dart';
import 'estado.dart';
import 'filtro_aparelhos.dart';
import 'formatos.dart';
import 'sincronizacao.dart';

/// Guia 108: uma OS em aberto que tem o aparelho (no celular) e onde ela está.
class OsDoAparelho {
  const OsDoAparelho(
      {required this.os, required this.onde, this.agendamento, this.item, this.parte, this.equipe, this.lider});

  final Map<String, dynamic> os;
  final Map<String, dynamic>? agendamento;

  /// O serviço em aberto (partes_itens) numa parte minha; null = sem serviço no celular.
  final Map<String, dynamic>? item;
  final Map<String, dynamic>? parte;

  /// meu_dia (numa parte minha de hoje, aberta para o check-in) | agenda_hoje |
  /// outro_dia | dia_anterior | fila | suspensa | sem_agendamento | outra_parte
  /// (na agenda de outra equipe ou de outro dia que não está no celular)
  final String onde;

  /// Da consulta com internet (os_do_aparelho): a equipe e o líder da parte
  /// em que ela está (a parte não está no celular).
  final String? equipe;
  final String? lider;

  /// Veio da consulta com internet (está com outra equipe).
  bool get remota => equipe != null;

  bool get noMeuDia => onde == 'meu_dia';

  /// A data do serviço (ou a prevista), aaaa-mm-dd.
  String get data => '${item?['data'] ?? agendamento?['data_prevista'] ?? ''}';

  /// Para trazer para a parte de hoje (os_puxar, guia 80).
  OsAberta get comoOsAberta => OsAberta({
        'os_id': os['id'],
        'codigo': codigoOs(os),
        'tipo': os['tipo'],
        'problema': os['problema_relatado'],
        'local_id': os['local_id'],
        'agendamento_id': agendamento?['id'],
        'agendamento_status': agendamento?['status'],
        'parte_item_id': item?['id'],
        'parte_id': item?['parte_id'],
        'item_status': item?['status'],
        'data': item?['data'],
        if (equipe != null)
          'equipe': equipe
        else if (parte != null)
          'equipe': EstadoApp.instancia.banco!.nomeEquipe(parte!['equipe_id']),
        'onde': onde == 'meu_dia' ? 'agenda_hoje' : (onde == 'outra_parte' ? 'sem_agendamento' : onde),
      }, clienteId: '${os['cliente_id']}');

  /// Dá para usar o "Atender agora"? (null = dá; senão, o motivo).
  String? get impedimento {
    if (noMeuDia) return null;
    if (onde == 'outra_parte') return 'Está na agenda de outra equipe ou de outro dia: fale com o escritório.';
    // Guia 113: no modo simples, sem parte hoje, o "Atender agora" abre o dia.
    if (AcoesOs.semParteHoje case final motivo?) return motivo;
    return comoOsAberta.impedimento;
  }
}

/// Ler a etiqueta fora da OS (guia 108): acha o aparelho e as OS em aberto
/// que o têm, tudo no banco do celular (sem internet).
class AcoesEtiqueta {
  AcoesEtiqueta._();

  static BancoLocal get _banco => EstadoApp.instancia.banco!;
  static Sincronizador get _sync => EstadoApp.instancia.sync!;

  static const _agendamentosAbertos = {'pendente', 'programado', 'em_andamento', 'suspenso'};

  /// Os aparelhos da etiqueta lida (QR, link, código ou código de barras).
  static List<Map<String, dynamic>> aparelhos(String lido) => aparelhosDaEtiqueta(_banco.todos('equipamentos'), lido);

  /// As OS em aberto com este aparelho que o celular conhece (na OS ou no
  /// checklist do plano): as da minha parte e as da fila do escritório; as do
  /// meu dia primeiro, depois pela data.
  static List<OsDoAparelho> osAbertas(Object? equipamentoId) {
    final ids = <String>{
      for (final l in _banco.todos('os_equipamentos'))
        if (l['equipamento_id'] == equipamentoId && l['excluido_em'] == null) '${l['os_id']}',
      for (final x in _banco.todos('plano_execucoes'))
        if (x['equipamento_id'] == equipamentoId && x['status'] != 'cancelada') '${x['os_id']}',
    };
    final hoje = _sync.hoje;
    final minhasDeHoje = {for (final p in AcoesOs.partesParaAtender()) '${p['id']}'};
    final lista = <OsDoAparelho>[];
    for (final id in ids) {
      final os = _banco.um('ordens_servico', id);
      if (os == null || os['status'] == 'concluida' || os['status'] == 'cancelada') continue;
      final ags = _banco
          .todos('agendamentos')
          .where((a) => a['os_id'] == id && _agendamentosAbertos.contains(a['status']))
          .toList();
      final agIds = {for (final a in ags) a['id']};
      final todosOsItens = _banco.todos('partes_itens').where((i) => agIds.contains(i['agendamento_id'])).toList();
      final abertos = todosOsItens.where((i) => AcoesParte.statusAbertos.contains(i['status'])).toList()
        ..sort((a, b) {
          final ma = minhasDeHoje.contains('${a['parte_id']}') ? 0 : 1;
          final mb = minhasDeHoje.contains('${b['parte_id']}') ? 0 : 1;
          if (ma != mb) return ma.compareTo(mb);
          return _distancia('${a['data']}', hoje).compareTo(_distancia('${b['data']}', hoje));
        });
      final item = abertos.firstOrNull;
      if (item != null) {
        final data = '${item['data']}';
        lista.add(OsDoAparelho(
          os: os,
          agendamento: _banco.agendamentoDo(item),
          item: item,
          parte: _banco.um('partes_diarias', item['parte_id']),
          onde: minhasDeHoje.contains('${item['parte_id']}')
              ? 'meu_dia'
              : data == hoje
                  ? 'agenda_hoje'
                  : data.compareTo(hoje) > 0
                      ? 'outro_dia'
                      : 'dia_anterior',
        ));
        continue;
      }
      // Sem serviço em aberto no celular: o agendamento sem serviço nenhum
      // (na fila ou suspenso) ou o que está numa parte que não desceu.
      // (o serviço retirado da minha parte ou não realizado não prende o agendamento)
      final usados = {
        for (final i in todosOsItens)
          if (i['status'] != 'removido' && i['status'] != 'nao_realizado') i['agendamento_id'],
      };
      final semServico = ags.where((a) => !usados.contains(a['id'])).toList();
      final fila = semServico.where((a) => a['status'] == 'pendente' || a['status'] == 'suspenso').firstOrNull;
      if (fila != null) {
        lista.add(OsDoAparelho(os: os, agendamento: fila, onde: fila['status'] == 'pendente' ? 'fila' : 'suspensa'));
      } else if (semServico.isNotEmpty) {
        lista.add(OsDoAparelho(os: os, agendamento: semServico.first, onde: 'outra_parte'));
      }
    }
    // As OS que estão só na fila do escritório (descem para o Ler etiqueta; a
    // que já está no dia do celular vale a de lá).
    for (final f in _banco.todos('os_fila')) {
      if (_banco.um('ordens_servico', f['id']) != null) continue;
      final aparelhos = (f['equipamentos'] as List?) ?? const [];
      if (!aparelhos.any((x) => '$x' == '$equipamentoId')) continue;
      lista.add(OsDoAparelho(
        os: f,
        agendamento: {
          'id': f['agendamento_id'],
          'os_id': f['id'],
          'status': f['agendamento_status'] ?? 'pendente',
          'tipo': f['agendamento_tipo'],
          'data_prevista': f['data_prevista'],
        },
        onde: 'fila',
      ));
    }
    _ordenar(lista, hoje);
    return lista;
  }

  static void _ordenar(List<OsDoAparelho> lista, String hoje) => lista.sort((a, b) {
        if (a.noMeuDia != b.noMeuDia) return a.noMeuDia ? -1 : 1;
        final d = _distancia(a.data, hoje).compareTo(_distancia(b.data, hoje));
        return d != 0 ? d : compararCodigo(a.os['codigo'], b.os['codigo']);
      });

  /// Com internet (os_do_aparelho): as OS em aberto do aparelho que estão
  /// com outras equipes (ou em partes que não estão no celular). null = sem
  /// internet (ou a plataforma não respondeu).
  static Future<List<OsDoAparelho>?> osDeOutrasEquipes(Object? equipamentoId) async {
    try {
      final r = await Supabase.instance.client.rpc('os_do_aparelho', params: {
        'p': {'dispositivo_id': EstadoApp.instancia.conta!.dispositivoId, 'equipamento_id': '$equipamentoId'},
      }).timeout(const Duration(seconds: 10));
      if (r is! Map || r['os'] is! List) return null;
      return [
        for (final x in (r['os'] as List).whereType<Map>())
          OsDoAparelho(
            os: {
              'id': x['os_id'],
              'codigo': x['codigo'],
              'tipo': x['tipo'],
              'status': x['status'],
              'cliente_id': x['cliente_id'],
              'local_id': x['local_id'],
              'problema_relatado': x['problema'],
            },
            agendamento: x['agendamento_id'] == null
                ? null
                : {
                    'id': x['agendamento_id'],
                    'os_id': x['os_id'],
                    'status': x['agendamento_status'],
                    'data_prevista': x['data_prevista'],
                  },
            item: x['parte_item_id'] == null
                ? null
                : {'id': x['parte_item_id'], 'parte_id': x['parte_id'], 'status': x['item_status'], 'data': x['data']},
            onde: '${x['onde'] ?? 'sem_agendamento'}',
            equipe: '${x['equipe'] ?? ''}',
            lider: x['lider'] == null ? null : '${x['lider']}',
          ),
      ];
    } catch (_) {
      return null;
    }
  }

  /// O que o celular sabe mais o que veio com internet: a OS que o celular não
  /// tem (ou só sabe que está em outra parte) entra com a equipe e o líder.
  static List<OsDoAparelho> juntar(List<OsDoAparelho> locais, List<OsDoAparelho>? remotas) {
    if (remotas == null) return locais;
    final porId = {for (final r in remotas) '${r.os['id']}': r};
    final lista = [
      for (final l in locais) (l.onde == 'outra_parte' ? porId['${l.os['id']}'] : null) ?? l,
    ];
    final ja = {for (final l in lista) '${l.os['id']}'};
    lista.addAll(remotas.where((r) => !ja.contains('${r.os['id']}')));
    _ordenar(lista, _sync.hoje);
    return lista;
  }

  /// Dias entre a data e hoje (sem data: no fim).
  static int _distancia(String data, String hoje) {
    final d = DateTime.tryParse(data), h = DateTime.tryParse(hoje);
    if (d == null || h == null) return 1 << 20;
    return d.difference(h).inDays.abs();
  }

  /// O último serviço neste aparelho que o celular conhece: (quando, o quê),
  /// ou null. Só o que desceu com a parte (ontem a depois de amanhã).
  static (String, String)? ultimoServico(Object? equipamentoId) {
    final vistos = <(String, String)>[];
    for (final atd in _banco.todos('atendimentos')) {
      if (atd['status'] != 'concluido') continue;
      final nele = _banco.identificacao(atd['id'], equipamentoId) != null ||
          _banco.todos('os_equipamentos').any((l) => l['os_id'] == atd['os_id'] && l['equipamento_id'] == equipamentoId);
      if (!nele) continue;
      final os = _banco.um('ordens_servico', atd['os_id']);
      final quando = '${atd['concluido_em'] ?? atd['iniciado_em'] ?? ''}';
      if (quando.isEmpty) continue;
      vistos.add((quando, [codigoOs(os), tiposOs[os?['tipo']] ?? ''].where((x) => x.isNotEmpty).join(' · ')));
    }
    for (final x in _banco.todos('plano_execucoes')) {
      if (x['equipamento_id'] != equipamentoId || x['executado_em'] == null) continue;
      final os = _banco.um('ordens_servico', x['os_id']);
      vistos.add(('${x['executado_em']}', 'Checklist da preventiva ${codigoOs(os)}'.trim()));
    }
    if (vistos.isEmpty) return null;
    vistos.sort((a, b) => b.$1.compareTo(a.$1));
    return vistos.first;
  }

  /// A próxima preventiva do aparelho no celular: o menor prazo dos itens
  /// ainda pendentes do checklist do plano (aaaa-mm-dd), ou null.
  static String? proximaPreventiva(Object? equipamentoId) {
    final prazos = [
      for (final x in _banco.todos('plano_execucoes'))
        if (x['equipamento_id'] == equipamentoId && x['status'] == 'pendente' && x['prazo'] != null) '${x['prazo']}',
    ]..sort();
    return prazos.firstOrNull;
  }
}
