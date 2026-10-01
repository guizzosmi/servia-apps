import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/status.dart';
import 'itens_os.dart' show dinheiro;
import 'status_chip.dart';

/// Orçamentos da OS (a versão mais nova de cada um) e o botão para criar.
class OrcamentosDaOs extends StatefulWidget {
  const OrcamentosDaOs({super.key, required this.osId, required this.podeCriar, this.versao = 0, this.aoMudar});

  final String osId;
  final bool podeCriar;

  /// Muda quando a tela da OS recarrega: recarrega junto.
  final int versao;
  final VoidCallback? aoMudar;

  @override
  State<OrcamentosDaOs> createState() => _OrcamentosDaOsState();
}

class _OrcamentosDaOsState extends State<OrcamentosDaOs> {
  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;
  List<Map<String, dynamic>> _orcamentos = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(OrcamentosDaOs antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.versao != widget.versao) _carregar();
  }

  int _pedido = 0;

  Future<void> _carregar() async {
    final meu = ++_pedido;
    try {
      final r = await Supabase.instance.client
          .from('orcamentos')
          .select('id, codigo, numero, versao_orcamento, status, total, validade_ate, substituido_por_id, '
              'aprovado_em, reprovado_em, enviado_em, criado_em')
          .eq('os_id', widget.osId)
          .isFilter('excluido_em', null)
          .order('numero', ascending: false)
          .order('versao_orcamento', ascending: false);
      if (!mounted || meu != _pedido) return;
      setState(() {
        _erro = null;
        // Só a versão mais nova de cada orçamento (as outras ficam dentro dele).
        _orcamentos = r.where((o) => o['substituido_por_id'] == null).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  bool get _temAberto => _orcamentos.any((o) => ['rascunho', 'enviado'].contains(o['status']));

  Future<void> _abrir(String id) async {
    await context.push('/orcamentos/$id');
    if (mounted) widget.aoMudar?.call();
  }

  Future<void> _criar() async {
    if (!mounted) return;
    setState(() => _ocupado = true);
    try {
      final r = await acaoOrcamento({'acao': 'criar', 'os_id': widget.osId});
      if (!mounted) return;
      await _abrir(r['orcamento_id'] as String);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(mensagemDeErro(e)), backgroundColor: Cores.erro));
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  String _quando(Map<String, dynamic> o) => switch (o['status']) {
        'aprovado' => 'aprovado em ${dataBr(o['aprovado_em'])}',
        'reprovado' => 'reprovado em ${dataBr(o['reprovado_em'])}',
        'enviado' => 'enviado em ${dataBr(o['enviado_em'])} · válido até ${dataBr(o['validade_ate'])}',
        _ => 'criado em ${dataBr(o['criado_em'])}',
      };

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const LinearProgressIndicator(minHeight: 2);
    if (_erro != null) return Text(_erro!, style: const TextStyle(color: Cores.erro));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_orcamentos.isEmpty) const Text('Nenhum orçamento.', style: TextStyle(color: Cores.neutro)),
      for (final o in _orcamentos)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.request_quote_outlined, color: Cores.indigo500),
          title: Text('${o['codigo']} v${o['versao_orcamento']} · ${dinheiro(o['total'])}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(_quando(o)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            StatusChip(statusOrcamentoVisivel(o), statusOrcamento),
            const Icon(Icons.chevron_right, color: Cores.neutro),
          ]),
          onTap: () => _abrir(o['id'] as String),
        ),
      if (widget.podeCriar && !_temAberto)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _ocupado ? null : _criar,
            icon: const Icon(Icons.add),
            label: const Text('Novo orçamento'),
          ),
        ),
    ]);
  }
}
