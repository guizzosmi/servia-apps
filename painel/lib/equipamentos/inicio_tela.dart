import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/comercial.dart' show reais;
import '../servicos/status.dart';
import '../widgets/margem.dart';
import 'servico.dart';
import 'widgets.dart';

/// Gestão de Equipamentos (guia 98): o dia e o mês num relance. Utilização, o que volta hoje, o que está
/// atrasado, o que tem de sair, parados no depósito, em manutenção, receita estimada e custo por equipamento.
class EqpInicioTela extends StatefulWidget {
  const EqpInicioTela({super.key});

  @override
  State<EqpInicioTela> createState() => _EqpInicioTelaState();
}

class _EqpInicioTelaState extends State<EqpInicioTela> {
  Map<String, dynamic>? _d;
  String? _erro;
  bool _carregando = true;
  int _ocioso = 15;

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
      final d = await eqp('eqp_indicadores', {'dias_ocioso': _ocioso});
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Widget _numero(String rotulo, String valor, {Color cor = Cores.tinta, String? destino}) => SizedBox(
        width: 170,
        child: Card(
          child: InkWell(
            onTap: destino == null ? null : () => context.go(destino),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Valor grande (R$ 12.345,00) diminui em vez de quebrar a linha no cartão.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(valor, maxLines: 1, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cor)),
                ),
                Text(rotulo, style: const TextStyle(color: Cores.neutro)),
              ]),
            ),
          ),
        ),
      );

  Widget _linha(Map<String, dynamic> x, String detalhe, {Color? cor}) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text('${x['codigo']} · ${x['descricao']}'),
        subtitle: Text(detalhe, style: TextStyle(color: cor ?? Cores.neutro)),
        trailing: x['locacao_id'] != null
            ? TextButton(onPressed: () => context.go('/equipamentos/locacoes/${x['locacao_id']}'), child: Text('${x['locacao']}'))
            : null,
        onTap: () => context.go('/equipamentos/ativo/${x['equipamento_id']}'),
      );

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    final d = _d;
    final status = Map<String, dynamic>.from((d?['por_status'] as Map?) ?? const {});
    int n(String s) => (status[s] as num?)?.toInt() ?? 0;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          Expanded(
            child: Text('Gestão de Equipamentos',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          IconButton(tooltip: 'Atualizar', onPressed: _carregando ? null : _carregar, icon: const Icon(Icons.refresh)),
        ]),
        const Text('Onde está cada equipamento, o que sai e volta hoje, o que está atrasado e quanto cada um rende e custa. '
            'Dica: peça ao Assistente "o que volta hoje?" ou "tem macaco livre de 10 a 20?".',
            style: TextStyle(color: Cores.neutro)),
        const SizedBox(height: 12),
        if (_carregando) const LinearProgressIndicator(minHeight: 2),
        if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
        if (d != null) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            _numero('equipamentos', '${d['equipamentos']}', destino: '/equipamentos/lista'),
            _numero('utilização no mês', '${d['utilizacao_pct']}%', cor: Cores.andamento),
            _numero('disponíveis', '${n('disponivel')}', cor: Cores.sucesso, destino: '/equipamentos/lista'),
            _numero('em uso', '${n('em_uso') + n('em_transito')}', cor: Cores.andamento),
            _numero('em manutenção', '${n('em_manutencao')}', cor: Cores.coral500),
            _numero('aguardando conferência', '${n('retornado')}', cor: Cores.alerta),
            _numero('contratos ativos', '${d['contratos_ativos']}', destino: '/equipamentos/locacoes'),
            _numero('receita estimada no mês', reais(d['receita_estimada']), cor: Cores.sucesso),
            if (d['custo'] != null) _numero('custo no mês', reais(d['custo']), cor: Cores.erro),
          ]),
          const SizedBox(height: 12),
          SecaoEqp(
            titulo: 'Atrasados (${listaDe(d['atrasados']).length})',
            child: listaDe(d['atrasados']).isEmpty
                ? const Text('Nenhum equipamento com a volta atrasada.', style: TextStyle(color: Cores.neutro))
                : Column(children: [
                    for (final x in listaDe(d['atrasados']))
                      _linha(x, '${x['com']} · devia voltar ${dataBr(x['fim_previsto'])} (${x['dias_atraso']} dia(s))',
                          cor: Cores.erro),
                  ]),
          ),
          SecaoEqp(
            titulo: 'Voltam hoje (${listaDe(d['a_devolver_hoje']).length})',
            child: listaDe(d['a_devolver_hoje']).isEmpty
                ? const Text('Nada previsto para voltar hoje.', style: TextStyle(color: Cores.neutro))
                : Column(children: [for (final x in listaDe(d['a_devolver_hoje'])) _linha(x, '${x['com']}')]),
          ),
          SecaoEqp(
            titulo: 'Saem hoje (${listaDe(d['saidas_hoje']).length})',
            child: listaDe(d['saidas_hoje']).isEmpty
                ? const Text('Nenhuma saída pendente.', style: TextStyle(color: Cores.neutro))
                : Column(children: [
                    for (final x in listaDe(d['saidas_hoje']))
                      _linha(x, '${x['com']}${x['atrasada'] == true ? ' · era para ${dataBr(x['inicio'])}' : ''}',
                          cor: x['atrasada'] == true ? Cores.alerta : null),
                  ]),
          ),
          SecaoEqp(
            titulo: 'Parados no depósito (${listaDe(d['ociosos']).length})',
            acoes: [
              for (final dias in const [7, 15, 30, 60])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ChoiceChip(
                    label: Text('$dias d'),
                    selected: _ocioso == dias,
                    onSelected: (_) {
                      setState(() => _ocioso = dias);
                      _carregar();
                    },
                  ),
                ),
            ],
            child: listaDe(d['ociosos']).isEmpty
                ? Text('Nenhum disponível sem reserva há $_ocioso dias ou mais.', style: const TextStyle(color: Cores.neutro))
                : Column(children: [
                    for (final x in listaDe(d['ociosos'])) _linha(x, '${x['local']} · parado há ${x['dias_parado']} dia(s)'),
                  ]),
          ),
          SecaoEqp(
            titulo: 'Em manutenção (${listaDe(d['em_manutencao']).length})',
            child: listaDe(d['em_manutencao']).isEmpty
                ? const Text('Nenhum em manutenção.', style: TextStyle(color: Cores.neutro))
                : Column(children: [
                    for (final x in listaDe(d['em_manutencao']))
                      _linha(x, 'desde ${dataBr(x['desde'])}${x['os'] != null ? ' · ${x['os']}' : ''}'),
                  ]),
          ),
          SecaoEqp(
            titulo: 'Receita estimada por equipamento (mês)',
            child: listaDe(d['receita_por_equipamento']).isEmpty
                ? const Text('Sem locação no mês.', style: TextStyle(color: Cores.neutro))
                : Column(children: [
                    for (final x in listaDe(d['receita_por_equipamento']).take(10)) _linha(x, reais(x['receita'])),
                    const Text('Dias locados × preço do contrato. A receita faturada vem com a medição (próxima etapa).',
                        style: TextStyle(color: Cores.neutro, fontSize: 12)),
                  ]),
          ),
          if (d['custo_por_equipamento'] is List)
            SecaoEqp(
              titulo: 'Custo por equipamento (mês)',
              child: listaDe(d['custo_por_equipamento']).isEmpty
                  ? const Text('Nenhum custo lançado no mês.', style: TextStyle(color: Cores.neutro))
                  : Column(children: [for (final x in listaDe(d['custo_por_equipamento']).take(10)) _linha(x, reais(x['custo']))]),
            ),
        ],
      ]),
    );
  }
}
