import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/comercial.dart' show reais;
import '../servicos/status.dart';
import '../widgets/margem.dart';
import 'servico.dart';
import 'widgets.dart';

/// Equipamentos da aplicação: status, onde está, com quem, até quando e a próxima reserva.
class EqpListaTela extends StatefulWidget {
  const EqpListaTela({super.key});

  @override
  State<EqpListaTela> createState() => _EqpListaTelaState();
}

class _EqpListaTelaState extends State<EqpListaTela> {
  final _busca = TextEditingController();
  String? _status;
  List<Map<String, dynamic>> _lista = [];
  bool _carregando = true;
  String? _erro;

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
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await eqp('eqp_lista', {
        if (_status != null) 'status': _status,
        if (_busca.text.trim().isNotEmpty) 'busca': _busca.text.trim(),
      });
      if (mounted) setState(() => _lista = listaDe(r['equipamentos']));
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _novo() async {
    final id = await novoEquipamentoEqp(context);
    if (id != null && mounted) context.go('/equipamentos/ativo/$id');
  }

  String _onde(Map<String, dynamic> e) => [
        '${e['local'] ?? ''}',
        if (e['com'] != null) '${e['com']}',
        if (e['fim_previsto'] != null) 'até ${dataBr(e['fim_previsto'])}',
        if (e['proxima_reserva'] != null) 'próxima reserva ${dataBr(e['proxima_reserva'])}',
      ].where((x) => x.isNotEmpty).join(' · ');

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          Expanded(
            child: Text('Equipamentos', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (Sessao.atual?.tem(Papel.gestor) ?? false)
            FilledButton.icon(onPressed: _novo, icon: const Icon(Icons.add), label: const Text('Novo equipamento')),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _busca,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Código, descrição, patrimônio, modelo ou série',
            suffixIcon: IconButton(onPressed: _carregar, icon: const Icon(Icons.arrow_forward)),
          ),
          onSubmitted: (_) => _carregar(),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          ChoiceChip(
            label: const Text('Todos'),
            selected: _status == null,
            onSelected: (_) {
              setState(() => _status = null);
              _carregar();
            },
          ),
          for (final s in statusEquipamento.entries)
            ChoiceChip(
              label: Text(s.value),
              selected: _status == s.key,
              onSelected: (_) {
                setState(() => _status = s.key);
                _carregar();
              },
            ),
        ]),
        const SizedBox(height: 8),
        if (_carregando) const LinearProgressIndicator(minHeight: 2),
        if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
        if (!_carregando && _lista.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nenhum equipamento. Cadastre um depósito em Equipamentos › Depósitos e obras e depois os equipamentos.',
                style: TextStyle(color: Cores.neutro)),
          ),
        for (final e in _lista)
          Card(
            child: ListTile(
              onTap: () => context.go('/equipamentos/ativo/${e['equipamento_id']}'),
              title: Text('${e['codigo']} · ${e['descricao']}${e['patrimonio'] != null ? ' · ${e['patrimonio']}' : ''}'),
              subtitle: Text(_onde(e), style: TextStyle(color: e['atrasado'] == true ? Cores.erro : Cores.neutro)),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                ChipStatusEqp('${e['status']}'),
                if (e['preco_diaria'] != null)
                  Text('${reais(e['preco_diaria'])}/dia', style: const TextStyle(color: Cores.neutro, fontSize: 12)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Cadastro de um equipamento novo da aplicação. Devolve o id do equipamento (ou null).
Future<String?> novoEquipamentoEqp(BuildContext context) async {
  Map<String, dynamic> apoio;
  try {
    apoio = await eqpApoio();
  } catch (e) {
    if (context.mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    return null;
  }
  final locais = listaDe(apoio['locais_empresa']);
  if (locais.isEmpty) {
    if (context.mounted) avisarEqp(context, 'Cadastre antes um depósito da empresa (Equipamentos › Depósitos e obras).', erro: true);
    return null;
  }
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (_) => _NovoEquipamento(locais: locais, tipos: listaDe(apoio['tipos_equipamento'])),
  );
}

class _NovoEquipamento extends StatefulWidget {
  const _NovoEquipamento({required this.locais, required this.tipos});

  final List<Map<String, dynamic>> locais;
  final List<Map<String, dynamic>> tipos;

  @override
  State<_NovoEquipamento> createState() => _NovoEquipamentoState();
}

class _NovoEquipamentoState extends State<_NovoEquipamento> {
  final _c = {
    for (final k in ['descricao', 'patrimonio', 'marca', 'modelo', 'numero_serie', 'leitura_inicial', 'preco_diaria',
      'preco_semana', 'preco_mes', 'valor_aquisicao', 'centro_custo'])
      k: TextEditingController(),
  };
  late String _local = '${(widget.locais.firstWhere((l) => l['categoria'] == 'deposito', orElse: () => widget.locais.first))['id']}';
  String? _tipo;
  String _medidor = 'nenhum';
  bool _salvando = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  num? _num(String k) => num.tryParse(_c[k]!.text.trim().replaceAll(',', '.'));
  String? _txt(String k) => _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim();

  Future<void> _salvar() async {
    if (_c['descricao']!.text.trim().isEmpty) {
      avisarEqp(context, 'Informe a descrição.', erro: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      final r = await eqp('eqp_ficha_acao', {
        'acao': 'incluir',
        'descricao': _txt('descricao'),
        'patrimonio': _txt('patrimonio'),
        'marca': _txt('marca'),
        'modelo': _txt('modelo'),
        'numero_serie': _txt('numero_serie'),
        'tipo_equipamento_id': _tipo,
        'local_base_id': _local,
        'medidor': _medidor,
        'leitura_inicial': _num('leitura_inicial'),
        'preco_diaria': _num('preco_diaria'),
        'preco_semana': _num('preco_semana'),
        'preco_mes': _num('preco_mes'),
        'valor_aquisicao': _num('valor_aquisicao'),
        'centro_custo': _txt('centro_custo'),
      });
      if (mounted) Navigator.of(context).pop('${r['equipamento_id']}');
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _campo(String k, String rotulo, {bool numero = false}) => TextField(
        controller: _c[k],
        keyboardType: numero ? const TextInputType.numberWithOptions(decimal: true) : null,
        decoration: InputDecoration(labelText: rotulo),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Novo equipamento'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _campo('descricao', 'Descrição (ex.: Macaco hidráulico 200 t)'),
              _campo('patrimonio', 'Patrimônio'),
              if (widget.tipos.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: _tipo,
                  decoration: const InputDecoration(labelText: 'Categoria (tipo)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Sem categoria')),
                    for (final t in widget.tipos) DropdownMenuItem<String?>(value: '${t['id']}', child: Text('${t['nome']}')),
                  ],
                  onChanged: (v) => setState(() => _tipo = v),
                ),
              Row(children: [
                Expanded(child: _campo('marca', 'Marca')),
                const SizedBox(width: 8),
                Expanded(child: _campo('modelo', 'Modelo')),
              ]),
              _campo('numero_serie', 'Número de série'),
              DropdownButtonFormField<String>(
                initialValue: _local,
                decoration: const InputDecoration(labelText: 'Depósito (local base)'),
                items: [
                  for (final l in widget.locais)
                    DropdownMenuItem<String>(value: '${l['id']}', child: Text('${l['nome']} (${categoriasLocal[l['categoria']] ?? 'local'})')),
                ],
                onChanged: (v) => setState(() => _local = v ?? _local),
              ),
              DropdownButtonFormField<String>(
                initialValue: _medidor,
                decoration: const InputDecoration(labelText: 'Medidor de uso'),
                items: const [
                  DropdownMenuItem(value: 'nenhum', child: Text('Nenhum')),
                  DropdownMenuItem(value: 'horas', child: Text('Horímetro (horas)')),
                  DropdownMenuItem(value: 'km', child: Text('Quilômetros')),
                  DropdownMenuItem(value: 'ciclos', child: Text('Ciclos')),
                ],
                onChanged: (v) => setState(() => _medidor = v ?? 'nenhum'),
              ),
              if (_medidor != 'nenhum') _campo('leitura_inicial', 'Leitura atual', numero: true),
              Row(children: [
                Expanded(child: _campo('preco_diaria', 'R\$ por dia', numero: true)),
                const SizedBox(width: 8),
                Expanded(child: _campo('preco_semana', 'R\$ por semana', numero: true)),
                const SizedBox(width: 8),
                Expanded(child: _campo('preco_mes', 'R\$ por mês', numero: true)),
              ]),
              Row(children: [
                Expanded(child: _campo('valor_aquisicao', 'Valor de aquisição', numero: true)),
                const SizedBox(width: 8),
                Expanded(child: _campo('centro_custo', 'Centro de custo (ERP)')),
              ]),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(onPressed: _salvando ? null : _salvar, child: const Text('Salvar')),
        ],
      );
}
