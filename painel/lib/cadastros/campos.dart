import 'dart:async';

import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'definicoes.dart';
import 'servico.dart';

/// Campo que escolhe um registro de outra tabela (ex.: o cliente).
/// Mostra o nome; ao tocar abre uma janela de busca.
class CampoLookup extends StatefulWidget {
  const CampoLookup({
    super.key,
    required this.campo,
    required this.valor,
    required this.valorPai,
    required this.rotuloPai,
    required this.habilitado,
    required this.aoMudar,
  });

  final CampoDef campo;
  final String? valor;

  /// Valor do campo do qual este depende (ex.: cliente_id para local_id).
  final String? valorPai;
  final String? rotuloPai;
  final bool habilitado;
  final ValueChanged<String?> aoMudar;

  @override
  State<CampoLookup> createState() => _CampoLookupState();
}

class _CampoLookupState extends State<CampoLookup> {
  final _texto = TextEditingController();
  String? _idDoTexto;

  Lookup get _lk => widget.campo.lookup!;

  @override
  void initState() {
    super.initState();
    _buscarRotulo();
  }

  @override
  void didUpdateWidget(CampoLookup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.valor != _idDoTexto) {
      // Trocar o texto aqui (no meio do build do formulário) faria o Form
      // se redesenhar durante o build; por isso fica para depois do quadro.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.valor != _idDoTexto) _buscarRotulo();
      });
    }
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _buscarRotulo() async {
    final id = widget.valor;
    _idDoTexto = id;
    if (id == null) {
      _texto.text = '';
      return;
    }
    _texto.text = '…';
    try {
      final r = await Supabase.instance.client
          .from(_lk.tabela)
          .select(_lk.colunaRotulo)
          .eq('id', id)
          .maybeSingle();
      if (mounted && _idDoTexto == id) {
        _texto.text = (r?[_lk.colunaRotulo] ?? '(não encontrado)').toString();
      }
    } catch (_) {
      if (mounted && _idDoTexto == id) _texto.text = '(erro ao carregar)';
    }
  }

  Future<void> _escolher() async {
    if (_lk.campoPai != null && widget.valorPai == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Escolha primeiro: ${widget.rotuloPai ?? _lk.campoPai}.')));
      return;
    }
    final escolhido = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoLookup(
        titulo: widget.campo.rotulo,
        lookup: _lk,
        valorPai: widget.valorPai,
      ),
    );
    if (escolhido == null) return;
    final id = escolhido['id'] as String;
    _idDoTexto = id;
    _texto.text = (escolhido[_lk.colunaRotulo] ?? '').toString();
    widget.aoMudar(id);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.campo;
    return TextFormField(
      controller: _texto,
      readOnly: true,
      enabled: widget.habilitado,
      onTap: widget.habilitado ? _escolher : null,
      decoration: InputDecoration(
        labelText: c.obrigatorio ? '${c.rotulo} *' : c.rotulo,
        helperText: c.ajuda,
        suffixIcon: !widget.habilitado
            ? null
            : (widget.valor != null && !c.obrigatorio)
                ? IconButton(
                    tooltip: 'Limpar',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _idDoTexto = null;
                      _texto.text = '';
                      widget.aoMudar(null);
                    },
                  )
                : const Icon(Icons.search),
      ),
      validator: (_) =>
          (c.obrigatorio && widget.valor == null) ? 'Obrigatório' : null,
    );
  }
}

class _DialogoLookup extends StatefulWidget {
  const _DialogoLookup({
    required this.titulo,
    required this.lookup,
    required this.valorPai,
  });

  final String titulo;
  final Lookup lookup;
  final String? valorPai;

  @override
  State<_DialogoLookup> createState() => _DialogoLookupState();
}

class _DialogoLookupState extends State<_DialogoLookup> {
  final _busca = TextEditingController();
  Timer? _espera;
  List<Map<String, dynamic>> _itens = [];
  bool _carregando = true;
  String? _erro;

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
    final lk = widget.lookup;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final colunas = ['id', lk.colunaRotulo, if (lk.colunaDetalhe != null) lk.colunaDetalhe!];
      var q = Supabase.instance.client
          .from(lk.tabela)
          .select(colunas.join(','))
          .isFilter('excluido_em', null);
      if (lk.colunaAtivo != null) q = q.eq(lk.colunaAtivo!, true);
      if (lk.colunaFiltro != null) q = q.eq(lk.colunaFiltro!, widget.valorPai!);
      final b = CadastroServico.limparBusca(_busca.text);
      if (b.isNotEmpty) q = q.ilike(lk.colunaRotulo, '%$b%');
      final dados = await q.order(lk.colunaRotulo).limit(30);
      if (mounted) setState(() => _itens = dados);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lk = widget.lookup;
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _busca,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Digite para buscar',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) {
                _espera?.cancel();
                _espera = Timer(const Duration(milliseconds: 300), _carregar);
              },
            ),
            const SizedBox(height: 8),
            if (_carregando) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _erro != null
                  ? Center(child: Text(_erro!, style: const TextStyle(color: Cores.erro)))
                  : (_itens.isEmpty && !_carregando)
                      ? const Center(child: Text('Nada encontrado.'))
                      : ListView.separated(
                          itemCount: _itens.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = _itens[i];
                            final detalhe = lk.colunaDetalhe == null
                                ? null
                                : r[lk.colunaDetalhe!]?.toString();
                            return ListTile(
                              title: Text((r[lk.colunaRotulo] ?? '').toString()),
                              subtitle: (detalhe == null || detalhe.isEmpty)
                                  ? null
                                  : Text(detalhe),
                              onTap: () => Navigator.of(context).pop(r),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

/// Várias escolhas (coluna text[]), exibidas como "chips".
class CampoMultiOpcoes extends StatelessWidget {
  const CampoMultiOpcoes({
    super.key,
    required this.campo,
    required this.valor,
    required this.habilitado,
    required this.aoMudar,
  });

  final CampoDef campo;
  final List<String> valor;
  final bool habilitado;
  final ValueChanged<List<String>> aoMudar;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: campo.rotulo,
        helperText: campo.ajuda,
        enabled: habilitado,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final o in campo.opcoes)
            FilterChip(
              label: Text(o.rotulo),
              selected: valor.contains(o.valor),
              onSelected: !habilitado
                  ? null
                  : (sel) {
                      final novo = List<String>.of(valor);
                      if (sel) {
                        novo.add(o.valor);
                      } else {
                        novo.remove(o.valor);
                      }
                      aoMudar(novo);
                    },
            ),
        ],
      ),
    );
  }
}
