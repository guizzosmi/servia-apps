import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'acoes_atendimento.dart';
import 'arquivos.dart';
import 'banco_local.dart';
import 'consultas.dart';
import 'estado.dart';
import 'formatos.dart';
import 'resumo.dart';
import 'sincronizacao.dart';

/// Configuração da empresa que o app usa (baixada na sincronização).
class ConfigApp {
  const ConfigApp(this._d);
  final Map<String, dynamic> _d;

  /// gestor | gestor_lider | todos
  String get quemMonta => '${_d['orcamento_quem_monta'] ?? 'gestor_lider'}';
  num get descontoMaxPct => num.tryParse('${_d['orcamento_desconto_max_pct'] ?? 10}') ?? 10;
  int get validadeDias => int.tryParse('${_d['orcamento_validade_dias'] ?? 15}') ?? 15;

  /// Itens fora do catálogo: desligado | gestor (vai para o gestor) | liberado
  String get itensAvulsos => '${_d['orcamento_itens_avulsos'] ?? 'desligado'}';
  String? get termo {
    final t = '${_d['termo_aceite'] ?? ''}'.trim();
    return t.isEmpty ? null : t;
  }

  /// desligado | opcional | obrigatorio
  String get aceiteConclusao => '${_d['aceite_conclusao'] ?? 'opcional'}';

  /// Modelos de mensagem que a empresa mudou (o resto é o padrão).
  Map? get mensagens => _d['mensagens'] as Map?;
}

/// Texto padrão do termo (o mesmo do PDF da plataforma), quando a empresa
/// não configurou o dela.
const termoPadrao =
    'Ao aprovar este orçamento, o cliente autoriza a execução dos serviços e o fornecimento dos itens descritos, '
    'nos valores, prazos e condições acima. A aprovação pode ser feita por assinatura neste documento, pelo link '
    'enviado pela empresa ou por outro meio registrado por ela, e fica guardada com a data, o nome de quem aprovou '
    'e a identificação deste documento. Valores válidos até a data de validade indicada.';

const declaracaoConclusao =
    'Declaro que acompanhei o atendimento descrito acima e que o serviço foi realizado e entregue.';

/// Um item do orçamento montado no app: do catálogo ([produto]) ou fora
/// dele (descrição, tipo, unidade e preço digitados), conforme a empresa.
class ItemOrcamento {
  ItemOrcamento({
    required this.id,
    this.produto,
    required this.quantidade,
    String? descricao,
    String? tipo,
    String? unidade,
    num? preco,
  })  : _descricao = descricao,
        _tipo = tipo,
        _unidade = unidade,
        _preco = preco;

  final String id;
  final Map<String, dynamic>? produto; // null = fora do catálogo
  num quantidade;
  final String? _descricao;
  final String? _tipo;
  final String? _unidade;
  final num? _preco;

  bool get avulso => produto == null;
  String get descricao => '${produto?['descricao'] ?? _descricao ?? 'Item'}';
  String get tipo => '${produto?['tipo'] ?? _tipo ?? 'servico'}';
  String get unidade => '${produto?['unidade'] ?? _unidade ?? 'un'}';
  num get preco => produto != null ? num.tryParse('${produto!['preco_venda'] ?? 0}') ?? 0 : _preco ?? 0;
  num get bruto => centavos(quantidade * preco);
  num desconto(num pct) => centavos(bruto * pct / 100);
  num total(num pct) => centavos(bruto - desconto(pct));

  Map<String, dynamic> paraRascunho() => {
        'id': id,
        'quantidade': quantidade,
        if (produto != null) 'produto_id': produto!['id'],
        if (avulso) ...{'descricao': descricao, 'tipo': tipo, 'unidade': unidade, 'preco': preco},
      };

  /// Item guardado no rascunho (o do catálogo volta com o preço de agora).
  static ItemOrcamento? doRascunho(Map i, Map<String, dynamic>? Function(Object? id) produto) {
    final qtd = num.tryParse('${i['quantidade']}') ?? 1;
    if (i['produto_id'] != null) {
      final p = produto(i['produto_id']);
      return p == null ? null : ItemOrcamento(id: '${i['id']}', produto: p, quantidade: qtd);
    }
    return ItemOrcamento(
      id: '${i['id']}',
      quantidade: qtd,
      descricao: '${i['descricao'] ?? 'Item'}',
      tipo: '${i['tipo'] ?? 'servico'}',
      unidade: '${i['unidade'] ?? 'un'}',
      preco: num.tryParse('${i['preco'] ?? 0}') ?? 0,
    );
  }
}

/// O que o cliente decidiu na tela de assinatura.
class Decisao {
  const Decisao({required this.nome, this.documento, this.png, required this.decisao, this.motivo});

  final String nome;
  final String? documento;
  final Uint8List? png; // null na recusa
  final String decisao; // aprovado | reprovado | ciente
  final String? motivo;
}

/// Orçamento e assinatura no app. Como as outras ações: entra na fila,
/// muda o banco do celular na hora e sobe quando houver internet.
class AcoesOrcamento {
  AcoesOrcamento._();

  static EstadoApp get _estado => EstadoApp.instancia;
  static BancoLocal get _banco => _estado.banco!;
  static Sincronizador get _sync => _estado.sync!;

  static ConfigApp get config {
    try {
      return ConfigApp(jsonDecode(_banco.meta('config') ?? '{}') as Map<String, dynamic>);
    } catch (_) {
      return const ConfigApp({});
    }
  }

  static Map<String, dynamic> get empresa {
    try {
      return jsonDecode(_banco.meta('empresa') ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  /// A pessoa pode montar ou colher assinatura de orçamento neste atendimento?
  static bool podeOrcar(Map<String, dynamic> atd) {
    switch (config.quemMonta) {
      case 'todos':
        return true;
      case 'gestor_lider':
        final item = _banco.um('partes_itens', atd['parte_item_id']);
        final parte = _banco.um('partes_diarias', item?['parte_id']);
        return parte != null && parte['lider_colaborador_id'] == AcoesAtendimento.eu;
      default:
        return false;
    }
  }

  static String motivoSemPermissao() => config.quemMonta == 'gestor_lider'
      ? 'Só o líder da equipe monta orçamento pelo app (configuração da empresa).'
      : 'A empresa não liberou orçamento pelo app. Fale com o gestor.';

  /// Orçamentos da OS (os mais novos primeiro).
  static List<Map<String, dynamic>> daOs(Object? osId) =>
      _banco.todos('orcamentos').where((o) => o['os_id'] == osId && o['excluido_em'] == null).toList()
        ..sort((a, b) => '${b['criado_em']}'.compareTo('${a['criado_em']}'));

  /// O orçamento em aberto da OS (rascunho ou enviado), se houver.
  static Map<String, dynamic>? abertoDaOs(Object? osId) =>
      daOs(osId).where((o) => o['status'] == 'rascunho' || o['status'] == 'enviado').firstOrNull;

  static List<Map<String, dynamic>> itensDe(Object? orcamentoId) =>
      _banco.todos('orcamento_itens').where((i) => i['orcamento_id'] == orcamentoId).toList()
        ..sort((a, b) => ((a['ordem'] ?? 0) as num).compareTo((b['ordem'] ?? 0) as num));

  static Map<String, dynamic>? aceiteDe(String entidade, Object? id) {
    final lista = _banco.todos('aceites').where((a) => a['entidade'] == entidade && a['entidade_id'] == id).toList()
      ..sort((a, b) => '${b['criado_em']}'.compareTo('${a['criado_em']}'));
    return lista.firstOrNull;
  }

  static String codigo(Map<String, dynamic> o) =>
      o['codigo'] == null ? 'Orçamento novo' : '${o['codigo']} v${o['versao_orcamento'] ?? 1}';

  // ------------------------------------------------------------------
  // Rascunho do app (guardado no aparelho até ser registrado)
  // ------------------------------------------------------------------

  static String _chaveRascunho(Object? atdId) => 'orc_rascunho:$atdId';

  static Map<String, dynamic>? rascunho(Object? atdId) {
    final t = _banco.meta(_chaveRascunho(atdId));
    if (t == null) return null;
    try {
      return jsonDecode(t) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> guardarRascunho(Object? atdId, Map<String, dynamic>? dados) =>
      _banco.gravarMeta(_chaveRascunho(atdId), dados == null ? null : jsonEncode(dados));

  // ------------------------------------------------------------------
  // Arquivos da assinatura (PNG + resumo em PDF)
  // ------------------------------------------------------------------

  /// Guarda os arquivos no aparelho e devolve o que vai na operação.
  static Future<Map<String, dynamic>> _guardarArquivos(String aceiteId, Uint8List png, Uint8List pdf) async {
    final conta = _estado.conta!;
    final agora = DateTime.now();
    final pasta = await Arquivos.pastaAssinaturas();
    await pasta.create(recursive: true);
    final localPng = p.join(pasta.path, '$aceiteId-assinatura.png');
    final localPdf = p.join(pasta.path, '$aceiteId-resumo.pdf');
    await File(localPng).writeAsBytes(png, flush: true);
    await File(localPdf).writeAsBytes(pdf, flush: true);
    final base = '${conta.contaId}/${conta.empresaId}/${agora.year}/${agora.month.toString().padLeft(2, '0')}/$aceiteId';
    return {
      'assinatura_caminho': '$base-assinatura.png',
      'resumo_caminho': '$base-resumo.pdf',
      'resumo_sha256': sha256.convert(pdf).toString(),
      // Só para o app: sobem antes da operação (a plataforma ignora).
      'arquivos': [
        {'bucket': 'assinaturas', 'caminho': '$base-assinatura.png', 'local': localPng, 'tipo': 'image/png'},
        {'bucket': 'assinaturas', 'caminho': '$base-resumo.pdf', 'local': localPdf, 'tipo': 'application/pdf'},
      ],
    };
  }

  static String get nomeDoTecnico => _banco.nomeColaborador(AcoesAtendimento.eu);

  /// Monta o "aceite" da operação: gera o resumo em PDF (com a assinatura)
  /// e guarda os arquivos. Na recusa, só o nome e o motivo.
  static Future<(Map<String, dynamic>, Map<String, dynamic>?)> _aceite(
      String aceiteId, ConteudoResumo conteudo, Decisao d) async {
    final aceite = <String, dynamic>{
      'aceite_id': aceiteId,
      'nome': d.nome.trim(),
      if (d.documento != null && d.documento!.trim().isNotEmpty) 'documento_pessoa': d.documento!.trim(),
      if (d.motivo != null && d.motivo!.trim().isNotEmpty) 'motivo': d.motivo!.trim(),
    };
    if (d.png == null) return (aceite, null);
    final pdf = await ResumoPdf.gerar(
      conteudo,
      RegistroAssinatura(
        nome: d.nome.trim(),
        documento: d.documento,
        png: d.png,
        decisao: d.decisao,
        motivo: d.motivo,
        em: DateTime.now(),
        tecnico: nomeDoTecnico,
      ),
    );
    final arquivos = await _guardarArquivos(aceiteId, d.png!, pdf);
    final anexos = arquivos.remove('arquivos') as List;
    return ({...aceite, ...arquivos}, {'arquivos': anexos});
  }

  static Future<void> _gravarAceiteLocal(String id, String entidade, Object? entidadeId, Decisao d) =>
      _banco.gravar('aceites', [
        {
          'id': id,
          'entidade': entidade,
          'entidade_id': entidadeId,
          'forma': 'presencial',
          'decisao': d.decisao,
          'nome': d.nome.trim(),
          'criado_em': DateTime.now().toUtc().toIso8601String(),
        }
      ]);

  // ------------------------------------------------------------------
  // Orçamento montado no app
  // ------------------------------------------------------------------

  /// destino: 'gestor' (rascunho para o gestor) ou a decisão do cliente
  /// ('aprovado' com assinatura, 'reprovado').
  static Future<void> registrarMontado({
    required Map<String, dynamic> atd,
    required String orcamentoId,
    required String? contatoId,
    String? aprovadorNome,
    required String diagnostico,
    required List<ItemOrcamento> itens,
    required num descontoPct,
    required String destino,
    ConteudoResumo? conteudo,
    Decisao? decisao,
  }) async {
    final aceiteId = AcoesAtendimento.novoId();
    // Sem contato cadastrado: o nome que o técnico digitou.
    final nomeLivre = contatoId == null ? aprovadorNome?.trim() : null;
    final aprovador = nomeLivre == null || nomeLivre.isEmpty ? null : nomeLivre;
    Map<String, dynamic>? aceite;
    Map<String, dynamic> extra = const {};
    if (destino != 'gestor') {
      final (a, anexos) = await _aceite(aceiteId, conteudo!, decisao!);
      aceite = a;
      extra = anexos ?? const {};
    }
    final hoje = _sync.hoje;
    final linhas = [
      for (final (k, i) in itens.indexed)
        {
          'id': i.id,
          'orcamento_id': orcamentoId,
          'ordem': k + 1,
          'tipo': i.tipo,
          'produto_id': i.produto?['id'],
          'descricao': i.descricao,
          'quantidade': i.quantidade,
          'unidade': i.unidade,
          'preco_unitario': i.preco,
          'desconto': i.desconto(descontoPct),
          'total': i.total(descontoPct),
        }
    ];
    final total = linhas.fold<num>(0, (s, l) => s + (l['total'] as num));
    await _sync.registrar(
      'orcamento_app',
      {
        'orcamento_id': orcamentoId,
        'atendimento_id': atd['id'],
        'destino': destino,
        if (contatoId != null) 'contato_id': contatoId,
        if (aprovador != null) 'aprovador_nome': aprovador,
        'diagnostico': diagnostico,
        'itens': [
          for (final l in linhas)
            {
              'item_id': l['id'],
              if (l['produto_id'] != null) 'produto_id': l['produto_id'],
              // Fora do catálogo: o que o técnico digitou.
              if (l['produto_id'] == null) ...{'descricao': l['descricao'], 'tipo': l['tipo'], 'unidade': l['unidade']},
              'quantidade': l['quantidade'],
              'preco_unitario': l['preco_unitario'],
              'desconto': l['desconto'],
            }
        ],
        if (aceite != null) 'aceite': aceite,
        ...extra,
      },
      aplicarLocal: () async {
        await _banco.gravar('orcamentos', [
          {
            'id': orcamentoId,
            'os_id': atd['os_id'],
            'codigo': null,
            'versao_orcamento': 1,
            'status': destino == 'gestor' ? 'rascunho' : destino,
            'origem': 'app',
            'contato_id': contatoId,
            'diagnostico': diagnostico,
            if (aprovador != null) 'observacoes': 'Quem aprova pelo cliente: $aprovador',
            'total': total,
            'desconto': linhas.fold<num>(0, (s, l) => s + (l['desconto'] as num)),
            'validade_ate': somarDias(hoje, config.validadeDias),
            'criado_em': DateTime.now().toUtc().toIso8601String(),
          }
        ]);
        await _banco.gravar('orcamento_itens', linhas);
        if (decisao != null) await _gravarAceiteLocal(aceiteId, 'orcamento', orcamentoId, decisao);
        await guardarRascunho(atd['id'], null);
      },
    );
  }

  /// O cliente decide, no local, um orçamento que o gestor já enviou.
  static Future<void> registrarAssinatura({
    required Map<String, dynamic> atd,
    required Map<String, dynamic> orcamento,
    required ConteudoResumo conteudo,
    required Decisao decisao,
  }) async {
    final aceiteId = AcoesAtendimento.novoId();
    final (aceite, anexos) = await _aceite(aceiteId, conteudo, decisao);
    await _sync.registrar(
      'orcamento_assinar',
      {
        'orcamento_id': orcamento['id'],
        'atendimento_id': atd['id'],
        'decisao': decisao.decisao,
        'aceite': aceite,
        ...?anexos,
      },
      aplicarLocal: () async {
        await _banco.alterar('orcamentos', orcamento['id'], {'status': decisao.decisao});
        await _gravarAceiteLocal(aceiteId, 'orcamento', orcamento['id'], decisao);
      },
    );
  }

  // ------------------------------------------------------------------
  // Assinatura do cliente na conclusão do atendimento
  // ------------------------------------------------------------------

  static Future<void> registrarConclusao({
    required Map<String, dynamic> atd,
    required ConteudoResumo conteudo,
    required Decisao decisao,
  }) async {
    final aceiteId = AcoesAtendimento.novoId();
    final (aceite, anexos) = await _aceite(aceiteId, conteudo, decisao);
    await _sync.registrar(
      'aceite_conclusao',
      {
        ...aceite,
        'atendimento_id': atd['id'],
        ...?anexos,
      },
      aplicarLocal: () => _gravarAceiteLocal(aceiteId, 'os_conclusao', atd['id'], decisao),
    );
  }
}
