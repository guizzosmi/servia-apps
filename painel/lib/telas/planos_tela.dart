import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/parametros.dart';
import '../servicos/planos.dart';
import '../servicos/status.dart';
import '../widgets/margem.dart';
import '../widgets/status_chip.dart';

/// Lista dos planos de preventiva e PMOC.
class PlanosTela extends StatefulWidget {
  const PlanosTela({super.key});

  @override
  State<PlanosTela> createState() => _PlanosTelaState();
}

class _PlanosTelaState extends State<PlanosTela> {
  String? _situacao = 'ativo';
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _itens = [];

  void _parametrosMudaram() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ParametrosEmpresa.instancia.addListener(_parametrosMudaram);
    _carregar();
  }

  @override
  void dispose() {
    ParametrosEmpresa.instancia.removeListener(_parametrosMudaram);
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      var q = Supabase.instance.client
          .from('planos')
          .select('id, tipo, nome, situacao, vigencia_inicio, vigencia_fim, clientes(nome), locais(nome), '
              'plano_equipamentos(id), plano_atividades(id)')
          .isFilter('excluido_em', null)
          .isFilter('plano_equipamentos.excluido_em', null)
          .isFilter('plano_atividades.excluido_em', null);
      if (_situacao != null) q = q.eq('situacao', _situacao!);
      final dados = await q.order('nome', ascending: true);
      if (mounted) setState(() => _itens = dados);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  static int _contagem(Object? lista) => (lista as List?)?.length ?? 0;

  Future<void> _abrir(String destino) async {
    await context.push(destino);
    if (mounted) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final podeEditar = Sessao.atual?.tem(Papel.gestor) ?? false;
    return ListView(padding: margemDaTela(context), children: [
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(ParametrosEmpresa.instancia.atendePmoc ? 'Planos de preventiva e PMOC' : 'Planos de preventiva',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (podeEditar)
          FilledButton.icon(
            onPressed: () => _abrir('/planos/novo'),
            icon: const Icon(Icons.add),
            label: const Text('Novo plano'),
          ),
        OutlinedButton.icon(
          onPressed: () => context.push('/c/modelos-atividade'),
          icon: const Icon(Icons.checklist_outlined),
          label: const Text('Biblioteca de atividades'),
        ),
      ]),
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
          child: Text('Nenhum plano aqui.', style: TextStyle(color: Cores.neutro)),
        ),
      for (final p in _itens)
        Card(
          child: ListTile(
            onTap: () => _abrir('/planos/${p['id']}'),
            title: Text('${p['nome']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([
              '${(p['clientes'] as Map?)?['nome'] ?? ''} · ${(p['locais'] as Map?)?['nome'] ?? ''}',
              'Vigência ${dataBr(p['vigencia_inicio'])}${p['vigencia_fim'] != null ? ' a ${dataBr(p['vigencia_fim'])}' : ''}',
              '${_contagem(p['plano_equipamentos'])} equipamento(s) · ${_contagem(p['plano_atividades'])} atividade(s)',
            ].join('\n')),
            isThreeLine: true,
            trailing: Wrap(spacing: 6, children: [
              StatusChip(p['tipo'] as String?, tiposPlano, compacto: true),
              StatusChip(p['situacao'] as String?, situacoesPlano, compacto: true),
            ]),
          ),
        ),
    ]);
  }
}
