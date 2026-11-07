import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/comercial.dart';
import '../servicos/status.dart';
import '../widgets/comercial_etapas.dart';
import '../widgets/margem.dart';

/// Funil do Comercial (guia 90): uma coluna por etapa; arraste o cartão para mudar de etapa.
/// Ganho e Perdido mostram o que fechou nos últimos 30 dias.
class ComercialFunilTela extends StatefulWidget {
  const ComercialFunilTela({super.key});

  @override
  State<ComercialFunilTela> createState() => _ComercialFunilTelaState();
}

class _ComercialFunilTelaState extends State<ComercialFunilTela> {
  final _busca = TextEditingController();
  String? _responsavel;
  List<Map<String, dynamic>> _responsaveis = [];
  List<Map<String, dynamic>> _etapas = [];
  List<Map<String, dynamic>> _ops = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
    Supabase.instance.client.rpc('comercial_responsaveis').then((r) {
      if (mounted && r is List) setState(() => _responsaveis = r.map((e) => Map<String, dynamic>.from(e as Map)).toList());
    }).catchError((_) {});
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
      final cliente = Supabase.instance.client;
      var r = await cliente.rpc('comercial_funil', params: {
        'p': {'responsavel_id': _responsavel, 'busca': _busca.text.trim()}
      });
      // Empresa que acabou de ligar o módulo: cria as etapas padrão.
      if (r is Map && (r['etapas'] as List).isEmpty) {
        await acaoComercial({'acao': 'etapas_padrao'});
        r = await cliente.rpc('comercial_funil', params: {'p': <String, dynamic>{}});
      }
      final m = Map<String, dynamic>.from(r as Map);
      if (!mounted) return;
      setState(() {
        _etapas = (m['etapas'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _ops = (m['oportunidades'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
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

  /// Soltou o cartão numa etapa. Perdido pede o motivo.
  Future<void> _mover(Map<String, dynamic> op, Map<String, dynamic> etapa) async {
    if (op['etapa_id'] == etapa['id']) return;
    String? motivo;
    if (etapa['tipo'] == 'perdido') {
      motivo = await pedirMotivoPerda(context);
      if (motivo == null) return;
    }
    final antes = op['etapa_id'];
    setState(() => op['etapa_id'] = etapa['id']);
    try {
      await acaoComercial({'acao': 'mover', 'oportunidade_id': op['id'], 'etapa_id': etapa['id'], 'motivo_perda': motivo});
      if (mounted) _carregar();
    } catch (e) {
      if (!mounted) return;
      setState(() => op['etapa_id'] = antes);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagemDeErro(e)), backgroundColor: Cores.erro));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visiveis = _etapas.where((e) => e['ativo'] == true).toList();
    return Padding(
      padding: margemDaTela(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Funil comercial', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          FilledButton.icon(
            onPressed: () => _abrir('/comercial/nova'),
            icon: const Icon(Icons.add),
            label: const Text('Nova oportunidade'),
          ),
          OutlinedButton.icon(
            onPressed: () => _abrir('/comercial/tarefas'),
            icon: const Icon(Icons.checklist),
            label: const Text('Tarefas'),
          ),
          OutlinedButton.icon(
            onPressed: () => _abrir('/comercial/indicadores'),
            icon: const Icon(Icons.insights_outlined),
            label: const Text('Indicadores'),
          ),
          TextButton.icon(
            onPressed: () async {
              final mudou = await editarEtapas(context, _etapas);
              if (mudou && mounted) _carregar();
            },
            icon: const Icon(Icons.tune),
            label: const Text('Etapas'),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: _busca,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar nome, telefone, cidade'),
              onSubmitted: (_) => _carregar(),
            ),
          ),
          DropdownButton<String?>(
            value: _responsavel,
            hint: const Text('Todos os responsáveis'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Todos os responsáveis')),
              for (final u in _responsaveis) DropdownMenuItem<String?>(value: u['id'] as String, child: Text('${u['nome']}')),
            ],
            onChanged: (v) {
              setState(() => _responsavel = v);
              _carregar();
            },
          ),
          IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
        ]),
        const SizedBox(height: 8),
        if (_carregando) const LinearProgressIndicator(minHeight: 2),
        if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final e in visiveis)
              _Coluna(
                etapa: e,
                ops: _ops.where((o) => o['etapa_id'] == e['id']).toList(),
                aoSoltar: (op) => _mover(op, e),
                aoAbrir: (op) => _abrir('/comercial/${op['id']}'),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _Coluna extends StatelessWidget {
  const _Coluna({required this.etapa, required this.ops, required this.aoSoltar, required this.aoAbrir});

  final Map<String, dynamic> etapa;
  final List<Map<String, dynamic>> ops;
  final void Function(Map<String, dynamic>) aoSoltar;
  final void Function(Map<String, dynamic>) aoAbrir;

  @override
  Widget build(BuildContext context) {
    final tipo = etapa['tipo'];
    final cor = tipo == 'ganho' ? Cores.sucesso : (tipo == 'perdido' ? Cores.erro : Cores.indigo700);
    final total = ops.fold<num>(0, (s, o) => s + (num.tryParse('${o['valor']}') ?? 0) + 12 * (num.tryParse('${o['valor_mensal']}') ?? 0));
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (d) => d.data['etapa_id'] != etapa['id'],
      onAcceptWithDetails: (d) => aoSoltar(d.data),
      builder: (context, candidatos, _) => Container(
        width: 290,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: candidatos.isNotEmpty ? Cores.indigo100 : Cores.fundo,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: candidatos.isNotEmpty ? Cores.indigo500 : Cores.linha),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('${etapa['nome']}', style: TextStyle(fontWeight: FontWeight.w800, color: cor))),
            Text('${ops.length}', style: const TextStyle(fontWeight: FontWeight.w700, color: Cores.neutro)),
          ]),
          Text(tipo == 'aberta' ? '${reais(total)} · ${etapa['probabilidade']}% de chance' : 'últimos 30 dias · ${reais(total)}',
              style: const TextStyle(fontSize: 12, color: Cores.neutro)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              for (final o in ops)
                Draggable<Map<String, dynamic>>(
                  data: o,
                  feedback: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(width: 270, child: _Cartao(o, aoAbrir: null)),
                  ),
                  childWhenDragging: Opacity(opacity: .35, child: _Cartao(o, aoAbrir: null)),
                  child: _Cartao(o, aoAbrir: () => aoAbrir(o)),
                ),
              if (ops.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Arraste um cartão para cá', textAlign: TextAlign.center, style: TextStyle(color: Cores.neutro, fontSize: 12)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao(this.o, {required this.aoAbrir});

  final Map<String, dynamic> o;
  final VoidCallback? aoAbrir;

  @override
  Widget build(BuildContext context) {
    final tarefa = o['proxima_tarefa'] is Map ? Map<String, dynamic>.from(o['proxima_tarefa'] as Map) : null;
    final quando = DateTime.tryParse('${tarefa?['previsto_para'] ?? ''}')?.toLocal();
    final atrasada = quando != null && quando.isBefore(DateTime.now());
    final valor = valorOportunidade(o);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: aoAbrir,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${o['titulo']}', style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (quemOportunidade(o).isNotEmpty)
              Text(quemOportunidade(o), style: const TextStyle(color: Cores.neutro), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (valor.isNotEmpty) Text(valor, style: const TextStyle(fontWeight: FontWeight.w600, color: Cores.indigo700)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${o['codigo']}', style: const TextStyle(fontSize: 11, color: Cores.neutro)),
              Text(origensComercial[o['origem']] ?? '', style: const TextStyle(fontSize: 11, color: Cores.neutro)),
              if (o['responsavel'] != null)
                Text('· ${(o['responsavel'] as String).split(' ').first}', style: const TextStyle(fontSize: 11, color: Cores.neutro)),
            ]),
            if (tarefa != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(atrasada ? Icons.warning_amber_rounded : Icons.schedule, size: 14, color: atrasada ? Cores.erro : Cores.neutro),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('${quando == null ? '' : '${dataHoraBr(tarefa['previsto_para'])} · '}${tarefa['titulo']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: atrasada ? Cores.erro : Cores.neutro)),
                ),
              ]),
            ] else if (o['situacao'] == 'aberta')
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Sem próxima tarefa', style: TextStyle(fontSize: 12, color: Cores.alerta)),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Pede o motivo da perda (com os mais comuns em atalho). null = desistiu.
Future<String?> pedirMotivoPerda(BuildContext context) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, definir) => AlertDialog(
        title: const Text('Por que perdeu?'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final m in motivosPerda)
                ActionChip(label: Text(m), onPressed: () => definir(() => c.text = m)),
            ]),
            const SizedBox(height: 8),
            TextField(controller: c, decoration: const InputDecoration(labelText: 'Motivo'), autofocus: true),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Marcar como perdida')),
        ],
      ),
    ),
  );
  final motivo = c.text.trim();
  c.dispose();
  return ok == true && motivo.isNotEmpty ? motivo : null;
}
