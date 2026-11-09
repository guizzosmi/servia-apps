import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cobranca/widgets_cobranca.dart' show BotaoTitulo;
import '../servicos/status.dart';
import '../widgets/itens_os.dart' show dinheiro, lerNumero;
import '../widgets/margem.dart';
import '../widgets/pix.dart';

/// Caixa simples e margem (guia 67): o que entrou, o que saiu e o que sobrou
/// no mês; o que falta receber; e a margem de cada OS (valor menos o custo das
/// peças) e de cada contrato. Gestor e financeiro.
class CaixaTela extends StatefulWidget {
  const CaixaTela({super.key});

  @override
  State<CaixaTela> createState() => _CaixaTelaState();
}

const _categorias = {
  'recebimento': 'Recebimento',
  'servico': 'Serviço',
  'combustivel': 'Combustível',
  'pecas': 'Peças',
  'gas': 'Gás',
  'ferramentas': 'Ferramentas',
  'veiculo': 'Veículo',
  'salarios': 'Salários',
  'aluguel': 'Aluguel',
  'impostos': 'Impostos',
  'contador': 'Contador',
  'sistemas': 'Sistemas',
  'retirada': 'Retirada do dono',
  'outro': 'Outro',
};
const _formas = {'pix': 'Pix', 'dinheiro': 'Dinheiro', 'cartao': 'Cartão', 'boleto': 'Boleto', 'transferencia': 'Transferência', 'outro': 'Outro'};
const _meses = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

class _CaixaTelaState extends State<CaixaTela> {
  late DateTime _mes;
  Map<String, dynamic>? _r;
  Map<String, dynamic>? _m;
  bool _carregando = true;
  String? _erro;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    final h = DateTime.now();
    _mes = DateTime(h.year, h.month);
    _carregar();
  }

  (String, String) get _periodo {
    final fim = DateTime(_mes.year, _mes.month + 1, 0);
    return (dataIso(_mes), dataIso(fim));
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final (de, ate) = _periodo;
      final r = await _db.rpc('caixa_resumo', params: {
        'p': {'de': de, 'ate': ate}
      });
      final m = await _db.rpc('os_margem', params: {
        'p': {'de': de, 'ate': ate}
      });
      if (mounted) {
        setState(() {
          _r = Map<String, dynamic>.from(r as Map);
          _m = Map<String, dynamic>.from(m as Map);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _avisar(String t, {bool erro = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Cores.erro : null));

  Future<void> _acao(Map<String, dynamic> p, String ok) async {
    try {
      await _db.rpc('caixa_acao', params: {'p': p});
      _avisar(ok);
      _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _lancar(String tipo) async {
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _DialogoLancamento(tipo: tipo));
    if (p != null) await _acao({'acao': 'lancar', 'tipo': tipo, ...p}, tipo == 'entrada' ? 'Entrada lançada.' : 'Saída lançada.');
  }

  Future<void> _receber(Map<String, dynamic> c) async {
    final p = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => _DialogoLancamento(tipo: 'entrada', recebimento: c));
    if (p != null) await _acao({'acao': 'receber', 'cobranca_id': c['id'], ...p}, 'Recebimento lançado.');
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return DefaultTabController(
      length: 3,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: margemDaTela(context).copyWith(bottom: 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text('Caixa', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: 'Mês anterior',
                onPressed: () {
                  setState(() => _mes = DateTime(_mes.year, _mes.month - 1));
                  _carregar();
                },
                icon: const Icon(Icons.chevron_left),
              ),
              Text('${_meses[_mes.month - 1]} de ${_mes.year}', style: const TextStyle(fontWeight: FontWeight.w600)),
              IconButton(
                tooltip: 'Próximo mês',
                onPressed: () {
                  setState(() => _mes = DateTime(_mes.year, _mes.month + 1));
                  _carregar();
                },
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: () => _lancar('entrada'), icon: const Icon(Icons.add), label: const Text('Entrada')),
              OutlinedButton.icon(onPressed: () => _lancar('saida'), icon: const Icon(Icons.remove), label: const Text('Saída')),
            ]),
            const SizedBox(height: 8),
            if (_carregando) const LinearProgressIndicator(minHeight: 2),
            if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
            if (r != null) _numeros(r),
            const TabBar(isScrollable: true, tabs: [Tab(text: 'Lançamentos'), Tab(text: 'A receber'), Tab(text: 'Margem')]),
          ]),
        ),
        Expanded(
          child: TabBarView(children: [_abaLancamentos(), _abaReceber(), _abaMargem()]),
        ),
      ]),
    );
  }

  Widget _numeros(Map<String, dynamic> r) {
    num n(Object? v) => num.tryParse('${v ?? 0}') ?? 0;
    final entrou = n(r['entrou']), saiu = n(r['saiu']);
    final os = Map<String, dynamic>.from((r['os_concluidas'] as Map?) ?? const {});
    Widget card(String t, String v, {String? d, Color? cor}) => SizedBox(
          width: 210,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: const TextStyle(color: Cores.neutro)),
                Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cor)),
                if (d != null) Text(d, style: const TextStyle(fontSize: 12, color: Cores.neutro)),
              ]),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        card('Entrou', dinheiro(entrou), cor: Cores.sucesso),
        card('Saiu', dinheiro(saiu), cor: Cores.erro),
        card('Sobrou', dinheiro(entrou - saiu), cor: entrou - saiu < 0 ? Cores.erro : Cores.indigo700),
        card('A receber', dinheiro(r['a_receber']), d: '${r['a_receber_qtd']} cobrança(s)'),
        card('OS concluídas', dinheiro(os['valor']),
            d: '${os['qtd'] ?? 0} OS · peças ${dinheiro(os['custo_pecas'])} · margem ${dinheiro(n(os['valor']) - n(os['custo_pecas']))}'),
      ]),
    );
  }

  Widget _abaLancamentos() {
    final l = ((_r?['lancamentos'] as List?) ?? const []).cast<Map>();
    if (!_carregando && l.isEmpty) {
      return Padding(
        padding: margemDaTela(context),
        child: const Text('Nenhum lançamento neste mês. Lance as entradas e saídas (combustível, peças, salários...) '
            'e receba as cobranças na aba "A receber".', style: TextStyle(color: Cores.neutro)),
      );
    }
    return ListView(padding: margemDaTela(context), children: [
      for (final x in l)
        ListTile(
          dense: true,
          leading: Icon(x['tipo'] == 'entrada' ? Icons.south_west : Icons.north_east,
              color: x['tipo'] == 'entrada' ? Cores.sucesso : Cores.erro),
          title: Text('${x['descricao']}'),
          subtitle: Text([
            dataBr(x['data']),
            _categorias[x['categoria']] ?? '${x['categoria']}',
            if (x['forma'] != null) _formas[x['forma']] ?? '${x['forma']}',
          ].join(' · ')),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${x['tipo'] == 'entrada' ? '+' : '-'} ${dinheiro(x['valor'])}',
                style: TextStyle(fontWeight: FontWeight.w700, color: x['tipo'] == 'entrada' ? Cores.sucesso : Cores.erro)),
            IconButton(
              tooltip: 'Excluir',
              onPressed: () => _acao({'acao': 'excluir', 'id': x['id']}, 'Lançamento excluído.'),
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
          ]),
        ),
    ]);
  }

  Widget _abaReceber() {
    final l = ((_r?['cobrancas_abertas'] as List?) ?? const []).cast<Map>();
    if (!_carregando && l.isEmpty) {
      return Padding(
        padding: margemDaTela(context),
        child: const Text('Nada a receber. As cobranças registradas em "A cobrar" aparecem aqui até serem recebidas.',
            style: TextStyle(color: Cores.neutro)),
      );
    }
    return ListView(padding: margemDaTela(context), children: [
      for (final c in l)
        ListTile(
          title: Text('${c['cliente'] ?? ''} · ${dinheiro(c['valor'])}'),
          subtitle: Text([
            'cobrado ${dataBr(c['criado_em'])}',
            c['forma'] == 'nota' ? 'NF ${c['nf_numero'] ?? ''}' : 'sem nota',
          ].join(' · ')),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            // Guia 100: boleto/Pix registrado (some no modo manual).
            BotaoTitulo(cobrancaId: '${c['id']}', aoMudar: _carregar),
            OutlinedButton.icon(
              onPressed: () => mostrarPix(context, cobrancaId: '${c['id']}'),
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Pix'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => _receber(Map<String, dynamic>.from(c)),
              child: const Text('Recebi'),
            ),
          ]),
        ),
    ]);
  }

  Widget _abaMargem() {
    final os = ((_m?['os'] as List?) ?? const []).cast<Map>();
    final ctr = ((_m?['contratos'] as List?) ?? const []).cast<Map>();
    num n(Object? v) => num.tryParse('${v ?? 0}') ?? 0;
    return ListView(padding: margemDaTela(context), children: [
      const Text('Margem = valor da OS menos o custo das peças (o preço de custo do cadastro; a entrada do estoque '
          'atualiza). As piores primeiro. As horas no cliente ajudam a ver o que pesou.',
          style: TextStyle(color: Cores.neutro)),
      const SizedBox(height: 8),
      if (ctr.isNotEmpty) ...[
        const Text('Contratos (mensalidade cobrada contra o custo das peças das OS do contrato)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        for (final k in ctr)
          ListTile(
            dense: true,
            title: Text('${k['codigo'] ?? ''} · ${k['cliente'] ?? ''}'),
            subtitle: Text('cobrado ${dinheiro(k['cobrado'])} · peças ${dinheiro(k['custo_pecas'])} · ${k['os']} OS'),
            trailing: Text(dinheiro(k['resultado']),
                style: TextStyle(fontWeight: FontWeight.w700, color: n(k['resultado']) < 0 ? Cores.erro : Cores.sucesso)),
            onTap: () => context.push('/contratos/${k['contrato_id']}'),
          ),
        const Divider(),
      ],
      const Text('OS concluídas no mês', style: TextStyle(fontWeight: FontWeight.w700)),
      if (!_carregando && os.isEmpty)
        const Padding(padding: EdgeInsets.all(8), child: Text('Nenhuma OS concluída no mês.', style: TextStyle(color: Cores.neutro))),
      for (final o in os)
        ListTile(
          dense: true,
          title: Text('${o['codigo']} · ${o['cliente'] ?? ''}'),
          subtitle: Text('valor ${dinheiro(o['valor'])} · peças ${dinheiro(o['custo_pecas'])} · ${o['horas']} h no cliente'),
          trailing: Text(dinheiro(o['margem']),
              style: TextStyle(fontWeight: FontWeight.w700, color: n(o['margem']) < 0 ? Cores.erro : Cores.sucesso)),
          onTap: () => context.push('/os/${o['os_id']}'),
        ),
    ]);
  }
}

class _DialogoLancamento extends StatefulWidget {
  const _DialogoLancamento({required this.tipo, this.recebimento});

  final String tipo;
  final Map<String, dynamic>? recebimento;

  @override
  State<_DialogoLancamento> createState() => _DialogoLancamentoState();
}

class _DialogoLancamentoState extends State<_DialogoLancamento> {
  final _desc = TextEditingController();
  late final _valor = TextEditingController(
      text: widget.recebimento == null ? '' : '${widget.recebimento!['valor'] ?? ''}'.replaceAll('.', ','));
  late String _categoria = widget.tipo == 'entrada' ? 'servico' : 'combustivel';
  String _forma = 'pix';
  DateTime _data = DateTime.now();
  String? _erro;

  @override
  void dispose() {
    _desc.dispose();
    _valor.dispose();
    super.dispose();
  }

  Widget _lista(String rotulo, String valor, Map<String, String> opcoes, ValueChanged<String> mudou) => InputDecorator(
        decoration: InputDecoration(labelText: rotulo),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: valor,
            isDense: true,
            isExpanded: true,
            items: [for (final o in opcoes.entries) DropdownMenuItem(value: o.key, child: Text(o.value))],
            onChanged: (v) => mudou(v ?? valor),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rec = widget.recebimento;
    final categorias = Map.of(_categorias)..remove('recebimento');
    return AlertDialog(
      title: Text(rec != null ? 'Recebimento · ${rec['cliente'] ?? ''}' : widget.tipo == 'entrada' ? 'Entrada' : 'Saída'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (rec == null) ...[
              TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Descrição *')),
              const SizedBox(height: 8),
              _lista('Categoria', _categoria, categorias, (v) => setState(() => _categoria = v)),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor (R\$) *'),
            ),
            const SizedBox(height: 8),
            _lista('Forma', _forma, _formas, (v) => setState(() => _forma = v)),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Data'),
              child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                      context: context, initialDate: _data, firstDate: DateTime(2024), lastDate: DateTime(2100));
                  if (d != null) setState(() => _data = d);
                },
                child: Text(dataBr(dataIso(_data))),
              ),
            ),
            if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final v = lerNumero(_valor.text);
            if (v == null || v <= 0 || (rec == null && _desc.text.trim().isEmpty)) {
              setState(() => _erro = 'Informe a descrição e o valor.');
              return;
            }
            Navigator.pop(context, {
              if (rec == null) 'descricao': _desc.text.trim(),
              if (rec == null) 'categoria': _categoria,
              'valor': v,
              'forma': _forma,
              'data': dataIso(_data),
            });
          },
          child: const Text('Lançar'),
        ),
      ],
    );
  }
}
