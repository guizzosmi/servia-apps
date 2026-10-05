import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_cadastro.dart';
import '../core/acoes_relato.dart';
import '../core/consultas.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import '../widgets/abas_atendimento.dart' show buscarProduto;
import '../widgets/cadastros_rapidos.dart';

/// Revisão do relato por áudio: o técnico confere o que a IA organizou e
/// leva para o atendimento (texto, equipamento, peças e mão de obra).
/// Nada da IA entra na OS sem passar por aqui.
class RevisaoRelatoTela extends StatefulWidget {
  const RevisaoRelatoTela({super.key, required this.atd, required this.relato});

  final Map<String, dynamic> atd;
  final RelatoAudio relato;

  @override
  State<RevisaoRelatoTela> createState() => _RevisaoRelatoTelaState();
}

class _RevisaoRelatoTelaState extends State<RevisaoRelatoTela> {
  late final Map<String, dynamic> _r = widget.relato.resultado ?? const {};
  late final Map _campos = _r['campos'] is Map ? _r['campos'] as Map : const {};
  late final Map _eq = _r['equipamento'] is Map ? _r['equipamento'] as Map : const {};
  late final Map<String, String> _camposIa = {
    for (final c in camposDoRelato.keys) c: '${_campos[c] ?? ''}'.trim(),
  };
  late final Map<String, TextEditingController> _textos = {
    for (final e in _camposIa.entries) e.key: TextEditingController(text: e.value),
  };
  late final List<PecaRevisada> _pecas = [
    for (final i in (_r['itens'] is List ? _r['itens'] as List : const []).whereType<Map>()) _peca(i),
  ];
  late final PecaRevisada? _mao = _maoDeObra();
  late final List<MedicaoRevisada> _medicoes = [
    for (final m in (_r['medicoes'] is List ? _r['medicoes'] as List : const []).whereType<Map>())
      MedicaoRevisada(
        falado: '${m['nome'] ?? 'Medição'}',
        valorIa: num.tryParse('${m['valor']}'),
        unidadeFalada: '${m['unidade'] ?? ''}',
      ),
  ];
  late final FluidoRevisado? _fluido = _fluidoFalado();

  /// O tipo do equipamento para o qual as medições foram propostas.
  String? _tipoDasMedicoes;
  bool _medicoesPropostas = false;

  // Equipamento
  late final String _proposta = '${_eq['tipo'] ?? 'confirmar'}';
  late final String? _equipIa =
      (_proposta == 'identificado' || _proposta == 'sugerido') ? _eq['equipamento_id'] as String? : null;
  late String? _ambiente = _eq['ambiente_id'] as String? ?? _ambienteDoEquip(_equipIa);
  late String? _equip = _equipIa;
  EquipamentoNovo? _novo;
  bool _salvando = false;

  Map<String, dynamic> get _os => EstadoApp.instancia.banco!.um('ordens_servico', widget.atd['os_id']) ?? const {};

  @override
  void dispose() {
    for (final c in _textos.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Candidatos do catálogo, sem repetidos e só com produto (o menu exige
  /// valores únicos).
  static List<Map<String, dynamic>> _candidatos(Object? v, {String chave = 'produto_id'}) {
    final vistos = <String>{};
    return [
      for (final c in (v is List ? v : const []).whereType<Map>())
        if (c[chave] != null && vistos.add('${c[chave]}')) c.cast<String, dynamic>(),
    ];
  }

  /// Proposta para uma peça: o 1º candidato do catálogo se a nota for boa;
  /// senão, o texto falado (o técnico troca se quiser).
  PecaRevisada _peca(Map i) {
    final cands = _candidatos(i['candidatos']);
    final bom = cands.isNotEmpty && (num.tryParse('${cands.first['nota']}') ?? 0) >= 0.4;
    final qtd = num.tryParse('${i['quantidade'] ?? 1}') ?? 1;
    return PecaRevisada(
      falado: '${i['falado'] ?? i['nome'] ?? 'Peça'}',
      quantidadeIa: qtd <= 0 ? 1 : qtd,
      unidade: '${i['unidade'] ?? 'un'}',
      candidatos: cands,
      escolhaIa: bom ? '${cands.first['produto_id']}' : PecaRevisada.livre,
    );
  }

  /// Mão de obra: com o item do catálogo, quando há quantidade e cobrança.
  PecaRevisada? _maoDeObra() {
    final mo = _r['mao_de_obra'] is Map ? _r['mao_de_obra'] as Map : const {};
    final cobrar = !(_r['cobranca'] is Map && (_r['cobranca'] as Map)['cobrar'] == false);
    final qtd = num.tryParse('${mo['quantidade'] ?? 0}') ?? 0;
    final cands = _candidatos(mo['candidatos']);
    if (qtd <= 0 && cands.isEmpty) return null;
    final incluir = cobrar && qtd > 0;
    return PecaRevisada(
      falado: 'Mão de obra',
      quantidadeIa: qtd,
      unidade: cands.isEmpty ? 'h' : '${cands.first['unidade'] ?? 'h'}',
      candidatos: cands,
      escolhaIa: !incluir ? PecaRevisada.nao : (cands.isEmpty ? PecaRevisada.livre : '${cands.first['produto_id']}'),
    );
  }

  FluidoRevisado? _fluidoFalado() {
    final f = _r['fluido'];
    if (f is! Map) return null;
    final ad = num.tryParse('${f['adicionado_kg'] ?? 0}') ?? 0;
    final rec = num.tryParse('${f['recolhido_kg'] ?? 0}') ?? 0;
    final tipo = '${f['tipo'] ?? ''}'.trim();
    if (tipo.isEmpty && ad == 0 && rec == 0) return null;
    return FluidoRevisado(tipoIa: tipo, adicionadoIa: ad, recolhidoIa: rec);
  }

  /// O tipo do equipamento escolhido (ou do cadastrado agora, se for de um tipo existente).
  String? get _tipoEquip {
    if (_novo != null) return _novo!.tipoNovo == null ? _novo!.tipoId : null;
    return _equip == null ? null : EstadoApp.instancia.banco!.um('equipamentos', _equip)?['tipo_equipamento_id'] as String?;
  }

  /// As medições do cadastro para o equipamento: propõe de novo quando o tipo muda.
  List<Map<String, dynamic>> _modelosAtuais() {
    final tipo = _tipoEquip;
    final modelos = tipo == null ? const <Map<String, dynamic>>[] : EstadoApp.instancia.banco!.modelosDoTipo(tipo);
    if (!_medicoesPropostas || tipo != _tipoDasMedicoes) {
      _medicoesPropostas = true;
      _tipoDasMedicoes = tipo;
      for (final m in _medicoes) {
        m.modeloIa = medicaoDoCadastro(modelos, m.falado, m.unidadeFalada);
        m.modeloId = m.modeloIa;
      }
    }
    return modelos;
  }

  String? _ambienteDoEquip(String? id) =>
      id == null ? null : EstadoApp.instancia.banco!.um('equipamentos', id)?['ambiente_id'] as String?;

  // ------------------------------------------------------------------

  Future<void> _aplicar() async {
    setState(() => _salvando = true);
    try {
      await AcoesRelato.aplicarRevisao(
        widget.atd,
        widget.relato.id,
        DecisaoRevisao(
          camposIa: _camposIa,
          camposFinal: {for (final e in _textos.entries) e.key: e.value.text},
          propostaEquipamento: _proposta,
          equipamentoIaId: _equipIa,
          equipamentoId: _novo == null ? _equip : null,
          equipamentoNovo: _novo,
          pecas: _pecas,
          maoDeObra: _mao,
          medicoes: _medicoes,
          fluido: _fluido,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Relato levado para o atendimento.')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível levar o relato: $e'), backgroundColor: Cores.erro));
    }
  }

  Future<void> _descartar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar este relato?'),
        content: const Text('Nada dele vai para o atendimento. O áudio continua registrado na plataforma.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Descartar', style: TextStyle(color: Cores.erro)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AcoesRelato.descartar(widget.relato.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _cadastrar() async {
    final os = _os;
    final novo = await cadastrarEquipamento(
      context,
      localId: os['local_id'] as String?,
      codigosUsados: AcoesCadastro.codigosDoCliente(os['cliente_id']),
      sugestao: '${_r['equipamento_falado'] ?? ''}'.trim(),
      ambienteId: _ambiente,
    );
    if (novo == null || !mounted) return;
    setState(() {
      _novo = novo;
      _equip = null;
    });
  }

  Future<void> _outroDoCatalogo(PecaRevisada p) async {
    final prod = await buscarProduto(context, titulo: p.falado);
    if (prod == null || !mounted) return;
    setState(() {
      if (!p.candidatos.any((c) => c['produto_id'] == prod['id'])) {
        p.candidatos.add({
          'produto_id': prod['id'],
          'codigo': prod['codigo'],
          'descricao': prod['descricao'],
          'tipo': prod['tipo'],
          'unidade': prod['unidade'],
        });
      }
      p.escolha = '${prod['id']}';
      if (p.quantidade <= 0) p.quantidade = 1;
    });
  }

  // ------------------------------------------------------------------

  Widget _titulo(String t, {String? ajuda}) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          if (ajuda != null) Text(ajuda, style: const TextStyle(color: Cores.neutro, fontSize: 13)),
        ]),
      );

  Widget _textosRelato() {
    final atual = EstadoApp.instancia.banco!.um('atendimentos', widget.atd['id']) ?? widget.atd;
    final jaTem = camposDoRelato.keys.any((c) => '${atual[c] ?? ''}'.trim().isNotEmpty);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Relato',
          ajuda: jaTem
              ? 'O atendimento já tem texto: o da IA entra embaixo do que está escrito.'
              : 'Confira e ajuste o texto. Ele vai para o relato do atendimento.'),
      for (final e in camposDoRelato.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _textos[e.key],
            minLines: 2,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: e.value, alignLabelWithHint: true),
          ),
        ),
    ]);
  }

  Widget _equipamento() {
    final banco = EstadoApp.instancia.banco!;
    final os = _os;
    final ambientes = AcoesCadastro.ambientesDo(os['local_id']);
    // Os ambientes que a IA achou parecidos vêm primeiro.
    final sugeridos = {
      for (final c in _candidatos(_eq['candidatos_ambientes'], chave: 'ambiente_id')) '${c['ambiente_id']}'
    };
    ambientes.sort((a, b) {
      final sa = sugeridos.contains('${a['id']}') ? 0 : 1, sb = sugeridos.contains('${b['id']}') ? 0 : 1;
      return sa != sb ? sa.compareTo(sb) : '${a['nome']}'.compareTo('${b['nome']}');
    });
    // Do ambiente escolhido; sem ambiente, os do local que não têm ambiente.
    final doAmbiente = banco
        .todos('equipamentos')
        .where((e) =>
            e['excluido_em'] == null &&
            e['situacao'] != 'removido' &&
            (_ambiente != null
                ? e['ambiente_id'] == _ambiente
                : e['local_id'] == os['local_id'] && e['ambiente_id'] == null))
        .toList()
      ..sort((a, b) => '${a['codigo'] ?? ''}'.compareTo('${b['codigo'] ?? ''}'));
    // O equipamento da OS (sem ambiente) também aparece.
    if (_equipIa != null && !doAmbiente.any((e) => e['id'] == _equipIa)) {
      final e = banco.um('equipamentos', _equipIa);
      if (e != null) doAmbiente.insert(0, e);
    }
    String rotulo(Map e) => [e['codigo'], e['descricao']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Equipamento', ajuda: 'A IA entendeu: ${_eq['texto'] ?? 'sem proposta'}.'),
      if (ambientes.isNotEmpty)
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Ambiente'),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: ambientes.any((a) => a['id'] == _ambiente) ? _ambiente : null,
              isDense: true,
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Escolha o ambiente')),
                for (final a in ambientes)
                  DropdownMenuItem<String?>(
                    value: '${a['id']}',
                    child: Text('${a['nome']}${sugeridos.contains('${a['id']}') ? '  (falado)' : ''}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() {
                _ambiente = v;
                if (_equip != null && _equip != _equipIa && _ambienteDoEquip(_equip) != v) _equip = null;
              }),
            ),
          ),
        ),
      if (_novo != null)
        Card(
          margin: const EdgeInsets.only(top: 8),
          child: ListTile(
            leading: const Icon(Icons.add_box_outlined, color: Cores.sucesso),
            title: Text(_novo!.rotulo),
            subtitle: const Text('Cadastrado agora (vai junto com o relato)'),
            trailing: IconButton(
              tooltip: 'Tirar',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _novo = null),
            ),
          ),
        )
      else ...[
        for (final e in doAmbiente)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_equip == e['id'] ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: _equip == e['id'] ? Cores.indigo500 : Cores.neutro),
            title: Text(rotulo(e)),
            subtitle: e['id'] == _equipIa ? const Text('Proposto pela IA') : null,
            onTap: () => setState(() => _equip = '${e['id']}'),
          ),
        if (_ambiente != null && doAmbiente.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nenhum equipamento cadastrado neste ambiente.', style: TextStyle(color: Cores.neutro)),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(_equip == null ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: _equip == null ? Cores.indigo500 : Cores.neutro),
          title: const Text('Não identificar agora'),
          onTap: () => setState(() => _equip = null),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _cadastrar,
            icon: const Icon(Icons.add),
            label: Text(_proposta == 'cadastrar' && '${_r['equipamento_falado'] ?? ''}'.trim().isNotEmpty
                ? 'Cadastrar ${_r['equipamento_falado']}'
                : 'Cadastrar equipamento'),
          ),
        ),
      ],
    ]);
  }

  Widget _linhaPeca(PecaRevisada p, {bool mao = false}) {
    String rotuloCand(Map c) {
      final nota = num.tryParse('${c['nota'] ?? ''}');
      final txt = [c['codigo'], c['descricao']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
      return nota == null ? txt : '$txt (${(nota * 100).round()}%)';
    }

    const outro = '_outro';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(mao ? 'Mão de obra' : 'Falado: "${p.falado}"', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (mao && p.escolhaIa == PecaRevisada.nao && p.quantidadeIa > 0)
            const Text('O técnico disse que não há cobrança.', style: TextStyle(color: Cores.alerta, fontSize: 13)),
          const SizedBox(height: 4),
          DropdownButton<String>(
            value: p.escolha,
            isExpanded: true,
            items: [
              for (final c in p.candidatos)
                DropdownMenuItem(value: '${c['produto_id']}', child: Text(rotuloCand(c), overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(
                value: PecaRevisada.livre,
                child: Text(mao ? 'Mão de obra (sem item do catálogo)' : 'Sem catálogo: "${p.falado}"',
                    overflow: TextOverflow.ellipsis),
              ),
              const DropdownMenuItem(value: outro, child: Text('Outro do catálogo...')),
              const DropdownMenuItem(value: PecaRevisada.nao, child: Text('Não incluir', style: TextStyle(color: Cores.erro))),
            ],
            onChanged: (v) {
              if (v == null) return;
              if (v == outro) {
                _outroDoCatalogo(p);
              } else {
                setState(() {
                  p.escolha = v;
                  // (mão de obra proposta com 0: escolheu incluir, começa em 1)
                  if (v != PecaRevisada.nao && p.quantidade <= 0) p.quantidade = 1;
                });
              }
            },
          ),
          if (p.escolha != PecaRevisada.nao)
            Row(children: [
              const Text('Quantidade'),
              const Spacer(),
              IconButton(
                onPressed: p.quantidade <= (mao ? 0.5 : 1)
                    ? null
                    : () => setState(() => p.quantidade = p.quantidade - (mao ? 0.5 : 1)),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('${numeroBr(p.quantidade)} ${p.unidade}', style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                onPressed: () => setState(() => p.quantidade = (p.quantidade <= 0 ? 0 : p.quantidade) + (mao ? 0.5 : 1)),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ]),
        ]),
      ),
    );
  }

  Widget _medicoesFaladas() {
    final modelos = _modelosAtuais()
        .where((x) => x['tipo_valor'] == null || x['tipo_valor'] == 'numero')
        .toList();
    final semEquip = _equip == null && _novo == null;
    final fl = _fluido;
    String rotulo(Map m) => '${m['nome']}${m['unidade'] == null || m['unidade'] == 'outro' ? '' : ' (${m['unidade']})'}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Medições faladas',
          ajuda: semEquip
              ? 'Escolha o equipamento (acima) para registrar as medições nele.'
              : 'Vão para a aba Medições do equipamento. Confira a medição do cadastro e o valor.'),
      for (final m in _medicoes)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Falado: "${m.falado}" ${numeroBr(m.valorIa)} ${m.unidadeFalada}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (!semEquip)
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButton<String?>(
                      value: modelos.any((x) => '${x['id']}' == m.modeloId) ? m.modeloId : null,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Não registrar', style: TextStyle(color: Cores.erro))),
                        for (final x in modelos)
                          DropdownMenuItem<String?>(
                              value: '${x['id']}', child: Text(rotulo(x), overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => m.modeloId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: m.valor == null ? '' : numeroBr(m.valor),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'Valor', isDense: true),
                      onChanged: (t) => m.valor = num.tryParse(t.trim().replaceAll(',', '.')),
                    ),
                  ),
                ]),
            ]),
          ),
        ),
      if (fl != null)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 12, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: fl.registrar && !semEquip,
                onChanged: semEquip ? null : (v) => setState(() => fl.registrar = v ?? false),
                title: Text('Fluido: ${fl.tipoIa.isEmpty ? '(tipo não falado)' : fl.tipoIa}'),
                subtitle: Text('${numeroBr(fl.adicionadoIa)} kg adicionados · ${numeroBr(fl.recolhidoIa)} kg recolhidos'),
              ),
              if (fl.registrar && !semEquip)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: fl.tipo,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(labelText: 'Fluido (ex.: R-410A)', isDense: true),
                        onChanged: (t) => fl.tipo = t,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: numeroBr(fl.adicionado),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Adicionado (kg)', isDense: true),
                        onChanged: (t) => fl.adicionado =
                            num.tryParse(t.trim().replaceAll(',', '.')) ?? 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: numeroBr(fl.recolhido),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Recolhido (kg)', isDense: true),
                        onChanged: (t) => fl.recolhido =
                            num.tryParse(t.trim().replaceAll(',', '.')) ?? 0,
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final duvidas = (_r['duvidas'] is List ? _r['duvidas'] as List : const [])
        .map((x) => '$x'.trim())
        .where((x) => x.isNotEmpty)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar o relato'),
        actions: [
          IconButton(tooltip: 'Descartar', onPressed: _salvando ? null : _descartar, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        Text('Gravado em ${dataHoraBr(widget.relato.gravadoEm)}', style: const TextStyle(color: Cores.neutro)),
        if (duvidas.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Cores.alerta.withValues(alpha: .1), borderRadius: BorderRadius.circular(8)),
            child: Text('A IA ficou em dúvida: ${duvidas.join(' · ')}', style: const TextStyle(color: Cores.alerta)),
          ),
        if ((widget.relato.transcricao ?? '').trim().isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('O que foi falado'),
            children: [
              Text(widget.relato.transcricao!, style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
          ),
        _textosRelato(),
        _equipamento(),
        _titulo('Peças',
            ajuda: _pecas.isEmpty ? 'Nenhuma peça falada.' : 'Confira o item do catálogo e a quantidade de cada uma.'),
        for (final p in _pecas) _linhaPeca(p),
        if (_mao != null) ...[
          _titulo('Mão de obra'),
          _linhaPeca(_mao, mao: true),
        ],
        if (_medicoes.isNotEmpty || _fluido != null) _medicoesFaladas(),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _salvando ? null : _aplicar,
            icon: _salvando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Levar para o atendimento'),
          ),
        ),
      ]),
    );
  }
}
