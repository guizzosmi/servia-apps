import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cadastros/campos.dart';
import '../cadastros/definicoes.dart';
import '../servicos/contratos.dart';
import '../servicos/planos.dart' show periodicidades;
import '../servicos/status.dart';
import '../widgets/campos_data_hora.dart';
import '../widgets/itens_os.dart' show dinheiro, lerNumero, numeroBr;
import '../widgets/margem.dart';
import '../widgets/status_chip.dart';

/// Um contrato do cliente: dados (modalidade, vigência, valores, franquia,
/// reajuste), a tabela de preços do ciclo de preventiva, a conferência dos
/// aparelhos, o consumo do mês e os reajustes. [id] null = contrato novo.
class ContratoTela extends StatefulWidget {
  const ContratoTela({super.key, this.id});

  final String? id;

  @override
  State<ContratoTela> createState() => _ContratoTelaState();
}

class _ContratoTelaState extends State<ContratoTela> {
  static const _campoCliente = CampoDef('cliente_id', 'Cliente',
      tipo: TipoCampo.lookup, obrigatorio: true, lookup: Lookup(tabela: 'clientes'));
  static const _campoLocal = CampoDef('local_id', 'Local (vazio = todos os locais do cliente)',
      tipo: TipoCampo.lookup,
      lookup: Lookup(tabela: 'locais', colunaDetalhe: 'cidade', colunaFiltro: 'cliente_id', campoPai: 'cliente_id'));

  final _form = GlobalKey<FormState>();
  final _descricao = TextEditingController();
  final _valorMensal = TextEditingController();
  final _franqVisitas = TextEditingController();
  final _franqHoras = TextEditingController();
  final _excVisita = TextEditingController();
  final _excHora = TextEditingController();
  final _diaFechamento = TextEditingController();
  final _diaVencimento = TextEditingController();
  final _obs = TextEditingController();
  String _modalidade = 'por_execucao';
  String _indice = 'ipca';
  String? _clienteId;
  String? _localId;
  DateTime? _inicio;
  DateTime? _fim;
  DateTime? _proxReajuste;

  Map<String, dynamic>? _contrato;
  List<Map<String, dynamic>> _precos = [];
  List<Map<String, dynamic>> _tipos = [];
  Map<String, dynamic>? _situacao; // consumo, conferência, reajustes
  DateTime _referencia = DateTime.now(); // competência mostrada no consumo
  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;

  bool get _novo => widget.id == null && _contrato == null;
  String? get _contratoId => _contrato?['id'] as String? ?? widget.id;
  String? get _sit => _contrato?['situacao'] as String?;
  bool get _podeEditar => _sit != 'encerrado';

  /// O que está gravado (o formulário pode ter mudança ainda não salva).
  String get _modalidadeSalva => _contrato?['modalidade'] as String? ?? _modalidade;
  String get _indiceSalvo => _contrato?['reajuste_indice'] as String? ?? _indice;

  @override
  void initState() {
    super.initState();
    if (widget.id == null) {
      final hoje = DateTime.now();
      _inicio = DateTime(hoje.year, hoje.month, hoje.day);
      _proxReajuste = DateTime(hoje.year + 1, hoje.month, hoje.day);
      _carregando = false;
    } else {
      _carregar();
    }
  }

  @override
  void dispose() {
    for (final c in [_descricao, _valorMensal, _franqVisitas, _franqHoras, _excVisita, _excHora, _diaFechamento,
      _diaVencimento, _obs]) {
      c.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Dados
  // ------------------------------------------------------------------

  Future<void> _carregar({bool dados = true}) async {
    final id = _contratoId;
    if (id == null) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    final db = Supabase.instance.client;
    try {
      final r = await Future.wait<Object>([
        db.from('contratos').select('*, clientes(nome), locais(nome)').eq('id', id).single(),
        db
            .from('contrato_precos')
            .select()
            .eq('contrato_id', id)
            .isFilter('excluido_em', null)
            .order('alvo', ascending: true)
            .order('valor', ascending: true),
        db.from('tipos_equipamento').select('id, nome').isFilter('excluido_em', null).order('nome', ascending: true),
      ]);
      if (!mounted) return;
      final c = r[0] as Map<String, dynamic>;
      setState(() {
        _contrato = c;
        if (dados) _preencher(c);
        _precos = (r[1] as List).cast<Map<String, dynamic>>();
        _tipos = (r[2] as List).cast<Map<String, dynamic>>();
      });
      await _carregarSituacao();
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _carregarSituacao() async {
    final id = _contratoId;
    if (id == null) return;
    try {
      final s = await situacaoContrato(id, data: dataIso(_referencia));
      if (mounted) setState(() => _situacao = s);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    }
  }

  static String _txt(Object? v) => v == null ? '' : numeroBr(v);

  void _preencher(Map<String, dynamic> c) {
    _modalidade = modalidadesContrato.containsKey(c['modalidade']) ? c['modalidade'] as String : 'por_execucao';
    _indice = indicesReajuste.containsKey(c['reajuste_indice']) ? c['reajuste_indice'] as String : 'ipca';
    _clienteId = c['cliente_id'] as String?;
    _localId = c['local_id'] as String?;
    _descricao.text = '${c['descricao'] ?? ''}';
    _inicio = DateTime.tryParse('${c['vigencia_inicio']}');
    _fim = DateTime.tryParse('${c['vigencia_fim'] ?? ''}');
    _proxReajuste = DateTime.tryParse('${c['proximo_reajuste'] ?? ''}');
    _valorMensal.text = _txt(c['valor_mensal']);
    _franqVisitas.text = _txt(c['franquia_visitas']);
    _franqHoras.text = _txt(c['franquia_horas']);
    _excVisita.text = _txt(c['valor_visita_excedente']);
    _excHora.text = _txt(c['valor_hora_excedente']);
    _diaFechamento.text = _txt(c['dia_fechamento']);
    _diaVencimento.text = _txt(c['dia_vencimento']);
    _obs.text = '${c['observacoes'] ?? ''}';
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
      final r = await acaoContrato(p);
      if (sucesso != null) _aviso(sucesso);
      return r;
    } catch (e) {
      _aviso(mensagemDeErro(e), erro: true);
      return null;
    } finally {
      if (mounted) {
        setState(() => _ocupado = false);
        await _carregar(dados: const {'alterar', 'reajustar', 'encerrar', 'reabrir'}.contains(p['acao']));
      }
    }
  }

  String? _numero(TextEditingController c) {
    final n = lerNumero(c.text);
    if (n == null) return null;
    return n == n.roundToDouble() ? '${n.toInt()}' : '$n';
  }

  Future<void> _salvar() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final franquia = _modalidade == 'franquia';
    final p = <String, dynamic>{
      'acao': _novo ? 'criar' : 'alterar',
      if (!_novo) 'contrato_id': _contratoId,
      'cliente_id': _clienteId,
      'local_id': _localId,
      'descricao': _descricao.text.trim(),
      'modalidade': _modalidade,
      'vigencia_inicio': _inicio == null ? null : dataIso(_inicio!),
      'vigencia_fim': _fim == null ? null : dataIso(_fim!),
      'valor_mensal': _modalidade == 'por_execucao' ? null : _numero(_valorMensal),
      'franquia_visitas': franquia ? _numero(_franqVisitas) : null,
      'franquia_horas': franquia ? _numero(_franqHoras) : null,
      'valor_visita_excedente': franquia ? _numero(_excVisita) : null,
      'valor_hora_excedente': franquia ? _numero(_excHora) : null,
      'dia_fechamento': _numero(_diaFechamento),
      'dia_vencimento': _numero(_diaVencimento),
      'reajuste_indice': _indice,
      'proximo_reajuste': _indice == 'nenhum' || _proxReajuste == null ? null : dataIso(_proxReajuste!),
      'observacoes': _obs.text.trim(),
    };
    if (_novo) {
      setState(() => _ocupado = true);
      try {
        final r = await acaoContrato(p);
        if (!mounted) return;
        _aviso(_modalidade == 'por_execucao'
            ? 'Contrato criado. Agora monte a tabela de preços e ative.'
            : 'Contrato criado. Confira os dados e ative.');
        context.pushReplacement('/contratos/${r['contrato_id']}');
      } catch (e) {
        _aviso(mensagemDeErro(e), erro: true);
        if (mounted) setState(() => _ocupado = false);
      }
      return;
    }
    await _acao(p, sucesso: 'Dados do contrato salvos.');
  }

  // ------------------------------------------------------------------
  // Situação, preços e reajuste
  // ------------------------------------------------------------------

  Future<bool> _confirmar(String titulo, String texto, String botao) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titulo),
          content: Text(texto),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(botao)),
          ],
        ),
      ) ==
      true;

  Future<void> _ativar() async {
    final r = await _acao({'acao': 'ativar', 'contrato_id': _contratoId});
    if (r == null) return;
    final os = (r['os'] as num?)?.toInt() ?? 0;
    final ciclos = (r['ciclos'] as num?)?.toInt() ?? 0;
    _aviso([
      'Contrato ativo.',
      if (os > 0) '$os OS do cliente ligada(s) a ele${ciclos > 0 ? ' ($ciclos do aparelho, já com o preço)' : ''}.',
    ].join(' '));
  }

  Future<void> _encerrar() async {
    if (!await _confirmar(
        'Encerrar o contrato?',
        'Ele para de valer (a vigência termina hoje, se não tiver terminado) e as OS novas do cliente nascem sem '
            'contrato. As OS que já são dele continuam.',
        'Encerrar')) {
      return;
    }
    await _acao({'acao': 'encerrar', 'contrato_id': _contratoId}, sucesso: 'Contrato encerrado.');
  }

  Future<void> _editarPreco([Map<String, dynamic>? preco]) async {
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoPreco(preco: preco, tipos: _tipos),
    );
    if (r == null) return;
    await _acao({
      'acao': 'preco_salvar',
      'contrato_id': _contratoId,
      if (preco != null) 'preco_id': preco['id'],
      ...r,
    }, sucesso: preco == null ? 'Preço incluído.' : 'Preço alterado.');
  }

  Future<void> _excluirPreco(Map<String, dynamic> preco) async {
    if (!await _confirmar('Excluir o preço?', '${preco['descricao']} · ${dinheiro(preco['valor'])}', 'Excluir')) return;
    await _acao({'acao': 'preco_excluir', 'contrato_id': _contratoId, 'preco_id': preco['id']},
        sucesso: 'Preço excluído.');
  }

  Future<void> _aplicarPrecos() async {
    final r = await _acao({'acao': 'aplicar_precos', 'contrato_id': _contratoId});
    if (r == null) return;
    final n = (r['os'] as num?)?.toInt() ?? 0;
    _aviso(n > 0
        ? '$n OS do aparelho recebeu(ram) o preço.'
        : 'Nenhuma OS mudou: ainda não há linha da tabela que sirva para elas.');
  }

  Future<void> _reajustar() async {
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoReajuste(indice: indicesReajuste[_indiceSalvo] ?? _indiceSalvo),
    );
    if (r == null) return;
    final res = await _acao({'acao': 'reajustar', 'contrato_id': _contratoId, ...r});
    if (res == null) return;
    _aviso('Reajuste aplicado em ${res['precos'] ?? 0} preço(s) e nos valores do contrato. '
        'Próximo: ${dataBr(res['proximo_reajuste'])}.');
  }

  void _mudarMes(int delta) {
    setState(() => _referencia = DateTime(_referencia.year, _referencia.month + delta, 15));
    _carregarSituacao();
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

  String? _validarNumero(String? v, {bool obrigatorio = false, num min = 0, num? max, bool inteiro = false}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return obrigatorio ? 'Obrigatório' : null;
    final n = lerNumero(t);
    if (n == null || (inteiro && n != n.roundToDouble())) return 'Número inválido';
    if (n < min || (max != null && n > max)) return max == null ? 'Mínimo ${numeroBr(min)}' : 'De ${numeroBr(min)} a ${numeroBr(max)}';
    return null;
  }

  Widget _dados(bool editar) {
    final rascunho = _novo || _sit == 'rascunho';
    return Form(
      key: _form,
      child: LayoutBuilder(builder: (context, box) {
        final cheio = box.maxWidth;
        final metade = cheio >= 640 ? (cheio - 16) / 2 : cheio;
        final quarto = cheio >= 640 ? (cheio - 48) / 4 : metade;
        Widget caixa(double w, Widget filho) => SizedBox(width: w, child: filho);
        Widget numero(TextEditingController c, String rotulo,
                {bool obrigatorio = false, String? ajuda, num min = 0, num? max, bool inteiro = false}) =>
            TextFormField(
              controller: c,
              enabled: editar,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: obrigatorio ? '$rotulo *' : rotulo, helperText: ajuda),
              validator: (v) => _validarNumero(v, obrigatorio: obrigatorio, min: min, max: max, inteiro: inteiro),
            );
        Widget lista<T>(String rotulo, T valor, Map<T, String> opcoes, ValueChanged<T> aoMudar) => InputDecorator(
              decoration: InputDecoration(labelText: rotulo),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: valor,
                  isDense: true,
                  isExpanded: true,
                  items: [
                    for (final e in opcoes.entries)
                      DropdownMenuItem<T>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: editar
                      ? (v) {
                          if (v != null) aoMudar(v);
                        }
                      : null,
                ),
              ),
            );
        return Wrap(spacing: 16, runSpacing: 16, children: [
          caixa(
            metade,
            CampoLookup(
              campo: _campoCliente,
              valor: _clienteId,
              valorPai: null,
              rotuloPai: null,
              habilitado: editar && rascunho,
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
              habilitado: editar && rascunho,
              aoMudar: (v) => setState(() => _localId = v),
            ),
          ),
          caixa(
            metade,
            lista<String>('Modalidade', _modalidade, {for (final e in modalidadesContrato.entries) e.key: e.value.texto},
                (v) => setState(() => _modalidade = v)),
          ),
          caixa(
            metade,
            TextFormField(
              controller: _descricao,
              enabled: editar,
              decoration: const InputDecoration(labelText: 'Descrição', hintText: 'Ex.: Manutenção e PMOC 2026/2027'),
            ),
          ),
          caixa(
            cheio,
            Text(explicacaoModalidade[_modalidade] ?? '', style: const TextStyle(fontSize: 12, color: Cores.neutro)),
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
              CampoData(rotulo: 'Fim (opcional)', valor: _fim, habilitado: editar, aoMudar: (d) => setState(() => _fim = d))),
          if (_modalidade != 'por_execucao')
            caixa(quarto, numero(_valorMensal, 'Valor mensal (R\$)', obrigatorio: true, min: 0.01)),
          caixa(
              quarto,
              numero(_diaFechamento, 'Dia do fechamento',
                  ajuda: 'Vazio: último dia do mês', min: 1, max: 28, inteiro: true)),
          caixa(quarto, numero(_diaVencimento, 'Dia do vencimento', ajuda: 'Do boleto, no mês seguinte', min: 1, max: 28,
              inteiro: true)),
          if (_modalidade == 'franquia') ...[
            caixa(quarto, numero(_franqVisitas, 'Visitas incluídas/mês', ajuda: 'Vazio: sem limite de visitas', min: 1,
                inteiro: true)),
            caixa(quarto, numero(_excVisita, 'Visita excedente (R\$)', ajuda: 'Obrigatório com limite de visitas')),
            caixa(quarto, numero(_franqHoras, 'Horas incluídas/mês', ajuda: 'Vazio: sem limite de horas', min: 0.25)),
            caixa(quarto, numero(_excHora, 'Hora excedente (R\$)', ajuda: 'Obrigatório com limite de horas')),
            caixa(
              cheio,
              const Text(
                  'Visita = cada atendimento concluído no cliente. Hora = hora de relógio no local (do início ao fim do '
                  'atendimento), não a soma das horas de cada técnico.',
                  style: TextStyle(fontSize: 12, color: Cores.neutro)),
            ),
          ],
          caixa(
            quarto,
            lista<String>('Reajuste', _indice, indicesReajuste, (v) => setState(() => _indice = v)),
          ),
          if (_indice != 'nenhum')
            caixa(
                quarto,
                CampoData(
                    rotulo: 'Próximo reajuste',
                    valor: _proxReajuste,
                    habilitado: editar,
                    aoMudar: (d) => setState(() => _proxReajuste = d))),
          caixa(
            cheio,
            TextFormField(
              controller: _obs,
              enabled: editar,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Observações (ex.: cláusulas, o que não está coberto)'),
            ),
          ),
          if (editar)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _ocupado ? null : _salvar,
                icon: const Icon(Icons.check),
                label: Text(_novo ? 'Criar contrato' : 'Salvar dados'),
              ),
            ),
        ]);
      }),
    );
  }

  Widget _tabelaPrecos(bool editar) {
    final aparelho = _precos.where((p) => p['alvo'] != 'geral').toList();
    final geral = _precos.where((p) => p['alvo'] == 'geral').toList();
    // contrato_precos não tem FK para tipos_equipamento: o nome vem da lista de tipos.
    final nomesTipos = {for (final t in _tipos) t['id']: '${t['nome']}'};
    Widget linha(Map<String, dynamic> p) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('${p['descricao']}'),
          subtitle: Text([
            if (p['alvo'] != 'geral')
              p['tipo_equipamento_id'] == null ? 'Qualquer tipo' : nomesTipos[p['tipo_equipamento_id']] ?? 'Tipo',
            if (p['alvo'] != 'geral') faixaCapacidade(p['capacidade_min'], p['capacidade_max']),
            periodicidades[p['periodicidade']] ?? 'qualquer periodicidade',
          ].join(' · ')),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(dinheiro(p['valor']), style: const TextStyle(fontWeight: FontWeight.w700)),
            if (editar) ...[
              IconButton(
                tooltip: 'Alterar',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: _ocupado ? null : () => _editarPreco(p),
              ),
              IconButton(
                tooltip: 'Excluir',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: _ocupado ? null : () => _excluirPreco(p),
              ),
            ],
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text(
          'O preço de cada ciclo fechado (a OS do aparelho). Vale a linha mais específica: tipo do aparelho, depois '
          'periodicidade, depois a faixa de capacidade mais estreita. Uma linha sem tipo nem faixa serve de preço '
          'padrão. O preço fica gravado na OS: mudar a tabela depois não muda OS já feitas.',
          style: TextStyle(fontSize: 12, color: Cores.neutro)),
      const SizedBox(height: 8),
      if (_precos.isEmpty) const Text('Nenhum preço ainda.', style: TextStyle(color: Cores.neutro)),
      if (aparelho.isNotEmpty) ...[
        const Text('Ciclo de cada aparelho', style: TextStyle(fontWeight: FontWeight.w700, color: Cores.indigo700)),
        for (final p in aparelho) linha(p),
      ],
      if (geral.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('Atividades gerais do plano', style: TextStyle(fontWeight: FontWeight.w700, color: Cores.indigo700)),
        for (final p in geral) linha(p),
      ],
    ]);
  }

  Widget _conferencia() {
    final lista = ((_situacao?['conferencia'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final semPreco = lista.where((u) => u['preco'] == null).toList();
    final osSemPreco = (_situacao?['os_sem_preco'] as num?)?.toInt() ?? 0;
    if (lista.isEmpty) {
      return const Text('Nenhum aparelho em plano ativo deste cliente (e local).', style: TextStyle(color: Cores.neutro));
    }
    String rotulo(Map<String, dynamic> u) => [
          u['codigo'] ?? 'Geral: ${u['descricao']}',
          if (u['codigo'] != null && u['descricao'] != null) u['descricao'],
          if (u['tipo'] != null) u['tipo'],
          if (u['capacidade_btu'] != null) '${milhar(u['capacidade_btu'])} BTU/h',
          periodicidades[u['periodicidade']]?.toLowerCase() ?? u['periodicidade'],
        ].join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        '${lista.length} item(ns) nos planos ativos: ${lista.length - semPreco.length} com preço'
        '${semPreco.isEmpty ? '' : ', ${semPreco.length} sem preço'}.',
        style: TextStyle(fontWeight: FontWeight.w700, color: semPreco.isEmpty ? Cores.sucesso : Cores.alerta),
      ),
      if (osSemPreco > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('$osSemPreco OS do aparelho já feita(s) sem preço.', style: const TextStyle(color: Cores.erro)),
            if (_podeEditar)
              OutlinedButton.icon(
                onPressed: _ocupado ? null : _aplicarPrecos,
                icon: const Icon(Icons.price_check, size: 18),
                label: const Text('Aplicar a tabela nelas'),
              ),
          ]),
        ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: semPreco.isNotEmpty && semPreco.length <= 10,
        title: Text(semPreco.isEmpty ? 'Ver o preço de cada um' : 'Ver os sem preço primeiro'),
        children: [
          for (final u in [...semPreco, ...lista.where((u) => u['preco'] != null)])
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(rotulo(u)),
              subtitle: Text(u['preco'] == null
                  ? 'sem preço: inclua uma linha que sirva (ou um preço padrão)'
                  : '${(u['preco'] as Map)['descricao']}'),
              trailing: Text(u['preco'] == null ? '—' : dinheiro((u['preco'] as Map)['valor']),
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: u['preco'] == null ? Cores.erro : null)),
            ),
        ],
      ),
    ]);
  }

  Widget _consumo() {
    final c = (_situacao?['consumo'] as Map?)?.cast<String, dynamic>();
    if (c == null) return const LinearProgressIndicator(minHeight: 2);
    final modalidade = _modalidadeSalva;
    final franquia = modalidade == 'franquia';
    Widget numeroGrande(String valor, String rotulo, {Color? cor}) => SizedBox(
          width: 170,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(valor, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cor)),
            Text(rotulo, style: const TextStyle(color: Cores.neutro)),
          ]),
        );
    final fv = c['franquia_visitas'];
    final fh = c['franquia_horas'];
    final excedente = (num.tryParse('${c['excedente_valor']}') ?? 0) > 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IconButton(tooltip: 'Competência anterior', onPressed: () => _mudarMes(-1), icon: const Icon(Icons.chevron_left)),
        Text('${dataBr(c['ini'])} a ${dataBr(c['fim'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
        IconButton(tooltip: 'Próxima competência', onPressed: () => _mudarMes(1), icon: const Icon(Icons.chevron_right)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 24, runSpacing: 16, children: [
        if (franquia) ...[
          numeroGrande('${c['visitas']}${fv != null ? ' de ${numeroBr(fv)}' : ''}', 'visitas',
              cor: fv != null && (c['visitas'] as num) > (fv as num) ? Cores.erro : null),
          numeroGrande('${numeroBr(c['horas'])}${fh != null ? ' de ${numeroBr(fh)}' : ''} h', 'horas no local',
              cor: fh != null && (num.tryParse('${c['horas']}') ?? 0) > (num.tryParse('$fh') ?? 0) ? Cores.erro : null),
          numeroGrande(dinheiro(c['excedente_valor']), 'excedente', cor: excedente ? Cores.erro : null),
        ] else
          numeroGrande('${c['visitas']}', 'visitas (${numeroBr(c['horas'])} h no local)'),
        numeroGrande('${c['ciclos']}', modalidade == 'por_execucao'
            ? 'ciclos de preventiva (${dinheiro(c['valor_ciclos'])})'
            : 'ciclos de preventiva (cobertos)'),
        numeroGrande('${c['outras_os']}', 'outras OS concluídas (${dinheiro(c['valor_outras_os'])} em peças e serviços)'),
        numeroGrande(dinheiro(c['estimado']), modalidade == 'por_execucao'
            ? 'estimado (ciclos)'
            : 'estimado (mensalidade${franquia ? ' + excedente' : ''})'),
      ]),
      const SizedBox(height: 8),
      const Text('Estimativa para conferir. A fatura (com as peças e serviços avulsos) vem com o faturamento.',
          style: TextStyle(fontSize: 12, color: Cores.neutro)),
    ]);
  }

  Widget _reajuste(bool editar) {
    final historico = ((_situacao?['reajustes'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final aviso = _situacao?['reajuste_aviso'] == true;
    final prox = _contrato?['proximo_reajuste'];
    final indice = _indiceSalvo;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        indice == 'nenhum' ? 'Sem reajuste.' : '${indicesReajuste[indice] ?? indice} · próximo em ${dataBr(prox)}',
        style: TextStyle(fontWeight: FontWeight.w700, color: aviso ? Cores.alerta : null),
      ),
      if (aviso)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Está na hora do reajuste. Consulte o índice acumulado dos últimos 12 meses e aplique.',
              style: TextStyle(color: Cores.alerta)),
        ),
      const SizedBox(height: 8),
      if (historico.isEmpty) const Text('Nenhum reajuste aplicado ainda.', style: TextStyle(color: Cores.neutro)),
      for (final h in historico)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.trending_up, size: 18),
          title: Text('${dataBr(h['aplicado_em'])} · ${numeroBr(h['percentual'])}% '
              '(${indicesReajuste[h['indice']] ?? h['indice']})'),
          subtitle: h['observacao'] == null ? null : Text('${h['observacao']}'),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final editar = _podeEditar && !_ocupado;
    final c = _contrato;
    return ListView(padding: margemDaTela(context), children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/contratos'),
          icon: const Icon(Icons.arrow_back),
        ),
        Text(_novo ? 'Novo contrato' : '${c?['codigo'] ?? 'Contrato'}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (!_novo) ...[
          StatusChip(_modalidadeSalva, modalidadesContrato),
          StatusChip(_sit, situacoesContrato),
        ],
        if (_ocupado || _carregando)
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        if (!_novo && _sit == 'rascunho')
          FilledButton.icon(
            onPressed: _ocupado ? null : _ativar,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Ativar'),
          ),
        if (!_novo && _sit == 'ativo')
          OutlinedButton.icon(
            onPressed: _ocupado ? null : _encerrar,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Encerrar'),
          ),
        if (!_novo && _sit == 'encerrado')
          OutlinedButton.icon(
            onPressed: _ocupado
                ? null
                : () => _acao({'acao': 'reabrir', 'contrato_id': _contratoId}, sucesso: 'Contrato reaberto como rascunho.'),
            icon: const Icon(Icons.replay),
            label: const Text('Reabrir'),
          ),
      ]),
      if (!_novo && c != null)
        Padding(
          padding: const EdgeInsets.only(left: 52, bottom: 12),
          child: Text(
              '${(c['clientes'] as Map?)?['nome'] ?? ''} · ${(c['locais'] as Map?)?['nome'] ?? 'todos os locais'}',
              style: const TextStyle(color: Cores.neutro)),
        ),
      if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
      const SizedBox(height: 8),
      _secao('Dados do contrato', [_dados(_novo ? !_ocupado : editar)]),
      if (!_novo && c != null) ...[
        if (_sit == 'ativo') _secao('Consumo da competência', [_consumo()]),
        if (_modalidadeSalva == 'por_execucao' || _precos.isNotEmpty)
          _secao('Tabela de preços da preventiva', [_tabelaPrecos(editar)], acoes: [
            if (editar)
              OutlinedButton.icon(
                onPressed: () => _editarPreco(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Novo preço'),
              ),
          ]),
        if (_modalidadeSalva == 'por_execucao')
          _secao('Conferência: o preço de cada aparelho', [_conferencia()]),
        _secao('Reajuste', [_reajuste(editar)], acoes: [
          if (_sit == 'ativo' && _indiceSalvo != 'nenhum' && editar)
            OutlinedButton.icon(
              onPressed: _reajustar,
              icon: const Icon(Icons.trending_up, size: 18),
              label: const Text('Aplicar reajuste'),
            ),
        ]),
      ],
    ]);
  }
}

/// Inclusão ou alteração de uma linha da tabela de preços.
class _DialogoPreco extends StatefulWidget {
  const _DialogoPreco({required this.preco, required this.tipos});

  final Map<String, dynamic>? preco;
  final List<Map<String, dynamic>> tipos;

  @override
  State<_DialogoPreco> createState() => _DialogoPrecoState();
}

class _DialogoPrecoState extends State<_DialogoPreco> {
  late String _alvo = '${widget.preco?['alvo'] ?? 'aparelho'}';
  late final _descricao = TextEditingController(text: '${widget.preco?['descricao'] ?? ''}');
  late String? _tipo = widget.tipos.any((t) => t['id'] == widget.preco?['tipo_equipamento_id'])
      ? (widget.preco?['tipo_equipamento_id'] as String?)
      : null;
  late String? _periodicidade = periodicidades.containsKey(widget.preco?['periodicidade'])
      ? (widget.preco?['periodicidade'] as String?)
      : null;
  late final _min = TextEditingController(text: widget.preco?['capacidade_min'] == null ? '' : milhar(widget.preco?['capacidade_min']));
  late final _max = TextEditingController(text: widget.preco?['capacidade_max'] == null ? '' : milhar(widget.preco?['capacidade_max']));
  late final _valor = TextEditingController(text: widget.preco?['valor'] == null ? '' : numeroBr(widget.preco?['valor']));
  String? _erro;

  @override
  void dispose() {
    for (final c in [_descricao, _min, _max, _valor]) {
      c.dispose();
    }
    super.dispose();
  }

  /// "12.000" -> 12000 (o ponto aqui é de milhar).
  static num? _capacidade(String t) => num.tryParse(t.trim().replaceAll('.', '').replaceAll(',', '.'));

  void _sugerirDescricao() {
    if (_descricao.text.trim().isNotEmpty) return;
    String? tipo;
    for (final t in widget.tipos) {
      if (t['id'] == _tipo) tipo = '${t['nome']}';
    }
    final faixa = faixaCapacidade(_capacidade(_min.text), _capacidade(_max.text));
    _descricao.text = [tipo ?? 'Aparelho', if (faixa != 'qualquer capacidade') faixa].join(' ');
  }

  void _salvar() {
    final valor = lerNumero(_valor.text);
    final min = _min.text.trim().isEmpty ? null : _capacidade(_min.text);
    final max = _max.text.trim().isEmpty ? null : _capacidade(_max.text);
    if (_alvo == 'aparelho') _sugerirDescricao();
    if (_descricao.text.trim().isEmpty) return setState(() => _erro = 'Descreva o preço.');
    if (valor == null || valor < 0) return setState(() => _erro = 'Informe o valor (zero ou mais).');
    if ((_min.text.trim().isNotEmpty && min == null) || (_max.text.trim().isNotEmpty && max == null)) {
      return setState(() => _erro = 'Capacidade inválida.');
    }
    if (min != null && max != null && min > max) return setState(() => _erro = 'A mínima é maior que a máxima.');
    Navigator.of(context).pop(<String, dynamic>{
      'alvo': _alvo,
      'descricao': _descricao.text.trim(),
      'tipo_equipamento_id': _alvo == 'aparelho' ? _tipo : null,
      'periodicidade': _periodicidade,
      'capacidade_min': _alvo == 'aparelho' && min != null ? '$min' : null,
      'capacidade_max': _alvo == 'aparelho' && max != null ? '$max' : null,
      'valor': '$valor',
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget lista<T>(String rotulo, T valor, Map<T, String> opcoes, ValueChanged<T?> aoMudar) => InputDecorator(
          decoration: InputDecoration(labelText: rotulo),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: valor,
              isDense: true,
              isExpanded: true,
              items: [for (final e in opcoes.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value))],
              onChanged: aoMudar,
            ),
          ),
        );
    return AlertDialog(
      title: Text(widget.preco == null ? 'Novo preço' : 'Alterar preço'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          lista<String>('Vale para', _alvo, alvosPreco, (v) => setState(() => _alvo = v ?? _alvo)),
          const SizedBox(height: 12),
          if (_alvo == 'aparelho') ...[
            lista<String?>('Tipo do aparelho', _tipo,
                {null: 'Qualquer tipo', for (final t in widget.tipos) '${t['id']}': '${t['nome']}'},
                (v) => setState(() => _tipo = v)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _min,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Capacidade de (BTU/h)', hintText: 'vazio = desde 0'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _max,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'até (BTU/h)', hintText: 'vazio = sem limite'),
                ),
              ),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('TR e kW do cadastro do aparelho são convertidos (1 TR = 12.000 BTU/h). '
                  'Aparelho sem capacidade só pega linha sem faixa.',
                  style: TextStyle(fontSize: 12, color: Cores.neutro)),
            ),
            const SizedBox(height: 12),
          ],
          lista<String?>('Periodicidade', _periodicidade, {null: 'Qualquer periodicidade', ...periodicidades},
              (v) => setState(() => _periodicidade = v)),
          const SizedBox(height: 12),
          TextField(
            controller: _descricao,
            decoration: InputDecoration(
                labelText: 'Descrição (sai na OS)',
                hintText: _alvo == 'aparelho' ? 'Ex.: Split até 12.000 BTU/h' : 'Ex.: Avaliação da qualidade do ar'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _valor,
            autofocus: widget.preco != null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor do ciclo (R\$) *'),
          ),
          if (_erro != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_erro!, style: const TextStyle(color: Cores.erro)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _salvar, child: const Text('Salvar')),
      ],
    );
  }
}

/// O percentual do reajuste (ex.: IPCA acumulado dos 12 meses).
class _DialogoReajuste extends StatefulWidget {
  const _DialogoReajuste({required this.indice});

  final String indice;

  @override
  State<_DialogoReajuste> createState() => _DialogoReajusteState();
}

class _DialogoReajusteState extends State<_DialogoReajuste> {
  final _pct = TextEditingController();
  final _obs = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _pct.dispose();
    _obs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Aplicar reajuste'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Informe o ${widget.indice} acumulado. O percentual vale para a tabela de preços, o valor mensal e os '
              'excedentes. As OS já feitas não mudam.'),
          const SizedBox(height: 12),
          TextField(
            controller: _pct,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Percentual (%)', hintText: 'Ex.: 4,62'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _obs,
            decoration: const InputDecoration(labelText: 'Observação (opcional)', hintText: 'Ex.: IPCA set/25 a ago/26'),
          ),
          if (_erro != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_erro!, style: const TextStyle(color: Cores.erro)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final n = lerNumero(_pct.text);
            if (n == null || n < -50 || n > 100) {
              setState(() => _erro = 'Percentual de -50 a 100.');
              return;
            }
            Navigator.of(context).pop(<String, dynamic>{'percentual': '$n', 'observacao': _obs.text.trim()});
          },
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}
