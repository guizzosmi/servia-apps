import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/comercial.dart' show reais;
import '../widgets/margem.dart';
import 'servico.dart';
import 'servico_manutencao.dart';
import 'widgets.dart';

/// Gestão de Equipamentos (guia 103): custo da hora por função (decisão 2 do dono), a função de custo de cada
/// colaborador, investimentos (retrofit fora do custo do mês) e o plano da aplicação (equipamentos incluídos).
class EqpCustosConfigTela extends StatefulWidget {
  const EqpCustosConfigTela({super.key});

  @override
  State<EqpCustosConfigTela> createState() => _EqpCustosConfigTelaState();
}

class _EqpCustosConfigTelaState extends State<EqpCustosConfigTela> {
  Map<String, dynamic>? _horas;
  Map<String, dynamic>? _plano;
  List<Map<String, dynamic>> _equipamentos = const [];
  String? _erro;
  bool _carregando = true;

  bool get _gestor => Sessao.atual?.tem(Papel.gestor) ?? false;
  bool get _custos => _gestor || (Sessao.atual?.tem(Papel.financeiro) ?? false);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final plano = await Supabase.instance.client.rpc('eqp_plano_uso');
      final r = _custos
          ? await Future.wait([eqp('eqp_custo_hora_acao', {'acao': 'listar'}), eqp('eqp_lista', {})])
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _plano = plano is Map ? Map<String, dynamic>.from(plano) : null;
          _horas = r.isNotEmpty ? r[0] : null;
          _equipamentos = r.length > 1 ? listaDe(r[1]['equipamentos']) : const [];
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar(String funcao, Map<String, dynamic> p, String ok) async {
    try {
      await eqp(funcao, p);
      if (mounted) avisarEqp(context, ok);
      await _carregar();
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _funcao([Map<String, dynamic>? f]) async {
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _Funcao(funcao: f));
    if (p == null) return;
    await _salvar('eqp_custo_hora_acao', {'acao': 'salvar', if (f != null) 'custo_hora_id': f['custo_hora_id'], ...p}, 'Custo da hora salvo');
  }

  Future<void> _investimento() async {
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _Investimento(equipamentos: _equipamentos));
    if (p == null) return;
    await _salvar('eqp_investimento_acao', {'acao': 'lancar', ...p}, 'Investimento lançado (soma ao valor do bem)');
  }

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    final h = _horas;
    final funcoes = listaDe(h?['funcoes']);
    final nomes = {for (final f in funcoes) '${f['funcao']}': '${f['nome']}'};
    final pl = _plano;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          Expanded(
            child: Text('Custos da manutenção e plano',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          IconButton(tooltip: 'Atualizar', onPressed: _carregando ? null : _carregar, icon: const Icon(Icons.refresh)),
        ]),
        const Text('Na conclusão da OS de equipamento, as horas de cada participante (check-in até a saída) são multiplicadas '
            'pelo custo da hora da função dele; quem não tem função cadastrada usa o padrão da empresa.',
            style: TextStyle(color: Cores.neutro)),
        const SizedBox(height: 12),
        if (_carregando) const LinearProgressIndicator(minHeight: 2),
        if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
        if (pl != null && pl['tem_plano'] == true)
          SecaoEqp(
            titulo: 'Plano da aplicação: ${pl['plano']}',
            child: Text([
              pl['equipamentos_incluidos'] == null
                  ? '${pl['equipamentos_ativos']} equipamento(s), sem limite'
                  : '${pl['equipamentos_ativos']} de ${pl['equipamentos_incluidos']} equipamento(s) incluídos',
              if ((num.tryParse('${pl['equipamentos_extras']}') ?? 0) > 0)
                '${pl['equipamentos_extras']} extra(s) × ${reais(pl['valor_equipamento_extra'])} = ${reais(pl['valor_extras'])} na mensalidade',
              if (pl['bloqueia_no_limite'] == true) 'no limite, o cadastro de equipamento para (fale com o ServPilot para mudar de plano)',
              if (pl['valor_plano'] != null) 'plano: ${reais(pl['valor_plano'])} por mês, além do da Refrigeração',
            ].join(' · ')),
          ),
        if (!_custos)
          const Text('Só o gestor e o financeiro veem os custos.', style: TextStyle(color: Cores.neutro))
        else if (h != null) ...[
          SecaoEqp(
            titulo: 'Custo da hora por função',
            acoes: [
              if (_gestor) TextButton.icon(onPressed: () => _funcao(), icon: const Icon(Icons.add, size: 18), label: const Text('Função')),
            ],
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (h['padrao'] == null)
                const Text('Cadastre o padrão da empresa (função "padrao"): sem ele, quem não tem função entra com custo zero.',
                    style: TextStyle(color: Cores.alerta)),
              for (final f in funcoes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${f['nome']}${f['ativo'] == true ? '' : ' (inativa)'}'),
                  subtitle: Text(f['funcao'] == 'padrao' ? 'Padrão da empresa' : 'função: ${f['funcao']}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${reais(f['valor_hora'])}/h', style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (_gestor) IconButton(tooltip: 'Editar', onPressed: () => _funcao(f), icon: const Icon(Icons.edit_outlined)),
                  ]),
                ),
            ]),
          ),
          SecaoEqp(
            titulo: 'Colaboradores',
            child: Column(children: [
              for (final c in listaDe(h['colaboradores']))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${c['nome']}'),
                  subtitle: Text('cadastro: ${c['funcao']} · vale ${c['valor_hora'] == null ? 'sem custo cadastrado' : '${reais(c['valor_hora'])}/h'}'),
                  trailing: !_gestor
                      ? Text(nomes['${c['funcao_custo']}'] ?? '')
                      : SizedBox(
                          width: 200,
                          child: DropdownButtonFormField<String>(
                            initialValue: nomes.containsKey('${c['funcao_custo']}') ? '${c['funcao_custo']}' : '',
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Função de custo', isDense: true),
                            items: [
                              const DropdownMenuItem(value: '', child: Text('A do cadastro')),
                              for (final f in funcoes)
                                if (f['funcao'] != 'padrao') DropdownMenuItem(value: '${f['funcao']}', child: Text('${f['nome']}')),
                            ],
                            onChanged: (v) => _salvar('eqp_custo_hora_acao',
                                {'acao': 'colaborador', 'colaborador_id': c['colaborador_id'], 'funcao_custo': v ?? ''}, 'Função de custo salva'),
                          ),
                        ),
                ),
            ]),
          ),
          SecaoEqp(
            titulo: 'Investimentos (retrofit)',
            acoes: [
              TextButton.icon(onPressed: _investimento, icon: const Icon(Icons.add, size: 18), label: const Text('Lançar')),
            ],
            child: const Text('Investimento soma ao valor do bem e fica fora do custo do mês (aparece no custo acumulado e no '
                'valor do bem, nos indicadores). O retrofit feito por OS segue o parâmetro da empresa (custo do mês ou '
                'investimento).',
                style: TextStyle(color: Cores.neutro)),
          ),
        ],
      ]),
    );
  }
}

class _Funcao extends StatefulWidget {
  const _Funcao({this.funcao});

  final Map<String, dynamic>? funcao;

  @override
  State<_Funcao> createState() => _FuncaoState();
}

class _FuncaoState extends State<_Funcao> {
  late final _funcao = TextEditingController(text: '${widget.funcao?['funcao'] ?? ''}');
  late final _nome = TextEditingController(text: '${widget.funcao?['nome'] ?? ''}');
  late final _valor = TextEditingController(text: widget.funcao == null ? '' : numBr(widget.funcao!['valor_hora'], casas: 2));
  late bool _ativo = widget.funcao?['ativo'] != false;

  @override
  void dispose() {
    _funcao.dispose();
    _nome.dispose();
    _valor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.funcao == null ? 'Custo da hora de uma função' : 'Custo da hora'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (widget.funcao == null)
              TextField(
                controller: _funcao,
                decoration: const InputDecoration(
                    labelText: 'Função (padrao, tecnico, ajudante, lider, eletricista...)', helperText: '"padrao" = valor da empresa'),
              ),
            TextField(controller: _nome, decoration: const InputDecoration(labelText: 'Nome (opcional)')),
            TextField(
              controller: _valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Custo da hora (R\$)'),
            ),
            if (widget.funcao != null)
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _ativo,
                title: const Text('Ativa'),
                onChanged: (v) => setState(() => _ativo = v),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              final v = num.tryParse(_valor.text.trim().replaceAll('.', '').replaceAll(',', '.'));
              if (v == null || v < 0) return;
              if (widget.funcao == null && _funcao.text.trim().isEmpty) return;
              Navigator.of(context).pop(<String, dynamic>{
                if (widget.funcao == null) 'funcao': _funcao.text.trim(),
                if (_nome.text.trim().isNotEmpty) 'nome': _nome.text.trim(),
                'valor_hora': v,
                'ativo': _ativo,
              });
            },
            child: const Text('Salvar'),
          ),
        ],
      );
}

class _Investimento extends StatefulWidget {
  const _Investimento({required this.equipamentos});

  final List<Map<String, dynamic>> equipamentos;

  @override
  State<_Investimento> createState() => _InvestimentoState();
}

class _InvestimentoState extends State<_Investimento> {
  String? _eqp;
  final _valor = TextEditingController();
  final _descricao = TextEditingController();
  final _motivo = TextEditingController();
  final _documento = TextEditingController();

  @override
  void dispose() {
    for (final c in [_valor, _descricao, _motivo, _documento]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Lançar investimento'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: _eqp,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Equipamento'),
                items: [
                  for (final e in widget.equipamentos)
                    DropdownMenuItem(value: '${e['equipamento_id']}', child: Text('${e['codigo']} · ${e['descricao']}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _eqp = v),
              ),
              TextField(
                controller: _valor,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Valor (R\$)'),
              ),
              TextField(controller: _descricao, decoration: const InputDecoration(labelText: 'Descrição (ex.: retrofit do hidráulico)')),
              TextField(controller: _motivo, decoration: const InputDecoration(labelText: 'Motivo (ex.: nota do fornecedor)')),
              TextField(controller: _documento, decoration: const InputDecoration(labelText: 'Documento (opcional)')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              final v = num.tryParse(_valor.text.trim().replaceAll('.', '').replaceAll(',', '.'));
              if (_eqp == null || v == null || v <= 0 || _descricao.text.trim().isEmpty || _motivo.text.trim().isEmpty) return;
              Navigator.of(context).pop(<String, dynamic>{
                'equipamento_id': _eqp,
                'valor': v,
                'descricao': _descricao.text.trim(),
                'motivo': _motivo.text.trim(),
                if (_documento.text.trim().isNotEmpty) 'documento': _documento.text.trim(),
              });
            },
            child: const Text('Lançar'),
          ),
        ],
      );
}
