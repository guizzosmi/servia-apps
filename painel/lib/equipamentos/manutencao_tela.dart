import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/arquivo_web.dart';
import '../servicos/comercial.dart' show reais;
import '../servicos/status.dart';
import '../widgets/margem.dart';
import 'servico.dart';
import 'servico_manutencao.dart';
import 'widgets.dart';

/// Gestão de Equipamentos (guia 103): falhas, OS de manutenção (fotos de antes e depois, checklist, causa e
/// conclusão com o custo), preventivas vencendo, reservas em que a preventiva vence e os parados há dias.
class EqpManutencaoTela extends StatefulWidget {
  const EqpManutencaoTela({super.key});

  @override
  State<EqpManutencaoTela> createState() => _EqpManutencaoTelaState();
}

class _EqpManutencaoTelaState extends State<EqpManutencaoTela> {
  Map<String, dynamic>? _d;
  String? _erro;
  bool _carregando = true;
  bool _ocupado = false;
  int _dias = 7;

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
      final d = await eqp('eqp_manutencao_resumo', {'dias_parado': _dias});
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Chama uma função, avisa e recarrega. Devolve o resultado (null = deu erro).
  Future<Map<String, dynamic>?> _rodar(String funcao, Map<String, dynamic> p, String ok) async {
    setState(() => _ocupado = true);
    try {
      final r = await eqp(funcao, p);
      if (mounted) avisarEqp(context, ok);
      await _carregar();
      return r;
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
      return null;
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _registrarFalha() async {
    List<Map<String, dynamic>> lista;
    try {
      lista = listaDe((await eqp('eqp_lista', {}))['equipamentos']);
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
      return;
    }
    if (!mounted) return;
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _NovaFalha(equipamentos: lista));
    if (p == null) return;
    await _rodar('eqp_falha_acao', {'acao': 'registrar', ...p}, 'Falha registrada');
  }

  Future<void> _causa({String? osId, String? falhaId, String? equipamentoId}) async {
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _Causa());
    if (p == null) return;
    final r = await _rodar('eqp_manutencao_acao', {
      'acao': 'causa',
      if (osId != null) 'os_id': osId,
      if (falhaId != null) 'falha_id': falhaId,
      if (equipamentoId != null) 'equipamento_id': equipamentoId,
      ...p,
    }, 'Causa informada');
    if (!mounted) return;
    if (r?['sugerir_cobrar'] == true) {
      avisarEqp(context, 'Mau uso ou acidente com o equipamento no cliente: avalie cobrar pela locação.');
    }
  }

  Future<void> _fotos(Map<String, dynamic> o, String momento) async {
    final arquivo = await escolherArquivo(aceitar: 'image/jpeg');
    if (arquivo == null || !mounted) return;
    setState(() => _ocupado = true);
    String caminho;
    try {
      caminho = await enviarFoto(arquivo);
    } catch (e) {
      if (mounted) {
        avisarEqp(context, 'Foto não enviada: ${mensagemDeErro(e)}', erro: true);
        setState(() => _ocupado = false);
      }
      return;
    }
    await _rodar('eqp_manutencao_acao', {
      'acao': 'fotos',
      'os_id': o['os_id'],
      'equipamento_id': o['equipamento_id'],
      'momento': momento,
      'fotos': [caminho],
    }, momento == 'antes' ? 'Foto de antes salva' : 'Foto de depois salva');
  }

  Future<void> _checklist(Map<String, dynamic> o) async {
    final itens = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => _Checklist(itens: listaDe(o['checklist']), preparacao: o['natureza'] == 'preparacao'),
    );
    if (itens == null) return;
    await _rodar('eqp_manutencao_acao',
        {'acao': 'checklist', 'os_id': o['os_id'], 'equipamento_id': o['equipamento_id'], 'checklist': itens}, 'Checklist salvo');
  }

  Future<void> _concluir(Map<String, dynamic> o) async {
    final precisaCausa = (o['natureza'] == 'corretiva' || o['natureza'] == 'reparo') && o['causa'] == null;
    final p = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _Concluir(codigo: '${o['codigo']}', precisaCausa: precisaCausa),
    );
    if (p == null) return;
    await _rodar('eqp_manutencao_acao', {'acao': 'concluir', 'os_id': o['os_id'], ...p}, '${o['codigo']} concluída; custo lançado');
  }

  Future<void> _reabrir(Map<String, dynamic> o) async {
    final motivo = await pedirTextoEqp(context, 'Reabrir ${o['codigo']}', 'Motivo (o custo lançado é estornado)');
    if (motivo == null) return;
    await _rodar('eqp_manutencao_acao', {'acao': 'reabrir', 'os_id': o['os_id'], 'motivo': motivo}, '${o['codigo']} reaberta');
  }

  Future<void> _cancelarFalha(Map<String, dynamic> f) async {
    final motivo = await pedirTextoEqp(context, 'Cancelar ${f['codigo']}', 'Motivo (registro errado; a OS não é cancelada)');
    if (motivo == null) return;
    await _rodar('eqp_falha_acao', {'acao': 'cancelar', 'falha_id': f['falha_id'], 'motivo': motivo}, 'Registro cancelado');
  }

  Widget _vazio(String texto) => Text(texto, style: const TextStyle(color: Cores.neutro));

  Widget _falha(Map<String, dynamic> f) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text('${f['codigo']} · ${f['equipamento']} · ${f['descricao']}'),
        subtitle: Text([
          '${f['sintoma']}',
          origensFalha[f['origem']] ?? '${f['origem']}',
          if (f['parou'] == true) 'parado há ${numBr(f['horas_parado'])} h',
          if (f['causa'] != null) 'causa: ${f['causa_nome']}',
          if (f['cliente'] != null) 'no cliente ${f['cliente']}',
          if (f['os'] != null) '${f['os']}',
        ].join(' · ')),
        onTap: f['os_id'] != null ? () => context.go('/os/${f['os_id']}') : null,
        trailing: !_gestor
            ? null
            : PopupMenuButton<String>(
                tooltip: 'Ações',
                onSelected: (v) {
                  if (v == 'causa') _causa(falhaId: '${f['falha_id']}');
                  if (v == 'os') _rodar('eqp_falha_acao', {'acao': 'abrir_os', 'falha_id': f['falha_id']}, 'OS aberta');
                  if (v == 'cancelar') _cancelarFalha(f);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'causa', child: Text('Informar a causa')),
                  if (f['os_id'] == null || f['os_status'] == 'cancelada')
                    const PopupMenuItem(value: 'os', child: Text('Abrir a OS corretiva')),
                  const PopupMenuItem(value: 'cancelar', child: Text('Cancelar o registro')),
                ],
              ),
      );

  Widget _os(Map<String, dynamic> o) {
    final pend = (o['pendencias'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    final planos = (o['planos'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('${o['codigo']} · ${naturezasManutencao[o['natureza']] ?? o['natureza']} · ${o['equipamento']} · ${o['descricao']}'),
          subtitle: Text([
            '${o['problema'] ?? ''}',
            if (planos.isNotEmpty) 'planos: ${planos.join(', ')}',
            'aberta em ${dataBr(o['abertura_em'])}',
            if (o['prevista_para'] != null) 'prevista para ${dataBr(o['prevista_para'])}',
            if (o['no_campo'] == true) 'no campo',
            'fotos: ${o['fotos_antes']} antes, ${o['fotos_depois']} depois',
          ].join(' · ')),
          trailing: ChipStatusEqp('${o['status_equipamento']}'),
          onTap: () => context.go('/os/${o['os_id']}'),
        ),
        if (pend.isNotEmpty)
          Wrap(spacing: 4, runSpacing: 4, children: [for (final x in pend) EtiquetaEqp('Falta: $x', cor: Cores.alerta)]),
        if (_gestor)
          Wrap(spacing: 4, children: [
            TextButton.icon(
              onPressed: _ocupado ? null : () => _fotos(o, 'antes'),
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('Foto de antes'),
            ),
            TextButton.icon(
              onPressed: _ocupado ? null : () => _fotos(o, 'depois'),
              icon: const Icon(Icons.photo_camera_back_outlined, size: 18),
              label: const Text('Foto de depois'),
            ),
            TextButton.icon(
              onPressed: _ocupado ? null : () => _checklist(o),
              icon: const Icon(Icons.checklist, size: 18),
              label: Text('Checklist (${listaDe(o['checklist']).length})'),
            ),
            if (o['natureza'] == 'corretiva' || o['natureza'] == 'reparo')
              TextButton.icon(
                onPressed: _ocupado ? null : () => _causa(osId: '${o['os_id']}', equipamentoId: '${o['equipamento_id']}'),
                icon: const Icon(Icons.manage_search, size: 18),
                label: Text(o['causa'] == null ? 'Informar a causa' : 'Causa: ${causasFalha[o['causa']] ?? o['causa']}'),
              ),
            FilledButton.tonalIcon(
              onPressed: _ocupado ? null : () => _concluir(o),
              icon: const Icon(Icons.task_alt, size: 18),
              label: const Text('Concluir'),
            ),
          ]),
        const Divider(height: 12),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    final d = _d;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          Expanded(
            child: Text('Manutenção dos equipamentos',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          IconButton(tooltip: 'Atualizar', onPressed: _carregando ? null : _carregar, icon: const Icon(Icons.refresh)),
        ]),
        const Text('Falhas, OS de manutenção (a OS de sempre, marcada como da Gestão de Equipamentos e "não cobrar"), '
            'preventivas por tempo e por uso e os equipamentos parados. Concluir a OS lança o custo de peças e horas no '
            'equipamento. Dica: diga ao Assistente "o EQ-0003 parou, não liga".',
            style: TextStyle(color: Cores.neutro)),
        const SizedBox(height: 8),
        if (_gestor)
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _ocupado ? null : _registrarFalha,
              icon: const Icon(Icons.report_problem_outlined),
              label: const Text('Registrar falha'),
            ),
            OutlinedButton.icon(
              onPressed: _ocupado ? null : () => _rodar('eqp_plano_acao', {'acao': 'gerar'}, 'Preventivas conferidas'),
              icon: const Icon(Icons.event_repeat_outlined),
              label: const Text('Gerar preventivas vencendo'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go('/equipamentos/planos'),
              icon: const Icon(Icons.rule_outlined),
              label: const Text('Planos de preventiva'),
            ),
          ]),
        const SizedBox(height: 12),
        if (_carregando) const LinearProgressIndicator(minHeight: 2),
        if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
        if (d != null) ...[
          if (d['fotos_obrigatorias'] == true || d['preparacao_obrigatoria'] == true)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                [
                  if (d['fotos_obrigatorias'] == true) 'A OS de equipamento só conclui com foto de antes e de depois.',
                  if (d['preparacao_obrigatoria'] == true) 'Depois de um retorno, o liberar exige a OS de preparação concluída.',
                  'Retrofit lançado como ${d['retrofit_como'] == 'investimento' ? 'investimento (valor do bem)' : 'custo do mês'}.',
                ].join(' '),
                style: const TextStyle(color: Cores.neutro, fontSize: 12),
              ),
            ),
          SecaoEqp(
            titulo: 'Falhas abertas (${listaDe(d['falhas_abertas']).length})',
            child: listaDe(d['falhas_abertas']).isEmpty
                ? _vazio('Nenhuma falha aberta.')
                : Column(children: [for (final f in listaDe(d['falhas_abertas'])) _falha(f)]),
          ),
          SecaoEqp(
            titulo: 'OS abertas (${listaDe(d['os_abertas']).length})',
            child: listaDe(d['os_abertas']).isEmpty
                ? _vazio('Nenhuma OS de manutenção aberta.')
                : Column(children: [for (final o in listaDe(d['os_abertas'])) _os(o)]),
          ),
          SecaoEqp(
            titulo: 'Preventivas vencendo (${listaDe(d['preventivas']).length})',
            child: listaDe(d['preventivas']).isEmpty
                ? _vazio('Nenhuma preventiva vencendo.')
                : Column(children: [
                    for (final p in listaDe(d['preventivas']))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${p['equipamento']} · ${p['descricao']} · ${p['plano']}'),
                        subtitle: Text([
                          if (p['proxima_data'] != null) 'até ${dataBr(p['proxima_data'])}',
                          if (p['proxima_uso'] != null)
                            'em ${numBr(p['proxima_uso'])} ${unidadesMedidor[p['medidor']] ?? ''} (está em ${numBr(p['uso_total'])})',
                          p['os'] != null ? '${p['os']}' : 'sem OS',
                        ].join(' · ')),
                        trailing: EtiquetaEqp(estadosPreventiva[p['estado']] ?? '${p['estado']}', cor: corDoEstado('${p['estado']}')),
                        onTap: p['os_id'] != null ? () => context.go('/os/${p['os_id']}') : null,
                      ),
                  ]),
          ),
          SecaoEqp(
            titulo: 'Reservas em que a preventiva vence (${listaDe(d['reservas_com_preventiva']).length})',
            child: listaDe(d['reservas_com_preventiva']).isEmpty
                ? _vazio('Nenhuma reserva com preventiva vencendo no período.')
                : Column(children: [
                    for (final r in listaDe(d['reservas_com_preventiva']))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${r['equipamento']} · ${r['descricao']} · ${quemSemObra(r)}'),
                        subtitle: Text('${dataBr(r['inicio'])}${r['fim_previsto'] != null ? ' a ${dataBr(r['fim_previsto'])}' : ''} · '
                            '${listaDe(r['avisos']).map((a) => '${a['mensagem']}').join('; ')}',
                            style: const TextStyle(color: Cores.alerta)),
                        onTap: () => context.go('/equipamentos/ativo/${r['equipamento_id']}'),
                      ),
                  ]),
          ),
          SecaoEqp(
            titulo: 'Concluídas no mês (${listaDe(d['os_concluidas_mes']).length})',
            child: listaDe(d['os_concluidas_mes']).isEmpty
                ? _vazio('Nenhuma OS de equipamento concluída no mês.')
                : Column(children: [
                    for (final o in listaDe(d['os_concluidas_mes']))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${o['codigo']} · ${naturezasManutencao[o['natureza']] ?? o['natureza']} · ${o['equipamento']}'),
                        subtitle: Text([
                          'concluída em ${dataBr(o['concluida_em'])}',
                          if (o['custo_pecas'] != null) 'peças ${reais(o['custo_pecas'])}',
                          if (o['custo_horas'] != null) 'mão de obra ${reais(o['custo_horas'])}',
                        ].join(' · ')),
                        onTap: () => context.go('/os/${o['os_id']}'),
                        trailing: _gestor
                            ? IconButton(tooltip: 'Reabrir', onPressed: _ocupado ? null : () => _reabrir(o), icon: const Icon(Icons.undo))
                            : null,
                      ),
                  ]),
          ),
          SecaoEqp(
            titulo: 'Parados (${listaDe(d['parados']).length})',
            acoes: [
              for (final dias in const [3, 7, 15, 30])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ChoiceChip(
                    label: Text('$dias d'),
                    selected: _dias == dias,
                    onSelected: (_) {
                      setState(() => _dias = dias);
                      _carregar();
                    },
                  ),
                ),
            ],
            child: listaDe(d['parados']).isEmpty
                ? _vazio('Nenhum em manutenção, bloqueado ou aguardando conferência há $_dias dias ou mais.')
                : Column(children: [
                    for (final x in listaDe(d['parados']))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${x['codigo']} · ${x['descricao']}'),
                        subtitle: Text('${x['local']} · há ${x['dias']} dia(s)'),
                        trailing: ChipStatusEqp('${x['status']}'),
                        onTap: () => context.go('/equipamentos/ativo/${x['equipamento_id']}'),
                      ),
                  ]),
          ),
        ],
      ]),
    );
  }
}

/// Registrar falha: equipamento, sintoma, se parou, componente e se já abre a OS.
class _NovaFalha extends StatefulWidget {
  const _NovaFalha({required this.equipamentos});

  final List<Map<String, dynamic>> equipamentos;

  @override
  State<_NovaFalha> createState() => _NovaFalhaState();
}

class _NovaFalhaState extends State<_NovaFalha> {
  String? _eqp;
  final _sintoma = TextEditingController();
  final _componente = TextEditingController();
  bool _parou = true;
  bool _abrirOs = true;

  @override
  void dispose() {
    _sintoma.dispose();
    _componente.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Registrar falha'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
              TextField(controller: _sintoma, maxLines: 2, decoration: const InputDecoration(labelText: 'O que aconteceu (sintoma)')),
              TextField(controller: _componente, decoration: const InputDecoration(labelText: 'Componente (opcional)')),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _parou,
                title: const Text('Parou (conta o tempo parado até liberar)'),
                onChanged: (v) => setState(() => _parou = v),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _abrirOs,
                title: const Text('Abrir a OS corretiva agora'),
                onChanged: (v) => setState(() => _abrirOs = v),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              if (_eqp == null || _sintoma.text.trim().isEmpty) return;
              Navigator.of(context).pop(<String, dynamic>{
                'equipamento_id': _eqp,
                'sintoma': _sintoma.text.trim(),
                if (_componente.text.trim().isNotEmpty) 'componente': _componente.text.trim(),
                'parou': _parou,
                'abrir_os': _abrirOs,
              });
            },
            child: const Text('Registrar'),
          ),
        ],
      );
}

/// Causa da falha (lista fixa + detalhe; "outra" exige o detalhe).
class _Causa extends StatefulWidget {
  const _Causa();

  @override
  State<_Causa> createState() => _CausaState();
}

class _CausaState extends State<_Causa> {
  String _causa = 'desgaste';
  final _detalhe = TextEditingController();
  final _componente = TextEditingController();
  bool _culpa = false;

  @override
  void dispose() {
    _detalhe.dispose();
    _componente.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Causa da falha'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in causasFalha.entries)
                ChoiceChip(label: Text(c.value), selected: _causa == c.key, onSelected: (_) => setState(() => _causa = c.key)),
            ]),
            TextField(controller: _detalhe, decoration: InputDecoration(labelText: _causa == 'outra' ? 'Qual foi?' : 'Detalhe (opcional)')),
            TextField(controller: _componente, decoration: const InputDecoration(labelText: 'Componente (opcional)')),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _culpa,
              title: const Text('Culpa do cliente'),
              onChanged: (v) => setState(() => _culpa = v),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              if (_causa == 'outra' && _detalhe.text.trim().isEmpty) return;
              Navigator.of(context).pop(<String, dynamic>{
                'causa': _causa,
                if (_detalhe.text.trim().isNotEmpty) 'causa_detalhe': _detalhe.text.trim(),
                if (_componente.text.trim().isNotEmpty) 'componente': _componente.text.trim(),
                'culpa_cliente': _culpa,
              });
            },
            child: const Text('Salvar'),
          ),
        ],
      );
}

/// Concluir: laudo e, se faltar, a causa.
class _Concluir extends StatefulWidget {
  const _Concluir({required this.codigo, required this.precisaCausa});

  final String codigo;
  final bool precisaCausa;

  @override
  State<_Concluir> createState() => _ConcluirState();
}

class _ConcluirState extends State<_Concluir> {
  final _laudo = TextEditingController();
  String? _causa;

  @override
  void dispose() {
    _laudo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Concluir ${widget.codigo}'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _laudo, maxLines: 3, decoration: const InputDecoration(labelText: 'O que foi feito (laudo)')),
            if (widget.precisaCausa) ...[
              const SizedBox(height: 8),
              const Text('Causa da falha (obrigatória)', style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in causasFalha.entries)
                  if (c.key != 'outra')
                    ChoiceChip(label: Text(c.value), selected: _causa == c.key, onSelected: (_) => setState(() => _causa = c.key)),
              ]),
            ],
            const SizedBox(height: 8),
            const Text('O custo de peças e horas vai para o equipamento na hora.', style: TextStyle(color: Cores.neutro, fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              if (widget.precisaCausa && _causa == null) return;
              Navigator.of(context).pop(<String, dynamic>{
                if (_laudo.text.trim().isNotEmpty) 'laudo_final': _laudo.text.trim(),
                if (_causa != null) 'causa': _causa,
              });
            },
            child: const Text('Concluir'),
          ),
        ],
      );
}

/// Checklist da OS do equipamento (na preparação, o liberar exige todos ok).
class _Checklist extends StatefulWidget {
  const _Checklist({required this.itens, required this.preparacao});

  final List<Map<String, dynamic>> itens;
  final bool preparacao;

  @override
  State<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends State<_Checklist> {
  late final Map<String, bool> _itens = widget.itens.isNotEmpty
      ? {for (final i in widget.itens) '${i['item']}': i['ok'] == true}
      : {for (final i in itensChecklistPadrao) i: false};
  final _novo = TextEditingController();

  @override
  void dispose() {
    _novo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.preparacao ? 'Checklist da preparação' : 'Checklist'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final e in _itens.entries)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: e.value,
                  title: Text(e.key),
                  onChanged: (v) => setState(() => _itens[e.key] = v ?? false),
                ),
              Row(children: [
                Expanded(child: TextField(controller: _novo, decoration: const InputDecoration(labelText: 'Outro item'))),
                IconButton(
                  tooltip: 'Incluir item',
                  onPressed: () {
                    final t = _novo.text.trim();
                    if (t.isEmpty) return;
                    setState(() {
                      _itens[t] = false;
                      _novo.clear();
                    });
                  },
                  icon: const Icon(Icons.add),
                ),
              ]),
              if (widget.preparacao)
                const Text('Com a preparação obrigatória, o equipamento só volta a disponível com todos os itens ok.',
                    style: TextStyle(color: Cores.neutro, fontSize: 12)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop([for (final e in _itens.entries) <String, dynamic>{'item': e.key, 'ok': e.value}]),
            child: const Text('Salvar'),
          ),
        ],
      );
}
