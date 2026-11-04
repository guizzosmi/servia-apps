import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/arquivo_web.dart' show abrirEmNovaAba;
import '../servicos/notas.dart';
import 'itens_os.dart' show dinheiro;

/// Botão "Nota fiscal" da OS (guia 81): mostra as notas da OS ou prepara
/// a NFS-e (e a NF-e das peças) e emite. Só aparece com o módulo contratado.
class BotaoNotaOs extends StatefulWidget {
  const BotaoNotaOs({super.key, required this.osId});
  final String osId;

  @override
  State<BotaoNotaOs> createState() => _BotaoNotaOsState();
}

class _BotaoNotaOsState extends State<BotaoNotaOs> {
  bool? _contratado;
  List<Map<String, dynamic>> _notas = [];

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final f = Map<String, dynamic>.from(await _db.rpc('fiscal_config') as Map);
      final r = await _db.rpc('notas_lista', params: {
        'p': {'os_id': widget.osId}
      });
      if (mounted) {
        setState(() {
          _contratado = f['contratado'] == true;
          _notas = ((r as Map)['notas'] as List? ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
        });
      }
    } catch (_) {
      // Técnico ou sem permissão: o botão não aparece.
      if (mounted) setState(() => _contratado = false);
    }
  }

  void _avisar(String t, {bool erro = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Cores.erro : null));

  Future<void> _preparar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nota fiscal desta OS'),
        content: const Text('Preparo a NFS-e dos serviços (e a NF-e das peças, se a empresa emite) com o cadastro do cliente. '
            'Você confere antes de emitir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Preparar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('notas_preparar', params: {
        'p': {
          'os_ids': [widget.osId],
          'agrupar': 'os'
        }
      }) as Map);
      final notas = ((r['notas'] as List?) ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
      final avisos = ((r['avisos'] as List?) ?? const []).map((x) => '${(x as Map)['aviso']}').toList();
      await _carregar();
      if (!mounted) return;
      if (notas.isEmpty) {
        _avisar('A OS não tem valor para nota.', erro: true);
        return;
      }
      final emitir = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Conferir'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final n in notas) Text('${rotuloTipoNota[n['tipo']]} · ${n['cliente']} · ${dinheiro(n['valor'])}'),
            if (avisos.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(avisos.map((a) => '• $a').join('\n'), style: const TextStyle(color: Cores.alerta)),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Deixar como rascunho')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Emitir agora')),
          ],
        ),
      );
      if (emitir != true) return;
      final (enviadas, falhas) = await emitirNotas([for (final n in notas) '${n['nota_id']}']);
      if (falhas.isEmpty) {
        _avisar(enviadas == 1 ? 'Nota enviada.' : '$enviadas notas enviadas.');
      } else {
        _avisar(falhas.join(' · '), erro: true);
      }
      await Future<void>.delayed(const Duration(seconds: 6));
      for (final n in notas) {
        try {
          await funcaoNotas({'acao': 'consultar', 'nota_id': n['nota_id']});
        } catch (_) {}
      }
      _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_contratado != true) return const SizedBox.shrink();
    final ativas = _notas.where((n) => n['status'] != 'cancelada').toList();
    if (ativas.isEmpty) {
      return OutlinedButton.icon(
          onPressed: _preparar, icon: const Icon(Icons.receipt_long_outlined), label: const Text('Emitir nota fiscal'));
    }
    return Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final n in ativas)
        InputChip(
          avatar: const Icon(Icons.receipt_long_outlined, size: 18),
          label: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${rotuloTipoNota[n['tipo']]}${(n['numero'] ?? '') != '' ? ' ${n['numero']}' : ''} '),
            SeloNota('${n['status']}'),
          ]),
          onPressed: (n['url_pdf'] ?? '') != '' ? () => abrirEmNovaAba('${n['url_pdf']}') : () => context.go('/notas'),
        ),
    ]);
  }
}
