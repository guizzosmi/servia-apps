import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/comercial.dart' show reais;
import '../servicos/status.dart';
import '../widgets/margem.dart';
import 'servico.dart';
import 'servico_manutencao.dart';
import 'widgets.dart';

/// Gestão de Equipamentos (guia 103): indicadores do mês (ocupação, disponibilidade, margem, MTBF, MTTR, custo por
/// hora, custo acumulado, avarias por cliente), exportar CSV e o fechamento do mês (gera o custo das OS, lança a
/// diária interna das obras próprias, trava os lançamentos e guarda os totais).
class EqpFechamentoTela extends StatefulWidget {
  const EqpFechamentoTela({super.key});

  @override
  State<EqpFechamentoTela> createState() => _EqpFechamentoTelaState();
}

class _EqpFechamentoTelaState extends State<EqpFechamentoTela> {
  final _meses = mesesRecentes();
  late String _mes = _meses.first;
  Map<String, dynamic>? _ind;
  Map<String, dynamic>? _fech;
  String? _erro;
  bool _carregando = true;
  bool _ocupado = false;

  bool get _custos => (Sessao.atual?.tem(Papel.gestor) ?? false) || (Sessao.atual?.tem(Papel.financeiro) ?? false);
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
      final r = await Future.wait([
        eqp('eqp_indicadores_mes', {'competencia': _mes}),
        if (_custos) eqp('eqp_fechamento_acao', {'acao': 'situacao', 'competencia': _mes}),
      ]);
      if (mounted) {
        setState(() {
          _ind = r[0];
          _fech = r.length > 1 ? r[1] : null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _acao(String acao, String ok, {Map<String, dynamic> extra = const {}}) async {
    setState(() => _ocupado = true);
    try {
      await eqp('eqp_fechamento_acao', {'acao': acao, 'competencia': _mes, ...extra});
      if (mounted) avisarEqp(context, ok);
      await _carregar();
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _fechar() async {
    final pend = listaDe(_fech?['pendencias']);
    final bloqueia = pend.any((p) => p['bloqueia'] == true);
    final texto = [
      'Gera o custo das OS concluídas que faltarem, lança a diária interna das obras próprias e trava os lançamentos de ${mesBr(_mes)}.',
      if (pend.isNotEmpty) 'Pendências: ${pend.map((p) => p['mensagem']).join('; ')}.',
    ].join('\n\n');
    if (!await confirmarEqp(context, 'Fechar ${mesBr(_mes)}', texto, sim: bloqueia ? 'Fechar assim mesmo' : 'Fechar')) return;
    await _acao('fechar', 'Mês fechado', extra: {if (bloqueia) 'forcar': true});
  }

  Future<void> _reabrir() async {
    final motivo = await pedirTextoEqp(context, 'Reabrir ${mesBr(_mes)}', 'Motivo');
    if (motivo == null) return;
    await _acao('reabrir', 'Mês reaberto', extra: {'motivo': motivo});
  }

  Future<void> _csv() async {
    try {
      final r = await eqp('eqp_indicadores_csv', {'competencia': _mes});
      baixarTextoEqp('${r['nome']}', '${r['csv'] ?? ''}');
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    }
  }

  Widget _cartao(String rotulo, String valor, {Color cor = Cores.tinta, String? dica}) => SizedBox(
        width: 170,
        child: Tooltip(
          message: dica ?? '',
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(valor, maxLines: 1, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cor)),
                ),
                Text(rotulo, style: const TextStyle(color: Cores.neutro)),
              ]),
            ),
          ),
        ),
      );

  DataCell _c(String t, {Color? cor}) => DataCell(Text(t, style: TextStyle(color: cor)));

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    final ind = _ind;
    final t = Map<String, dynamic>.from((ind?['totais'] as Map?) ?? const {});
    final lista = listaDe(ind?['equipamentos_lista']);
    final fech = _fech;
    final fechada = fech?['situacao'] == 'fechada';
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          Expanded(
            child: Text('Indicadores e fechamento',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String>(
              initialValue: _mes,
              decoration: const InputDecoration(labelText: 'Mês'),
              items: [for (final m in _meses) DropdownMenuItem(value: m, child: Text(mesBr(m)))],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _mes = v);
                _carregar();
              },
            ),
          ),
          IconButton(tooltip: 'Exportar CSV', onPressed: _carregando ? null : _csv, icon: const Icon(Icons.download_outlined)),
          IconButton(tooltip: 'Atualizar', onPressed: _carregando ? null : _carregar, icon: const Icon(Icons.refresh)),
        ]),
        const Text('Dias por status vêm dos movimentos (horas ÷ 24). Ocupação = dias com reserva ativa ÷ dias no período; '
            'comercial = dias locado ÷ (dias − manutenção − bloqueado); disponibilidade = dias fora de manutenção, conferência '
            'e bloqueio. MTBF = horas de uso ÷ falhas; MTTR = horas parado ÷ falhas. A diária interna da obra própria aparece '
            'à parte do resultado.',
            style: TextStyle(color: Cores.neutro, fontSize: 12)),
        const SizedBox(height: 12),
        if (_carregando) const LinearProgressIndicator(minHeight: 2),
        if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
        if (ind != null) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            _cartao('ocupação', pctBr(t['ocupacao_pct']), cor: Cores.andamento),
            _cartao('ocupação comercial', pctBr(t['ocupacao_comercial_pct']), cor: Cores.andamento),
            _cartao('disponibilidade', pctBr(t['disponibilidade_pct']), cor: Cores.sucesso),
            _cartao(t['receita_fonte'] == 'medicao' ? 'receita (medições)' : 'receita estimada', reais(t['receita']), cor: Cores.sucesso),
            _cartao('avarias', reais(t['avarias'])),
            if (t['custo'] != null) _cartao('custo', reais(t['custo']), cor: Cores.erro),
            if (t['margem'] != null)
              _cartao('margem${t['margem_pct'] != null ? ' (${pctBr(t['margem_pct'])})' : ''}', reais(t['margem']),
                  cor: (num.tryParse('${t['margem']}') ?? 0) < 0 ? Cores.erro : Cores.sucesso),
            _cartao('falhas', '${t['falhas'] ?? 0}'),
            _cartao('MTBF', t['mtbf_horas'] == null ? '–' : '${numBr(t['mtbf_horas'])} h', dica: 'Horas de uso por falha'),
            _cartao('MTTR', t['mttr_horas'] == null ? '–' : '${numBr(t['mttr_horas'])} h', dica: 'Horas parado por falha'),
            _cartao('receita interna (à parte)', reais(t['receita_interna']), cor: Cores.neutro,
                dica: 'Diária interna das obras próprias, lançada no fechamento'),
          ]),
          const SizedBox(height: 12),
          SecaoEqp(
            titulo: 'Por equipamento (${lista.length})',
            child: lista.isEmpty
                ? const Text('Nenhum equipamento no período.', style: TextStyle(color: Cores.neutro))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 18,
                      headingRowHeight: 36,
                      dataRowMinHeight: 32,
                      dataRowMaxHeight: 40,
                      columns: [
                        const DataColumn(label: Text('Equipamento')),
                        const DataColumn(label: Text('Dias'), numeric: true),
                        const DataColumn(label: Text('Ocupação'), numeric: true),
                        const DataColumn(label: Text('Comercial'), numeric: true),
                        const DataColumn(label: Text('Disponib.'), numeric: true),
                        const DataColumn(label: Text('Receita'), numeric: true),
                        if (_custos) const DataColumn(label: Text('Custo'), numeric: true),
                        if (_custos) const DataColumn(label: Text('Margem'), numeric: true),
                        const DataColumn(label: Text('Falhas'), numeric: true),
                        const DataColumn(label: Text('MTBF'), numeric: true),
                        const DataColumn(label: Text('MTTR'), numeric: true),
                        if (_custos) const DataColumn(label: Text('Custo/uso'), numeric: true),
                        if (_custos) const DataColumn(label: Text('Acumulado'), numeric: true),
                        const DataColumn(label: Text('Preparação'), numeric: true),
                      ],
                      rows: [
                        for (final e in lista)
                          DataRow(
                            onSelectChanged: (_) => context.go('/equipamentos/ativo/${e['equipamento_id']}'),
                            cells: [
                              _c('${e['codigo']} · ${e['descricao']}'),
                              _c(numBr(e['dias'])),
                              _c(pctBr(e['ocupacao_pct'])),
                              _c(pctBr(e['ocupacao_comercial_pct'])),
                              _c(pctBr(e['disponibilidade_pct'])),
                              _c(reais(e['receita'])),
                              if (_custos) _c(reais(e['custo'])),
                              if (_custos)
                                _c(reais(e['margem']), cor: (num.tryParse('${e['margem']}') ?? 0) < 0 ? Cores.erro : null),
                              _c('${e['falhas'] ?? 0}'),
                              _c(e['mtbf_horas'] == null ? '–' : '${numBr(e['mtbf_horas'])} h'),
                              _c(e['mttr_horas'] == null ? '–' : '${numBr(e['mttr_horas'])} h'),
                              if (_custos) _c(e['custo_por_uso'] == null ? '–' : reais(e['custo_por_uso'])),
                              if (_custos) _c(e['custo_acumulado_pct'] == null ? '–' : pctBr(e['custo_acumulado_pct'])),
                              _c(e['prazo_preparacao_dias'] == null ? '–' : '${numBr(e['prazo_preparacao_dias'])} d'),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
          if (ind['custo_por_natureza'] is Map && (ind['custo_por_natureza'] as Map).isNotEmpty)
            SecaoEqp(
              titulo: 'Custo por natureza',
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in (ind['custo_por_natureza'] as Map).entries)
                  Chip(label: Text('${naturezasCusto[e.key] ?? e.key}: ${reais(e.value)}')),
              ]),
            ),
          SecaoEqp(
            titulo: 'Avarias por cliente',
            child: listaDe(ind['avarias_por_cliente']).isEmpty
                ? const Text('Nenhuma avaria nem falha com equipamento no cliente.', style: TextStyle(color: Cores.neutro))
                : Column(children: [
                    for (final a in listaDe(ind['avarias_por_cliente']))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${a['cliente']}'),
                        subtitle: Text([
                          '${a['avarias'] ?? 0} avaria(s) na devolução (${reais(a['valor_avarias'])})',
                          '${a['falhas'] ?? 0} falha(s) com o equipamento lá',
                          if ((num.tryParse('${a['mau_uso_ou_acidente']}') ?? 0) > 0) '${a['mau_uso_ou_acidente']} por mau uso ou acidente',
                        ].join(' · ')),
                      ),
                  ]),
          ),
        ],
        if (fech != null)
          SecaoEqp(
            titulo: 'Fechamento de ${mesBr(_mes)}: ${fechada ? 'fechado' : fech['situacao'] == 'reaberta' ? 'reaberto' : 'aberto'}',
            acoes: [if (fechada) const Icon(Icons.lock_outline, color: Cores.sucesso)],
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (fechada && fech['fechado_em'] != null)
                Text('Fechado em ${dataHoraBr(fech['fechado_em'])}. Lançamento novo deste mês é recusado; estorno cai no mês atual.',
                    style: const TextStyle(color: Cores.neutro)),
              if (fech['situacao'] == 'reaberta' && fech['motivo_reabertura'] != null)
                Text('Reaberto: ${fech['motivo_reabertura']}', style: const TextStyle(color: Cores.alerta)),
              for (final p in listaDe(fech['pendencias']))
                Text('• ${p['mensagem']}', style: TextStyle(color: p['bloqueia'] == true ? Cores.erro : Cores.alerta)),
              if (listaDe(fech['receita_interna']).isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Diária interna lançada (à parte do resultado)', style: TextStyle(fontWeight: FontWeight.w600)),
                for (final r in listaDe(fech['receita_interna']))
                  Text('${r['equipamento']} · ${r['obra']} · ${numBr(r['dias'])} dia(s) × ${reais(r['diaria'])} = ${reais(r['valor'])}'
                      '${r['centro_custo'] != null ? ' · CC ${r['centro_custo']}' : ''}'),
              ],
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (!fechada)
                  OutlinedButton.icon(
                    onPressed: _ocupado ? null : () => _acao('gerar_custos', 'Custos das OS conferidos'),
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('Gerar custos das OS'),
                  ),
                if (!fechada)
                  OutlinedButton.icon(
                    onPressed: _ocupado ? null : () => _acao('diaria_interna', 'Diária interna lançada'),
                    icon: const Icon(Icons.apartment_outlined),
                    label: const Text('Lançar diária interna'),
                  ),
                if (!fechada)
                  FilledButton.icon(
                    onPressed: _ocupado ? null : _fechar,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Fechar o mês'),
                  ),
                if (fechada && _gestor)
                  OutlinedButton.icon(
                    onPressed: _ocupado ? null : _reabrir,
                    icon: const Icon(Icons.lock_open_outlined),
                    label: const Text('Reabrir'),
                  ),
              ]),
            ]),
          ),
      ]),
    );
  }
}
