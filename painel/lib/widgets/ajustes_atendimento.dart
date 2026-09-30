import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'campos_data_hora.dart';
import 'itens_os.dart';

// Diálogos do gestor para corrigir um atendimento. Cada um devolve o que
// vai para atendimento_acao (ou uma lista de ações, nas medições).

/// Data (calendário) + hora (relógio) num campo só.
class _DataHora extends StatelessWidget {
  const _DataHora({required this.rotulo, required this.valor, required this.aoMudar});

  final String rotulo;
  final DateTime? valor;
  final ValueChanged<DateTime?> aoMudar;

  @override
  Widget build(BuildContext context) {
    final v = valor;
    return Row(children: [
      Expanded(
        child: CampoData(
          rotulo: rotulo,
          valor: v,
          aoMudar: (d) => aoMudar(d == null
              ? null
              : DateTime(d.year, d.month, d.day, v?.hour ?? DateTime.now().hour, v?.minute ?? 0)),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 130,
        child: CampoHora(
          rotulo: 'Hora',
          valor: v == null ? null : TimeOfDay.fromDateTime(v),
          aoMudar: (t) {
            if (t == null) return aoMudar(null);
            final base = v ?? DateTime.now();
            aoMudar(DateTime(base.year, base.month, base.day, t.hour, t.minute));
          },
        ),
      ),
    ]);
  }
}

// =====================================================================
// Horas de uma pessoa
// =====================================================================

/// Corrige um período (entrada e saída) ou inclui um que faltou.
/// [periodo] null = incluir; [pessoas] = colaboradores para escolher.
class DialogoPeriodo extends StatefulWidget {
  const DialogoPeriodo({super.key, required this.atendimentoId, this.periodo, this.pessoas = const []});

  final String atendimentoId;
  final Map<String, dynamic>? periodo;
  final List<Map<String, dynamic>> pessoas;

  @override
  State<DialogoPeriodo> createState() => _DialogoPeriodoState();
}

class _DialogoPeriodoState extends State<DialogoPeriodo> {
  late DateTime? _entrada = DateTime.tryParse('${widget.periodo?['entrada_em'] ?? ''}')?.toLocal();
  late DateTime? _saida = DateTime.tryParse('${widget.periodo?['saida_em'] ?? ''}')?.toLocal();
  String? _pessoa;
  final _motivo = TextEditingController();
  String? _erro;

  bool get _novo => widget.periodo == null;
  bool get _aberto => !_novo && widget.periodo!['saida_em'] == null;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  bool _validar({bool excluir = false}) {
    String? erro;
    if (_motivo.text.trim().isEmpty) {
      erro = 'Informe o motivo.';
    } else if (!excluir) {
      if (_novo && _pessoa == null) {
        erro = 'Escolha a pessoa.';
      } else if (_entrada == null) {
        erro = 'Informe a entrada.';
      } else if (_saida == null && !_aberto) {
        erro = 'Informe a saída.';
      } else if (_saida != null && !_saida!.isAfter(_entrada!)) {
        erro = 'A saída precisa ser depois da entrada.';
      } else if (_entrada!.isAfter(DateTime.now()) || (_saida?.isAfter(DateTime.now()) ?? false)) {
        erro = 'Entrada e saída não podem ser no futuro.';
      }
    }
    setState(() => _erro = erro);
    return erro == null;
  }

  @override
  Widget build(BuildContext context) {
    final nome = (widget.periodo?['colaboradores'] as Map?)?['nome'];
    return AlertDialog(
      title: Text(_novo ? 'Incluir horas' : 'Corrigir horas de $nome'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_novo) ...[
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Pessoa'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _pessoa,
                    isDense: true,
                    isExpanded: true,
                    hint: const Text('Escolha'),
                    items: [
                      for (final p in widget.pessoas)
                        DropdownMenuItem(value: p['id'] as String, child: Text('${p['nome']}')),
                    ],
                    onChanged: (v) => setState(() => _pessoa = v),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _DataHora(rotulo: 'Entrada', valor: _entrada, aoMudar: (d) => setState(() => _entrada = d)),
            const SizedBox(height: 12),
            _DataHora(rotulo: 'Saída', valor: _saida, aoMudar: (d) => setState(() => _saida = d)),
            if (_aberto)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Sem saída = a pessoa continua no serviço.', style: TextStyle(fontSize: 12, color: Cores.neutro)),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _motivo,
              decoration: const InputDecoration(labelText: 'Motivo (obrigatório)', hintText: 'Ex.: esqueceu de sair no app'),
            ),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_erro!, style: const TextStyle(color: Cores.erro)),
              ),
          ]),
        ),
      ),
      actions: [
        if (!_novo)
          TextButton(
            onPressed: () {
              if (!_validar(excluir: true)) return;
              Navigator.of(context).pop(<String, dynamic>{
                'acao': 'participante_excluir',
                'participante_id': widget.periodo!['id'],
                'motivo': _motivo.text.trim(),
              });
            },
            style: TextButton.styleFrom(foregroundColor: Cores.erro),
            child: const Text('Excluir período'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
        FilledButton(
          onPressed: () {
            if (!_validar()) return;
            Navigator.of(context).pop(<String, dynamic>{
              'acao': 'participante_salvar',
              'atendimento_id': widget.atendimentoId,
              if (!_novo) 'participante_id': widget.periodo!['id'],
              if (_novo) 'colaborador_id': _pessoa,
              'entrada_em': _entrada!.toUtc().toIso8601String(),
              'saida_em': _saida?.toUtc().toIso8601String() ?? '',
              'motivo': _motivo.text.trim(),
            });
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

// =====================================================================
// Relato
// =====================================================================

class DialogoRelato extends StatefulWidget {
  const DialogoRelato({super.key, required this.atendimento});

  final Map<String, dynamic> atendimento;

  @override
  State<DialogoRelato> createState() => _DialogoRelatoState();
}

class _DialogoRelatoState extends State<DialogoRelato> {
  static const _campos = {
    'problema_identificado': 'Problema identificado',
    'causa': 'Causa',
    'solucao': 'Solução',
    'observacoes': 'Observações',
    'resultado_observacao': 'Observação do não realizado',
  };

  late final Map<String, TextEditingController> _textos = {
    for (final c in _campos.keys) c: TextEditingController(text: '${widget.atendimento[c] ?? ''}'),
  };
  late final _contato = TextEditingController(text: '${widget.atendimento['contato_cliente_nome'] ?? ''}');
  late bool _acompanhou = widget.atendimento['cliente_presente'] == true;

  @override
  void dispose() {
    for (final c in _textos.values) {
      c.dispose();
    }
    _contato.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final naoRealizado = widget.atendimento['status'] == 'nao_realizado';
    return AlertDialog(
      title: const Text('Relato do atendimento'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final c in _campos.entries)
              if (c.key != 'resultado_observacao' || naoRealizado)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _textos[c.key],
                    minLines: 1,
                    maxLines: 5,
                    decoration: InputDecoration(labelText: c.value),
                  ),
                ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _acompanhou,
              onChanged: (v) => setState(() => _acompanhou = v),
              title: const Text('O cliente acompanhou'),
            ),
            TextField(controller: _contato, decoration: const InputDecoration(labelText: 'Quem acompanhou')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(<String, dynamic>{
            'acao': 'atendimento_alterar',
            'atendimento_id': widget.atendimento['id'],
            'campos': {
              for (final c in _textos.entries)
                if (c.key != 'resultado_observacao' || naoRealizado) c.key: c.value.text.trim(),
              // Só manda se mudou (vazio no banco não vira "não" sem querer).
              if (_acompanhou != (widget.atendimento['cliente_presente'] == true)) 'cliente_presente': _acompanhou,
              'contato_cliente_nome': _contato.text.trim(),
            },
          }),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

// =====================================================================
// Medições e fluido de um equipamento
// =====================================================================

/// Devolve a lista de ações (uma por medição ou fluido que mudou).
class DialogoMedicoes extends StatefulWidget {
  const DialogoMedicoes({
    super.key,
    required this.atendimentoId,
    required this.osId,
    required this.medicoes,
    required this.fluidos,
  });

  final String atendimentoId;
  final String osId;

  /// Medições e fluidos já gravados neste atendimento.
  final List<Map<String, dynamic>> medicoes;
  final List<Map<String, dynamic>> fluidos;

  @override
  State<DialogoMedicoes> createState() => _DialogoMedicoesState();
}

class _DialogoMedicoesState extends State<DialogoMedicoes> {
  SupabaseClient get _db => Supabase.instance.client;

  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _equipamentos = [];
  Map<String, dynamic>? _equip;
  List<Map<String, dynamic>> _modelos = [];
  final Map<String, TextEditingController> _campos = {};
  final Map<String, String> _originais = {};
  final _fluido = TextEditingController();
  final _adicionado = TextEditingController();
  final _recolhido = TextEditingController();
  String _fluidoOriginal = '';
  bool _fluidoExiste = false;
  bool _carregandoModelos = false;

  /// Retrato dos 3 campos do fluido ('' = tudo vazio).
  String _estadoFluido() =>
      _fluido.text.trim().isEmpty && _adicionado.text.trim().isEmpty && _recolhido.text.trim().isEmpty
          ? ''
          : '${_fluido.text.trim()}|${_adicionado.text.trim()}|${_recolhido.text.trim()}';

  @override
  void initState() {
    super.initState();
    _carregarEquipamentos();
  }

  @override
  void dispose() {
    for (final c in _campos.values) {
      c.dispose();
    }
    _fluido.dispose();
    _adicionado.dispose();
    _recolhido.dispose();
    super.dispose();
  }

  Future<void> _carregarEquipamentos() async {
    try {
      final r = await _db
          .from('os_equipamentos')
          .select('equipamento_id, equipamentos(id, codigo, descricao, tipo_equipamento_id, fluido_refrigerante)')
          .eq('os_id', widget.osId)
          .isFilter('excluido_em', null);
      final lista = [for (final e in r) if (e['equipamentos'] is Map) Map<String, dynamic>.from(e['equipamentos'] as Map)];
      if (!mounted) return;
      setState(() => _equipamentos = lista);
      if (lista.isNotEmpty) await _escolher(lista.first);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String _chave(Object? equip, Object? modelo) => '$equip:$modelo';

  String _valorTexto(Map<String, dynamic>? m) {
    if (m == null) return '';
    return m['valor_numero'] != null ? numeroBr(m['valor_numero']) : '${m['valor_texto'] ?? ''}';
  }

  Future<void> _escolher(Map<String, dynamic> equip) async {
    setState(() {
      _equip = equip;
      _modelos = [];
      _carregandoModelos = true;
    });
    var modelos = <Map<String, dynamic>>[];
    try {
      // Equipamento sem tipo: sem medições do cadastro (o fluido continua).
      if (equip['tipo_equipamento_id'] != null) {
        modelos = await _db
            .from('modelos_medicao')
            .select('id, nome, unidade, tipo_valor, faixa_min, faixa_max, ordem')
            .eq('tipo_equipamento_id', '${equip['tipo_equipamento_id']}')
            .eq('ativo', true)
            .isFilter('excluido_em', null)
            .order('ordem');
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    }
    // Trocou de equipamento enquanto carregava: esta resposta não vale mais.
    if (!mounted || !identical(_equip, equip)) return;
    setState(() {
      _carregandoModelos = false;
      _modelos = modelos;
      for (final m in modelos) {
        final k = _chave(equip['id'], m['id']);
        if (!_campos.containsKey(k)) {
          final atual = widget.medicoes
              .where((x) => x['equipamento_id'] == equip['id'] && x['modelo_medicao_id'] == m['id'])
              .firstOrNull;
          _originais[k] = _valorTexto(atual);
          _campos[k] = TextEditingController(text: _originais[k]);
        }
      }
      final f = widget.fluidos.where((x) => x['equipamento_id'] == equip['id']).firstOrNull;
      _fluido.text = '${f?['fluido'] ?? equip['fluido_refrigerante'] ?? ''}';
      _adicionado.text = f == null ? '' : numeroBr(f['adicionado_kg']);
      _recolhido.text = f == null ? '' : numeroBr(f['recolhido_kg']);
      _fluidoExiste = f != null;
      _fluidoOriginal = _estadoFluido();
    });
  }

  bool _fora(Map<String, dynamic> m, String texto) {
    final n = lerNumero(texto);
    if (n == null) return false;
    final min = num.tryParse('${m['faixa_min'] ?? ''}'), max = num.tryParse('${m['faixa_max'] ?? ''}');
    return (min != null && n < min) || (max != null && n > max);
  }

  /// Confere antes de fechar (senão parte salva e parte se perde).
  String? _validar() {
    for (final m in _modelos) {
      final c = _campos[_chave(_equip!['id'], m['id'])];
      final t = c?.text.trim() ?? '';
      if (m['tipo_valor'] == 'numero' && t.isNotEmpty && lerNumero(t) == null) {
        return '${m['nome']}: número inválido.';
      }
    }
    for (final c in [_adicionado, _recolhido]) {
      final t = c.text.trim();
      if (t.isNotEmpty && ((lerNumero(t) ?? -1) < 0)) return 'Fluido: quantidade inválida.';
    }
    if (_fluido.text.trim().isEmpty && (_adicionado.text.trim().isNotEmpty || _recolhido.text.trim().isNotEmpty)) {
      return 'Informe o fluido (ex.: R-410A).';
    }
    return null;
  }

  List<Map<String, dynamic>> _acoes() {
    final equip = _equip!;
    final acoes = <Map<String, dynamic>>[];
    for (final m in _modelos) {
      final k = _chave(equip['id'], m['id']);
      final campo = _campos[k];
      if (campo == null) continue;
      final texto = campo.text.trim();
      if (texto == (_originais[k] ?? '')) continue;
      final numero = m['tipo_valor'] == 'numero';
      acoes.add({
        'acao': 'medicao_salvar',
        'atendimento_id': widget.atendimentoId,
        'equipamento_id': equip['id'],
        'modelo_medicao_id': m['id'],
        'valor_numero': numero ? texto : '',
        'valor_texto': numero ? '' : texto,
      });
    }
    final fluidoAgora = _estadoFluido();
    // Mudou (e não é "apagar o que nem existe").
    if (fluidoAgora != _fluidoOriginal && (fluidoAgora.isNotEmpty || _fluidoExiste)) {
      acoes.add({
        'acao': 'fluido_salvar',
        'atendimento_id': widget.atendimentoId,
        'equipamento_id': equip['id'],
        if (fluidoAgora.isEmpty) 'excluir': true,
        'fluido': _fluido.text.trim(),
        'adicionado_kg': _adicionado.text.trim(),
        'recolhido_kg': _recolhido.text.trim(),
      });
    }
    return acoes;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Medições e fluido'),
      content: SizedBox(
        width: 560,
        child: _carregando
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
                  if (_equipamentos.isEmpty)
                    const Text('Esta OS não tem equipamento.', style: TextStyle(color: Cores.neutro))
                  else ...[
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Equipamento'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _equip?['id'] as String?,
                          isDense: true,
                          isExpanded: true,
                          items: [
                            for (final e in _equipamentos)
                              DropdownMenuItem(
                                value: e['id'] as String,
                                child: Text([e['codigo'], e['descricao']].where((x) => x != null).join(' · ')),
                              ),
                          ],
                          // Trocar de equipamento no meio perderia o que foi digitado: salve um por vez.
                          onChanged: (v) {
                            if (v == null || v == _equip?['id']) return;
                            if (_carregandoModelos) return;
                            if (_acoes().isNotEmpty) {
                              setState(() => _erro = 'Salve as mudanças deste equipamento antes de trocar.');
                              return;
                            }
                            _erro = null;
                            _escolher(_equipamentos.firstWhere((e) => e['id'] == v));
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_carregandoModelos)
                      const LinearProgressIndicator(minHeight: 2)
                    else if (_modelos.isEmpty)
                      const Text('Nenhuma medição cadastrada para o tipo deste equipamento.',
                          style: TextStyle(color: Cores.neutro)),
                    for (final m in _modelos)
                      Builder(builder: (_) {
                        final c = _campos[_chave(_equip!['id'], m['id'])];
                        if (c == null) return const SizedBox.shrink();
                        final fora = _fora(m, c.text);
                        final faixa = [m['faixa_min'], m['faixa_max']].any((x) => x != null)
                            ? 'faixa ${numeroBr(m['faixa_min'])}–${numeroBr(m['faixa_max'])}'
                            : null;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TextField(
                            controller: c,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: '${m['nome']} (${m['unidade']})',
                              helperText: fora ? 'Fora da faixa! ($faixa)' : faixa,
                              helperStyle: fora ? const TextStyle(color: Cores.erro, fontWeight: FontWeight.w700) : null,
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 8),
                    const Text('FLUIDO REFRIGERANTE',
                        style: TextStyle(fontSize: 11, letterSpacing: .6, fontWeight: FontWeight.w700, color: Cores.neutro)),
                    Row(children: [
                      Expanded(child: TextField(controller: _fluido, decoration: const InputDecoration(labelText: 'Fluido'))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextField(
                              controller: _adicionado, decoration: const InputDecoration(labelText: 'Adicionado (kg)'))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextField(
                              controller: _recolhido, decoration: const InputDecoration(labelText: 'Recolhido (kg)'))),
                    ]),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Campo vazio apaga a medição. Tudo vazio no fluido apaga o fluido.',
                          style: TextStyle(fontSize: 12, color: Cores.neutro)),
                    ),
                  ],
                ]),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
        FilledButton(
          onPressed: _equip == null || _carregandoModelos
              ? null
              : () {
                  final erro = _validar();
                  if (erro != null) return setState(() => _erro = erro);
                  Navigator.of(context).pop(_acoes());
                },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
