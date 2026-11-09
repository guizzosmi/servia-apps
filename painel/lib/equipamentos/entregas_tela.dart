import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/arquivo_web.dart';
import '../servicos/comercial.dart' show reais;
import '../servicos/status.dart';
import '../widgets/margem.dart';
import 'servico.dart';
import 'widgets.dart';

/// Guia 104: o que vem do app do técnico na entrega e na devolução.
///   Divergências  apontamentos (avaria, falta, sujeira, uso acima) para o gestor decidir: cobrar, absorver ou reparar
///   Checklists    o que o app pede na saída, no retorno, na preparação, na preventiva e na manutenção
class EqpEntregasTela extends StatefulWidget {
  const EqpEntregasTela({super.key});

  @override
  State<EqpEntregasTela> createState() => _EqpEntregasTelaState();
}

const tiposApontamentoEqp = {'avaria': 'Avaria', 'falta': 'Falta', 'sujeira': 'Sujeira', 'uso_acima': 'Uso acima'};
const decisoesApontamentoEqp = {'pendente': 'Pendente', 'cobrar': 'Cobrar', 'absorver': 'Absorvido', 'reparar': 'Reparo'};
const tiposChecklistEqp = {
  'saida': 'Saída',
  'retorno': 'Retorno',
  'preparacao': 'Preparação',
  'preventiva': 'Preventiva',
  'manutencao': 'Manutenção',
};
const respostasChecklistEqp = {'ok_nok': 'OK / não OK', 'numero': 'Número', 'texto': 'Texto'};

class _EqpEntregasTelaState extends State<EqpEntregasTela> {
  String _situacao = 'aberto';
  List<Map<String, dynamic>>? _apontamentos;
  List<Map<String, dynamic>>? _checklists;
  String? _erro;

  bool get _gestor => Sessao.atual?.tem(Papel.gestor) ?? false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final a = await eqp('eqp_apontamentos_lista', {'situacao': _situacao});
      final c = await eqp('eqp_checklist_modelos_lista');
      if (mounted) {
        setState(() {
          _apontamentos = listaDe(a['apontamentos']);
          _checklists = listaDe(c['checklists']);
          _erro = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    }
  }

  Future<void> _acao(String funcao, Map<String, dynamic> p, String ok) async {
    try {
      final r = await eqp(funcao, p);
      if (mounted) avisarEqp(context, r['os'] != null ? '$ok · ${r['os']}' : ok);
      await _carregar();
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _cobrar(Map<String, dynamic> a) async {
    final valor = await pedirTextoEqp(context, 'Cobrar ${a['codigo']}',
        'Valor a cobrar (sugerido: ${a['valor_sugerido'] == null ? 'nenhum' : reais(a['valor_sugerido'])})',
        obrigatorio: false);
    if (valor == null) return;
    final n = num.tryParse(valor.replaceAll('.', '').replaceAll(',', '.'));
    await _acao('eqp_apontamento_acao', {
      'acao': 'decidir',
      'apontamento_id': a['id'],
      'decisao': 'cobrar',
      if (n != null) 'valor_cobrar': n,
    }, 'Vai para a cobrança da locação');
  }

  Future<void> _decidir(Map<String, dynamic> a, String decisao) async {
    final motivo = await pedirTextoEqp(
        context, decisao == 'reparar' ? 'Reparar ${a['codigo']}' : 'Absorver ${a['codigo']}', 'Motivo (opcional)',
        obrigatorio: false);
    if (motivo == null) return;
    await _acao('eqp_apontamento_acao', {'acao': 'decidir', 'apontamento_id': a['id'], 'decisao': decisao, 'motivo': motivo},
        decisao == 'reparar' ? 'OS de reparo aberta' : 'Absorvido pela empresa');
  }

  Future<void> _cancelar(Map<String, dynamic> a) async {
    final motivo = await pedirTextoEqp(context, 'Cancelar ${a['codigo']}', 'Motivo');
    if (motivo == null) return;
    await _acao('eqp_apontamento_acao', {'acao': 'cancelar', 'apontamento_id': a['id'], 'motivo': motivo}, 'Apontamento cancelado');
  }

  Future<void> _checklist([Map<String, dynamic>? c]) async {
    final apoio = await eqpApoio();
    if (!mounted) return;
    final p = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditorChecklist(checklist: c, tipos: listaDe(apoio['tipos_equipamento'])),
    );
    if (p == null) return;
    await _acao('eqp_checklist_acao', {'acao': 'salvar', if (c != null) 'checklist_modelo_id': c['id'], ...p}, 'Checklist salvo');
  }

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    if (_erro != null && _apontamentos == null) return Center(child: Text(_erro!, style: const TextStyle(color: Cores.erro)));
    if (_apontamentos == null) return const Center(child: CircularProgressIndicator());
    return DefaultTabController(
      length: 2,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: margemDaTela(context).copyWith(bottom: 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Entregas e devoluções',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const Text(
                'O app do técnico registra a entrega e a devolução com o ponto do GPS, fotos, checklist e a assinatura de '
                'quem recebe. O que voltou diferente aparece aqui para você decidir.',
                style: TextStyle(color: Cores.neutro)),
            const TabBar(isScrollable: true, tabs: [Tab(text: 'Divergências'), Tab(text: 'Checklists')]),
          ]),
        ),
        Expanded(
          child: TabBarView(children: [
            _divergencias(),
            _listaChecklists(),
          ]),
        ),
      ]),
    );
  }

  Widget _divergencias() => RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(padding: margemDaTela(context), children: [
          Wrap(spacing: 6, children: [
            for (final s in const {'aberto': 'Para decidir', 'decidido': 'Decididos', 'todos': 'Todos'}.entries)
              ChoiceChip(
                label: Text(s.value),
                selected: _situacao == s.key,
                onSelected: (_) {
                  setState(() => _situacao = s.key);
                  _carregar();
                },
              ),
          ]),
          const SizedBox(height: 8),
          if (_apontamentos!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nenhuma divergência aqui.', style: TextStyle(color: Cores.neutro)),
            ),
          for (final a in _apontamentos!)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text('${a['codigo']} · ${tiposApontamentoEqp[a['tipo']] ?? a['tipo']} · ${a['equipamento']}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Text(a['situacao'] == 'cancelado' ? 'Cancelado' : decisoesApontamentoEqp[a['decisao']] ?? '',
                        style: TextStyle(
                            color: a['situacao'] == 'aberto' ? Cores.alerta : Cores.neutro, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 4),
                  Text('${a['descricao']}'),
                  Text(
                    [
                      dataHoraBr(a['apontado_em']),
                      if (a['cliente'] != null) '${a['cliente']}',
                      if (a['locacao'] != null) '${a['locacao']}',
                      if (a['quem'] != null) 'por ${a['quem']}',
                      if (a['aceite'] != null) 'assinado por ${a['aceite']}',
                    ].join(' · '),
                    style: const TextStyle(color: Cores.neutro, fontSize: 13),
                  ),
                  Text(
                    [
                      if (a['valor_sugerido'] != null) 'Sugerido ${reais(a['valor_sugerido'])}',
                      if (a['valor_cobrar'] != null) 'A cobrar ${reais(a['valor_cobrar'])}',
                      if (a['os'] != null) 'Reparo ${a['os']}',
                      if (a['motivo_decisao'] != null) '${a['motivo_decisao']}',
                    ].join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if ((a['fotos'] as List?)?.isNotEmpty ?? false) FotosEqp(a['fotos'] as List),
                  const SizedBox(height: 4),
                  Wrap(spacing: 4, children: [
                    if (a['movimento_id'] != null)
                      TextButton.icon(
                        onPressed: () => verRegistroEqp(context, '${a['movimento_id']}'),
                        icon: const Icon(Icons.fact_check_outlined, size: 18),
                        label: const Text('Ver o registro'),
                      ),
                    if (_gestor && a['situacao'] == 'aberto') ...[
                      if (a['cliente'] != null)
                        TextButton(onPressed: () => _cobrar(a), child: const Text('Cobrar do cliente')),
                      TextButton(onPressed: () => _decidir(a, 'absorver'), child: const Text('Absorver')),
                      TextButton(onPressed: () => _decidir(a, 'reparar'), child: const Text('Reparar (abre OS)')),
                    ],
                    if (_gestor && a['situacao'] != 'cancelado' && a['medicao_id'] == null)
                      TextButton(
                        onPressed: () => _cancelar(a),
                        child: const Text('Cancelar', style: TextStyle(color: Cores.erro)),
                      ),
                  ]),
                ]),
              ),
            ),
        ]),
      );

  Widget _listaChecklists() => RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(padding: margemDaTela(context), children: [
          if (_gestor)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _checklist(),
                icon: const Icon(Icons.add),
                label: const Text('Novo checklist'),
              ),
            ),
          const SizedBox(height: 8),
          if (_checklists!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'Nenhum checklist. Sem ele, o app registra a entrega só com GPS, fotos, horímetro e a assinatura.',
                  style: TextStyle(color: Cores.neutro)),
            ),
          for (final c in _checklists!)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('${c['nome']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  tiposChecklistEqp[c['tipo']] ?? '${c['tipo']}',
                  '${c['vale_para']}',
                  '${listaDe(c['itens']).length} itens',
                  if (c['ativo'] != true) 'inativo',
                ].join(' · ')),
                trailing: _gestor
                    ? Wrap(children: [
                        IconButton(tooltip: 'Editar', onPressed: () => _checklist(c), icon: const Icon(Icons.edit_outlined)),
                        IconButton(
                          tooltip: c['ativo'] == true ? 'Inativar' : 'Ativar',
                          onPressed: () => _acao(
                              'eqp_checklist_acao',
                              {'acao': c['ativo'] == true ? 'inativar' : 'ativar', 'checklist_modelo_id': c['id']},
                              c['ativo'] == true ? 'Checklist inativado' : 'Checklist ativado'),
                          icon: Icon(c['ativo'] == true ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        ),
                      ])
                    : null,
              ),
            ),
        ]),
      );
}

/// O registro feito pelo app: ponto do GPS (com o mapa), fotos, checklist, aceite e apontamentos.
Future<void> verRegistroEqp(BuildContext context, String movimentoId) async {
  Map<String, dynamic> r;
  try {
    r = await eqp('eqp_registro_ver', {'movimento_id': movimentoId});
  } catch (e) {
    if (context.mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    return;
  }
  if (!context.mounted) return;
  final m = Map<String, dynamic>.from((r['movimento'] as Map?) ?? const {});
  final gps = Map<String, dynamic>.from((r['gps'] as Map?) ?? const {});
  final ck = r['checklist'] is Map ? Map<String, dynamic>.from(r['checklist'] as Map) : null;
  final ac = r['aceite'] is Map ? Map<String, dynamic>.from(r['aceite'] as Map) : null;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${nomesEvento[m['evento']] ?? m['evento']} · ${m['equipamento'] ?? ''}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${dataHoraBr(m['ocorrido_em'])} · ${m['quem'] ?? ''} · ${m['para'] ?? ''}'),
            const SizedBox(height: 8),
            if (gps['latitude'] != null) ...[
              Text('Ponto do GPS: ${gps['latitude']}, ${gps['longitude']} (± ${num.tryParse('${gps['precisao_m']}')?.round() ?? '?'} m, '
                  '${dataHoraBr(gps['em'])})'),
              TextButton.icon(
                onPressed: () => abrirEmNovaAba('${gps['mapa']}'),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Abrir no mapa'),
              ),
            ] else
              Text('Sem o ponto do GPS${gps['motivo'] != null ? ': ${gps['motivo']}' : ''}.',
                  style: const TextStyle(color: Cores.alerta)),
            if ((m['fotos'] as List?)?.isNotEmpty ?? false) FotosEqp(m['fotos'] as List),
            if (m['leitura'] != null) Text('Leitura: ${m['leitura']}'),
            if (ck != null) ...[
              const SizedBox(height: 8),
              Text('Checklist${ck['nome'] != null ? ' · ${ck['nome']}' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
              for (final i in listaDe(ck['respostas']))
                Text('• ${i['texto']}: ${i['ok'] == null ? (i['numero'] ?? i['valor_texto'] ?? '—') : (i['ok'] == true ? 'OK' : 'NÃO OK')}'
                    '${i['observacao'] != null ? ' (${i['observacao']})' : ''}'),
            ],
            const SizedBox(height: 8),
            if (ac != null) ...[
              Text('Assinado por ${ac['nome']}${ac['documento_pessoa'] != null ? ' (${ac['documento_pessoa']})' : ''} '
                  'em ${dataHoraBr(ac['criado_em'])}'),
              if (ac['documento_sha256'] != null)
                SelectableText('Identificação do resumo (SHA-256): ${ac['documento_sha256']}',
                    style: const TextStyle(fontSize: 12, color: Cores.neutro)),
              if (ac['documento_caminho'] != null)
                TextButton.icon(
                  onPressed: () async {
                    try {
                      abrirEmNovaAba(await Supabase.instance.client.storage
                          .from('assinaturas')
                          .createSignedUrl('${ac['documento_caminho']}', 600));
                    } catch (e) {
                      if (ctx.mounted) avisarEqp(ctx, mensagemDeErro(e), erro: true);
                    }
                  },
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Resumo assinado (PDF)'),
                ),
            ] else if (m['aceite_motivo'] != null)
              Text('Sem assinatura: ${m['aceite_motivo']}', style: const TextStyle(color: Cores.alerta)),
            for (final a in listaDe(r['apontamentos']))
              Text('${a['codigo']} · ${tiposApontamentoEqp[a['tipo']] ?? a['tipo']}: ${a['descricao']}'
                  '${a['valor_sugerido'] != null ? ' · ${reais(a['valor_sugerido'])}' : ''}'),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fechar'))],
    ),
  );
}

class _ItemEditor {
  _ItemEditor({this.id, String texto = '', this.resposta = 'ok_nok', this.obrigatorio = true, this.foto = false})
      : texto = TextEditingController(text: texto);
  final String? id;
  final TextEditingController texto;
  String resposta;
  bool obrigatorio;
  bool foto;
}

class _EditorChecklist extends StatefulWidget {
  const _EditorChecklist({this.checklist, required this.tipos});
  final Map<String, dynamic>? checklist;
  final List<Map<String, dynamic>> tipos;

  @override
  State<_EditorChecklist> createState() => _EditorChecklistState();
}

class _EditorChecklistState extends State<_EditorChecklist> {
  late final _nome = TextEditingController(text: '${widget.checklist?['nome'] ?? ''}');
  late String _tipo = '${widget.checklist?['tipo'] ?? 'saida'}';
  late String? _tipoEquipamento = widget.checklist?['tipo_equipamento_id'] as String?;
  late final List<_ItemEditor> _itens = [
    for (final i in listaDe(widget.checklist?['itens']))
      _ItemEditor(
        id: i['id'] as String?,
        texto: '${i['texto']}',
        resposta: '${i['resposta'] ?? 'ok_nok'}',
        obrigatorio: i['obrigatorio'] != false,
        foto: i['foto_obrigatoria'] == true,
      ),
    if (widget.checklist == null) ...[
      _ItemEditor(texto: 'Equipamento completo (acessórios, mangueiras, cabos)'),
      _ItemEditor(texto: 'Funcionando no teste'),
      _ItemEditor(texto: 'Sem vazamento', foto: true),
      _ItemEditor(texto: 'Limpo'),
    ],
  ];
  String? _erro;

  bool get _especifico => widget.checklist?['equipamento_id'] != null || widget.checklist?['modelo_id'] != null;

  @override
  void dispose() {
    _nome.dispose();
    for (final i in _itens) {
      i.texto.dispose();
    }
    super.dispose();
  }

  void _ok() {
    final itens = _itens.where((i) => i.texto.text.trim().isNotEmpty).toList();
    if (_nome.text.trim().isEmpty || itens.isEmpty) {
      setState(() => _erro = 'Informe o nome e ao menos um item.');
      return;
    }
    Navigator.of(context).pop({
      'nome': _nome.text.trim(),
      'tipo': _tipo,
      // Checklist de um equipamento ou de um modelo (pela API): o "vale para" fica como está.
      if (!_especifico) 'tipo_equipamento_id': _tipoEquipamento,
      'itens': [
        for (final i in itens)
          {
            if (i.id != null) 'id': i.id,
            'texto': i.texto.text.trim(),
            'resposta': i.resposta,
            'obrigatorio': i.obrigatorio,
            'foto_obrigatoria': i.foto,
          },
      ],
    });
  }

  @override
  Widget build(BuildContext context) {
    final especifico = _especifico;
    return AlertDialog(
      title: Text(widget.checklist == null ? 'Novo checklist' : 'Editar checklist'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _nome, decoration: const InputDecoration(labelText: 'Nome (ex.: Saída do macaco)')),
            const SizedBox(height: 10),
            const Text('Quando o app pede', style: TextStyle(fontWeight: FontWeight.w700)),
            Wrap(spacing: 6, children: [
              for (final t in tiposChecklistEqp.entries)
                ChoiceChip(label: Text(t.value), selected: _tipo == t.key, onSelected: (_) => setState(() => _tipo = t.key)),
            ]),
            const SizedBox(height: 10),
            const Text('Vale para', style: TextStyle(fontWeight: FontWeight.w700)),
            if (especifico)
              Text('${widget.checklist?['vale_para']} (mude pela API, se precisar)', style: const TextStyle(color: Cores.neutro))
            else
              Wrap(spacing: 6, runSpacing: 4, children: [
                ChoiceChip(
                  label: const Text('Todos os equipamentos'),
                  selected: _tipoEquipamento == null,
                  onSelected: (_) => setState(() => _tipoEquipamento = null),
                ),
                for (final t in widget.tipos)
                  ChoiceChip(
                    label: Text('${t['nome']}'),
                    selected: _tipoEquipamento == t['id'],
                    onSelected: (_) => setState(() => _tipoEquipamento = t['id'] as String?),
                  ),
              ]),
            const SizedBox(height: 10),
            const Text('Itens', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final i in _itens)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Expanded(child: TextField(controller: i.texto, decoration: const InputDecoration(isDense: true))),
                  const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    tooltip: 'Tipo de resposta',
                    initialValue: i.resposta,
                    onSelected: (v) => setState(() => i.resposta = v),
                    itemBuilder: (_) => [
                      for (final r in respostasChecklistEqp.entries) PopupMenuItem(value: r.key, child: Text(r.value)),
                    ],
                    child: Chip(label: Text(respostasChecklistEqp[i.resposta] ?? i.resposta)),
                  ),
                  Tooltip(
                    message: 'Obrigatório',
                    child: Checkbox(value: i.obrigatorio, onChanged: (v) => setState(() => i.obrigatorio = v ?? true)),
                  ),
                  IconButton(
                    tooltip: i.foto ? 'Pede foto' : 'Sem foto',
                    onPressed: () => setState(() => i.foto = !i.foto),
                    icon: Icon(i.foto ? Icons.photo_camera : Icons.photo_camera_outlined,
                        color: i.foto ? Cores.indigo500 : Cores.neutro),
                  ),
                  IconButton(
                    tooltip: 'Tirar o item',
                    onPressed: () => setState(() => _itens.remove(i)),
                    icon: const Icon(Icons.close),
                  ),
                ]),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _itens.add(_ItemEditor())),
                icon: const Icon(Icons.add),
                label: const Text('Item'),
              ),
            ),
            const Text('A caixa marca o item obrigatório; a câmera, que o item pede foto.',
                style: TextStyle(color: Cores.neutro, fontSize: 12)),
            if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _ok, child: const Text('Salvar')),
      ],
    );
  }
}
