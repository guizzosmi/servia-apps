import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/comercial.dart' show reais;
import '../servicos/status.dart';
import '../widgets/itens_os.dart' show numeroBr;
import '../widgets/margem.dart';
import 'servico.dart';
import 'widgets.dart';

const situacoesMedicao = {'aberta': 'Aberta', 'fechada': 'Fechada', 'faturada': 'Faturada', 'cancelada': 'Cancelada'};

Color corDaMedicao(String? s) => switch (s) {
      'aberta' => Cores.info,
      'fechada' || 'faturada' => Cores.sucesso,
      _ => Cores.erro,
    };

/// "MM/AAAA" de uma data AAAA-MM-DD.
String mesBr(Object? v) {
  final t = '${v ?? ''}';
  return t.length >= 7 ? '${t.substring(5, 7)}/${t.substring(0, 4)}' : t;
}

/// Medições da locação (guia 102): o período de cada contrato entre dois cortes vira a receita do mês e o título de
/// cobrança. Também a diária interna das obras próprias (decisão 1), mostrada à parte.
class EqpMedicoesTela extends StatefulWidget {
  const EqpMedicoesTela({super.key, this.locacaoId});

  /// Só as medições de um contrato (vindo da tela de cobrança do contrato).
  final String? locacaoId;

  @override
  State<EqpMedicoesTela> createState() => _EqpMedicoesTelaState();
}

class _EqpMedicoesTelaState extends State<EqpMedicoesTela> {
  Map<String, dynamic>? _d;
  String? _situacao;
  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;
  DateTime _mesInterno = DateTime(DateTime.now().year, DateTime.now().month - 1);
  Map<String, dynamic>? _interna;

  bool get _gestor => Sessao.atual?.tem(Papel.gestor) ?? false;
  bool get _financeiro => Sessao.atual?.temAlgum(const [Papel.gestor, Papel.financeiro]) ?? false;

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
      final d = await eqp('eqp_medicoes_lista', {
        if (widget.locacaoId != null) 'locacao_id': widget.locacaoId,
        if (_situacao != null) 'situacao': _situacao,
      });
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _gerar(Map<String, dynamic> c) async {
    setState(() => _ocupado = true);
    try {
      final r = await eqp('eqp_medicao_acao', {'acao': 'gerar', 'locacao_id': c['locacao_id']});
      if (mounted) context.go('/equipamentos/medicoes/${r['medicao_id']}');
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _diariaInterna({required bool lancar}) async {
    if (lancar &&
        !await confirmarEqp(context, 'Lançar a diária interna de ${mesBr(iso(_mesInterno))}',
            'Grava dias em obra própria × diária de cada equipamento (refaz o mês, se já lançado). Mês fechado não aceita.')) {
      return;
    }
    if (!mounted) return;
    setState(() => _ocupado = true);
    try {
      final r = await eqp('eqp_diaria_interna', {'competencia': iso(_mesInterno), 'lancar': lancar});
      if (!mounted) return;
      setState(() => _interna = r);
      if (lancar) avisarEqp(context, 'Diária interna lançada: ${reais(r['total'])}');
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    final medicoes = listaDe(_d?['medicoes']);
    final aMedir = listaDe(_d?['a_medir']);
    final receita = listaDe(_d?['receita_por_mes']);
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          if (widget.locacaoId != null)
            IconButton(
              tooltip: 'Voltar',
              onPressed: () => context.go('/equipamentos/cobranca/${widget.locacaoId}'),
              icon: const Icon(Icons.arrow_back),
            ),
          Expanded(
            child: Text('Medições', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ]),
        const Text('Cada medição fecha o período do contrato (até o dia da medição ou o fim do mês): dias em campo, uso acima '
            'da franquia, avarias e o abatimento dos dias parados por falha nossa, aprovado pelo gestor. Fechar é a receita do '
            'mês e gera a cobrança.', style: TextStyle(color: Cores.neutro)),
        const SizedBox(height: 8),
        if (_carregando || _ocupado) const LinearProgressIndicator(minHeight: 2),
        if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
        if (aMedir.isNotEmpty)
          SecaoEqp(
            titulo: 'Períodos a medir (${aMedir.length})',
            child: Column(children: [
              for (final c in aMedir)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${c['locacao']} · ${c['cliente']}'),
                  subtitle: Text('${dataBr(c['inicio'])} a ${dataBr(c['fim'])}'
                      '${c['aberta'] != null ? ' · ${c['aberta']} aberta' : ''}'),
                  trailing: _gestor && c['aberta'] == null
                      ? FilledButton.tonal(onPressed: _ocupado ? null : () => _gerar(c), child: const Text('Gerar'))
                      : null,
                ),
            ]),
          ),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final s in {'todas': 'Todas', ...situacoesMedicao}.entries)
            ChoiceChip(
              label: Text(s.value),
              selected: (_situacao ?? 'todas') == s.key,
              onSelected: (_) {
                setState(() => _situacao = s.key == 'todas' ? null : s.key);
                _carregar();
              },
            ),
        ]),
        const SizedBox(height: 8),
        if (!_carregando && medicoes.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('Nenhuma medição.', style: TextStyle(color: Cores.neutro))),
        for (final m in medicoes)
          Card(
            child: ListTile(
              onTap: () => context.go('/equipamentos/medicoes/${m['medicao_id']}'),
              title: Text('${m['codigo']} · ${m['locacao']} · ${m['cliente']}'),
              subtitle: Text('${dataBr(m['periodo_inicio'])} a ${dataBr(m['periodo_fim'])} · competência ${mesBr(m['competencia'])}'
                  '${(m['pendentes'] as num? ?? 0) > 0 ? '\nAbatimento aguardando o gestor' : ''}'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(situacoesMedicao[m['situacao']] ?? '${m['situacao']}',
                    style: TextStyle(color: corDaMedicao('${m['situacao']}'), fontWeight: FontWeight.w700)),
                Text(reais(m['valor_total'])),
              ]),
            ),
          ),
        if (receita.isNotEmpty && widget.locacaoId == null)
          SecaoEqp(
            titulo: 'Receita medida por mês',
            child: Column(children: [
              for (final r in receita)
                Row(children: [Expanded(child: Text(mesBr(r['competencia']))), Text(reais(r['valor']))]),
            ]),
          ),
        if (_financeiro && widget.locacaoId == null)
          SecaoEqp(
            titulo: 'Diária interna das obras próprias',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Dias de cada equipamento em obra própria × diária interna (a da ficha ou a do modelo). Fica à parte '
                  'do resultado: não é receita de locação.', style: TextStyle(color: Cores.neutro)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                IconButton(
                  tooltip: 'Mês anterior',
                  onPressed: () => setState(() => _mesInterno = DateTime(_mesInterno.year, _mesInterno.month - 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(mesBr(iso(_mesInterno)), style: const TextStyle(fontWeight: FontWeight.w600)),
                IconButton(
                  tooltip: 'Mês seguinte',
                  onPressed: () => setState(() => _mesInterno = DateTime(_mesInterno.year, _mesInterno.month + 1)),
                  icon: const Icon(Icons.chevron_right),
                ),
                OutlinedButton(onPressed: _ocupado ? null : () => _diariaInterna(lancar: false), child: const Text('Calcular')),
                FilledButton(onPressed: _ocupado ? null : () => _diariaInterna(lancar: true), child: const Text('Lançar o mês')),
              ]),
              if (_interna != null) ...[
                for (final l in listaDe(_interna!['linhas']))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${l['codigo']} · ${l['descricao']}'),
                    subtitle: Text('${l['obra'] ?? ''} · ${l['dias']} dia(s) × ${reais(l['diaria'])}'
                        '${l['centro_custo'] != null ? ' · CC ${l['centro_custo']}' : ''}'),
                    trailing: Text(reais(l['valor'])),
                  ),
                Text('Total: ${reais(_interna!['total'])}'
                    '${_interna!['lancado'] == true ? ' (lançado)' : ' · já lançado no mês: ${reais(_interna!['lancado_antes'])}'}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ]),
          ),
      ]),
    );
  }
}

/// Uma medição: itens com dias, valor, uso e franquia, avaria e dias parados; ajustar, aprovar o abatimento e fechar.
class EqpMedicaoTela extends StatefulWidget {
  const EqpMedicaoTela({super.key, required this.id});

  final String id;

  @override
  State<EqpMedicaoTela> createState() => _EqpMedicaoTelaState();
}

class _EqpMedicaoTelaState extends State<EqpMedicaoTela> {
  Map<String, dynamic>? _d;
  String? _erro;
  bool _ocupado = false;

  bool get _gestor => Sessao.atual?.tem(Papel.gestor) ?? false;
  Map<String, dynamic> get _m => Map<String, dynamic>.from((_d?['medicao'] as Map?) ?? const {});

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final d = await eqp('eqp_medicao_ver', {'medicao_id': widget.id});
      if (mounted) {
        setState(() {
          _d = d;
          _erro = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    }
  }

  Future<void> _acao(Map<String, dynamic> p, String ok) async {
    if (!mounted) return;
    setState(() => _ocupado = true);
    try {
      await eqp('eqp_medicao_acao', {'medicao_id': widget.id, ...p});
      if (mounted) avisarEqp(context, ok);
      await _carregar();
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _ajustar(Map<String, dynamic> i) async {
    final dias = await pedirTextoEqp(context, 'Dias parados de ${i['codigo']}',
        'Dias parados por falha nossa (0 a ${i['dias']}; sugestão do sistema: ${i['dias_parados_sugeridos']})');
    if (dias == null || !mounted) return;
    final n = int.tryParse(dias.trim());
    if (n == null) {
      avisarEqp(context, 'Informe um número de dias.', erro: true);
      return;
    }
    final motivo = await pedirTextoEqp(context, 'Motivo', 'Por que parou (opcional)', obrigatorio: false);
    if (motivo == null) return;
    await _acao({'acao': 'ajustar', 'medicao_item_id': i['medicao_item_id'], 'dias_parados': n, 'motivo': motivo},
        'Dias parados ajustados: o abatimento espera a aprovação');
  }

  Future<void> _decidir(Map<String, dynamic>? i, {required bool aprovar}) async {
    String? motivo = '';
    if (!aprovar) {
      motivo = await pedirTextoEqp(context, 'Recusar o abatimento', 'Motivo (ex.: falha por mau uso do cliente)');
      if (motivo == null) return;
    }
    await _acao({
      'acao': 'aprovar_abatimento',
      'aprovar': aprovar,
      if (i != null) 'medicao_item_id': i['medicao_item_id'],
      if (motivo.isNotEmpty) 'motivo': motivo,
    }, aprovar ? 'Abatimento aprovado' : 'Abatimento recusado');
  }

  Future<void> _fechar() async {
    final m = _m;
    if (!await confirmarEqp(context, 'Fechar ${m['codigo']}',
        'Total ${reais(m['valor_total'])}. Vira a receita de ${mesBr(m['competencia'])} e gera a cobrança como a empresa escolheu.',
        sim: 'Fechar')) {
      return;
    }
    await _acao({'acao': 'fechar'}, 'Medição fechada');
  }

  Future<void> _cancelar() async {
    final motivo = await pedirTextoEqp(context, 'Cancelar ${_m['codigo']}', 'Motivo do cancelamento');
    if (motivo == null) return;
    await _acao({'acao': 'cancelar', 'motivo': motivo}, 'Medição cancelada');
  }

  Widget _linha(String rotulo, Object? valor, {bool negrito = false, Color? cor}) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(children: [
          Expanded(child: Text(rotulo, style: const TextStyle(color: Cores.neutro))),
          Text(reais(valor), style: TextStyle(fontWeight: negrito ? FontWeight.w700 : null, color: cor)),
        ]),
      );

  String _abatimento(Map<String, dynamic> i) => switch ('${i['abatimento_situacao']}') {
        'aprovado' => 'abatimento aprovado: - ${reais(i['valor_abatimento'])}',
        'recusado' => i['abatimento_motivo'] == null ? 'abatimento recusado' : 'abatimento recusado (${i['abatimento_motivo']})',
        'pendente' => 'aguardando o gestor',
        _ => 'sem abatimento',
      };

  String _medida(Map<String, dynamic> i) {
    final un = switch ('${i['medidor']}') { 'km' => 'km', 'ciclos' => 'ciclos', _ => 'h' };
    if (i['uso'] == null) return '';
    final partes = ['uso ${numeroBr(i['uso'])} $un'];
    if (i['franquia'] != null) partes.add('franquia ${numeroBr(i['franquia'])} $un');
    if ((num.tryParse('${i['excedente']}') ?? 0) > 0) {
      partes.add('excedente ${numeroBr(i['excedente'])} $un × ${reais(i['preco_excedente'])}');
    }
    return partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    if (_erro != null && _d == null) return Center(child: Text(_erro!, style: const TextStyle(color: Cores.erro)));
    if (_d == null) return const Center(child: CircularProgressIndicator());
    final m = _m;
    final sit = '${m['situacao']}';
    final aberta = sit == 'aberta';
    final itens = listaDe(_d!['itens']);
    final pendentes = itens.where((i) => i['abatimento_situacao'] == 'pendente').length;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          IconButton(tooltip: 'Voltar', onPressed: () => context.go('/equipamentos/medicoes'), icon: const Icon(Icons.arrow_back)),
          Expanded(
            child: Text('${m['codigo']} · ${m['locacao']} · ${m['cliente']}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text(situacoesMedicao[sit] ?? sit, style: TextStyle(color: corDaMedicao(sit), fontWeight: FontWeight.w700)),
        ]),
        Text('${dataBr(m['periodo_inicio'])} a ${dataBr(m['periodo_fim'])} · competência ${mesBr(m['competencia'])}'
            '${m['forma_cobranca'] == 'obra' ? ' · por obra (valor fechado)' : ''}', style: const TextStyle(color: Cores.neutro)),
        if (_ocupado) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 8),
        if (_gestor && aberta)
          Wrap(spacing: 8, runSpacing: 8, children: [
            ActionChip(
              avatar: const Icon(Icons.refresh, size: 18),
              label: const Text('Recalcular'),
              onPressed: _ocupado ? null : () => _acao({'acao': 'recalcular'}, 'Medição recalculada'),
            ),
            if (pendentes > 0)
              ActionChip(
                avatar: const Icon(Icons.thumb_up_alt_outlined, size: 18),
                label: Text('Aprovar todos os abatimentos ($pendentes)'),
                onPressed: _ocupado ? null : () => _decidir(null, aprovar: true),
              ),
            ActionChip(
              avatar: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Fechar medição'),
              onPressed: _ocupado || pendentes > 0 ? null : _fechar,
            ),
            ActionChip(avatar: const Icon(Icons.close, size: 18), label: const Text('Cancelar'), onPressed: _ocupado ? null : _cancelar),
          ]),
        if (_gestor && sit == 'fechada' && m['titulo_id'] == null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: _ocupado ? null : _cancelar, icon: const Icon(Icons.undo, size: 18), label: const Text('Cancelar a medição')),
          ),
        if (pendentes > 0 && aberta)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Há dias parados por falha nossa: o gestor aprova (abate proporcional) ou recusa antes de fechar.',
                style: TextStyle(color: Cores.alerta)),
          ),
        const SizedBox(height: 12),
        SecaoEqp(
          titulo: 'Totais',
          child: Column(children: [
            _linha('Locação', m['valor_locacao']),
            _linha('Excedente da franquia', m['valor_excedente']),
            _linha('Avarias', m['valor_avarias']),
            _linha('Abatimento (dias parados)', m['valor_abatimento'], cor: Cores.erro),
            const Divider(),
            _linha('Total', m['valor_total'], negrito: true),
            if (sit != 'aberta')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  m['cobranca'] == 'titulo'
                      ? 'Cobrança gerada pelo módulo de cobrança da empresa.'
                      : sit == 'cancelada'
                          ? 'Cancelada: ${m['motivo_cancelamento'] ?? ''}'
                          : 'Cobrança manual (a empresa ainda não configurou a cobrança).',
                  style: const TextStyle(color: Cores.neutro),
                ),
              ),
          ]),
        ),
        SecaoEqp(
          titulo: 'Equipamentos (${itens.length})',
          child: Column(children: [
            for (final i in itens)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text('${i['codigo']} · ${i['descricao']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Text(reais(i['valor_total']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  Text(
                    [
                      if (i['inicio'] != null) '${dataBr(i['inicio'])} a ${dataBr(i['fim'])} · ${i['dias']} dia(s)',
                      if (i['periodicidade'] == 'obra')
                        'por obra: ${reais(i['valor_locacao'])}'
                      else if (i['preco'] != null)
                        '${reais(i['preco'])} ${periodicidades[i['periodicidade']] ?? ''} = ${reais(i['valor_locacao'])}',
                    ].join(' · '),
                    style: const TextStyle(color: Cores.neutro),
                  ),
                  if (_medida(i).isNotEmpty) Text(_medida(i), style: const TextStyle(color: Cores.neutro)),
                  if ((num.tryParse('${i['valor_avarias']}') ?? 0) > 0)
                    Text('Avaria: ${i['avaria_descricao'] ?? ''} · ${reais(i['valor_avarias'])}', style: const TextStyle(color: Cores.alerta)),
                  if ((num.tryParse('${i['dias_parados']}') ?? 0) > 0 || (num.tryParse('${i['dias_parados_sugeridos']}') ?? 0) > 0)
                    Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(
                        'Parado por falha nossa: ${i['dias_parados']} dia(s)'
                        '${i['dias_ajustados'] == true ? ' (ajustado; sugestão ${i['dias_parados_sugeridos']})' : ''}'
                        ' · ${_abatimento(i)}',
                        style: TextStyle(color: i['abatimento_situacao'] == 'pendente' ? Cores.alerta : Cores.neutro),
                      ),
                      if (_gestor && aberta && i['abatimento_situacao'] != 'nenhum') ...[
                        TextButton(onPressed: _ocupado ? null : () => _decidir(i, aprovar: true), child: const Text('Aprovar')),
                        TextButton(onPressed: _ocupado ? null : () => _decidir(i, aprovar: false), child: const Text('Recusar')),
                      ],
                    ]),
                  if (_gestor && aberta && (num.tryParse('${i['dias']}') ?? 0) > 0)
                    TextButton.icon(
                      onPressed: _ocupado ? null : () => _ajustar(i),
                      icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                      label: const Text('Ajustar dias parados'),
                    ),
                  const Divider(height: 12),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}
