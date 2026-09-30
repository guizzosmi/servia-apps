import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cadastros/campos.dart';
import '../cadastros/definicoes.dart';
import '../cadastros/lista.dart';
import '../cadastros/servico.dart';
import '../servicos/status.dart';
import '../widgets/status_chip.dart';

/// Lista das ordens de serviço, com filtro por situação, cliente e busca.
class OsListaTela extends StatefulWidget {
  const OsListaTela({super.key});

  @override
  State<OsListaTela> createState() => _OsListaTelaState();
}

enum _Situacao { abertas, aguardando, concluidas, canceladas, todas }

const _statusDaSituacao = {
  _Situacao.abertas: ['aberta', 'agendada', 'em_andamento', 'aguardando_aprovacao', 'aguardando_peca', 'aguardando_cliente'],
  _Situacao.aguardando: ['aguardando_aprovacao', 'aguardando_peca', 'aguardando_cliente'],
  _Situacao.concluidas: ['concluida'],
  _Situacao.canceladas: ['cancelada'],
};

const _nomesSituacao = {
  _Situacao.abertas: 'Em aberto',
  _Situacao.aguardando: 'Aguardando',
  _Situacao.concluidas: 'Concluídas',
  _Situacao.canceladas: 'Canceladas',
  _Situacao.todas: 'Todas',
};

class _OsListaTelaState extends State<OsListaTela> {
  static const _campoCliente = CampoDef('cliente_id', 'Cliente',
      tipo: TipoCampo.lookup, lookup: Lookup(tabela: 'clientes'));
  static const _tamanho = 30;

  final _busca = TextEditingController();
  Timer? _espera;
  _Situacao _situacao = _Situacao.abertas;
  String? _clienteId;
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

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      var q = Supabase.instance.client
          .from('ordens_servico')
          .select('id, codigo, numero, tipo, status, prioridade, abertura_em, prevista_para, '
              'problema_relatado, garantia_status, clientes(nome), locais(nome, cidade)')
          .isFilter('excluido_em', null);
      final lista = _statusDaSituacao[_situacao];
      if (lista != null) q = q.inFilter('status', lista);
      if (_clienteId != null) q = q.eq('cliente_id', _clienteId!);
      final b = CadastroServico.limparBusca(_busca.text);
      if (b.isNotEmpty) {
        q = q.or('codigo.ilike."*$b*",problema_relatado.ilike."*$b*"');
      }
      final inicio = _pagina * _tamanho;
      final dados = await q.order('numero', ascending: false).range(inicio, inicio + _tamanho);
      if (!mounted) return;
      setState(() {
        _temMais = dados.length > _tamanho;
        _itens = _temMais ? dados.sublist(0, _tamanho) : dados;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _recarregarDoInicio() {
    _pagina = 0;
    _carregar();
  }

  Future<void> _abrir(String destino) async {
    await context.push(destino);
    if (mounted) _carregar();
  }

  Future<void> _novaOs() async {
    final novaOs = await context.push<String>('/os/nova');
    if (!mounted) return;
    // Voltando de "Nova OS" com a OS criada, já abre ela.
    if (novaOs != null) await context.push('/os/$novaOs');
    if (mounted) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final largo = MediaQuery.sizeOf(context).width >= 900;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text('Ordens de serviço',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (podeEditarCadastros())
              FilledButton.icon(
                onPressed: _novaOs,
                icon: const Icon(Icons.add),
                label: const Text('Nova OS'),
              ),
          ]),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<_Situacao>(
                segments: [
                  for (final s in _Situacao.values)
                    ButtonSegment(value: s, label: Text(_nomesSituacao[s]!)),
                ],
                selected: {_situacao},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  _situacao = s.first;
                  _recarregarDoInicio();
                },
              ),
              SizedBox(
                width: 260,
                child: CampoLookup(
                  campo: _campoCliente,
                  valor: _clienteId,
                  valorPai: null,
                  rotuloPai: null,
                  habilitado: true,
                  aoMudar: (v) {
                    _clienteId = v;
                    _recarregarDoInicio();
                  },
                ),
              ),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _busca,
                  decoration: const InputDecoration(
                    hintText: 'Número ou problema',
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
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
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_erro!, style: const TextStyle(color: Cores.erro)))
                : _itens.isEmpty && !_carregando
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nenhuma OS encontrada.', style: TextStyle(color: Cores.neutro)))
                    : Column(children: [
                        for (final os in _itens) ...[
                          _LinhaOs(os: os, largo: largo, aoTocar: () => _abrir('/os/${os['id']}')),
                          if (os != _itens.last) const Divider(height: 1),
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

class _LinhaOs extends StatelessWidget {
  const _LinhaOs({required this.os, required this.largo, required this.aoTocar});

  final Map<String, dynamic> os;
  final bool largo;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final cliente = (os['clientes'] as Map?)?['nome'] ?? '';
    final local = (os['locais'] as Map?)?['nome'] ?? '';
    final problema = (os['problema_relatado'] ?? '') as String;
    final garantia = os['garantia_status'] == 'confirmada' || os['garantia_status'] == 'sugerida';
    return InkWell(
      onTap: aoTocar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text((os['codigo'] ?? '') as String,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$cliente · $local', overflow: TextOverflow.ellipsis),
                  if (problema.isNotEmpty)
                    Text(problema,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Cores.neutro, fontSize: 13)),
                ],
              ),
            ),
            if (largo) ...[
              SizedBox(width: 90, child: Text(tiposOs[os['tipo']] ?? '', style: const TextStyle(fontSize: 13))),
              SizedBox(width: 90, child: Text(dataBr(os['abertura_em']), style: const TextStyle(fontSize: 13))),
              SizedBox(
                width: 80,
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: StatusChip(os['prioridade'] as String?, prioridades, compacto: true)),
              ),
            ],
            if (garantia)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Tooltip(message: 'Retorno em garantia', child: Icon(Icons.verified_user_outlined, size: 18, color: Cores.alerta)),
              ),
            StatusChip(os['status'] as String?, statusOs),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Cores.neutro),
          ],
        ),
      ),
    );
  }
}
