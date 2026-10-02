import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cadastros/servico.dart';
import '../servicos/status.dart';
import '../widgets/itens_os.dart' show dinheiro;
import '../widgets/margem.dart';
import '../widgets/status_chip.dart';

/// Lista dos orçamentos, por situação. O orçamento nasce dentro da OS.
class OrcamentosTela extends StatefulWidget {
  const OrcamentosTela({super.key});

  @override
  State<OrcamentosTela> createState() => _OrcamentosTelaState();
}

enum _Situacao { abertos, aprovados, reprovados, outros, todos }

const _statusDaSituacao = {
  _Situacao.abertos: ['rascunho', 'enviado'],
  _Situacao.aprovados: ['aprovado'],
  _Situacao.reprovados: ['reprovado'],
  _Situacao.outros: ['expirado', 'substituido', 'cancelado'],
};

const _nomesSituacao = {
  _Situacao.abertos: 'Em aberto',
  _Situacao.aprovados: 'Aprovados',
  _Situacao.reprovados: 'Reprovados',
  _Situacao.outros: 'Substituídos e cancelados',
  _Situacao.todos: 'Todos',
};

class _OrcamentosTelaState extends State<OrcamentosTela> {
  static const _tamanho = 30;

  final _busca = TextEditingController();
  Timer? _espera;
  _Situacao _situacao = _Situacao.abertos;
  int _pagina = 0;
  bool _temMais = false;
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _itens = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    _busca.dispose();
    super.dispose();
  }

  /// Só a resposta do pedido mais recente vale (filtros trocados rápido).
  int _pedido = 0;

  Future<void> _carregar() async {
    final meu = ++_pedido;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      var q = Supabase.instance.client
          .from('orcamentos')
          .select('id, codigo, numero, versao_orcamento, status, total, validade_ate, enviado_em, criado_em, '
              'ordens_servico(codigo, clientes(nome), locais(nome))')
          .isFilter('excluido_em', null);
      final lista = _statusDaSituacao[_situacao];
      if (lista != null) q = q.inFilter('status', lista);
      final b = CadastroServico.limparBusca(_busca.text);
      if (b.isNotEmpty) q = q.ilike('codigo', '%$b%');
      final inicio = _pagina * _tamanho;
      final dados = await q
          .order('numero', ascending: false)
          .order('versao_orcamento', ascending: false)
          .range(inicio, inicio + _tamanho);
      if (!mounted || meu != _pedido) return;
      setState(() {
        _temMais = dados.length > _tamanho;
        _itens = _temMais ? dados.sublist(0, _tamanho) : dados;
      });
    } catch (e) {
      if (mounted && meu == _pedido) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted && meu == _pedido) setState(() => _carregando = false);
    }
  }

  void _recarregarDoInicio() {
    _pagina = 0;
    _carregar();
  }

  Future<void> _abrir(String id) async {
    await context.push('/orcamentos/$id');
    if (mounted) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final largo = MediaQuery.sizeOf(context).width >= 900;
    return SingleChildScrollView(
      padding: margemDaTela(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Orçamentos',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Para fazer um orçamento, abra a OS e use "Novo orçamento".',
              style: TextStyle(color: Cores.neutro)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<_Situacao>(
                segments: [
                  for (final s in _Situacao.values) ButtonSegment(value: s, label: Text(_nomesSituacao[s]!)),
                ],
                selected: {_situacao},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  _situacao = s.first;
                  _recarregarDoInicio();
                },
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _busca,
                  decoration: const InputDecoration(hintText: 'Número (ORC-...)', prefixIcon: Icon(Icons.search, size: 20)),
                  onChanged: (_) {
                    _espera?.cancel();
                    _espera = Timer(const Duration(milliseconds: 350), _recarregarDoInicio);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_carregando) const LinearProgressIndicator(minHeight: 2),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: _erro != null
                ? Padding(padding: const EdgeInsets.all(24), child: Text(_erro!, style: const TextStyle(color: Cores.erro)))
                : _itens.isEmpty && !_carregando
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nenhum orçamento encontrado.', style: TextStyle(color: Cores.neutro)))
                    : Column(children: [
                        for (final o in _itens) ...[
                          _Linha(o: o, largo: largo, aoTocar: () => _abrir(o['id'] as String)),
                          if (o != _itens.last) const Divider(height: 1),
                        ],
                      ]),
          ),
          if (_pagina > 0 || _temMais)
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('Página ${_pagina + 1}', style: const TextStyle(color: Cores.neutro)),
              IconButton(
                tooltip: 'Anterior',
                onPressed: _pagina == 0 || _carregando
                    ? null
                    : () {
                        _pagina--;
                        _carregar();
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Próxima',
                onPressed: !_temMais || _carregando
                    ? null
                    : () {
                        _pagina++;
                        _carregar();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
        ],
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.o, required this.largo, required this.aoTocar});

  final Map<String, dynamic> o;
  final bool largo;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final os = o['ordens_servico'] as Map? ?? const {};
    final cliente = (os['clientes'] as Map?)?['nome'] ?? '';
    final local = (os['locais'] as Map?)?['nome'] ?? '';
    return InkWell(
      onTap: aoTocar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          SizedBox(
            width: 140,
            child: Text('${o['codigo']} v${o['versao_orcamento']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$cliente · $local', overflow: TextOverflow.ellipsis),
              Text('${os['codigo'] ?? ''}', style: const TextStyle(color: Cores.neutro, fontSize: 13)),
            ]),
          ),
          if (largo) ...[
            SizedBox(
              width: 140,
              child: Text(o['validade_ate'] == null ? '' : 'válido até ${dataBr(o['validade_ate'])}',
                  style: const TextStyle(fontSize: 13)),
            ),
          ],
          SizedBox(
            width: 120,
            child: Text(dinheiro(o['total']),
                textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 16),
          StatusChip(statusOrcamentoVisivel(o), statusOrcamento),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Cores.neutro),
        ]),
      ),
    );
  }
}
