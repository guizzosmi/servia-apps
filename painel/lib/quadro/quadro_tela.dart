import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/status.dart';
import '../widgets/fila.dart';
import 'coluna.dart';
import 'dialogos.dart';
import 'log_do_dia.dart';
import 'modelo.dart';

/// Quadro da parte diária: fila à esquerda, uma coluna por equipe e o log
/// do dia à direita. Tudo ao vivo (Supabase Realtime).
class QuadroTela extends StatefulWidget {
  const QuadroTela({super.key, this.data});

  /// Data inicial (aaaa-mm-dd), vinda de /quadro?data=...
  final String? data;

  @override
  State<QuadroTela> createState() => _QuadroTelaState();
}

class _QuadroTelaState extends State<QuadroTela> implements AcoesQuadro {
  static const _selectItem = 'id, parte_id, agendamento_id, ordem, papel_equipe, status, designados, orientacoes, '
      'incluido_apos_publicacao, alterado_apos_publicacao, iniciado_em, concluido_em, '
      'resultado_motivo, resultado_observacao, agendamentos($selectFila)';

  late DateTime _dia;
  bool _carregando = true;
  String? _erro;

  List<Map<String, dynamic>> _equipes = [];
  Map<String, Map<String, dynamic>> _partePorEquipe = {};
  List<Map<String, dynamic>> _itens = []; // do dia, inclusive removidos (para o log)
  List<Map<String, dynamic>> _composicao = [];
  List<Map<String, dynamic>> _colaboradores = [];
  Map<String, String> _nomes = {};
  List<Map<String, dynamic>> _fila = [];
  List<Map<String, dynamic>> _eventos = [];

  /// parte_item_id -> check-ins abertos (quem está no serviço agora)
  Map<String, List<Map<String, dynamic>>> _noServico = {};

  // Filtros da fila
  final _busca = TextEditingController();
  String? _prioridade;
  String? _tipo;
  bool _ateODia = false;

  bool? _mostrarLog;
  bool _verFila = false; // celular: fila ou equipes (não cabem lado a lado)
  final _rolagem = ScrollController();

  // Ao vivo
  RealtimeChannel? _canal;
  bool _aoVivo = false;
  Timer? _espera;
  Timer? _relogio;
  DateTime _agora = DateTime.now();
  bool _arrastandoAgora = false;
  bool _recarregarDepois = false;
  int _geracao = 0;

  @override
  void initState() {
    super.initState();
    final d = DateTime.tryParse(widget.data ?? '');
    final hoje = DateTime.now();
    _dia = d ?? DateTime(hoje.year, hoje.month, hoje.day);
    _carregar();
    _escutar();
    _relogio = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _agora = DateTime.now());
    });
  }

  @override
  void dispose() {
    _espera?.cancel();
    _relogio?.cancel();
    final canal = _canal;
    if (canal != null) Supabase.instance.client.removeChannel(canal);
    _busca.dispose();
    _rolagem.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Dados
  // ------------------------------------------------------------------

  Future<void> _carregar() async {
    final geracao = ++_geracao;
    final db = Supabase.instance.client;
    final data = dataIso(_dia);
    final inicio = DateTime(_dia.year, _dia.month, _dia.day).toUtc().toIso8601String();
    final fim = DateTime(_dia.year, _dia.month, _dia.day + 1).toUtc().toIso8601String();
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await Future.wait<List<Map<String, dynamic>>>([
        db.from('equipes').select('id, nome, cor, ativa').isFilter('excluido_em', null).order('nome', ascending: true),
        db.from('partes_diarias').select().eq('data', data).isFilter('excluido_em', null),
        db.from('partes_itens').select(_selectItem).eq('data', data).isFilter('excluido_em', null)
            .order('ordem', ascending: true),
        db.from('partes_composicao')
            .select('id, parte_id, colaborador_id, papel, entrada_em, saida_em, origem')
            .eq('data', data)
            .isFilter('excluido_em', null)
            .order('entrada_em', ascending: true),
        db.from('colaboradores').select('id, nome, ativo').isFilter('excluido_em', null)
            .order('nome', ascending: true),
        carregarFila(),
        db.from('eventos_log')
            .select('id, entidade, entidade_id, acao, dados, ator_nome, criado_em')
            .inFilter('entidade', ['parte', 'parte_item'])
            .gte('criado_em', inicio)
            .lt('criado_em', fim)
            .order('criado_em', ascending: false)
            .limit(300),
        // Quem está em cada serviço agora (check-ins abertos).
        db.from('atendimento_participantes')
            .select('colaborador_id, entrada_em, atendimentos(parte_item_id)')
            .isFilter('saida_em', null)
            .isFilter('excluido_em', null),
      ]);
      if (!mounted || geracao != _geracao) return;
      setState(() {
        _equipes = r[0];
        _partePorEquipe = {for (final p in r[1]) p['equipe_id'] as String: p};
        _itens = r[2];
        _composicao = r[3];
        _colaboradores = r[4];
        _nomes = {for (final c in r[4]) c['id'] as String: (c['nome'] ?? '') as String};
        _fila = r[5];
        _eventos = r[6];
        _noServico = {};
        for (final pa in r[7]) {
          final item = (pa['atendimentos'] as Map?)?['parte_item_id'] as String?;
          if (item != null) _noServico.putIfAbsent(item, () => []).add(pa);
        }
      });
    } catch (e) {
      if (mounted && geracao == _geracao) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted && geracao == _geracao) setState(() => _carregando = false);
    }
  }

  /// Escuta as mudanças do banco (desta empresa) e recarrega o quadro.
  void _escutar() {
    final empresa = Sessao.atual?.empresaId;
    if (empresa == null) return;
    final filtro = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'empresa_id', value: empresa);
    var canal = Supabase.instance.client.channel('quadro-$empresa-${DateTime.now().millisecondsSinceEpoch}');
    for (final tabela in [
      'partes_diarias',
      'partes_itens',
      'partes_composicao',
      'agendamentos',
      'eventos_log',
      'atendimentos',
      'atendimento_participantes',
    ]) {
      canal = canal.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: tabela,
        filter: filtro,
        callback: (_) => _mudouNoBanco(),
      );
    }
    _canal = canal.subscribe((status, _) {
      if (!mounted) return;
      setState(() => _aoVivo = status == RealtimeSubscribeStatus.subscribed);
      // Voltou a conexão: pode ter perdido algo no meio.
      if (status == RealtimeSubscribeStatus.subscribed) _mudouNoBanco();
    });
  }

  /// Junta várias mudanças seguidas numa recarga só (e espera soltar o arrasto).
  void _mudouNoBanco() {
    if (!mounted) return;
    if (_arrastandoAgora) {
      _recarregarDepois = true;
      return;
    }
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _carregar();
    });
  }

  List<ColunaQuadro> get _colunas {
    final itensPorParte = <String, List<Map<String, dynamic>>>{};
    for (final i in _itens) {
      if (i['status'] == 'removido') continue;
      itensPorParte.putIfAbsent(i['parte_id'] as String, () => []).add(i);
    }
    final compPorParte = <String, List<Map<String, dynamic>>>{};
    for (final c in _composicao) {
      compPorParte.putIfAbsent(c['parte_id'] as String, () => []).add(c);
    }
    return [
      for (final e in _equipes)
        if (e['ativa'] == true || _partePorEquipe.containsKey(e['id'])) _coluna(e, itensPorParte, compPorParte),
    ];
  }

  ColunaQuadro _coluna(
    Map<String, dynamic> equipe,
    Map<String, List<Map<String, dynamic>>> itensPorParte,
    Map<String, List<Map<String, dynamic>>> compPorParte,
  ) {
    final parte = _partePorEquipe[equipe['id']];
    final itens = [
      for (final i in [...?itensPorParte[parte?['id']]])
        {...i, 'no_servico': _noServico[i['id']] ?? const <Map<String, dynamic>>[]},
    ]..sort((a, b) => ((a['ordem'] ?? 0) as int).compareTo((b['ordem'] ?? 0) as int));
    final comp = [...?compPorParte[parte?['id']]]
      ..sort((a, b) {
        if (a['papel'] != b['papel']) return a['papel'] == 'lider' ? -1 : 1;
        return nomeColaborador(a['colaborador_id'] as String?).compareTo(nomeColaborador(b['colaborador_id'] as String?));
      });
    return ColunaQuadro(equipe: equipe, parte: parte, itens: itens, composicao: comp);
  }

  List<Map<String, dynamic>> get _filaFiltrada {
    final b = _busca.text.trim().toLowerCase();
    final limite = dataIso(_dia);
    return _fila.where((a) {
      if (_prioridade != null && a['prioridade'] != _prioridade) return false;
      if (_tipo != null && a['tipo'] != _tipo) return false;
      if (_ateODia) {
        final d = a['data_prevista'] as String?;
        if (d != null && d.compareTo(limite) > 0) return false;
      }
      if (b.isNotEmpty && !textoDeBuscaFila(a).contains(b)) return false;
      return true;
    }).toList();
  }

  ContextoLog get _contextoLog => ContextoLog(
        equipePorParte: {for (final p in _partePorEquipe.values) p['id'] as String: p['equipe_id'] as String},
        partePorItem: {for (final i in _itens) i['id'] as String: i['parte_id'] as String},
        osPorItem: {
          for (final i in _itens)
            if (((i['agendamentos'] as Map?)?['ordens_servico'] as Map?)?['codigo'] case final String codigo)
              i['id'] as String: codigo,
        },
        equipes: {
          for (final e in _equipes)
            if (e['ativa'] == true || _partePorEquipe.containsKey(e['id'])) e['id'] as String: e,
        },
        nomeColaborador: nomeColaborador,
      );

  // ------------------------------------------------------------------
  // Ações (AcoesQuadro)
  // ------------------------------------------------------------------

  @override
  bool get podeEditar => Sessao.atual?.tem(Papel.gestor) ?? false;

  @override
  String nomeColaborador(String? id) => _nomes[id] ?? '?';

  @override
  void arrastando(bool sim) {
    _arrastandoAgora = sim;
    if (!sim && _recarregarDepois) {
      _recarregarDepois = false;
      _mudouNoBanco();
    }
  }

  void _aviso(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: erro ? Cores.erro : null,
      duration: Duration(seconds: erro ? 6 : 3),
    ));
  }

  /// Chama uma regra; mostra o erro (em português) e recarrega o quadro.
  Future<Map<String, dynamic>?> _executar(Future<Map<String, dynamic>> Function() acao, {String? sucesso}) async {
    try {
      final r = await acao();
      if (sucesso != null) _aviso(sucesso);
      return r;
    } catch (e) {
      _aviso(mensagemDeErro(e), erro: true);
      return null;
    } finally {
      if (mounted) _carregar();
    }
  }

  /// Garante que a equipe tem parte no dia (abre se preciso) e devolve o id.
  Future<String?> _garantirParte(ColunaQuadro coluna) async {
    if (coluna.parteId != null) return coluna.parteId;
    try {
      final r = await acaoParte({'acao': 'abrir_dia', 'data': dataIso(_dia), 'equipe_id': coluna.equipeId});
      _avisarJaAlocados(r);
      final criadas = (r['criadas'] as List?) ?? const [];
      if (criadas.isNotEmpty) return (criadas.first as Map)['parte_id'] as String;
      // Alguém abriu ao mesmo tempo: busca a que existe.
      final p = await Supabase.instance.client
          .from('partes_diarias')
          .select('id')
          .eq('equipe_id', coluna.equipeId)
          .eq('data', dataIso(_dia))
          .isFilter('excluido_em', null)
          .maybeSingle();
      return p?['id'] as String?;
    } catch (e) {
      _aviso(mensagemDeErro(e), erro: true);
      return null;
    }
  }

  void _avisarJaAlocados(Map<String, dynamic> r) {
    final fora = (r['ja_alocados'] as List?) ?? const [];
    if (fora.isEmpty) return;
    final nomes = fora.map((x) => '${(x as Map)['colaborador']}').join(', ');
    _aviso('Não copiado(s) para a equipe padrão, pois já estão em outra equipe neste dia: $nomes.');
  }

  String _statusDaParte(String parteId) =>
      (_partePorEquipe.values.firstWhere((p) => p['id'] == parteId, orElse: () => const {})['status'] ?? '')
          as String;

  @override
  Future<void> soltar(Arrasto a, ColunaQuadro destino, Map<String, dynamic>? itemAlvo) async {
    final alt = HardwareKeyboard.instance.isAltPressed;
    arrastando(false);
    if (a is ArrastoPessoa) {
      await _moverPessoa(a, destino);
      return;
    }
    final parteId = await _garantirParte(destino);
    if (parteId == null) return;
    final ordem = itemAlvo?['ordem'];
    final status = destino.parte == null ? 'rascunho' : destino.status;
    final acao = status == 'rascunho' ? 'programar' : 'encaixar';

    switch (a) {
      case ArrastoFila(:final ag):
        await _executar(() => acaoParte({
              'acao': acao,
              'parte_id': parteId,
              'agendamento_id': ag['id'],
              if (ordem != null) 'ordem': ordem,
            }));
      case ArrastoItem(:final item, :final id, parteId: final origem):
        if (origem == parteId) {
          if (alt || itemAlvo?['id'] == id) return;
          // Mesma equipe: só muda a ordem.
          final ids = destino.itens.map((i) => i['id'] as String).toList()..remove(id);
          final pos = itemAlvo == null ? ids.length : ids.indexOf(itemAlvo['id'] as String);
          ids.insert(pos < 0 ? ids.length : pos, id);
          await _executar(() => acaoParte({'acao': 'reordenar', 'parte_id': parteId, 'itens': ids}));
        } else if (alt) {
          // Alt + soltar: esta equipe vai de apoio no mesmo serviço.
          await _executar(
            () => acaoParte({
              'acao': acao,
              'parte_id': parteId,
              'agendamento_id': item['agendamento_id'],
              'papel_equipe': 'apoio',
              if (ordem != null) 'ordem': ordem,
            }),
            sucesso: '${destino.nome} vai de apoio neste serviço.',
          );
        } else {
          await _executar(() => acaoParte({
                'acao': 'mover',
                'parte_item_id': id,
                'destino_parte_id': parteId,
                if (ordem != null) 'ordem': ordem,
              }));
        }
      case ArrastoPessoa():
        break;
    }
  }

  Future<void> _moverPessoa(ArrastoPessoa a, ColunaQuadro destino) async {
    final parteId = await _garantirParte(destino);
    if (parteId == null || parteId == a.parteId) {
      if (mounted) _carregar();
      return;
    }
    await _executar(
      () => acaoParte({
        'acao': 'composicao',
        'movimento': 'sair',
        'parte_id': a.parteId,
        'colaborador_id': a.colaboradorId,
        'destino_parte_id': parteId,
      }),
      sucesso: _statusDaParte(a.parteId) == 'rascunho'
          ? '${a.nome} foi para a ${destino.nome}.'
          : '${a.nome} saiu e entrou na ${destino.nome} às ${horaDe(DateTime.now().toIso8601String())}.',
    );
  }

  /// Fila -> equipe sem arrastar (no celular é o único jeito; no computador é
  /// um atalho). Entra no fim da lista da equipe.
  Future<void> _mandarParaEquipe(Map<String, dynamic> ag) async {
    final os = '${(ag['ordens_servico'] as Map?)?['codigo'] ?? 'O serviço'}';
    final destino = await escolherEquipe(
      context,
      titulo: 'Mandar $os para qual equipe?',
      colunas: _colunas.where((c) => c.aceitaMudancas).toList(),
    );
    if (destino == null || !mounted) return;
    final parteId = await _garantirParte(destino);
    if (parteId == null) return;
    final rascunho = destino.parte == null || destino.rascunho;
    await _executar(
      () => acaoParte({
        'acao': rascunho ? 'programar' : 'encaixar',
        'parte_id': parteId,
        'agendamento_id': ag['id'],
      }),
      sucesso: rascunho ? '$os programada na ${destino.nome}.' : '$os encaixada na ${destino.nome}.',
    );
  }

  /// Soltar um serviço de volta na fila = tirar da parte.
  Future<void> _devolverParaFila(ArrastoItem a) async {
    arrastando(false);
    await _executar(() => acaoParte({'acao': 'remover', 'parte_item_id': a.id}),
        sucesso: 'Serviço voltou para a fila.');
  }

  @override
  Future<void> acaoEquipe(String acao, ColunaQuadro coluna) async {
    switch (acao) {
      case 'abrir':
        await _garantirParte(coluna);
        if (mounted) _carregar();
      case 'publicar':
        await _executar(() => acaoParte({'acao': 'publicar', 'parte_id': coluna.parteId}),
            sucesso: 'Parte da ${coluna.nome} publicada.');
      case 'encerrar':
        final r = await pedirEncerramento(context, coluna: coluna);
        if (r == null) return;
        await _executar(
            () => acaoParte({
                  'acao': 'encerrar',
                  'parte_id': coluna.parteId,
                  'motivos': r['motivos'],
                  'resumo_texto': r['resumo_texto'],
                }),
            sucesso: 'Dia da ${coluna.nome} encerrado.');
      case 'reabrir':
        await _executar(() => acaoParte({'acao': 'reabrir', 'parte_id': coluna.parteId}),
            sucesso: 'Parte reaberta.');
      case 'nova_os':
        await _novaOsNaEquipe(coluna);
      case 'incluir_pessoa':
        await _incluirPessoa(coluna);
    }
  }

  Future<void> _novaOsNaEquipe(ColunaQuadro coluna) async {
    final osId = await context.push<String>('/os/nova');
    if (osId == null || !mounted) return;
    try {
      final ag = await Supabase.instance.client
          .from('agendamentos')
          .select('id')
          .eq('os_id', osId)
          .eq('status', 'pendente')
          .isFilter('excluido_em', null)
          .order('criado_em', ascending: true)
          .limit(1)
          .maybeSingle();
      if (ag == null) {
        _aviso('A OS foi aberta, mas não há agendamento na fila para programar.');
        if (mounted) _carregar();
        return;
      }
      final parteId = await _garantirParte(coluna);
      if (parteId == null) return;
      final rascunho = coluna.parte == null || coluna.rascunho;
      await _executar(
        () => acaoParte({
          'acao': rascunho ? 'programar' : 'encaixar',
          'parte_id': parteId,
          'agendamento_id': ag['id'],
        }),
        sucesso: rascunho ? 'OS programada na ${coluna.nome}.' : 'OS encaixada na ${coluna.nome}.',
      );
    } catch (e) {
      _aviso(mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _incluirPessoa(ColunaQuadro coluna) async {
    final colunas = _colunas;
    final alocados = <String, ({String parteId, String equipe})>{};
    for (final c in colunas) {
      for (final p in c.presentes) {
        alocados[p['colaborador_id'] as String] = (parteId: c.parteId!, equipe: c.nome);
      }
    }
    final aqui = coluna.presentes.map((p) => p['colaborador_id']).toSet();
    final escolha = await escolherPessoa(
      context,
      equipe: coluna.nome,
      colaboradores: _colaboradores.where((c) => c['ativo'] == true && !aqui.contains(c['id'])).toList(),
      alocados: alocados,
    );
    if (escolha == null) return;
    final parteId = await _garantirParte(coluna);
    if (parteId == null) return;
    final nome = nomeColaborador(escolha.colaboradorId);
    if (escolha.deParteId != null && escolha.deParteId != parteId) {
      await _executar(
        () => acaoParte({
          'acao': 'composicao',
          'movimento': 'sair',
          'parte_id': escolha.deParteId,
          'colaborador_id': escolha.colaboradorId,
          'destino_parte_id': parteId,
        }),
        sucesso: '$nome veio para a ${coluna.nome}.',
      );
    } else if (escolha.deParteId == null) {
      await _executar(
        () => acaoParte({
          'acao': 'composicao',
          'movimento': 'entrar',
          'parte_id': parteId,
          'colaborador_id': escolha.colaboradorId,
        }),
        sucesso: '$nome entrou na ${coluna.nome}.',
      );
    } else if (mounted) {
      _carregar();
    }
  }

  @override
  Future<void> acaoItem(String acao, Map<String, dynamic> item, ColunaQuadro coluna) async {
    final ag = item['agendamentos'] as Map? ?? const {};
    final os = (ag['ordens_servico'] as Map?)?['codigo'] ?? '';
    if (acao == 'abrir_os') {
      await context.push('/os/${ag['os_id']}');
      if (mounted) _carregar();
      return;
    }
    if (acao.startsWith('status:')) {
      final novo = acao.substring(7);
      final p = <String, dynamic>{'acao': 'item_status', 'parte_item_id': item['id'], 'status': novo};
      if (novo == 'nao_realizado') {
        final r = await pedirNaoRealizado(context, 'Não realizado · $os');
        if (r == null) return;
        p['motivo'] = r.motivo;
        if (r.observacao.isNotEmpty) p['observacao'] = r.observacao;
      }
      await _executar(() => acaoParte(p));
      return;
    }
    switch (acao) {
      case 'designar':
        final r = await escolherDesignados(
          context,
          presentes: coluna.presentes,
          atuais: (item['designados'] as List? ?? const []).cast<String>(),
          nome: nomeColaborador,
        );
        if (r == null) return;
        await _executar(() => acaoParte({'acao': 'designar', 'parte_item_id': item['id'], 'designados': r}));
      case 'apoio':
        final outras = _colunas.where((c) => c.equipeId != coluna.equipeId && c.aceitaMudancas).toList();
        final destino = await escolherEquipe(context, titulo: 'Qual equipe vai de apoio em $os?', colunas: outras);
        if (destino == null) return;
        final parteId = await _garantirParte(destino);
        if (parteId == null) return;
        final rascunho = destino.parte == null || destino.rascunho;
        await _executar(
          () => acaoParte({
            'acao': rascunho ? 'programar' : 'encaixar',
            'parte_id': parteId,
            'agendamento_id': item['agendamento_id'],
            'papel_equipe': 'apoio',
          }),
          sucesso: '${destino.nome} vai de apoio em $os.',
        );
      case 'mover':
        final outras = _colunas.where((c) => c.equipeId != coluna.equipeId && c.aceitaMudancas).toList();
        final destino = await escolherEquipe(context, titulo: 'Mandar $os para qual equipe?', colunas: outras);
        if (destino == null) return;
        final parteId = await _garantirParte(destino);
        if (parteId == null) return;
        await _executar(
          () => acaoParte({'acao': 'mover', 'parte_item_id': item['id'], 'destino_parte_id': parteId}),
          sucesso: '$os foi para a ${destino.nome}.',
        );
      case 'subir' || 'descer':
        // Troca de lugar com o vizinho (no celular não dá para arrastar).
        final ids = coluna.itens.map((i) => i['id'] as String).toList();
        final de = ids.indexOf(item['id'] as String);
        final para = acao == 'subir' ? de - 1 : de + 1;
        if (de < 0 || para < 0 || para >= ids.length) return;
        ids[de] = ids[para];
        ids[para] = item['id'] as String;
        await _executar(() => acaoParte({'acao': 'reordenar', 'parte_id': coluna.parteId, 'itens': ids}));
      case 'remover':
        final obs = await confirmarComObservacao(
          context,
          titulo: 'Tirar $os da parte?',
          texto: 'O serviço volta para a fila de pendentes.',
          botao: 'Tirar da parte',
        );
        if (obs == null) return;
        await _executar(() => acaoParte({
              'acao': 'remover',
              'parte_item_id': item['id'],
              if (obs.isNotEmpty) 'observacao': obs,
            }));
    }
  }

  @override
  Future<void> acaoPessoa(String acao, Map<String, dynamic> comp, ColunaQuadro coluna) async {
    final nome = nomeColaborador(comp['colaborador_id'] as String?);
    switch (acao) {
      case 'lider':
        await _executar(
          () => acaoParte({'acao': 'lider', 'parte_id': coluna.parteId, 'colaborador_id': comp['colaborador_id']}),
          sucesso: '$nome agora é o líder da ${coluna.nome}.',
        );
      case 'sair':
        await _executar(
          () => acaoParte({
            'acao': 'composicao',
            'movimento': 'sair',
            'parte_id': coluna.parteId,
            'colaborador_id': comp['colaborador_id'],
          }),
          sucesso: '$nome saiu da ${coluna.nome}.',
        );
    }
  }

  Future<void> _abrirODia() async {
    await _executar(() async {
      final r = await acaoParte({'acao': 'abrir_dia', 'data': dataIso(_dia)});
      final n = ((r['criadas'] as List?) ?? const []).length;
      _aviso(n == 0 ? 'Todas as equipes já tinham parte neste dia.' : '$n parte(s) aberta(s) em rascunho.');
      _avisarJaAlocados(r);
      return r;
    });
  }

  Future<void> _publicarTodas(List<ColunaQuadro> colunas) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publicar todas?'),
        content: Text('Publica ${colunas.length} parte(s) em rascunho que têm serviços: '
            '${colunas.map((c) => c.nome).join(', ')}.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Publicar')),
        ],
      ),
    );
    if (ok != true) return;
    var feitas = 0;
    for (final c in colunas) {
      try {
        await acaoParte({'acao': 'publicar', 'parte_id': c.parteId});
        feitas++;
      } catch (e) {
        _aviso('${c.nome}: ${mensagemDeErro(e)}', erro: true);
      }
    }
    _aviso('$feitas parte(s) publicada(s).');
    if (mounted) _carregar();
  }

  void _irPara(DateTime d) {
    setState(() => _dia = DateTime(d.year, d.month, d.day));
    _carregar();
  }

  // ------------------------------------------------------------------
  // Tela
  // ------------------------------------------------------------------

  static const _diasDaSemana = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.sizeOf(context).width;
    final mostrarLog = _mostrarLog ?? largura >= 1500;
    final colunas = _colunas;
    final hoje = DateTime.now();
    final ehHoje = _dia.year == hoje.year && _dia.month == hoje.month && _dia.day == hoje.day;
    final semParte = colunas.where((c) => c.parte == null && c.equipe['ativa'] == true).length;
    final paraPublicar = colunas.where((c) => c.rascunho && c.itens.isNotEmpty).toList();
    final estreito = largura < 760; // celular: uma coisa de cada vez

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Barra do topo
      Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(estreito ? 4 : 16, 10, estreito ? 4 : 16, 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (!estreito) ...[
                Text('Quadro do dia',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(width: 16),
              ],
              IconButton(
                tooltip: 'Dia anterior',
                onPressed: () => _irPara(_dia.subtract(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_left),
              ),
              Flexible(
                child: TextButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text('${_diasDaSemana[_dia.weekday - 1]}, ${dataBr(dataIso(_dia))}',
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _dia,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d != null && mounted) _irPara(d);
                  },
                ),
              ),
              IconButton(
                tooltip: 'Próximo dia',
                onPressed: () => _irPara(_dia.add(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_right),
              ),
              if (!ehHoje) TextButton(onPressed: () => _irPara(hoje), child: const Text('Hoje')),
            ]),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (estreito)
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: false, label: Text('Equipes')),
                    ButtonSegment(value: true, label: Text('Fila (${_filaFiltrada.length})')),
                  ],
                  selected: {_verFila},
                  onSelectionChanged: (v) => setState(() {
                    _verFila = v.first;
                    _mostrarLog = false;
                  }),
                ),
              Tooltip(
                message: _aoVivo
                    ? 'Mudanças de outras pessoas e do app aparecem sozinhas.'
                    : 'Sem conexão ao vivo: use Atualizar.',
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 10, color: _aoVivo ? Cores.sucesso : Cores.neutro),
                  const SizedBox(width: 4),
                  Text(_aoVivo ? 'Ao vivo' : 'Offline',
                      style: TextStyle(fontSize: 12, color: _aoVivo ? Cores.sucesso : Cores.neutro)),
                ]),
              ),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: _carregando ? null : _carregar,
                icon: const Icon(Icons.refresh),
              ),
              if (podeEditar && semParte > 0)
                OutlinedButton.icon(
                  onPressed: _abrirODia,
                  icon: const Icon(Icons.playlist_add, size: 18),
                  label: Text('Abrir o dia ($semParte)'),
                ),
              if (podeEditar && paraPublicar.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _publicarTodas(paraPublicar),
                  icon: const Icon(Icons.send, size: 18),
                  label: Text('Publicar todas (${paraPublicar.length})'),
                ),
              IconButton(
                tooltip: mostrarLog ? 'Esconder log do dia' : 'Mostrar log do dia',
                isSelected: mostrarLog,
                onPressed: () => setState(() => _mostrarLog = !mostrarLog),
                icon: const Icon(Icons.history),
              ),
            ]),
          ],
        ),
      ),
      const Divider(height: 1),
      if (_carregando) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
      if (_erro != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_erro!, style: const TextStyle(color: Cores.erro)),
        ),
      Expanded(
        child: estreito
            // Celular: a fila, as equipes ou o log ocupam a tela toda.
            ? (mostrarLog
                ? _log()
                : _verFila
                    ? _painelFila(estreito: true)
                    : _quadroEquipes(colunas))
            : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _painelFila(),
                Expanded(child: _quadroEquipes(colunas)),
                if (mostrarLog) _log(),
              ]),
      ),
    ]);
  }

  Widget _log() => LogDoDia(
        eventos: _eventos,
        contexto: _contextoLog,
        aoFechar: () => setState(() => _mostrarLog = false),
      );

  Widget _quadroEquipes(List<ColunaQuadro> colunas) => colunas.isEmpty && !_carregando
      ? const Center(
          child: Text('Nenhuma equipe ativa. Cadastre em Cadastros > Equipes.',
              textAlign: TextAlign.center, style: TextStyle(color: Cores.neutro)),
        )
      : Scrollbar(
          controller: _rolagem,
          thumbVisibility: true,
          child: ListView(
            controller: _rolagem,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 12, 0, 16),
            children: [
              for (final c in colunas)
                ColunaEquipe(key: ValueKey(c.equipeId), coluna: c, acoes: this, agora: _agora),
            ],
          ),
        );

  /// A fila de pendentes. No celular ([estreito]) ocupa a tela sozinha: tudo
  /// rola junto (cabe com o teclado aberto) e não há arrasto (não há onde
  /// soltar); o botão de mandar para uma equipe faz o papel do arrasto.
  Widget _painelFila({bool estreito = false}) {
    final itens = _filaFiltrada;
    final arrastar = podeEditar && !estreito;

    Widget cartaoDe(Map<String, dynamic> ag) {
      final cartao = CartaoFila(
        ag: ag,
        compacto: true,
        aoTocar: () async {
          await context.push('/os/${ag['os_id']}');
          if (mounted) _carregar();
        },
        acoes: podeEditar
            ? IconButton(
                tooltip: 'Mandar para uma equipe',
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                color: Cores.indigo500,
                onPressed: () => _mandarParaEquipe(ag),
                icon: const Icon(Icons.send_outlined),
              )
            : null,
      );
      if (!arrastar) return cartao;
      return arrastavel(
        data: ArrastoFila(ag),
        onDragStarted: () => arrastando(true),
        onDragEnd: (_) => arrastando(false),
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(width: 280, child: Opacity(opacity: .9, child: cartao)),
        ),
        childWhenDragging: Opacity(opacity: .35, child: cartao),
        child: cartao,
      );
    }

    List<Widget> cabecalho(bool soltando) => [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(children: [
              Text('Fila (${itens.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const Spacer(),
              if (podeEditar)
                TextButton.icon(
                  onPressed: () async {
                    final osId = await context.push<String>('/os/nova');
                    if (mounted && osId != null) _carregar();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nova OS'),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _busca,
              decoration: const InputDecoration(
                  hintText: 'Cliente, local, região, OS...', prefixIcon: Icon(Icons.search, size: 20), isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(children: [
              Expanded(child: _filtro('Prioridade', _prioridade, {for (final p in prioridades.entries) p.key: p.value.texto},
                  (v) => _prioridade = v)),
              const SizedBox(width: 8),
              Expanded(child: _filtro('Tipo', _tipo, tiposAgendamento, (v) => _tipo = v)),
            ]),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            controlAffinity: ListTileControlAffinity.leading,
            value: _ateODia,
            onChanged: (v) => setState(() => _ateODia = v ?? false),
            title: Text('Só desejados até ${dataBr(dataIso(_dia))}'),
          ),
          if (soltando)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Solte aqui para tirar da parte e devolver para a fila.',
                  style: TextStyle(color: Cores.indigo700, fontWeight: FontWeight.w600)),
            ),
          const Divider(height: 1),
        ];

    const vazia = Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: Text('Fila vazia.', style: TextStyle(color: Cores.neutro))),
    );

    if (estreito) {
      return ColoredBox(
        color: Colors.white,
        child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
          ...cabecalho(false),
          if (itens.isEmpty) vazia,
          for (final ag in itens)
            Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: cartaoDe(ag)),
          if (podeEditar)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Text('Toque na setinha de um serviço para mandar para uma equipe. '
                  'Em Equipes, os 3 pontinhos de cada serviço trocam de equipe e de ordem.',
                  style: TextStyle(fontSize: 11, color: Cores.neutro)),
            ),
        ]),
      );
    }

    return DragTarget<Arrasto>(
      onWillAcceptWithDetails: (d) => podeEditar && d.data is ArrastoItem,
      onAcceptWithDetails: (d) => _devolverParaFila(d.data as ArrastoItem),
      builder: (context, candidatos, _) => Container(
        width: 310,
        decoration: BoxDecoration(
          color: candidatos.isNotEmpty ? Cores.indigo100 : Colors.white,
          border: const Border(right: BorderSide(color: Cores.linha)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ...cabecalho(candidatos.isNotEmpty),
          Expanded(
            child: itens.isEmpty
                ? vazia
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: itens.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => cartaoDe(itens[i]),
                  ),
          ),
          if (podeEditar)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Text('Arraste para uma equipe (ou use a setinha do cartão). Segure Alt ao soltar um '
                  'serviço de outra equipe para mandar como apoio.',
                  style: TextStyle(fontSize: 11, color: Cores.neutro)),
            ),
        ]),
      ),
    );
  }

  Widget _filtro(String rotulo, String? valor, Map<String, String> opcoes, ValueChanged<String?> aoMudar) {
    return InputDecorator(
      decoration: InputDecoration(labelText: rotulo, isDense: true),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: opcoes.containsKey(valor) ? valor : null,
          isDense: true,
          isExpanded: true,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
            for (final e in opcoes.entries)
              DropdownMenuItem<String?>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => aoMudar(v)),
        ),
      ),
    );
  }
}
