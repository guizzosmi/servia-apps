import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/cobranca.dart';
import '../servicos/contratos.dart' show modalidadesContrato;
import '../servicos/status.dart';
import '../widgets/itens_os.dart' show dinheiro, numeroBr;
import '../widgets/margem.dart';

/// Um cliente na lista: as OS e as mensalidades a cobrar.
typedef _Grupo = ({String id, String nome, List<Map<String, dynamic>> os, List<Map<String, dynamic>> ct});

/// A cobrar (guia 31): o que foi feito e ainda não foi cobrado, por
/// cliente. O escritório confere, copia o texto para a nota (MarketUP) e
/// registra: com nota (número), sem nota ou não cobrar.
class CobrarTela extends StatefulWidget {
  const CobrarTela({super.key});

  @override
  State<CobrarTela> createState() => _CobrarTelaState();
}

class _CobrarTelaState extends State<CobrarTela> {
  bool _historico = false;
  bool _carregando = true;
  String? _erro;
  Map<String, dynamic> _dados = const {};
  final _busca = TextEditingController();

  /// Selecionados (sempre de um cliente só): `os:<id>` e `ct:<contrato>:<ini>`.
  final _marcados = <String>{};
  String? _clienteMarcado;

  /// Histórico: 0 = este mês, 1 = mês passado.
  int _mes = 0;

  /// Só vale a resposta da última carga (troca rápida de aba ou de mês).
  int _geracao = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final geracao = ++_geracao;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final hoje = DateTime.now();
      final ini = DateTime(hoje.year, hoje.month - _mes, 1);
      final fim = DateTime(ini.year, ini.month + 1, 0);
      final r = _historico
          ? await listaACobrar(resolvidas: true, de: dataIso(ini), ate: dataIso(fim))
          : await listaACobrar();
      if (!mounted || geracao != _geracao) return;
      setState(() {
        _dados = r;
        _marcados.clear();
        _clienteMarcado = null;
      });
    } catch (e) {
      if (mounted && geracao == _geracao) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted && geracao == _geracao) setState(() => _carregando = false);
    }
  }

  void _limparMarcados() {
    _marcados.clear();
    _clienteMarcado = null;
  }

  void _aviso(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));
  }

  Future<void> _executar(Future<Object?> Function() acao, String sucesso) async {
    try {
      await acao();
      _aviso(sucesso);
    } catch (e) {
      _aviso(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) _carregar();
    }
  }

  // ------------------------------------------------------------------
  // Dados
  // ------------------------------------------------------------------

  List<Map<String, dynamic>> get _os => ((_dados['os'] as List?) ?? const []).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _contratos =>
      ((_dados['contratos'] as List?) ?? const []).cast<Map<String, dynamic>>();

  static String _chaveCt(Map c) => 'ct:${c['contrato_id']}:${c['competencia_ini']}';

  /// Cliente -> (nome, OS, mensalidades), filtrado pela busca.
  List<_Grupo> get _grupos {
    final b = _busca.text.trim().toLowerCase();
    final porCliente = <String, _Grupo>{};
    _Grupo grupo(Map x) =>
        porCliente.putIfAbsent('${x['cliente_id']}', () => (id: '${x['cliente_id']}', nome: '${x['cliente'] ?? ''}', os: [], ct: []));
    for (final o in _os) {
      if (b.isNotEmpty && !'${o['cliente']} ${o['codigo']} ${o['local']}'.toLowerCase().contains(b)) continue;
      grupo(o).os.add(o);
    }
    for (final c in _contratos) {
      if (b.isNotEmpty && !'${c['cliente']} ${c['codigo']}'.toLowerCase().contains(b)) continue;
      grupo(c).ct.add(c);
    }
    return porCliente.values.toList()..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
  }

  List<Map<String, dynamic>> get _osMarcadas => [for (final o in _os) if (_marcados.contains('os:${o['id']}')) o];
  List<Map<String, dynamic>> get _ctMarcados => [for (final c in _contratos) if (_marcados.contains(_chaveCt(c))) c];

  num get _somaMarcada =>
      _osMarcadas.fold<num>(0, (s, o) => s + (num.tryParse('${o['valor_total'] ?? 0}') ?? 0)) +
      _ctMarcados.fold<num>(0, (s, c) => s + (num.tryParse('${c['valor'] ?? 0}') ?? 0));

  void _marcar(String cliente, String chave, bool sim) {
    setState(() {
      if (_clienteMarcado != cliente) {
        _marcados.clear();
        _clienteMarcado = cliente;
      }
      sim ? _marcados.add(chave) : _marcados.remove(chave);
      if (_marcados.isEmpty) _clienteMarcado = null;
    });
  }

  // ------------------------------------------------------------------
  // Ações
  // ------------------------------------------------------------------

  Future<void> _copiar() async {
    await Clipboard.setData(ClipboardData(text: textoParaNota(os: _osMarcadas, contratos: _ctMarcados)));
    _aviso('Texto copiado: cole na descrição da nota.');
  }

  Future<void> _registrar() async {
    final os = _osMarcadas;
    final cts = _ctMarcados;
    if (cts.length > 1) {
      _aviso('Uma mensalidade por cobrança: registre uma competência de cada vez.', erro: true);
      return;
    }
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoRegistrar(
        sugerido: _somaMarcada,
        cliente: '${(os.isNotEmpty ? os.first : cts.first)['cliente'] ?? ''}',
        mesEmAberto: cts.any((c) => c['em_aberto'] == true),
      ),
    );
    if (r == null) return;
    await _executar(
      () => registrarCobranca({
        'os_ids': [for (final o in os) o['id']],
        if (cts.isNotEmpty) 'contrato_id': cts.first['contrato_id'],
        if (cts.isNotEmpty) 'competencia_ini': cts.first['competencia_ini'],
        ...r,
      }),
      r['forma'] == 'nota' ? 'Cobrança registrada com a nota ${r['nf_numero']}.' : 'Cobrança registrada (sem nota).',
    );
  }

  Future<void> _naoCobrar() async {
    final os = _osMarcadas;
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Não cobrar ${os.length == 1 ? os.first['codigo'] : '${os.length} OS'}?'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final m in const ['Garantia', 'Cortesia', 'Retrabalho', 'Coberto pelo contrato'])
                  ActionChip(label: Text(m), onPressed: () => setState(() => motivo.text = m)),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: motivo,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Por que não vai cobrar?'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: motivo.text.trim().isEmpty ? null : () => Navigator.of(ctx).pop(true),
              child: const Text('Não cobrar'),
            ),
          ],
        ),
      ),
    );
    final texto = motivo.text.trim();
    motivo.dispose();
    if (ok != true) return;
    await _executar(() => naoCobrar([for (final o in os) '${o['id']}'], texto),
        os.length == 1 ? '${os.first['codigo']} não será cobrada.' : '${os.length} OS não serão cobradas.');
  }

  Future<void> _desfazer(String titulo, Future<Object?> Function() acao) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: const Text('As OS voltam para "a cobrar". Se a nota já foi emitida, cancele também no sistema de notas.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Desfazer')),
        ],
      ),
    );
    if (ok == true) await _executar(acao, 'Desfeito.');
  }

  // ------------------------------------------------------------------
  // Tela
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final grupos = _historico ? const <_Grupo>[] : _grupos;
    final soma = _os.fold<num>(0, (s, o) => s + (num.tryParse('${o['valor_total'] ?? 0}') ?? 0)) +
        _contratos.where((c) => c['em_aberto'] != true).fold<num>(0, (s, c) => s + (num.tryParse('${c['valor'] ?? 0}') ?? 0));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(padding: margemDaTela(context), children: [
          Text('A cobrar', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('O que foi feito e ainda não foi cobrado. Marque as OS (e a mensalidade) de um cliente, copie o '
              'texto para a nota e registre como cobrou: com nota, sem nota ou não cobrar.',
              style: TextStyle(color: Cores.neutro)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('A cobrar')),
                ButtonSegment(value: true, label: Text('Já resolvidas')),
              ],
              selected: {_historico},
              onSelectionChanged: (v) {
                setState(() {
                  _historico = v.first;
                  _limparMarcados();
                });
                _carregar();
              },
            ),
            if (_historico)
              for (final m in const [(0, 'Este mês'), (1, 'Mês passado')])
                ChoiceChip(
                  label: Text(m.$2),
                  selected: _mes == m.$1,
                  onSelected: (_) {
                    setState(() => _mes = m.$1);
                    _carregar();
                  },
                ),
            if (!_historico)
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _busca,
                  // O que some da lista pela busca não fica marcado escondido.
                  onChanged: (_) => setState(_limparMarcados),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Cliente, OS, local',
                  ),
                ),
              ),
            IconButton(tooltip: 'Atualizar', onPressed: _carregando ? null : _carregar, icon: const Icon(Icons.refresh)),
          ]),
          if (_carregando) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
          if (_erro != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_erro!, style: const TextStyle(color: Cores.erro))),
          if (!_historico && !_carregando && _erro == null) ...[
            const SizedBox(height: 8),
            Text('${_os.length} OS · ${dinheiro(soma)} (sem contar as mensalidades do mês em aberto)',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (grupos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('Nada a cobrar.', style: TextStyle(color: Cores.neutro))),
              ),
            for (final g in grupos) _cartaoCliente(g),
          ],
          if (_historico && !_carregando && _erro == null) ..._historicoLista(),
          const SizedBox(height: 80),
        ]),
      ),
      if (_marcados.isNotEmpty) _barraDeAcoes(),
    ]);
  }

  Widget _cartaoCliente(_Grupo g) {
    // "Marcar tudo": as OS e uma mensalidade fechada (a mais antiga); o mês em
    // aberto e as outras competências se marcam uma a uma.
    final fechadas = g.ct.where((c) => c['em_aberto'] != true).toList()
      ..sort((a, b) => '${a['competencia_ini']}'.compareTo('${b['competencia_ini']}'));
    final chaves = [for (final o in g.os) 'os:${o['id']}', if (fechadas.isNotEmpty) _chaveCt(fechadas.first)];
    final todos = _clienteMarcado == g.id && chaves.every(_marcados.contains);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Checkbox(
              value: todos,
              onChanged: (v) {
                setState(() {
                  _marcados.clear();
                  _clienteMarcado = v == true ? g.id : null;
                  if (v == true) _marcados.addAll(chaves);
                });
              },
            ),
            Expanded(child: Text(g.nome, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            Text('${g.os.length} OS${g.ct.isEmpty ? '' : ' · ${g.ct.length} mensalidade(s)'}',
                style: const TextStyle(color: Cores.neutro)),
          ]),
          for (final c in g.ct) _linhaContrato(g.id, c),
          for (final o in g.os) _linhaOs(g.id, o),
        ]),
      ),
    );
  }

  Widget _linhaContrato(String cliente, Map<String, dynamic> c) {
    final chave = _chaveCt(c);
    final exc = num.tryParse('${c['excedente_valor'] ?? 0}') ?? 0;
    return CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: _marcados.contains(chave),
      onChanged: (v) => _marcar(cliente, chave, v == true),
      title: Text('Mensalidade ${c['codigo']} · ${diaBr(c['competencia_ini'])} a ${diaBr(c['competencia_fim'])}'
          '${c['em_aberto'] == true ? ' (mês em aberto)' : ''}'),
      subtitle: exc > 0
          ? Text('${dinheiro(c['valor_mensal'])} + excedente ${dinheiro(exc)} '
              '(${numeroBr(c['excedente_visitas'])} visita(s), ${numeroBr(c['excedente_horas'])} h)')
          : null,
      secondary: Text(dinheiro(c['valor']), style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _linhaOs(String cliente, Map<String, dynamic> o) {
    final chave = 'os:${o['id']}';
    final itens = ((o['itens'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final contrato = o['contrato'] as Map?;
    final valor = num.tryParse('${o['valor_total'] ?? 0}') ?? 0;
    final selos = <(String, Color)>[
      if (contrato != null)
        ('${contrato['codigo']} · ${modalidadesContrato[contrato['modalidade']]?.texto ?? contrato['modalidade']}',
            Cores.indigo500),
      if (o['sem_preco'] == true) ('Sem preço no contrato', Cores.erro),
      if (o['garantia_status'] == 'sugerida') ('Garantia a confirmar', Cores.alerta),
      if (valor == 0 && o['sem_preco'] != true) ('Valor zero', Cores.alerta),
    ];
    return CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: _marcados.contains(chave),
      onChanged: (v) => _marcar(cliente, chave, v == true),
      title: Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        InkWell(
          onTap: () async {
            await context.push('/os/${o['id']}');
            if (mounted) _carregar();
          },
          child: Text('${o['codigo']}',
              style: const TextStyle(fontWeight: FontWeight.w800, color: Cores.indigo700, decoration: TextDecoration.underline)),
        ),
        Text('${diaBr(o['concluida_em'])} · ${o['local'] ?? ''}'),
        for (final s in selos)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: s.$2.withValues(alpha: .1), borderRadius: BorderRadius.circular(6)),
            child: Text(s.$1, style: TextStyle(fontSize: 11, color: s.$2, fontWeight: FontWeight.w700)),
          ),
      ]),
      subtitle: Text(
        [
          oQueFoiFeito(o),
          for (final i in itens) '${numeroBr(i['quantidade'])} ${i['unidade'] ?? ''} ${i['descricao']} ${dinheiro(i['total'])}',
          if (itens.isEmpty) 'Sem peças nem serviços lançados na OS',
        ].where((x) => x.isNotEmpty).join('\n'),
      ),
      secondary: Text(dinheiro(valor), style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _barraDeAcoes() {
    final soOs = _ctMarcados.isEmpty;
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${_marcados.length} marcado(s) · ${dinheiro(_somaMarcada)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            OutlinedButton.icon(onPressed: _copiar, icon: const Icon(Icons.copy, size: 18), label: const Text('Copiar texto da nota')),
            FilledButton.icon(
              onPressed: _registrar,
              icon: const Icon(Icons.receipt_long, size: 18),
              label: const Text('Registrar cobrança'),
            ),
            if (soOs) TextButton(onPressed: _naoCobrar, child: const Text('Não cobrar')),
            TextButton(
              onPressed: () => setState(() {
                _marcados.clear();
                _clienteMarcado = null;
              }),
              child: const Text('Limpar'),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _historicoLista() {
    final res = _dados['resolvidas'] as Map? ?? const {};
    final cobrancas = ((res['cobrancas'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final nao = ((res['nao_cobrar'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final total = cobrancas.fold<num>(0, (s, b) => s + (num.tryParse('${b['valor'] ?? 0}') ?? 0));
    return [
      const SizedBox(height: 12),
      Text('Cobranças registradas: ${cobrancas.length} · ${dinheiro(total)}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      if (cobrancas.isEmpty)
        const Padding(padding: EdgeInsets.all(12), child: Text('Nenhuma.', style: TextStyle(color: Cores.neutro))),
      for (final b in cobrancas)
        Card(
          margin: const EdgeInsets.only(top: 8),
          child: ListTile(
            title: Text('${b['cliente']} · ${dinheiro(b['valor'])}'
                '${_diferente(b['valor'], b['valor_sugerido']) ? ' (sugerido ${dinheiro(b['valor_sugerido'])})' : ''}'),
            subtitle: Text([
              b['forma'] == 'nota' ? 'NF ${b['nf_numero']}${b['nf_data'] != null ? ' de ${diaBr(b['nf_data'])}' : ''}' : 'Sem nota',
              'registrada em ${diaBr(b['criado_em'])}',
              if (((b['os'] as List?) ?? const []).isNotEmpty) (b['os'] as List).join(', '),
              if (b['contrato'] != null)
                'Mensalidade ${b['contrato']} (${diaBr(b['competencia_ini'])} a ${diaBr(b['competencia_fim'])})',
              if (b['observacao'] != null) '${b['observacao']}',
            ].join(' · ')),
            trailing: TextButton(
              onPressed: () => _desfazer('Desfazer esta cobrança?', () => desfazerCobranca(cobrancaId: '${b['id']}')),
              child: const Text('Desfazer'),
            ),
          ),
        ),
      const SizedBox(height: 16),
      Text('Não cobradas: ${nao.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      for (final o in nao)
        Card(
          margin: const EdgeInsets.only(top: 8),
          child: ListTile(
            title: Text('${o['codigo']} · ${o['cliente']} · ${dinheiro(o['valor_total'])}'),
            subtitle: Text('${diaBr(o['concluida_em'])} · ${o['garantia'] == true ? 'Garantia' : (o['motivo'] ?? '')}'),
            trailing: o['garantia'] == true
                ? null
                : TextButton(
                    onPressed: () => _desfazer('Cobrar de novo a ${o['codigo']}?', () => desfazerCobranca(osId: '${o['id']}')),
                    child: const Text('Cobrar de novo'),
                  ),
          ),
        ),
    ];
  }
}

bool _diferente(Object? a, Object? b) =>
    ((num.tryParse('${a ?? 0}') ?? 0) - (num.tryParse('${b ?? 0}') ?? 0)).abs() >= 0.005;

/// Forma (com nota / sem nota), número e data da nota, valor e observação.
class _DialogoRegistrar extends StatefulWidget {
  const _DialogoRegistrar({required this.sugerido, required this.cliente, this.mesEmAberto = false});

  final num sugerido;
  final String cliente;
  final bool mesEmAberto;

  @override
  State<_DialogoRegistrar> createState() => _DialogoRegistrarState();
}

class _DialogoRegistrarState extends State<_DialogoRegistrar> {
  String _forma = 'nota';
  late final _valor = TextEditingController(text: widget.sugerido.toStringAsFixed(2).replaceAll('.', ','));
  final _nf = TextEditingController();
  final _obs = TextEditingController();
  DateTime _dataNf = DateTime.now();

  @override
  void dispose() {
    _valor.dispose();
    _nf.dispose();
    _obs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valor = lerValor(_valor.text);
    final pronto = valor != null && valor >= 0 && (_forma == 'sem_nota' || _nf.text.trim().isNotEmpty);
    return AlertDialog(
      title: Text('Registrar cobrança · ${widget.cliente}'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'nota', label: Text('Com nota')),
              ButtonSegment(value: 'sem_nota', label: Text('Sem nota')),
            ],
            selected: {_forma},
            onSelectionChanged: (v) => setState(() => _forma = v.first),
          ),
          if (widget.mesEmAberto)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('A mensalidade marcada é do mês em aberto: o excedente da franquia ainda pode mudar.',
                  style: TextStyle(color: Cores.alerta)),
            ),
          const SizedBox(height: 12),
          if (_forma == 'nota')
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _nf,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Número da nota'),
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                icon: const Icon(Icons.event, size: 18),
                label: Text(dataBr(dataIso(_dataNf))),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _dataNf,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (d != null) setState(() => _dataNf = d);
                },
              ),
            ]),
          TextField(
            controller: _valor,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Valor cobrado (R\$)',
              errorText: _valor.text.trim().isNotEmpty && valor == null ? 'Valor inválido' : null,
              helperText: 'Sugerido: ${dinheiro(widget.sugerido)}. Ajuste se cobrou diferente.',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _obs,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Observação (opcional)'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: !pronto
              ? null
              : () => Navigator.of(context).pop({
                    'forma': _forma,
                    'valor': valor,
                    if (_forma == 'nota') 'nf_numero': _nf.text.trim(),
                    if (_forma == 'nota') 'nf_data': dataIso(_dataNf),
                    if (_obs.text.trim().isNotEmpty) 'observacao': _obs.text.trim(),
                  }),
          child: const Text('Registrar'),
        ),
      ],
    );
  }
}
