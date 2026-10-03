import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/contratos.dart';
import '../servicos/status.dart';
import '../widgets/itens_os.dart' show dinheiro;
import '../widgets/margem.dart';
import '../widgets/status_chip.dart';

/// Lista dos contratos dos clientes.
class ContratosTela extends StatefulWidget {
  const ContratosTela({super.key});

  @override
  State<ContratosTela> createState() => _ContratosTelaState();
}

class _ContratosTelaState extends State<ContratosTela> {
  String? _situacao = 'ativo';
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _itens = [];

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
      var q = Supabase.instance.client
          .from('contratos')
          .select('id, codigo, descricao, modalidade, situacao, vigencia_inicio, vigencia_fim, valor_mensal, '
              'proximo_reajuste, reajuste_indice, clientes(nome), locais(nome)')
          .isFilter('excluido_em', null);
      if (_situacao != null) q = q.eq('situacao', _situacao!);
      final dados = await q.order('numero', ascending: false);
      if (mounted) setState(() => _itens = dados);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _abrir(String destino) async {
    await context.push(destino);
    if (mounted) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: margemDaTela(context), children: [
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Contratos', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        FilledButton.icon(
          onPressed: () => _abrir('/contratos/novo'),
          icon: const Icon(Icons.add),
          label: const Text('Novo contrato'),
        ),
      ]),
      const SizedBox(height: 4),
      const Text('Como cada cliente paga: por execução, mensalidade ou franquia. A OS do cliente já nasce com o '
          'contrato, e a OS do aparelho (ciclo da preventiva) leva o preço.',
          style: TextStyle(color: Cores.neutro)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        for (final s in const [('ativo', 'Ativos'), ('rascunho', 'Rascunhos'), ('encerrado', 'Encerrados'), (null, 'Todos')])
          ChoiceChip(
            label: Text(s.$2),
            selected: _situacao == s.$1,
            onSelected: (_) {
              setState(() => _situacao = s.$1);
              _carregar();
            },
          ),
      ]),
      const SizedBox(height: 12),
      if (_carregando) const LinearProgressIndicator(minHeight: 2),
      if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
      if (!_carregando && _erro == null && _itens.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Nenhum contrato aqui.', style: TextStyle(color: Cores.neutro)),
        ),
      for (final c in _itens)
        Card(
          child: ListTile(
            onTap: () => _abrir('/contratos/${c['id']}'),
            title: Text(
                [c['codigo'], (c['clientes'] as Map?)?['nome'], if (c['descricao'] != null) c['descricao']].join(' · '),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([
              (c['locais'] as Map?)?['nome'] ?? 'Todos os locais do cliente',
              'Vigência ${dataBr(c['vigencia_inicio'])}${c['vigencia_fim'] != null ? ' a ${dataBr(c['vigencia_fim'])}' : ''}'
                  '${c['valor_mensal'] != null ? ' · ${dinheiro(c['valor_mensal'])}/mês' : ''}',
              if (c['proximo_reajuste'] != null && c['reajuste_indice'] != 'nenhum')
                'Reajuste ${indicesReajuste[c['reajuste_indice']] ?? ''} em ${dataBr(c['proximo_reajuste'])}',
            ].join('\n')),
            isThreeLine: true,
            trailing: Wrap(spacing: 6, children: [
              StatusChip(c['modalidade'] as String?, modalidadesContrato, compacto: true),
              StatusChip(c['situacao'] as String?, situacoesContrato, compacto: true),
            ]),
          ),
        ),
    ]);
  }
}
