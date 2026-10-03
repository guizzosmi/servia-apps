import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cadastros/campos.dart';
import '../cadastros/definicoes.dart';
import '../servicos/parametros.dart';
import '../servicos/planos.dart';
import '../servicos/status.dart';
import '../widgets/campos_data_hora.dart';
import '../widgets/escolha_equipamentos.dart';
import '../widgets/margem.dart';
import '../widgets/prazos_preventivas.dart';
import '../widgets/status_chip.dart';

/// Um plano de preventiva ou PMOC: dados, equipamentos cobertos, atividades
/// (com periodicidade), o andamento (aparelhos e lotes) e os vencimentos de
/// cada aparelho. [id] null = plano novo.
class PlanoTela extends StatefulWidget {
  const PlanoTela({super.key, this.id});

  final String? id;

  @override
  State<PlanoTela> createState() => _PlanoTelaState();
}

class _PlanoTelaState extends State<PlanoTela> {
  static const _campoCliente = CampoDef('cliente_id', 'Cliente',
      tipo: TipoCampo.lookup, obrigatorio: true, lookup: Lookup(tabela: 'clientes'));
  static const _campoLocal = CampoDef('local_id', 'Local',
      tipo: TipoCampo.lookup,
      obrigatorio: true,
      lookup: Lookup(tabela: 'locais', colunaDetalhe: 'cidade', colunaFiltro: 'cliente_id', campoPai: 'cliente_id'));

  final _form = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _antecedencia = TextEditingController();
  final _tolerancia = TextEditingController();
  String _lote = 'mensal';
  final _rtNome = TextEditingController();
  final _rtRegistro = TextEditingController();
  final _art = TextEditingController();
  final _obs = TextEditingController();
  String _tipo = 'preventiva';
  String _controle = 'periodo';
  String? _clienteId;
  String? _localId;
  DateTime? _inicio;
  DateTime? _fim;

  Map<String, dynamic>? _plano;
  List<Map<String, dynamic>> _equipamentos = []; // equipamentos do plano (com ambiente e tipo)
  List<Map<String, dynamic>> _atividades = [];
  List<Map<String, dynamic>> _unidades = []; // vencimento de cada aparelho (e atividade geral)
  List<Map<String, dynamic>> _tipos = [];
  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;
  final _prazos = GlobalKey<PrazosPreventivasState>();

  bool get _novo => widget.id == null && _plano == null;
  String? get _planoId => _plano?['id'] as String? ?? widget.id;
  bool get _podeEditar => (Sessao.atual?.tem(Papel.gestor) ?? false) && _plano?['situacao'] != 'encerrado';

  void _parametrosMudaram() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ParametrosEmpresa.instancia.addListener(_parametrosMudaram);
    if (widget.id == null) {
      final hoje = DateTime.now();
      _inicio = DateTime(hoje.year, hoje.month, hoje.day);
      _carregando = false;
    } else {
      _carregar();
    }
  }

  @override
  void dispose() {
    ParametrosEmpresa.instancia.removeListener(_parametrosMudaram);
    for (final c in [_nome, _antecedencia, _tolerancia, _rtNome, _rtRegistro, _art, _obs]) {
      c.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Dados
  // ------------------------------------------------------------------

  /// [dados] = false mantém o que está digitado em "Dados do plano"
  /// (recarga depois de mexer em equipamentos, atividades ou situação).
  Future<void> _carregar({bool dados = true}) async {
    final id = _planoId;
    if (id == null) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    final db = Supabase.instance.client;
    try {
      final r = await Future.wait<Object>([
        db.from('planos').select('*, clientes(nome), locais(nome)').eq('id', id).single(),
        db
            .from('plano_equipamentos')
            .select('equipamento_id, equipamentos(id, codigo, descricao, situacao, tipo_equipamento_id, ambientes(nome), '
                'tipos_equipamento(nome))')
            .eq('plano_id', id)
            .isFilter('excluido_em', null),
        db
            .from('plano_atividades')
            .select('*, tipos_equipamento(nome)')
            .eq('plano_id', id)
            .isFilter('excluido_em', null)
            .order('ordem', ascending: true),
        db.from('tipos_equipamento').select('id, nome').isFilter('excluido_em', null).order('nome', ascending: true),
        db
            .from('plano_unidades')
            .select('id, equipamento_id, periodicidade, primeiro_vencimento, ultimo_ciclo_em, proximo_vencimento, '
                'equipamentos(codigo, descricao, ambientes(nome)), plano_atividades(descricao)')
            .eq('plano_id', id)
            .eq('ativo', true)
            .isFilter('excluido_em', null)
            .order('proximo_vencimento', ascending: true),
      ]);
      if (!mounted) return;
      final p = r[0] as Map<String, dynamic>;
      setState(() {
        _plano = p;
        if (dados) _preencherDados(p);
        _equipamentos = [
          for (final l in (r[1] as List).cast<Map<String, dynamic>>())
            if (l['equipamentos'] case final Map<String, dynamic> e) e,
        ]..sort((a, b) => '${a['codigo']}'.compareTo('${b['codigo']}'));
        _atividades = (r[2] as List).cast<Map<String, dynamic>>();
        _tipos = (r[3] as List).cast<Map<String, dynamic>>();
        _unidades = (r[4] as List).cast<Map<String, dynamic>>();
      });
      _prazos.currentState?.recarregar();
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _preencherDados(Map<String, dynamic> p) {
    _tipo = p['tipo'] as String;
    _controle = (p['controle_prazo'] ?? 'periodo') as String;
    _nome.text = '${p['nome'] ?? ''}';
    _clienteId = p['cliente_id'] as String?;
    _localId = p['local_id'] as String?;
    _inicio = DateTime.tryParse('${p['vigencia_inicio']}');
    _fim = DateTime.tryParse('${p['vigencia_fim'] ?? ''}');
    _antecedencia.text = '${p['antecedencia_dias'] ?? ''}';
    _tolerancia.text = '${p['tolerancia_dias'] ?? ''}';
    _lote = lotesPeriodo.containsKey(p['lote_periodo']) ? p['lote_periodo'] as String : 'mensal';
    _rtNome.text = '${p['responsavel_tecnico_nome'] ?? ''}';
    _rtRegistro.text = '${p['responsavel_tecnico_registro'] ?? ''}';
    _art.text = '${p['art_numero'] ?? ''}';
    _obs.text = '${p['observacoes'] ?? ''}';
  }

  void _aviso(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: erro ? Cores.erro : null,
    ));
  }

  /// Chama a regra, avisa e recarrega. Devolve a resposta (null se deu erro).
  Future<Map<String, dynamic>?> _acao(Map<String, dynamic> p, {String? sucesso}) async {
    setState(() => _ocupado = true);
    try {
      final r = await acaoPlano(p);
      if (sucesso != null) _aviso(sucesso);
      return r;
    } catch (e) {
      _aviso(mensagemDeErro(e), erro: true);
      return null;
    } finally {
      if (mounted) {
        setState(() => _ocupado = false);
        await _carregar(dados: p['acao'] == 'alterar');
      }
    }
  }

  Future<void> _salvarDados() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final p = <String, dynamic>{
      'acao': _novo ? 'criar' : 'alterar',
      if (!_novo) 'plano_id': _planoId,
      'tipo': _tipo,
      'nome': _nome.text.trim(),
      'cliente_id': _clienteId,
      'local_id': _localId,
      'vigencia_inicio': _inicio == null ? null : dataIso(_inicio!),
      'vigencia_fim': _fim == null ? null : dataIso(_fim!),
      'controle_prazo': _controle,
      'antecedencia_dias': int.tryParse(_antecedencia.text.trim()),
      'tolerancia_dias': int.tryParse(_tolerancia.text.trim()),
      'lote_periodo': _lote,
      'responsavel_tecnico_nome': _rtNome.text.trim(),
      'responsavel_tecnico_registro': _rtRegistro.text.trim(),
      'art_numero': _art.text.trim(),
      'observacoes': _obs.text.trim(),
    };
    if (_novo) {
      setState(() => _ocupado = true);
      try {
        final r = await acaoPlano(p);
        if (!mounted) return;
        _aviso('Plano criado. Agora inclua os equipamentos e as atividades.');
        context.pushReplacement('/planos/${r['plano_id']}');
      } catch (e) {
        _aviso(mensagemDeErro(e), erro: true);
        if (mounted) setState(() => _ocupado = false);
      }
      return;
    }
    await _acao(p, sucesso: 'Dados do plano salvos.');
  }

  // ------------------------------------------------------------------
  // Equipamentos
  // ------------------------------------------------------------------

  Future<void> _escolherEquipamentos() async {
    // Sempre o cliente e o local gravados no plano (não os que estão sendo editados).
    final atuais = {for (final e in _equipamentos) '${e['id']}'};
    final r = await escolherEquipamentos(context,
        clienteId: '${_plano!['cliente_id']}', localId: '${_plano!['local_id']}', atuais: atuais);
    if (r == null || !mounted) return;
    final incluir = r.keys.where((id) => !atuais.contains(id)).toList();
    // A janela só mostra os ativos: um inativo do plano não some por não aparecer lá.
    final tirar = [
      for (final e in _equipamentos)
        if (e['situacao'] == 'ativo' && !r.containsKey('${e['id']}')) '${e['id']}',
    ];
    if (incluir.isEmpty && tirar.isEmpty) return;
    var ok = true;
    if (incluir.isNotEmpty) {
      ok = await _acao({'acao': 'equipamentos_incluir', 'plano_id': _planoId, 'equipamentos': incluir}) != null;
    }
    if (ok && tirar.isNotEmpty) {
      ok = await _acao({'acao': 'equipamentos_tirar', 'plano_id': _planoId, 'equipamentos': tirar}) != null;
    }
    if (ok) _aviso('${incluir.length} incluído(s), ${tirar.length} retirado(s).');
  }

  // ------------------------------------------------------------------
  // Atividades
  // ------------------------------------------------------------------

  /// Tipos dos equipamentos do plano (id -> nome).
  Map<String, String> get _tiposNoPlano => {
        for (final e in _equipamentos)
          if (e['tipo_equipamento_id'] != null)
            '${e['tipo_equipamento_id']}': '${(e['tipos_equipamento'] as Map?)?['nome'] ?? 'Tipo'}',
      };

  Future<void> _copiarModelos() async {
    final r = await _acao({'acao': 'copiar_modelos', 'plano_id': _planoId});
    if (r == null || !mounted) return;
    final n = (r['quantidade'] as num?)?.toInt() ?? 0;
    if (n > 0) {
      _aviso('$n atividade(s) copiada(s) da biblioteca.');
      return;
    }
    // Nada copiado: talvez a biblioteca não tenha atividades para os tipos do plano.
    final tipos = _tiposNoPlano;
    if (tipos.isEmpty) {
      _aviso('Inclua equipamentos (com tipo) antes de copiar as atividades por aparelho.');
      return;
    }
    if (!ParametrosEmpresa.instancia.atendePmoc) {
      _aviso('A biblioteca não tem (outras) atividades para: ${tipos.values.join(', ')}. '
          'Cadastre em "Biblioteca de atividades" ou use "Nova atividade".');
      return;
    }
    final carregar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nada novo para copiar'),
        content: Text('A biblioteca não tem (outras) atividades para: ${tipos.values.join(', ')}.\n\n'
            'Quer carregar as atividades padrão do PMOC (Portaria 3.523/98) para esses tipos e copiar para o plano? '
            'Depois dá para ajustar a periodicidade de cada uma.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Não')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Carregar o padrão')),
        ],
      ),
    );
    if (carregar != true || !mounted) return;
    try {
      for (final t in tipos.keys) {
        await carregarPadraoPmoc(t);
      }
    } catch (e) {
      _aviso(mensagemDeErro(e), erro: true);
      return;
    }
    final r2 = await _acao({'acao': 'copiar_modelos', 'plano_id': _planoId});
    if (r2 != null) _aviso('${r2['quantidade'] ?? 0} atividade(s) copiada(s).');
  }

  Future<void> _editarAtividade([Map<String, dynamic>? a]) async {
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoAtividade(atividade: a, tipos: _tipos, inicioPlano: _inicio),
    );
    if (r == null) return;
    await _acao({
      'acao': 'atividade_salvar',
      'plano_id': _planoId,
      if (a != null) 'atividade_id': a['id'],
      ...r,
    }, sucesso: a == null ? 'Atividade incluída.' : 'Atividade alterada.');
  }

  Future<void> _excluirAtividade(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir a atividade?'),
        content: Text('${a['descricao']}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok == true) await _acao({'acao': 'atividade_excluir', 'atividade_id': a['id']}, sucesso: 'Atividade excluída.');
  }

  /// O contrato mudou (ex.: de trimestral para semestral): todas de uma vez.
  Future<void> _mudarPeriodicidade() async {
    String escolha = 'semestral';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Mudar a periodicidade de todas'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Vale para todas as atividades por aparelho deste plano (as gerais não mudam).'),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Nova periodicidade'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: escolha,
                    isDense: true,
                    isExpanded: true,
                    items: [
                      for (final e in periodicidades.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() => escolha = v ?? escolha),
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Mudar todas')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final r = await _acao({'acao': 'atividades_periodicidade', 'plano_id': _planoId, 'periodicidade': escolha});
    if (r != null) _aviso('${r['quantidade'] ?? 0} atividade(s) agora ${periodicidades[escolha]?.toLowerCase()}.');
  }

  // ------------------------------------------------------------------
  // Situação
  // ------------------------------------------------------------------

  Future<void> _situacao(String acao, String sucesso) async {
    if (acao == 'encerrar') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Encerrar o plano?'),
          content: const Text('Ele para de valer (a vigência termina hoje, se não tiver fim) e não pode mais ser '
              'alterado, a não ser que seja reaberto.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Encerrar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final r = await _acao({'acao': acao, 'plano_id': _planoId}, sucesso: acao == 'ativar' ? null : sucesso);
    if (r != null && acao == 'ativar' && mounted) await _gerar(ativou: true);
  }

  /// Gera os lotes que já podem nascer (antecedência) e põe os abertos em dia.
  Future<void> _gerar({bool ativou = false}) async {
    if (!mounted) return;
    setState(() => _ocupado = true);
    try {
      final r = await gerarPreventivas(planoId: _planoId);
      final n = (r['os_criadas'] as num?)?.toInt() ?? 0;
      final itens = (r['itens_criados'] as num?)?.toInt() ?? 0;
      _aviso([
        if (ativou) 'Plano ativo.',
        n > 0
            ? '$n lote(s) gerado(s): estão na Fila.'
            : itens > 0
                ? '$itens item(ns) novo(s) no checklist dos lotes abertos.'
                : 'Nenhum lote novo: os aparelhos do próximo mês ainda não estão na antecedência.',
      ].join(' '));
    } catch (e) {
      _aviso(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
      _prazos.currentState?.recarregar();
    }
  }

  // ------------------------------------------------------------------
  // Tela
  // ------------------------------------------------------------------

  Widget _secao(String titulo, List<Widget> filhos, {List<Widget> acoes = const []}) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(titulo, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ...acoes,
            ]),
            const SizedBox(height: 12),
            ...filhos,
          ]),
        ),
      );

  Widget _dados(bool editar) {
    return Form(
      key: _form,
      child: LayoutBuilder(builder: (context, box) {
        final cheio = box.maxWidth;
        final metade = cheio >= 640 ? (cheio - 16) / 2 : cheio;
        final quarto = cheio >= 640 ? (cheio - 48) / 4 : metade;
        Widget caixa(double w, Widget filho) => SizedBox(width: w, child: filho);
        return Wrap(spacing: 16, runSpacing: 16, children: [
          caixa(
            quarto,
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Tipo'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _tipo,
                  isDense: true,
                  isExpanded: true,
                  items: [
                    for (final e in tiposPlano.entries)
                      if (e.key != 'pmoc' || ParametrosEmpresa.instancia.atendePmoc || _tipo == 'pmoc')
                        DropdownMenuItem(value: e.key, child: Text(e.value.texto)),
                  ],
                  onChanged: editar ? (v) => setState(() => _tipo = v ?? _tipo) : null,
                ),
              ),
            ),
          ),
          caixa(
            cheio >= 640 ? cheio - quarto - 16 : cheio,
            TextFormField(
              controller: _nome,
              enabled: editar,
              decoration: const InputDecoration(labelText: 'Nome do plano *', hintText: 'Ex.: PMOC Friella 2026/2027'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Dê um nome ao plano' : null,
            ),
          ),
          caixa(
            metade,
            CampoLookup(
              campo: _campoCliente,
              valor: _clienteId,
              valorPai: null,
              rotuloPai: null,
              habilitado: editar && _equipamentos.isEmpty,
              aoMudar: (v) => setState(() {
                _clienteId = v;
                _localId = null;
              }),
            ),
          ),
          caixa(
            metade,
            CampoLookup(
              campo: _campoLocal,
              valor: _localId,
              valorPai: _clienteId,
              rotuloPai: 'Cliente',
              habilitado: editar && _equipamentos.isEmpty,
              aoMudar: (v) => setState(() => _localId = v),
            ),
          ),
          caixa(
              quarto,
              CampoData(
                  rotulo: 'Vigência: início *',
                  valor: _inicio,
                  habilitado: editar,
                  aoMudar: (d) => setState(() => _inicio = d))),
          caixa(
              quarto,
              CampoData(
                  rotulo: 'Fim (opcional)', valor: _fim, habilitado: editar, aoMudar: (d) => setState(() => _fim = d))),
          caixa(
            quarto,
            TextFormField(
              controller: _antecedencia,
              enabled: editar,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Antecedência (dias)', helperText: 'Vazio: o padrão da empresa'),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                final n = int.tryParse(t);
                return n == null || n < 0 || n > 90 ? 'De 0 a 90' : null;
              },
            ),
          ),
          caixa(
            metade,
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Lote (como os aparelhos viram OS na Fila)'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _lote,
                  isDense: true,
                  isExpanded: true,
                  items: [
                    for (final e in lotesPeriodo.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: editar ? (v) => setState(() => _lote = v ?? _lote) : null,
                ),
              ),
            ),
          ),
          caixa(
            quarto,
            TextFormField(
              controller: _tolerancia,
              enabled: editar,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Tolerância (dias)', helperText: 'Antes do vencimento. Vazio: o da empresa'),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                final n = int.tryParse(t);
                return n == null || n < 0 || n > 90 ? 'De 0 a 90' : null;
              },
            ),
          ),
          if (_tipo == 'pmoc') ...[
            caixa(
              metade,
              TextFormField(
                controller: _rtNome,
                enabled: editar,
                decoration: const InputDecoration(labelText: 'Responsável técnico (RT)', helperText: 'Obrigatório para ativar'),
              ),
            ),
            caixa(
              quarto,
              TextFormField(
                controller: _rtRegistro,
                enabled: editar,
                decoration: const InputDecoration(labelText: 'Registro CREA/CFT'),
              ),
            ),
            caixa(
              quarto,
              TextFormField(
                controller: _art,
                enabled: editar,
                decoration: const InputDecoration(labelText: 'ART/TRT (se houver)'),
              ),
            ),
          ],
          caixa(
            cheio,
            TextFormField(
              controller: _obs,
              enabled: editar,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Observações (ex.: regras do contrato)'),
            ),
          ),
          if (editar)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _ocupado ? null : _salvarDados,
                icon: const Icon(Icons.check),
                label: Text(_novo ? 'Criar plano' : 'Salvar dados'),
              ),
            ),
        ]);
      }),
    );
  }

  Widget _listaEquipamentos(bool editar) {
    final porAmbiente = <String, List<Map<String, dynamic>>>{};
    for (final e in _equipamentos) {
      final amb = '${(e['ambientes'] as Map?)?['nome'] ?? 'Sem ambiente'}';
      porAmbiente.putIfAbsent(amb, () => []).add(e);
    }
    final ambientes = porAmbiente.keys.toList()..sort();
    final semTipo = _equipamentos.where((e) => e['tipo_equipamento_id'] == null).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_equipamentos.isEmpty)
        const Text('Nenhum equipamento ainda. Use "Todos do local" ou "Escolher".', style: TextStyle(color: Cores.neutro)),
      if (semTipo > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('$semTipo equipamento(s) sem tipo: as atividades por aparelho não valem para eles. '
              'Ajuste o tipo no cadastro do equipamento.',
              style: const TextStyle(color: Cores.alerta)),
        ),
      for (final amb in ambientes)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(amb),
          subtitle: Text('${porAmbiente[amb]!.length} equipamento(s)'),
          children: [
            for (final e in porAmbiente[amb]!)
              ListTile(
                dense: true,
                title: Text(rotuloEquipamento(e)),
                subtitle: Text('${(e['tipos_equipamento'] as Map?)?['nome'] ?? 'Sem tipo'}'),
                trailing: editar
                    ? IconButton(
                        tooltip: 'Tirar do plano',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _ocupado
                            ? null
                            : () => _acao({
                                  'acao': 'equipamentos_tirar',
                                  'plano_id': _planoId,
                                  'equipamentos': [e['id']],
                                }),
                      )
                    : null,
              ),
          ],
        ),
    ]);
  }

  Widget _listaAtividades(bool editar) {
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final a in _atividades) {
      final g = a['tipo_equipamento_id'] == null
          ? 'Geral do plano (uma vez por período)'
          : 'Por aparelho: ${(a['tipos_equipamento'] as Map?)?['nome'] ?? 'Tipo'}';
      grupos.putIfAbsent(g, () => []).add(a);
    }
    final tiposSemAtividade = _tiposNoPlano.entries
        .where((t) => !_atividades.any((a) => a['tipo_equipamento_id'] == t.key))
        .map((t) => t.value)
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_atividades.isEmpty)
        const Text('Nenhuma atividade ainda. Use "Copiar da biblioteca" ou "Nova atividade".',
            style: TextStyle(color: Cores.neutro)),
      if (tiposSemAtividade.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Sem atividades para: ${tiposSemAtividade.join(', ')}.',
              style: const TextStyle(color: Cores.alerta)),
        ),
      for (final g in grupos.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(g.key, style: const TextStyle(fontWeight: FontWeight.w700, color: Cores.indigo700)),
        ),
        for (final a in g.value)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            enabled: a['ativo'] != false,
            leading: Icon(a['exige_foto'] == true ? Icons.photo_camera_outlined : Icons.check_box_outlined, size: 20),
            title: Text('${a['descricao']}'),
            subtitle: Text([
              periodicidades[a['periodicidade']] ?? '${a['periodicidade']}',
              'a partir de ${dataBr(a['data_base'])}',
              if (a['exige_foto'] == true) 'exige foto',
              if (a['ativo'] == false) 'pausada',
            ].join(' · ')),
            trailing: editar
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Alterar',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: _ocupado ? null : () => _editarAtividade(a),
                    ),
                    IconButton(
                      tooltip: 'Excluir',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: _ocupado ? null : () => _excluirAtividade(a),
                    ),
                  ])
                : null,
          ),
      ],
    ]);
  }

  static const _meses = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro',
      'outubro', 'novembro', 'dezembro'];

  /// Muda o vencimento de um aparelho (o lote dele acompanha).
  Future<void> _mudarVencimento(Map<String, dynamic> u) async {
    final atual = DateTime.tryParse('${u['proximo_vencimento']}') ?? DateTime.now();
    final hoje = DateTime.now();
    // Mesmos limites da plataforma: até 1 ano atrás (não antes do início da vigência) e até o fim dela.
    var primeiro = hoje.subtract(const Duration(days: 365));
    final inicio = DateTime.tryParse('${_plano?['vigencia_inicio'] ?? ''}');
    if (inicio != null && inicio.isAfter(primeiro)) primeiro = inicio;
    var ultimo = DateTime.tryParse('${_plano?['vigencia_fim'] ?? ''}') ?? DateTime(hoje.year + 3);
    if (ultimo.isBefore(primeiro)) ultimo = primeiro;
    final inicial = atual.isBefore(primeiro) ? primeiro : (atual.isAfter(ultimo) ? ultimo : atual);
    final d = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: primeiro,
      lastDate: ultimo,
      helpText: 'Novo vencimento',
    );
    if (d == null || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await acaoUnidade({'acao': 'vencimento', 'unidade_id': u['id'], 'data': dataIso(d)});
      _aviso('Vencimento mudado para ${dataBr(dataIso(d))}. O aparelho vai para o lote desse mês.');
    } catch (e) {
      _aviso(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) {
        setState(() => _ocupado = false);
        await _carregar(dados: false);
      }
    }
  }

  Future<void> _redistribuir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Distribuir o 1º ciclo de novo?'),
        content: const Text('Os aparelhos que ainda não tiveram ciclo feito são divididos de novo pelos meses do período, '
            'por ambiente. Os que já tiveram ciclo feito não mudam.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Distribuir')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _ocupado = true);
    try {
      final r = await acaoUnidade({'acao': 'redistribuir', 'plano_id': _planoId});
      _aviso('${r['quantidade'] ?? 0} aparelho(s) redistribuído(s).');
    } catch (e) {
      _aviso(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) {
        setState(() => _ocupado = false);
        await _carregar(dados: false);
      }
    }
  }

  /// Vencimentos por mês: quantos aparelhos vencem em cada mês e quais.
  Widget _listaVencimentos(bool podeMudar) {
    if (_unidades.isEmpty) {
      return const Text(
          'Os vencimentos aparecem quando o plano é ativado: o 1º ciclo é distribuído pelos meses do período '
          '(ex.: semestral = 6 meses), agrupado por ambiente.',
          style: TextStyle(color: Cores.neutro));
    }
    final porMes = <String, List<Map<String, dynamic>>>{};
    for (final u in _unidades) {
      porMes.putIfAbsent('${u['proximo_vencimento']}'.substring(0, 7), () => []).add(u);
    }
    final hoje = dataIso(DateTime.now());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final m in porMes.entries)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('${_meses[int.parse(m.key.substring(5, 7)) - 1]}/${m.key.substring(0, 4)}'),
          subtitle: Text([
            '${m.value.where((u) => u['equipamento_id'] != null).length} aparelho(s)',
            if (m.value.any((u) => u['equipamento_id'] == null))
              '${m.value.where((u) => u['equipamento_id'] == null).length} atividade(s) geral(is)',
          ].join(' · ')),
          children: [
            for (final u in m.value)
              Builder(builder: (_) {
                final e = u['equipamentos'] as Map?;
                final vencido = '${u['proximo_vencimento']}'.compareTo(hoje) < 0;
                return ListTile(
                  dense: true,
                  title: Text(e != null
                      ? rotuloEquipamento(e)
                      : 'Geral: ${(u['plano_atividades'] as Map?)?['descricao'] ?? ''}'),
                  subtitle: Text([
                    if (e != null) '${(e['ambientes'] as Map?)?['nome'] ?? 'Sem ambiente'}',
                    'vence ${dataBr(u['proximo_vencimento'])}',
                    u['ultimo_ciclo_em'] != null ? 'último ciclo ${dataBr(u['ultimo_ciclo_em'])}' : '1º ciclo',
                    periodicidades[u['periodicidade']] ?? '${u['periodicidade']}',
                  ].join(' · '), style: TextStyle(color: vencido ? Cores.erro : null)),
                  trailing: podeMudar
                      ? TextButton(onPressed: _ocupado ? null : () => _mudarVencimento(u), child: const Text('Mudar'))
                      : null,
                );
              }),
          ],
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final editar = _podeEditar && !_ocupado;
    final situacao = _plano?['situacao'] as String?;
    final gestor = Sessao.atual?.tem(Papel.gestor) ?? false;
    return ListView(padding: margemDaTela(context), children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/planos'),
          icon: const Icon(Icons.arrow_back),
        ),
        Text(_novo ? 'Novo plano' : '${_plano?['nome'] ?? 'Plano'}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (!_novo) ...[
          StatusChip(_tipo, tiposPlano),
          StatusChip(situacao, situacoesPlano),
        ],
        if (_ocupado || _carregando)
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        if (!_novo && gestor && situacao == 'rascunho')
          FilledButton.icon(
            onPressed: _ocupado ? null : () => _situacao('ativar', 'Plano ativo.'),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Ativar'),
          ),
        if (!_novo && gestor && situacao == 'ativo')
          OutlinedButton.icon(
            onPressed: _ocupado ? null : () => _situacao('encerrar', 'Plano encerrado.'),
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Encerrar'),
          ),
        if (!_novo && gestor && situacao == 'encerrado')
          OutlinedButton.icon(
            onPressed: _ocupado ? null : () => _situacao('reabrir', 'Plano reaberto como rascunho.'),
            icon: const Icon(Icons.replay),
            label: const Text('Reabrir'),
          ),
      ]),
      if (!_novo && _plano != null)
        Padding(
          padding: const EdgeInsets.only(left: 52, bottom: 12),
          child: Text('${(_plano!['clientes'] as Map?)?['nome'] ?? ''} · ${(_plano!['locais'] as Map?)?['nome'] ?? ''}',
              style: const TextStyle(color: Cores.neutro)),
        ),
      if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
      const SizedBox(height: 8),
      _secao('Dados do plano', [_dados(_novo ? !_ocupado : editar)]),
      if (!_novo && _plano != null) ...[
        _secao('Equipamentos (${_equipamentos.length})', [_listaEquipamentos(editar)], acoes: [
          if (editar) ...[
            OutlinedButton.icon(
              onPressed: () => _acao({'acao': 'equipamentos_incluir', 'plano_id': _planoId, 'todos_do_local': true},
                  sucesso: 'Equipamentos do local incluídos.'),
              icon: const Icon(Icons.select_all, size: 18),
              label: const Text('Todos do local'),
            ),
            OutlinedButton.icon(
              onPressed: _escolherEquipamentos,
              icon: const Icon(Icons.checklist, size: 18),
              label: const Text('Escolher'),
            ),
          ],
        ]),
        _secao('Atividades (${_atividades.length})', [_listaAtividades(editar)], acoes: [
          if (editar) ...[
            OutlinedButton.icon(
              onPressed: _copiarModelos,
              icon: const Icon(Icons.library_add_outlined, size: 18),
              label: const Text('Copiar da biblioteca'),
            ),
            OutlinedButton.icon(
              onPressed: () => _editarAtividade(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nova atividade'),
            ),
            if (_atividades.any((a) => a['tipo_equipamento_id'] != null))
              OutlinedButton.icon(
                onPressed: _mudarPeriodicidade,
                icon: const Icon(Icons.event_repeat, size: 18),
                label: const Text('Mudar periodicidade de todas'),
              ),
          ],
        ]),
        _secao('Andamento', [
          const Text(
              'Cada mês (ou quinzena) vira um lote na Fila, com os aparelhos que vencem nele. A equipe marca o '
              'checklist no app; aparelho com tudo marcado fecha o ciclo e ganha a OS dele (a que vai para o '
              'cliente). O que ficar para trás passa para o lote seguinte.',
              style: TextStyle(fontSize: 12, color: Cores.neutro)),
          const SizedBox(height: 8),
          PrazosPreventivas(key: _prazos, planoId: _planoId),
        ], acoes: [
          if (gestor && situacao == 'ativo')
            OutlinedButton.icon(
              onPressed: _ocupado ? null : _gerar,
              icon: const Icon(Icons.bolt_outlined, size: 18),
              label: const Text('Gerar agora'),
            ),
        ]),
        _secao('Vencimentos dos aparelhos', [
          const Text(
              '1º ciclo: os aparelhos são distribuídos pelos meses do período, por ambiente. Depois, cada um vence um '
              'período depois da última vez que o ciclo fechou (a tolerância é a janela antes do vencimento).',
              style: TextStyle(fontSize: 12, color: Cores.neutro)),
          const SizedBox(height: 8),
          _listaVencimentos(gestor && situacao == 'ativo'),
        ], acoes: [
          if (gestor && situacao == 'ativo' && _unidades.any((u) => u['ultimo_ciclo_em'] == null))
            OutlinedButton.icon(
              onPressed: _ocupado ? null : _redistribuir,
              icon: const Icon(Icons.shuffle, size: 18),
              label: const Text('Distribuir o 1º ciclo de novo'),
            ),
        ]),
      ],
    ]);
  }
}

/// Inclusão ou alteração de uma atividade do plano. Devolve o que vai para
/// a regra (descricao, periodicidade, tipo, data base, exige foto, ativo).
class _DialogoAtividade extends StatefulWidget {
  const _DialogoAtividade({required this.atividade, required this.tipos, required this.inicioPlano});

  final Map<String, dynamic>? atividade;
  final List<Map<String, dynamic>> tipos;
  final DateTime? inicioPlano;

  @override
  State<_DialogoAtividade> createState() => _DialogoAtividadeState();
}

class _DialogoAtividadeState extends State<_DialogoAtividade> {
  late final _descricao = TextEditingController(text: '${widget.atividade?['descricao'] ?? ''}');
  late String _periodicidade = '${widget.atividade?['periodicidade'] ?? 'mensal'}';
  late String? _tipo = widget.tipos.any((t) => t['id'] == widget.atividade?['tipo_equipamento_id'])
      ? (widget.atividade?['tipo_equipamento_id'] as String?)
      : null;
  late DateTime? _base = DateTime.tryParse('${widget.atividade?['data_base'] ?? ''}') ?? widget.inicioPlano;
  late bool _foto = widget.atividade?['exige_foto'] == true;
  late bool _ativo = widget.atividade?['ativo'] != false;

  @override
  void dispose() {
    _descricao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.atividade == null ? 'Nova atividade' : 'Alterar atividade'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _descricao,
            autofocus: widget.atividade == null,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Descrição *', hintText: 'Ex.: Limpeza dos filtros de ar'),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Vale para'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _tipo,
                isDense: true,
                isExpanded: true,
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('O plano todo (uma vez por período)')),
                  for (final t in widget.tipos)
                    DropdownMenuItem<String?>(value: '${t['id']}', child: Text('Cada aparelho: ${t['nome']}')),
                ],
                onChanged: (v) => setState(() => _tipo = v),
              ),
            ),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Periodicidade'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _periodicidade,
                isDense: true,
                isExpanded: true,
                items: [for (final e in periodicidades.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _periodicidade = v ?? _periodicidade),
              ),
            ),
          ),
          const SizedBox(height: 12),
          CampoData(rotulo: 'A partir de (data base)', valor: _base, aoMudar: (d) => setState(() => _base = d)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _foto,
            onChanged: (v) => setState(() => _foto = v),
            title: const Text('Exige foto'),
          ),
          if (widget.atividade != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _ativo,
              onChanged: (v) => setState(() => _ativo = v),
              title: const Text('Ativa'),
              subtitle: const Text('Desligada, ela fica pausada (não entra nos prazos).'),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (_descricao.text.trim().isEmpty) return;
            Navigator.of(context).pop(<String, dynamic>{
              'descricao': _descricao.text.trim(),
              'periodicidade': _periodicidade,
              'tipo_equipamento_id': _tipo,
              'data_base': _base == null ? null : dataIso(_base!),
              'exige_foto': _foto,
              'ativo': _ativo,
            });
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
