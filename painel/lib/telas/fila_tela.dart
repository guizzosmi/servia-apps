import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/status.dart';
import '../widgets/fila.dart';

/// Fila de pendentes: tudo o que precisa ir para a parte de alguma equipe.
/// (No guia 07 esta mesma fila vira a coluna da esquerda do quadro.)
class FilaTela extends StatefulWidget {
  const FilaTela({super.key});

  @override
  State<FilaTela> createState() => _FilaTelaState();
}

class _FilaTelaState extends State<FilaTela> {
  final _busca = TextEditingController();
  bool _comSuspensos = false;
  String? _prioridade;
  String? _regiao;
  List<Map<String, dynamic>> _todos = [];
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
      final dados = await carregarFila(comSuspensos: _comSuspensos);
      if (mounted) setState(() => _todos = dados);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  List<String> get _regioes {
    final s = <String>{};
    for (final a in _todos) {
      final r = (((a['ordens_servico'] as Map?)?['locais'] as Map?)?['regiao']) as String?;
      if (r != null && r.isNotEmpty) s.add(r);
    }
    // A região escolhida continua na lista mesmo se sumiu dos dados
    // (senão o filtro fica preso e o Dropdown falha por valor inexistente).
    if (_regiao != null) s.add(_regiao!);
    return s.toList()..sort();
  }

  List<Map<String, dynamic>> get _filtrados {
    final b = _busca.text.trim().toLowerCase();
    return _todos.where((a) {
      if (_prioridade != null && a['prioridade'] != _prioridade) return false;
      if (_regiao != null && ((a['ordens_servico'] as Map?)?['locais'] as Map?)?['regiao'] != _regiao) return false;
      if (b.isNotEmpty && !textoDeBuscaFila(a).contains(b)) return false;
      return true;
    }).toList();
  }

  // Método da própria tela (usa o context do State, conferido pelo mounted).
  Future<void> _novaOs() async {
    final novaOs = await context.push<String>('/os/nova');
    if (!mounted) return;
    if (novaOs != null) await context.push('/os/$novaOs');
    if (mounted) _carregar();
  }

  Future<void> _abrirOs(String osId) async {
    await context.push('/os/$osId');
    if (mounted) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final itens = _filtrados;
    final largura = MediaQuery.sizeOf(context).width;
    final colunas = largura >= 1400 ? 3 : (largura >= 1000 ? 2 : 1);
    return RefreshIndicator(
      onRefresh: _carregar,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('Fila de pendentes',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            IconButton(tooltip: 'Atualizar', onPressed: _carregando ? null : _carregar, icon: const Icon(Icons.refresh)),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _novaOs,
              icon: const Icon(Icons.add),
              label: const Text('Nova OS'),
            ),
          ]),
          const SizedBox(height: 4),
          const Text('Cada cartão é uma visita a programar. Urgentes primeiro, depois pela data desejada.',
              style: TextStyle(color: Cores.neutro)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _busca,
                decoration: const InputDecoration(hintText: 'Cliente, local, cidade, OS...', prefixIcon: Icon(Icons.search, size: 20)),
                onChanged: (_) => setState(() {}),
              ),
            ),
            for (final p in prioridades.entries)
              FilterChip(
                label: Text(p.value.texto),
                selected: _prioridade == p.key,
                onSelected: (s) => setState(() => _prioridade = s ? p.key : null),
              ),
            if (_regioes.isNotEmpty)
              SizedBox(
                width: 200,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Região'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _regiao,
                      isDense: true,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                        for (final r in _regioes) DropdownMenuItem<String?>(value: r, child: Text(r)),
                      ],
                      onChanged: (v) => setState(() => _regiao = v),
                    ),
                  ),
                ),
              ),
            FilterChip(
              label: const Text('Mostrar suspensos'),
              selected: _comSuspensos,
              onSelected: (s) {
                _comSuspensos = s;
                _carregar();
              },
            ),
          ]),
          const SizedBox(height: 12),
          if (_carregando) const LinearProgressIndicator(minHeight: 2),
          if (_erro != null)
            Text(_erro!, style: const TextStyle(color: Cores.erro))
          else if (!_carregando && itens.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Fila vazia.', style: TextStyle(color: Cores.neutro))),
            )
          else ...[
            Text('${itens.length} na fila', style: const TextStyle(color: Cores.neutro)),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, box) {
              final w = (box.maxWidth - (colunas - 1) * 12) / colunas;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                for (final a in itens)
                  SizedBox(width: w, child: CartaoFila(ag: a, aoTocar: () => _abrirOs(a['os_id'] as String))),
              ]);
            }),
          ],
        ]),
      ),
    );
  }
}
