import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/status.dart';
import '../widgets/margem.dart';
import 'servico.dart';
import 'servico_manutencao.dart';
import 'widgets.dart';

/// Gestão de Equipamentos (guia 103): planos de preventiva por tempo e por uso (o que vier primeiro), por equipamento
/// ou por modelo, e a situação de cada equipamento (última execução, próximo vencimento, OS aberta).
class EqpPlanosTela extends StatefulWidget {
  const EqpPlanosTela({super.key});

  @override
  State<EqpPlanosTela> createState() => _EqpPlanosTelaState();
}

class _EqpPlanosTelaState extends State<EqpPlanosTela> {
  Map<String, dynamic>? _d;
  List<Map<String, dynamic>> _equipamentos = const [];
  String? _erro;
  bool _carregando = true;
  bool _soVencendo = false;

  bool get _gestor => Sessao.atual?.tem(Papel.gestor) ?? false;

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
      final r = await Future.wait([eqp('eqp_planos_lista', {'so_vencendo': _soVencendo}), eqp('eqp_lista', {})]);
      if (mounted) {
        setState(() {
          _d = r[0];
          _equipamentos = listaDe(r[1]['equipamentos']);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _rodar(Map<String, dynamic> p, String ok) async {
    try {
      final r = await eqp('eqp_plano_acao', p);
      if (!mounted) return;
      final abertas = (r['os_abertas'] as num?)?.toInt();
      avisarEqp(context, abertas == null ? ok : '$ok: $abertas OS aberta(s), ${r['os_completadas'] ?? 0} completada(s)');
      await _carregar();
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _plano([Map<String, dynamic>? pl]) async {
    final p = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _Plano(plano: pl, equipamentos: _equipamentos, modelos: listaDe(_d?['modelos'])),
    );
    if (p == null) return;
    await _rodar({'acao': 'salvar', if (pl != null) 'plano_id': pl['plano_id'], ...p}, 'Plano salvo');
  }

  String _intervalo(Map<String, dynamic> pl) => [
        if (pl['intervalo_dias'] != null) 'a cada ${pl['intervalo_dias']} dias',
        if (pl['intervalo_uso'] != null) 'a cada ${numBr(pl['intervalo_uso'])} de uso',
      ].join(' ou ');

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    final d = _d;
    final planos = listaDe(d?['planos']);
    final sits = listaDe(d?['situacoes']);
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          IconButton(tooltip: 'Manutenção', onPressed: () => context.go('/equipamentos/manutencao'), icon: const Icon(Icons.arrow_back)),
          Expanded(
            child: Text('Planos de preventiva',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          IconButton(tooltip: 'Atualizar', onPressed: _carregando ? null : _carregar, icon: const Icon(Icons.refresh)),
        ]),
        const Text('Por tempo, por uso (horímetro, km, ciclos) ou os dois: vale o que vier primeiro. O plano do modelo vale para '
            'todos os equipamentos dele; o equipamento com plano próprio deixa de seguir o do modelo. Vencendo (dentro da '
            'antecedência), abre uma OS preventiva por equipamento, todo dia e logo depois de cada leitura.',
            style: TextStyle(color: Cores.neutro)),
        const SizedBox(height: 8),
        if (_gestor)
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: () => _plano(), icon: const Icon(Icons.add), label: const Text('Novo plano')),
            OutlinedButton.icon(
              onPressed: () => _rodar({'acao': 'gerar'}, 'Preventivas conferidas'),
              icon: const Icon(Icons.event_repeat_outlined),
              label: const Text('Gerar agora'),
            ),
          ]),
        const SizedBox(height: 12),
        if (_carregando) const LinearProgressIndicator(minHeight: 2),
        if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
        if (d != null) ...[
          SecaoEqp(
            titulo: 'Planos (${planos.length})',
            child: planos.isEmpty
                ? const Text('Nenhum plano ainda.', style: TextStyle(color: Cores.neutro))
                : Column(children: [
                    for (final pl in planos)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${pl['descricao']}${pl['ativo'] == true ? '' : ' (inativo)'}'),
                        subtitle: Text([
                          pl['equipamento'] != null ? '${pl['equipamento']}' : 'Modelo ${pl['modelo'] ?? ''}',
                          _intervalo(pl),
                          'antecedência ${pl['antecedencia_dias']} dias'
                              '${(num.tryParse('${pl['antecedencia_uso']}') ?? 0) > 0 ? ' ou ${numBr(pl['antecedencia_uso'])} de uso' : ''}',
                          if (pl['no_campo'] == true) 'em campo, vai até ele',
                          '${pl['equipamentos']} equipamento(s)',
                          if ((pl['atividades'] as List?)?.isNotEmpty ?? false) (pl['atividades'] as List).join(', '),
                        ].join(' · ')),
                        trailing: !_gestor
                            ? null
                            : Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(tooltip: 'Editar', onPressed: () => _plano(pl), icon: const Icon(Icons.edit_outlined)),
                                if (pl['ativo'] == true)
                                  IconButton(
                                    tooltip: 'Inativar',
                                    onPressed: () async {
                                      if (!await confirmarEqp(context, 'Inativar plano', '${pl['descricao']} deixa de gerar preventivas.')) {
                                        return;
                                      }
                                      await _rodar({'acao': 'inativar', 'plano_id': pl['plano_id']}, 'Plano inativado');
                                    },
                                    icon: const Icon(Icons.pause_circle_outline),
                                  ),
                              ]),
                      ),
                  ]),
          ),
          SecaoEqp(
            titulo: 'Situação por equipamento (${sits.length})',
            acoes: [
              FilterChip(
                label: const Text('Só vencendo'),
                selected: _soVencendo,
                onSelected: (v) {
                  setState(() => _soVencendo = v);
                  _carregar();
                },
              ),
            ],
            child: sits.isEmpty
                ? const Text('Nada para mostrar.', style: TextStyle(color: Cores.neutro))
                : Column(children: [
                    for (final s in sits)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${s['codigo']} · ${s['descricao']} · ${s['plano']}'),
                        subtitle: Text([
                          s['ultima_data'] != null
                              ? 'última ${dataBr(s['ultima_data'])}${s['ultima_uso'] != null ? ' (${numBr(s['ultima_uso'])})' : ''}'
                              : 'contando desde ${dataBr(s['base_data'])}',
                          if (s['proxima_data'] != null) 'próxima até ${dataBr(s['proxima_data'])}',
                          if (s['proxima_uso'] != null)
                            'ou em ${numBr(s['proxima_uso'])} ${unidadesMedidor[s['medidor']] ?? ''} (está em ${numBr(s['uso_total'])})',
                          if (s['os'] != null) '${s['os']}',
                        ].join(' · ')),
                        trailing: EtiquetaEqp(estadosPreventiva[s['estado']] ?? '${s['estado']}', cor: corDoEstado('${s['estado']}')),
                        onTap: s['os_id'] != null
                            ? () => context.go('/os/${s['os_id']}')
                            : () => context.go('/equipamentos/ativo/${s['equipamento_id']}'),
                      ),
                  ]),
          ),
        ],
      ]),
    );
  }
}

class _Plano extends StatefulWidget {
  const _Plano({this.plano, required this.equipamentos, required this.modelos});

  final Map<String, dynamic>? plano;
  final List<Map<String, dynamic>> equipamentos;
  final List<Map<String, dynamic>> modelos;

  @override
  State<_Plano> createState() => _PlanoState();
}

class _PlanoState extends State<_Plano> {
  late final _descricao = TextEditingController(text: '${widget.plano?['descricao'] ?? ''}');
  late final _dias = TextEditingController(text: '${widget.plano?['intervalo_dias'] ?? ''}');
  late final _uso = TextEditingController(text: widget.plano?['intervalo_uso'] == null ? '' : numBr(widget.plano?['intervalo_uso']));
  late final _antDias = TextEditingController(text: '${widget.plano?['antecedencia_dias'] ?? 7}');
  late final _antUso = TextEditingController(text: numBr(widget.plano?['antecedencia_uso'] ?? 0));
  late final _atividades = TextEditingController(
      text: ((widget.plano?['atividades'] as List?) ?? const []).map((e) => '$e').join('\n'));
  final _ultimaUso = TextEditingController();
  late String? _eqp = widget.plano?['equipamento_id'] as String?;
  late String? _modelo = widget.plano?['modelo_id'] as String?;
  late bool _noCampo = widget.plano?['no_campo'] == true;
  late bool _porModelo = widget.plano != null && widget.plano!['modelo_id'] != null;
  DateTime? _ultima;

  bool get _novo => widget.plano == null;

  @override
  void dispose() {
    for (final c in [_descricao, _dias, _uso, _antDias, _antUso, _atividades, _ultimaUso]) {
      c.dispose();
    }
    super.dispose();
  }

  num? _n(TextEditingController c) => num.tryParse(c.text.trim().replaceAll('.', '').replaceAll(',', '.'));

  void _ok() {
    final dias = int.tryParse(_dias.text.trim());
    final uso = _n(_uso);
    if (_descricao.text.trim().isEmpty || (dias == null && uso == null)) return;
    if (_novo && !_porModelo && _eqp == null) return;
    if (_novo && _porModelo && _modelo == null) return;
    final atividades = _atividades.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    Navigator.of(context).pop(<String, dynamic>{
      'descricao': _descricao.text.trim(),
      if (_novo && _porModelo) 'modelo_id': _modelo,
      if (_novo && !_porModelo) 'equipamento_id': _eqp,
      'intervalo_dias': dias,
      'intervalo_uso': uso,
      'antecedencia_dias': int.tryParse(_antDias.text.trim()) ?? 7,
      'antecedencia_uso': _n(_antUso) ?? 0,
      'atividades': atividades,
      'no_campo': _noCampo,
      if (_ultima != null) 'ultima_data': iso(_ultima!),
      if (_ultima != null && _n(_ultimaUso) != null) 'ultima_leitura': _n(_ultimaUso),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_novo ? 'Novo plano de preventiva' : 'Plano de preventiva'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: _descricao, decoration: const InputDecoration(labelText: 'Descrição (ex.: Revisão 250 h)')),
              if (_novo && widget.modelos.isNotEmpty)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _porModelo,
                  title: const Text('Plano do modelo (vale para todos do modelo)'),
                  onChanged: (v) => setState(() => _porModelo = v),
                ),
              if (_novo && _porModelo)
                DropdownButtonFormField<String>(
                  initialValue: _modelo,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Modelo'),
                  items: [
                    for (final m in widget.modelos)
                      DropdownMenuItem(value: '${m['id']}', child: Text('${m['nome']}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _modelo = v),
                )
              else if (_novo)
                DropdownButtonFormField<String>(
                  initialValue: _eqp,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Equipamento'),
                  items: [
                    for (final e in widget.equipamentos)
                      DropdownMenuItem(
                        value: '${e['equipamento_id']}',
                        child: Text('${e['codigo']} · ${e['descricao']}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _eqp = v),
                ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _dias,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'A cada (dias)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _uso,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Ou a cada (horas, km, ciclos)'),
                  ),
                ),
              ]),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _antDias,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Antecedência (dias)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _antUso,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Antecedência (uso)'),
                  ),
                ),
              ]),
              TextField(
                controller: _atividades,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Atividades (uma por linha)'),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _noCampo,
                title: const Text('Em campo, a OS vai até ele (senão fica para o retorno)'),
                onChanged: (v) => setState(() => _noCampo = v),
              ),
              if (!_porModelo) ...[
                const SizedBox(height: 8),
                const Text('Última feita antes do sistema (opcional)', style: TextStyle(fontWeight: FontWeight.w600)),
                Row(children: [
                  CampoDataEqp(rotulo: 'Data', data: _ultima, aoMudar: (d) => setState(() => _ultima = d)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _ultimaUso,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Horímetro, km ou ciclos naquele dia'),
                    ),
                  ),
                ]),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(onPressed: _ok, child: const Text('Salvar')),
        ],
      );
}
