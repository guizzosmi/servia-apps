import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/comercial.dart' show reais;
import '../servicos/status.dart';
import '../widgets/margem.dart';
import 'servico.dart';
import 'widgets.dart';

/// Contratos de locação (LC-00001): rascunho → confirmada (reserva) → em andamento (retirada) → encerrada (devolução).
class EqpLocacoesTela extends StatefulWidget {
  const EqpLocacoesTela({super.key});

  @override
  State<EqpLocacoesTela> createState() => _EqpLocacoesTelaState();
}

class _EqpLocacoesTelaState extends State<EqpLocacoesTela> {
  final _busca = TextEditingController();
  String? _situacao = 'abertas';
  List<Map<String, dynamic>> _lista = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await eqp('eqp_locacoes_lista', {
        if (_situacao != null) 'situacao': _situacao,
        if (_busca.text.trim().isNotEmpty) 'busca': _busca.text.trim(),
      });
      if (mounted) setState(() => _lista = listaDe(r['locacoes']));
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _nova() async {
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _NovaLocacao());
    if (p == null || !mounted) return;
    try {
      final r = await eqp('eqp_locacao_acao', {'acao': 'criar', ...p});
      if (mounted) context.go('/equipamentos/locacoes/${r['locacao_id']}');
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    }
  }

  Color _cor(String? s) => switch (s) {
        'rascunho' => Cores.neutro,
        'confirmada' => Cores.info,
        'em_andamento' => Cores.andamento,
        'encerrada' => Cores.sucesso,
        _ => Cores.erro,
      };

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    final gestor = Sessao.atual?.tem(Papel.gestor) ?? false;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          Expanded(
            child: Text('Locações', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (gestor) FilledButton.icon(onPressed: _nova, icon: const Icon(Icons.add), label: const Text('Nova locação')),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _busca,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Contrato (LC-00001) ou cliente',
            suffixIcon: IconButton(onPressed: _carregar, icon: const Icon(Icons.arrow_forward)),
          ),
          onSubmitted: (_) => _carregar(),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final s in {'abertas': 'Abertas', ...situacoesLocacao, 'todas': 'Todas'}.entries)
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
        if (_carregando) const LinearProgressIndicator(minHeight: 2),
        if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
        if (!_carregando && _lista.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('Nenhum contrato.', style: TextStyle(color: Cores.neutro))),
        for (final l in _lista)
          Card(
            child: ListTile(
              onTap: () => context.go('/equipamentos/locacoes/${l['locacao_id']}'),
              title: Text('${l['codigo']} · ${l['cliente']}'),
              subtitle: Text(
                '${dataBr(l['inicio'])} a ${dataBr(l['fim_previsto'])} · ${l['itens']} equipamento(s)'
                '${(l['em_campo'] as num? ?? 0) > 0 ? ' · ${l['em_campo']} em campo' : ''}'
                '${l['equipamentos'] != null ? '\n${l['equipamentos']}' : ''}'
                '${l['atrasada'] == true ? '\nATRASADA: passou do fim previsto' : ''}',
                style: TextStyle(color: l['atrasada'] == true ? Cores.erro : Cores.neutro),
              ),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(situacoesLocacao[l['situacao']] ?? '${l['situacao']}',
                    style: TextStyle(color: _cor('${l['situacao']}'), fontWeight: FontWeight.w700)),
                Text(reais(l['valor_previsto'])),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Cliente, endereço de entrega, período e condições. Os equipamentos entram na tela do contrato.
class _NovaLocacao extends StatefulWidget {
  const _NovaLocacao();

  @override
  State<_NovaLocacao> createState() => _NovaLocacaoState();
}

class _NovaLocacaoState extends State<_NovaLocacao> {
  final _busca = TextEditingController();
  final _contato = TextEditingController();
  final _condicoes = TextEditingController();
  List<Map<String, dynamic>> _clientes = [];
  List<Map<String, dynamic>> _locais = [];
  String? _cliente;
  String? _local;
  DateTime _inicio = DateTime.now();
  DateTime _fim = DateTime.now().add(const Duration(days: 6));

  @override
  void dispose() {
    _busca.dispose();
    _contato.dispose();
    _condicoes.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final b = _busca.text.trim().replaceAll(RegExp(r'[%,()]'), ' ');
    try {
      var q = Supabase.instance.client
          .from('clientes')
          .select('id, nome, nome_fantasia')
          .eq('interno', false)
          .isFilter('excluido_em', null);
      if (b.isNotEmpty) q = q.or('nome.ilike.%$b%,nome_fantasia.ilike.%$b%');
      final r = await q.order('nome').limit(20);
      if (mounted) setState(() => _clientes = List<Map<String, dynamic>>.from(r));
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _escolher(String id) async {
    setState(() {
      _cliente = id;
      _local = null;
      _locais = [];
    });
    try {
      final r = await Supabase.instance.client
          .from('locais')
          .select('id, nome, cidade')
          .eq('cliente_id', id)
          .isFilter('excluido_em', null)
          .order('nome');
      if (mounted) {
        setState(() {
          _locais = List<Map<String, dynamic>>.from(r);
          _local = _locais.isEmpty ? null : '${_locais.first['id']}';
        });
      }
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nova locação'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _busca,
                decoration: InputDecoration(
                  labelText: 'Cliente (nome)',
                  suffixIcon: IconButton(onPressed: _buscar, icon: const Icon(Icons.search)),
                ),
                onSubmitted: (_) => _buscar(),
              ),
              for (final c in _clientes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_cliente == '${c['id']}' ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20),
                  title: Text('${c['nome_fantasia'] ?? c['nome']}'),
                  onTap: () => _escolher('${c['id']}'),
                ),
              if (_cliente != null)
                _locais.isEmpty
                    ? const Text('Este cliente não tem endereço (local). Cadastre um local para ele antes.',
                        style: TextStyle(color: Cores.alerta))
                    : DropdownButtonFormField<String>(
                        initialValue: _local,
                        decoration: const InputDecoration(labelText: 'Endereço de entrega (obra)'),
                        items: [
                          for (final l in _locais)
                            DropdownMenuItem<String>(value: '${l['id']}', child: Text('${l['nome']}${l['cidade'] != null ? ' · ${l['cidade']}' : ''}')),
                        ],
                        onChanged: (v) => setState(() => _local = v),
                      ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                CampoDataEqp(rotulo: 'Início', data: _inicio, aoMudar: (d) => setState(() => _inicio = d)),
                CampoDataEqp(rotulo: 'Fim previsto', data: _fim, aoMudar: (d) => setState(() => _fim = d)),
              ]),
              TextField(controller: _contato, decoration: const InputDecoration(labelText: 'Contato no cliente')),
              TextField(
                controller: _condicoes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Condições (franquia, avarias, frete, pagamento)'),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              if (_cliente == null || _local == null) return;
              Navigator.of(context).pop(<String, dynamic>{
                'cliente_id': _cliente,
                'local_id': _local,
                'inicio': iso(_inicio),
                'fim_previsto': iso(_fim),
                if (_contato.text.trim().isNotEmpty) 'contato': _contato.text.trim(),
                if (_condicoes.text.trim().isNotEmpty) 'condicoes': _condicoes.text.trim(),
              });
            },
            child: const Text('Criar e escolher os equipamentos'),
          ),
        ],
      );
}
