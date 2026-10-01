import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// PDF gerado na plataforma (função "relatorios").
/// tipo: 'orcamento' ou 'os'.
Future<Uint8List> pdfDoServidor(String tipo, String id) async {
  final r = await Supabase.instance.client.functions.invoke('relatorios', body: {'tipo': tipo, 'id': id});
  final d = r.data;
  if (d is Uint8List) return d;
  if (d is List<int>) return Uint8List.fromList(d);
  throw StateError('O servidor não devolveu o PDF.');
}

/// Botão "PDF" com as opções Ver e imprimir / Baixar.
class BotaoPdf extends StatefulWidget {
  const BotaoPdf({super.key, required this.tipo, required this.id, required this.nomeArquivo, this.rotulo = 'PDF'});

  final String tipo;
  final String id;
  final String nomeArquivo; // sem ".pdf"
  final String rotulo;

  @override
  State<BotaoPdf> createState() => _BotaoPdfState();
}

class _BotaoPdfState extends State<BotaoPdf> {
  bool _gerando = false;

  Future<void> _abrir(bool baixar) async {
    setState(() => _gerando = true);
    try {
      final bytes = await pdfDoServidor(widget.tipo, widget.id);
      if (baixar) {
        await Printing.sharePdf(bytes: bytes, filename: '${widget.nomeArquivo}.pdf');
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: widget.nomeArquivo);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(mensagemDeErro(e)), backgroundColor: Cores.erro));
      }
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<bool>(
      tooltip: widget.rotulo,
      enabled: !_gerando,
      onSelected: _abrir,
      itemBuilder: (_) => const [
        PopupMenuItem(value: false, child: ListTile(leading: Icon(Icons.print_outlined), title: Text('Ver e imprimir'))),
        PopupMenuItem(value: true, child: ListTile(leading: Icon(Icons.download_outlined), title: Text('Baixar'))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: Cores.linha), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _gerando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.picture_as_pdf_outlined, size: 18, color: Cores.indigo500),
          const SizedBox(width: 8),
          Text(_gerando ? 'Gerando…' : widget.rotulo, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
