import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../widgets/margem.dart';
import 'definicoes.dart';
import 'servico.dart';

/// Quem pode incluir/alterar/excluir cadastros (o admin passa em todos).
bool podeEditarCadastros() => Sessao.atual?.tem(Papel.gestor) ?? false;

/// Lista com busca e paginação para qualquer cadastro.
/// Usada como página inteira (/c/clientes) e embutida no formulário do pai
/// (ex.: locais dentro do cliente), neste caso com [filtros] e [herdados].
class ListaCadastro extends StatefulWidget {
  const ListaCadastro({
    super.key,
    required this.def,
    this.filtros = const {},
    this.herdados = const {},
    this.embutida = false,
  });

  final CadastroDef def;

  /// Filtros fixos (ex.: {'cliente_id': '...'}).
  final Map<String, Object?> filtros;

  /// Valores já preenchidos ao incluir um registro novo a partir desta lista.
  final Map<String, String> herdados;
  final bool embutida;

  @override
  State<ListaCadastro> createState() => _ListaCadastroState();
}

class _ListaCadastroState extends State<ListaCadastro> {
  late final CadastroServico _servico = CadastroServico(widget.def);
  final _busca = TextEditingController();
  Timer? _espera;
  int _pagina = 0;
  bool _carregando = true;
  String? _erro;
  Pagina? _dados;

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
      final p = await _servico.listar(
        busca: _busca.text,
        filtros: widget.filtros,
        pagina: _pagina,
        tamanho: widget.embutida ? 10 : 25,
      );
      if (mounted) setState(() => _dados = p);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _aoDigitar(String _) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 350), () {
      _pagina = 0;
      _carregar();
    });
  }

  Future<void> _abrir(String? id) async {
    final base = '/c/${widget.def.chave}';
    final destino = id != null
        ? '$base/$id'
        : Uri(path: '$base/novo',
                queryParameters: widget.herdados.isEmpty ? null : widget.herdados)
            .toString();
    await context.push(destino);
    if (mounted) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.def;
    final editar = podeEditarCadastros();
    final largo = MediaQuery.sizeOf(context).width >= 760;

    final barra = Row(
      children: [
        if (!widget.embutida)
          Expanded(
            child: Text(def.titulo,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          )
        else
          Expanded(
            child: Text(def.titulo,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
        if (def.colunasBusca.isNotEmpty)
        SizedBox(
          width: largo ? 280 : 160,
          child: TextField(
            controller: _busca,
            onChanged: _aoDigitar,
            decoration: const InputDecoration(
              hintText: 'Buscar',
              prefixIcon: Icon(Icons.search, size: 20),
            ),
          ),
        ),
        if (!widget.embutida && largo)
          for (final a in def.acoes) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => context.push(a.rota),
              icon: Icon(a.icone),
              label: Text(a.rotulo),
            ),
          ],
        if (editar) ...[
          const SizedBox(width: 8),
          widget.embutida
              ? OutlinedButton.icon(
                  onPressed: () => _abrir(null),
                  icon: const Icon(Icons.add),
                  label: const Text('Incluir'),
                )
              : FilledButton.icon(
                  onPressed: () => _abrir(null),
                  icon: const Icon(Icons.add),
                  label: Text(largo ? 'Novo ${def.singular.toLowerCase()}' : 'Novo'),
                ),
        ],
      ],
    );

    Widget corpo;
    if (_carregando && _dados == null) {
      corpo = const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_erro != null) {
      corpo = Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(_erro!, style: const TextStyle(color: Cores.erro)),
            TextButton(onPressed: _carregar, child: const Text('Tentar de novo')),
          ],
        ),
      );
    } else if (_dados!.itens.isEmpty) {
      corpo = Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            _busca.text.isNotEmpty
                ? 'Nada encontrado para "${_busca.text}".'
                : 'Nenhum registro ainda.',
            style: const TextStyle(color: Cores.neutro),
          ),
        ),
      );
    } else {
      corpo = _Tabela(
        def: def,
        itens: _dados!.itens,
        largo: largo,
        aoTocar: (r) => _abrir(r['id'] as String),
      );
    }

    final rodape = (_dados != null && (_pagina > 0 || _dados!.temMais))
        ? Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Página ${_pagina + 1}',
                  style: const TextStyle(color: Cores.neutro)),
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
                onPressed: !_dados!.temMais || _carregando
                    ? null
                    : () {
                        _pagina++;
                        _carregar();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          )
        : const SizedBox.shrink();

    final conteudo = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        barra,
        if (!widget.embutida && def.aviso != null) ...[
          const SizedBox(height: 8),
          Text(def.aviso!, style: const TextStyle(color: Cores.neutro)),
        ],
        const SizedBox(height: 12),
        if (_carregando && _dados != null) const LinearProgressIndicator(minHeight: 2),
        Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias, child: corpo),
        rodape,
      ],
    );

    if (widget.embutida) return conteudo;
    return SingleChildScrollView(
      padding: margemDaTela(context),
      child: conteudo,
    );
  }
}

class _Tabela extends StatelessWidget {
  const _Tabela({
    required this.def,
    required this.itens,
    required this.largo,
    required this.aoTocar,
  });

  final CadastroDef def;
  final List<Map<String, dynamic>> itens;
  final bool largo;
  final void Function(Map<String, dynamic>) aoTocar;

  String _texto(Map<String, dynamic> r, ColunaDef c) =>
      formatarValor(valorPorCaminho(r, c.caminho), c.tipo, c.opcoes);

  Widget _celula(Map<String, dynamic> r, ColunaDef c) {
    if (c.tipo == TipoCampo.cor) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: corDeTexto(valorPorCaminho(r, c.caminho)),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
    }
    return Text(_texto(r, c), overflow: TextOverflow.ellipsis);
  }

  @override
  Widget build(BuildContext context) {
    final colunas = def.colunas;
    if (!largo) {
      // Tela estreita: primeira coluna como título, as duas seguintes embaixo.
      return Column(
        children: [
          for (final r in itens) ...[
            ListTile(
              title: Text(_texto(r, colunas.first)),
              subtitle: Text(colunas
                  .skip(1)
                  .take(2)
                  .map((c) => _texto(r, c))
                  .where((t) => t.isNotEmpty)
                  .join(' · ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => aoTocar(r),
            ),
            if (r != itens.last) const Divider(height: 1),
          ],
        ],
      );
    }
    const estiloCabecalho = TextStyle(
        fontWeight: FontWeight.w700, color: Cores.neutro, fontSize: 12);
    return Column(
      children: [
        Container(
          color: Cores.fundo,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              for (final c in colunas)
                Expanded(
                    flex: c.flex,
                    child: Text(c.rotulo.toUpperCase(), style: estiloCabecalho)),
              const SizedBox(width: 24),
            ],
          ),
        ),
        for (final r in itens) ...[
          InkWell(
            onTap: () => aoTocar(r),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  for (final c in colunas)
                    Expanded(
                      flex: c.flex,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _celula(r, c),
                      ),
                    ),
                  const Icon(Icons.chevron_right, size: 20, color: Cores.neutro),
                ],
              ),
            ),
          ),
          if (r != itens.last) const Divider(height: 1),
        ],
      ],
    );
  }
}
