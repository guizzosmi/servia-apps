import 'dart:io';

import 'package:uuid/uuid.dart';

import 'acoes_atendimento.dart';
import 'acoes_cadastro.dart';
import 'acoes_orcamento.dart';
import 'banco_local.dart';
import 'consultas.dart';
import 'estado.dart';
import 'sincronizacao.dart';

/// Os campos do relato do atendimento que a IA escreve.
const camposDoRelato = {
  'problema_identificado': 'Problema identificado',
  'causa': 'Causa',
  'solucao': 'Solução',
  'observacoes': 'Observações',
};

/// Uma peça (ou a mão de obra) na revisão: o que a IA entendeu e o que o
/// técnico decidiu. [escolha]: id do produto do catálogo, [livre] (texto
/// falado, sem catálogo) ou [nao] (não incluir).
class PecaRevisada {
  PecaRevisada({
    required this.falado,
    required this.quantidadeIa,
    required this.unidade,
    required this.candidatos,
    required this.escolhaIa,
  })  : quantidade = quantidadeIa,
        escolha = escolhaIa;

  static const livre = '_livre';
  static const nao = '_nao';

  final String falado;
  final num quantidadeIa;
  final String unidade;
  final List<Map<String, dynamic>> candidatos;

  /// O que a revisão propõe sem o técnico mexer.
  final String escolhaIa;
  num quantidade;
  String escolha;

  bool get incluida => escolha != nao && quantidade > 0;
  bool get igual => escolha == escolhaIa && quantidade == quantidadeIa;

  Map<String, dynamic> paraRevisao(String? itemId) => {
        'falado': falado,
        'quantidade_ia': quantidadeIa,
        'quantidade': quantidade,
        'escolha_ia': escolhaIa,
        'escolha': escolha,
        'incluida': incluida,
        'igual': igual,
        if (itemId != null) 'item_id': itemId,
      };
}

/// O que o técnico decidiu na revisão de um relato.
class DecisaoRevisao {
  DecisaoRevisao({
    required this.camposIa,
    required this.camposFinal,
    required this.propostaEquipamento,
    this.equipamentoIaId,
    this.equipamentoId,
    this.equipamentoNovo,
    required this.pecas,
    this.maoDeObra,
    this.medicoes = const [],
    this.fluido,
  });

  final Map<String, String> camposIa;
  final Map<String, String> camposFinal;

  /// identificado | sugerido | escolher | confirmar | cadastrar
  final String propostaEquipamento;
  final String? equipamentoIaId;
  final String? equipamentoId;
  final EquipamentoNovo? equipamentoNovo;
  final List<PecaRevisada> pecas;
  final PecaRevisada? maoDeObra;
  final List<MedicaoRevisada> medicoes;
  final FluidoRevisado? fluido;
}

/// Uma medição falada na revisão: a medição do cadastro (do tipo do
/// equipamento) e o valor. [modeloId] null = não registrar.
class MedicaoRevisada {
  MedicaoRevisada({required this.falado, required this.valorIa, required this.unidadeFalada}) : valor = valorIa;

  final String falado;
  final num? valorIa;
  final String unidadeFalada;

  /// A medição do cadastro que a revisão propôs (muda com o equipamento).
  String? modeloIa;
  String? modeloId;
  num? valor;

  bool get incluida => modeloId != null && valor != null;
  bool get igual => modeloId == modeloIa && valor == valorIa;

  Map<String, dynamic> paraRevisao(String? medicaoId) => {
        'falado': falado,
        'valor_ia': valorIa,
        'valor': valor,
        'modelo_ia': modeloIa,
        'modelo': modeloId,
        'incluida': incluida,
        'igual': igual,
        if (medicaoId != null) 'medicao_id': medicaoId,
      };
}

/// O fluido falado (carga ou recolhimento) na revisão.
class FluidoRevisado {
  FluidoRevisado({required this.tipoIa, required this.adicionadoIa, required this.recolhidoIa})
      : tipo = tipoIa,
        adicionado = adicionadoIa,
        recolhido = recolhidoIa;

  final String tipoIa;
  final num adicionadoIa;
  final num recolhidoIa;
  String tipo;
  num adicionado;
  num recolhido;
  bool registrar = true;

  bool get incluido => registrar && tipo.trim().isNotEmpty && (adicionado > 0 || recolhido > 0);
  bool get igual => registrar && tipo == tipoIa && adicionado == adicionadoIa && recolhido == recolhidoIa;
}

/// Texto simples para comparar nomes falados com o cadastro.
String _simples(Object? t) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const para = 'aaaaaeeeeiiiiooooouuuuc';
  final b = StringBuffer();
  for (final c in '${t ?? ''}'.toLowerCase().split('')) {
    final i = de.indexOf(c);
    b.write(i >= 0 ? para[i] : c);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// Unidade falada -> a do cadastro (psi, bar, c, a, v, kg).
String? _unidade(String u) {
  final s = _simples(u);
  if (s.isEmpty) return null;
  if (s.startsWith('psi') || s.startsWith('libra')) return 'psi';
  if (s.startsWith('bar')) return 'bar';
  if (s == 'c' || s.contains('grau') || s.contains('celsius')) return 'c';
  if (s == 'a' || s.startsWith('amp')) return 'a';
  if (s == 'v' || s.startsWith('volt')) return 'v';
  if (s == 'kg' || s.startsWith('quilo')) return 'kg';
  return null;
}

/// A medição do cadastro que corresponde à falada (pelas palavras do nome e
/// do código; unidade diferente não serve). null = nenhuma.
String? medicaoDoCadastro(List<Map<String, dynamic>> modelos, String falado, String unidade) {
  const fora = {'de', 'do', 'da', 'no', 'na', 'e', 'o', 'a'};
  final palavras = _simples(falado).split(' ').where((p) => p.isNotEmpty && !fora.contains(p)).toSet();
  final u = _unidade(unidade);
  String? melhor;
  var nota = 0.0;
  var empate = false;
  for (final m in modelos) {
    if (m['tipo_valor'] != null && m['tipo_valor'] != 'numero') continue;
    if (u != null && m['unidade'] != null && m['unidade'] != 'outro' && m['unidade'] != u) continue;
    final dele = _simples('${m['nome']} ${'${m['codigo'] ?? ''}'.replaceAll('_', ' ')}')
        .split(' ')
        .where((p) => p.isNotEmpty && !fora.contains(p))
        .toSet();
    if (dele.isEmpty) continue;
    final n = dele.intersection(palavras).length / dele.length;
    if (n > nota) {
      nota = n;
      melhor = '${m['id']}';
      empate = false;
    } else if (n == nota && n > 0) {
      empate = true; // ("pressão" serve para sucção e descarga: o técnico escolhe)
    }
  }
  return nota >= 0.5 && !empate ? melhor : null;
}

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
    this.abertura,
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

  /// OS falada: a proposta (cliente, local, tipo, o que fazer, equipamento).
  final Map<String, dynamic>? abertura;
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
    Map<String, dynamic>? atd, {
    required String audioId,
    required String arquivoLocal,
    required Duration duracao,
    bool abertura = false,
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
      if (abertura) 'finalidade': 'abrir_os' else 'atendimento_id': atd!['id'],
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

  /// OS falada (guia 17b): o áudio sobe sem OS e a IA propõe cliente, local,
  /// tipo, o que fazer e o equipamento. Ver [osFaladas].
  static Future<void> registrarAbertura({
    required String audioId,
    required String arquivoLocal,
    required Duration duracao,
  }) =>
      registrar(null, audioId: audioId, arquivoLocal: arquivoLocal, duracao: duracao, abertura: true);

  /// A OS foi aberta a partir do áudio: liga um ao outro. [comoRelato]: o
  /// áudio também é o relato do serviço (o técnico revisa no atendimento).
  static Future<void> vincular(String audioId, String osId, {required bool comoRelato}) => _sync.registrar(
        'relato_vincular',
        {'audio_id': audioId, 'os_id': osId, 'como_relato': comoRelato},
        aplicarLocal: () => _banco.alterar('audios', audioId, {
          'os_id': osId,
          if (comoRelato) 'finalidade': 'relato' else 'status': 'revisado',
        }),
      );

  /// As OS faladas e ainda não abertas (no aparelho ou já com a proposta).
  static List<RelatoAudio> osFaladas() {
    // Já usadas numa OS (a ligação ainda na fila): não aparecem mais.
    final vinculando = {
      for (final o in _banco.fila)
        if (o.tipo == 'relato_vincular') '${o.dados['audio_id']}',
    };
    final naFila = <String, RelatoAudio>{};
    for (final o in _banco.fila) {
      if (o.tipo != 'relato_gravado' || o.dados['finalidade'] != 'abrir_os') continue;
      if (vinculando.contains('${o.dados['audio_id']}')) continue;
      final id = '${o.dados['audio_id']}';
      naFila[id] = RelatoAudio(
        id: id,
        status: o.situacao == 'recusada' ? 'recusado' : 'aguardando_envio',
        gravadoEm: '${o.dados['gravado_em'] ?? o.em}',
        duracaoS: num.tryParse('${o.dados['duracao_s']}'),
        erro: o.erro,
        opId: o.opId,
      );
    }
    final lista = [
      ...naFila.values,
      for (final a in _banco.todos('audios'))
        if (a['finalidade'] == 'abrir_os' &&
            a['os_id'] == null &&
            !const ['revisado', 'descartado'].contains(a['status']) &&
            !naFila.containsKey('${a['id']}') &&
            !vinculando.contains('${a['id']}'))
          _doBanco(a),
    ];
    lista.sort((a, b) => _quando(b).compareTo(_quando(a)));
    return lista;
  }

  /// Um relato (ou OS falada) pelo id: o do banco ou o que ainda está na fila.
  static RelatoAudio? um(String audioId) {
    final a = _banco.um('audios', audioId);
    if (a != null && !_banco.fila.any((o) => o.tipo == 'relato_gravado' && o.dados['audio_id'] == audioId)) {
      return _doBanco(a);
    }
    return osFaladas().where((r) => r.id == audioId).firstOrNull;
  }

  static RelatoAudio _doBanco(Map<String, dynamic> a) => RelatoAudio(
        id: '${a['id']}',
        status: '${a['status']}',
        gravadoEm: '${a['gravado_em']}',
        duracaoS: num.tryParse('${a['duracao_s']}'),
        gravadoPor: a['gravado_por'] as String?,
        erro: a['erro'] as String?,
        resultado: (a['resultado'] as Map?)?.cast<String, dynamic>(),
        transcricao: a['transcricao'] as String?,
        abertura: (a['abertura'] as Map?)?.cast<String, dynamic>(),
      );

  // (a hora da plataforma vem com fuso; a do aparelho, em UTC)
  static DateTime _quando(RelatoAudio r) => DateTime.tryParse(r.gravadoEm)?.toUtc() ?? DateTime(2000);

  /// Pede para a IA processar de novo (relato com erro ou parado).
  static Future<void> processarDeNovo(String audioId) async {
    await _banco.gravarMeta('relato_processar:$audioId', '1', avisar: true);
    await _sync.sincronizar();
  }

  /// Leva o que o técnico aceitou para o atendimento, com as operações de
  /// sempre (relato, equipamento, itens) e, por último, "relato_revisar", que
  /// fecha o relato e guarda o que mudou em relação à IA.
  static Future<void> aplicarRevisao(Map<String, dynamic> atd, String audioId, DecisaoRevisao d) async {
    final atual = _banco.um('atendimentos', atd['id']) ?? atd;

    // 1. Texto: campo vazio recebe o da IA; campo já escrito ganha o novo embaixo.
    final campos = <String, dynamic>{};
    for (final e in d.camposFinal.entries) {
      final novo = e.value.trim();
      final ja = '${atual[e.key] ?? ''}'.trim();
      if (novo.isEmpty || ja.contains(novo)) continue;
      campos[e.key] = ja.isEmpty ? novo : '$ja\n$novo';
    }
    if (campos.isNotEmpty) await AcoesAtendimento.salvarRelato('${atd['id']}', campos);

    // 2. Equipamento: o cadastrado na hora ou o escolhido.
    if (d.equipamentoNovo != null) {
      await AcoesCadastro.equipamentoNoAtendimento(atd, d.equipamentoNovo!);
    } else if (d.equipamentoId != null && _banco.identificacao(atd['id'], d.equipamentoId) == null) {
      await AcoesAtendimento.identificarEquipamento(
          atd, _banco.um('equipamentos', d.equipamentoId) ?? {'id': d.equipamentoId},
          leitura: 'ia');
    }

    // 3. Peças e mão de obra.
    final ids = <String>[];
    final pecas = <Map<String, dynamic>>[];
    for (final p in [...d.pecas, ?d.maoDeObra]) {
      String? itemId;
      if (p.incluida) {
        itemId = AcoesAtendimento.novoId();
        final livre = p.escolha == PecaRevisada.livre;
        Map<String, dynamic>? produto;
        if (!livre) {
          final cand = p.candidatos.where((c) => c['produto_id'] == p.escolha).firstOrNull;
          produto = _banco.um('produtos', p.escolha) ??
              {
                'id': p.escolha,
                'descricao': cand?['descricao'] ?? p.falado,
                'tipo': cand?['tipo'] ?? 'produto',
                'unidade': cand?['unidade'] ?? p.unidade,
              };
        }
        final ehMao = identical(p, d.maoDeObra);
        await AcoesAtendimento.salvarItem(atd,
            produto: produto,
            descricao: livre ? p.falado : null,
            tipo: livre && ehMao ? 'servico' : null,
            unidade: livre ? p.unidade : null,
            quantidade: p.quantidade,
            itemId: itemId);
        ids.add(itemId);
      }
      pecas.add(p.paraRevisao(itemId));
    }

    // 4. Medições e fluido, no equipamento escolhido (ou cadastrado agora).
    final equipId = d.equipamentoNovo?.id ?? d.equipamentoId;
    final medIds = <String>{};
    final medicoes = <Map<String, dynamic>>[];
    String? fluidoId;
    final equip = equipId == null ? null : _banco.um('equipamentos', equipId) ?? {'id': equipId};
    for (final m in d.medicoes) {
      String? id;
      final modelo = m.modeloId == null ? null : _banco.um('modelos_medicao', m.modeloId);
      final idDela = equipId == null ? null : AcoesAtendimento.idMedicao(atd['id'], equipId, m.modeloId);
      // (duas faladas na mesma medição do cadastro: vale a primeira)
      if (equip != null && m.incluida && modelo != null && idDela != null && !medIds.contains(idDela)) {
        await AcoesAtendimento.salvarMedicao(atd, equip, modelo, numero: m.valor);
        id = idDela;
        medIds.add(idDela);
      }
      medicoes.add(m.paraRevisao(id));
    }
    final f = d.fluido;
    if (equip != null && f != null && f.incluido) {
      await AcoesAtendimento.salvarFluido(atd, equip,
          fluido: f.tipo.trim(), adicionadoKg: f.adicionado, recolhidoKg: f.recolhido);
      fluidoId = AcoesAtendimento.idFluido(atd['id'], equipId);
    }

    // 5. A revisão: o que foi aceito sem mudar (para medir a IA).
    var total = 0, iguais = 0;
    final campoRev = <String, dynamic>{};
    for (final e in d.camposIa.entries) {
      if (e.value.trim().isEmpty) continue;
      final igual = (d.camposFinal[e.key] ?? '').trim() == e.value.trim();
      total++;
      if (igual) iguais++;
      campoRev[e.key] = {'ia': e.value, 'final': d.camposFinal[e.key], 'igual': igual};
    }
    final eqIgual = d.equipamentoNovo == null && d.equipamentoId == d.equipamentoIaId;
    if (d.equipamentoIaId != null) {
      total++;
      if (eqIgual) iguais++;
    } else if (d.propostaEquipamento == 'cadastrar') {
      // A IA disse "cadastrar": acertou se o técnico cadastrou.
      total++;
      if (d.equipamentoNovo != null) iguais++;
    }
    for (final p in [...d.pecas, ?d.maoDeObra]) {
      if (p.quantidadeIa <= 0 && p.escolhaIa == PecaRevisada.nao) continue;
      total++;
      if (p.igual) iguais++;
    }
    // (sem equipamento, as medições e o fluido não foram registrados: não contam)
    if (equipId != null) {
      for (final m in d.medicoes) {
        total++;
        if (m.igual && m.incluida) iguais++;
      }
      if (d.fluido != null) {
        total++;
        if (d.fluido!.igual) iguais++;
      }
    }
    await _sync.registrar(
      'relato_revisar',
      {
        'audio_id': audioId,
        // (o relato que veio da abertura da OS fica neste atendimento)
        'atendimento_id': atd['id'],
        'itens_ids': ids,
        'medicoes_ids': medIds.toList(),
        'fluidos_ids': [?fluidoId],
        'revisao': {
          'versao': 1,
          'campos': campoRev,
          'equipamento': {
            'proposta': d.propostaEquipamento,
            'equipamento_ia_id': d.equipamentoIaId,
            'equipamento_id': d.equipamentoNovo?.id ?? d.equipamentoId,
            'cadastrado_na_revisao': d.equipamentoNovo != null,
            'igual': eqIgual,
          },
          'itens': pecas,
          'medicoes': medicoes,
          if (d.fluido != null)
            'fluido': {
              'tipo_ia': d.fluido!.tipoIa,
              'tipo': d.fluido!.tipo,
              'adicionado_kg': d.fluido!.adicionado,
              'recolhido_kg': d.fluido!.recolhido,
              'incluido': fluidoId != null,
              'igual': d.fluido!.igual,
            },
          'aceitos_sem_editar': iguais,
          'total': total,
        },
      },
      aplicarLocal: () => _banco.alterar('audios', audioId, {
        'status': 'revisado',
        // (o relato que veio da abertura fica neste atendimento, como na plataforma)
        if (_banco.um('audios', audioId)?['atendimento_id'] == null) 'atendimento_id': atd['id'],
      }),
    );
  }

  /// Descarta o relato (fica registrado na plataforma, mas sai da tela).
  static Future<void> descartar(String audioId) => _sync.registrar(
        'relato_revisar',
        {'audio_id': audioId, 'descartar': true},
        aplicarLocal: () => _banco.alterar('audios', audioId, {'status': 'descartado'}),
      );

  /// Este relato está esperando a IA neste aparelho?
  static bool aguardandoIa(String audioId) => _banco.meta('relato_processar:$audioId') != null;

  /// Os relatos do atendimento, do mais novo para o mais antigo.
  static List<RelatoAudio> doAtendimento(Map<String, dynamic> atd) {
    final atdId = atd['id'];
    // OS falada que virou o relato desta OS, ainda na fila (sem internet).
    final daAbertura = {
      for (final o in _banco.fila)
        if (o.tipo == 'relato_vincular' && o.dados['como_relato'] == true && o.dados['os_id'] == atd['os_id'])
          '${o.dados['audio_id']}',
    };
    final naFila = <String, RelatoAudio>{};
    for (final o in _banco.fila) {
      if (o.tipo != 'relato_gravado') continue;
      if (o.dados['atendimento_id'] != atdId && !daAbertura.contains('${o.dados['audio_id']}')) continue;
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
        // (o relato que veio da abertura da OS ainda não tem atendimento: vale o da OS)
        if ((a['atendimento_id'] == atdId ||
                (a['atendimento_id'] == null && a['os_id'] == atd['os_id'] && a['finalidade'] != 'abrir_os')) &&
            a['status'] != 'descartado' &&
            !naFila.containsKey('${a['id']}'))
          _doBanco(a),
    ];
    lista.sort((a, b) => _quando(b).compareTo(_quando(a)));
    return lista;
  }
}
