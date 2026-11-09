import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/comercial.dart' show reais;
import '../servicos/status.dart';
import '../widgets/itens_os.dart' show lerNumero, numeroBr;
import '../widgets/margem.dart';
import 'medicoes_tela.dart' show corDaMedicao, mesBr, situacoesMedicao;
import 'servico.dart';
import 'widgets.dart';

const formasCobranca = {
  '': 'Cada equipamento com a sua periodicidade',
  'dia': 'Por dia',
  'semana': 'Por semana',
  'mes': 'Por mês',
  'obra': 'Por obra (valor fechado)',
};

/// Cobrança de um contrato de locação (guia 102): forma (dia, semana, mês ou por obra), dia da medição, franquia de
/// uso e excedente por equipamento, e as medições do contrato.
class EqpCobrancaTela extends StatefulWidget {
  const EqpCobrancaTela({super.key, required this.id});

  /// Contrato de locação.
  final String id;

  @override
  State<EqpCobrancaTela> createState() => _EqpCobrancaTelaState();
}

class _EqpCobrancaTelaState extends State<EqpCobrancaTela> {
  Map<String, dynamic>? _d;
  Map<String, Map<String, dynamic>> _franquias = {};
  List<Map<String, dynamic>> _medicoes = [];
  String? _erro;
  bool _ocupado = false;

  bool get _gestor => Sessao.atual?.tem(Papel.gestor) ?? false;
  Map<String, dynamic> get _l => Map<String, dynamic>.from((_d?['locacao'] as Map?) ?? const {});

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final d = await eqp('eqp_locacao_ver', {'locacao_id': widget.id});
      final f = await Supabase.instance.client
          .from('eqp_locacao_itens')
          .select('id, franquia_uso, preco_excedente')
          .eq('locacao_id', widget.id)
          .isFilter('excluido_em', null);
      final m = await eqp('eqp_medicoes_lista', {'locacao_id': widget.id});
      if (mounted) {
        setState(() {
          _d = d;
          _franquias = {for (final x in List<Map<String, dynamic>>.from(f)) '${x['id']}': x};
          _medicoes = listaDe(m['medicoes']);
          _erro = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    }
  }

  Future<void> _salvar(Map<String, dynamic> p, String ok) async {
    if (!mounted) return;
    setState(() => _ocupado = true);
    try {
      await eqp('eqp_locacao_cobranca', {'locacao_id': widget.id, ...p});
      if (mounted) avisarEqp(context, ok);
      await _carregar();
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _condicoes() async {
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _Condicoes(locacao: _l));
    if (p == null) return;
    await _salvar(p, 'Condições de cobrança salvas');
  }

  Future<void> _item(Map<String, dynamic> i) async {
    final f = _franquias['${i['item_id']}'] ?? const <String, dynamic>{};
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _ItemCobranca(item: i, franquia: f));
    if (p == null) return;
    await _salvar({
      'itens': [
        {'item_id': i['item_id'], ...p},
      ],
    }, 'Item salvo');
  }

  Future<void> _gerar() async {
    setState(() => _ocupado = true);
    try {
      final r = await eqp('eqp_medicao_acao', {'acao': 'gerar', 'locacao_id': widget.id});
      if (mounted) context.go('/equipamentos/medicoes/${r['medicao_id']}');
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    if (_erro != null && _d == null) return Center(child: Text(_erro!, style: const TextStyle(color: Cores.erro)));
    if (_d == null) return const Center(child: CircularProgressIndicator());
    final l = _l;
    final itens = listaDe(_d!['itens']).where((i) => i['situacao'] != 'cancelado').toList();
    final sit = '${l['situacao']}';
    final forma = '${l['forma_cobranca'] ?? ''}';
    final podeMudar = _gestor && sit != 'cancelada';
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          IconButton(tooltip: 'Voltar', onPressed: () => context.go('/equipamentos/locacoes/${widget.id}'), icon: const Icon(Icons.arrow_back)),
          Expanded(
            child: Text('Cobrança · ${l['codigo']} · ${l['cliente']}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text(situacoesLocacao[sit] ?? sit, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        if (_ocupado) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 8),
        SecaoEqp(
          titulo: 'Condições',
          acoes: [
            if (podeMudar) TextButton.icon(onPressed: _ocupado ? null : _condicoes, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Mudar')),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Forma: ${formasCobranca[forma] ?? forma}'),
            if (forma == 'obra') Text('Valor fechado: ${reais(l['valor_obra'])} (sai inteiro na primeira medição)'),
            Text('Dia da medição: ${l['dia_medicao'] == null ? 'último dia do mês' : 'dia ${l['dia_medicao']}'}'),
            Text('Período: ${dataBr(l['inicio'])} a ${dataBr(l['fim_previsto'])} · previsto ${reais(l['valor_previsto'])}',
                style: const TextStyle(color: Cores.neutro)),
          ]),
        ),
        SecaoEqp(
          titulo: 'Equipamentos (${itens.length})',
          child: Column(children: [
            for (final i in itens)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${i['codigo']} · ${i['descricao']}'),
                subtitle: Text([
                  '${reais(i['preco'])} ${periodicidades[i['periodicidade']] ?? ''}',
                  if (_franquias['${i['item_id']}']?['franquia_uso'] != null)
                    'franquia ${numeroBr(_franquias['${i['item_id']}']?['franquia_uso'])} por mês'
                  else
                    'franquia do modelo (se houver)',
                  if (_franquias['${i['item_id']}']?['preco_excedente'] != null)
                    'excedente ${reais(_franquias['${i['item_id']}']?['preco_excedente'])}',
                  situacoesItem[i['situacao']] ?? '${i['situacao']}',
                ].join(' · ')),
                trailing: podeMudar
                    ? IconButton(tooltip: 'Preço e franquia', onPressed: _ocupado ? null : () => _item(i), icon: const Icon(Icons.edit_outlined))
                    : null,
              ),
          ]),
        ),
        SecaoEqp(
          titulo: 'Medições (${_medicoes.length})',
          acoes: [
            if (_gestor && (sit == 'em_andamento' || sit == 'encerrada'))
              TextButton.icon(onPressed: _ocupado ? null : _gerar, icon: const Icon(Icons.add, size: 18), label: const Text('Gerar medição')),
          ],
          child: Column(children: [
            if (_medicoes.isEmpty)
              const Text('Nenhuma medição. A primeira sai no dia da medição (ou no fim do mês), depois da retirada.',
                  style: TextStyle(color: Cores.neutro)),
            for (final m in _medicoes)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                onTap: () => context.go('/equipamentos/medicoes/${m['medicao_id']}'),
                title: Text('${m['codigo']} · ${dataBr(m['periodo_inicio'])} a ${dataBr(m['periodo_fim'])}'),
                subtitle: Text('Competência ${mesBr(m['competencia'])}'),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(situacoesMedicao[m['situacao']] ?? '${m['situacao']}',
                      style: TextStyle(color: corDaMedicao('${m['situacao']}'), fontWeight: FontWeight.w700)),
                  Text(reais(m['valor_total'])),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Forma de cobrança, valor da obra e dia da medição.
class _Condicoes extends StatefulWidget {
  const _Condicoes({required this.locacao});

  final Map<String, dynamic> locacao;

  @override
  State<_Condicoes> createState() => _CondicoesState();
}

class _CondicoesState extends State<_Condicoes> {
  late String _forma;
  final _obra = TextEditingController();
  final _dia = TextEditingController();

  @override
  void initState() {
    super.initState();
    _forma = '${widget.locacao['forma_cobranca'] ?? ''}';
    if (widget.locacao['valor_obra'] != null) _obra.text = numeroBr(widget.locacao['valor_obra']);
    if (widget.locacao['dia_medicao'] != null) _dia.text = '${widget.locacao['dia_medicao']}';
  }

  @override
  void dispose() {
    _obra.dispose();
    _dia.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Condições de cobrança'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<String>(
              initialValue: _forma,
              decoration: const InputDecoration(labelText: 'Forma de cobrança'),
              items: [for (final f in formasCobranca.entries) DropdownMenuItem<String>(value: f.key, child: Text(f.value))],
              onChanged: (v) => setState(() => _forma = v ?? ''),
            ),
            if (_forma == 'dia' || _forma == 'semana' || _forma == 'mes')
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Todos os equipamentos passam para essa periodicidade, com o preço de tabela (da ficha ou do modelo).',
                    style: TextStyle(color: Cores.neutro)),
              ),
            if (_forma == 'obra')
              TextField(
                controller: _obra,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Valor fechado da obra (R\$)'),
              ),
            TextField(
              controller: _dia,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Dia da medição (1 a 28; vazio = último dia do mês)'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              final dia = int.tryParse(_dia.text.trim());
              if (_dia.text.trim().isNotEmpty && (dia == null || dia < 1 || dia > 28)) return;
              final obra = lerNumero(_obra.text);
              if (_forma == 'obra' && (obra == null || obra <= 0)) return;
              Navigator.of(context).pop(<String, dynamic>{
                'forma_cobranca': _forma,
                if (_forma == 'obra') 'valor_obra': obra,
                'dia_medicao': dia ?? '',
              });
            },
            child: const Text('Salvar'),
          ),
        ],
      );
}

/// Preço, franquia de uso por mês e preço do excedente de um equipamento do contrato.
class _ItemCobranca extends StatefulWidget {
  const _ItemCobranca({required this.item, required this.franquia});

  final Map<String, dynamic> item;
  final Map<String, dynamic> franquia;

  @override
  State<_ItemCobranca> createState() => _ItemCobrancaState();
}

class _ItemCobrancaState extends State<_ItemCobranca> {
  final _preco = TextEditingController();
  final _franquia = TextEditingController();
  final _excedente = TextEditingController();

  @override
  void initState() {
    super.initState();
    _preco.text = numeroBr(widget.item['preco']);
    if (widget.franquia['franquia_uso'] != null) _franquia.text = numeroBr(widget.franquia['franquia_uso']);
    if (widget.franquia['preco_excedente'] != null) _excedente.text = numeroBr(widget.franquia['preco_excedente']);
  }

  @override
  void dispose() {
    _preco.dispose();
    _franquia.dispose();
    _excedente.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('${widget.item['codigo']} · cobrança'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _preco,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Preço (R\$ ${periodicidades[widget.item['periodicidade']] ?? ''})'),
            ),
            TextField(
              controller: _franquia,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Franquia de uso por mês (horas, km ou ciclos; vazio = a do modelo)'),
            ),
            TextField(
              controller: _excedente,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Preço do excedente por unidade (R\$; vazio = o do modelo)'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              final preco = lerNumero(_preco.text);
              if (preco == null || preco < 0) return;
              Navigator.of(context).pop(<String, dynamic>{
                'preco': preco,
                'franquia_uso': lerNumero(_franquia.text) ?? '',
                'preco_excedente': lerNumero(_excedente.text) ?? '',
              });
            },
            child: const Text('Salvar'),
          ),
        ],
      );
}
