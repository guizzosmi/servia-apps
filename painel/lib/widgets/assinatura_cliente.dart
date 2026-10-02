import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/status.dart';

/// Assinatura do cliente colhida na tela do app: a imagem, quem assinou,
/// quando, e o resumo que ele viu (PDF gerado no aparelho).
/// Os arquivos ficam no bucket "assinaturas" (só gestor, financeiro e admin leem).
class AssinaturaCliente extends StatefulWidget {
  const AssinaturaCliente({super.key, required this.aceite, this.titulo});

  /// Linha da tabela aceites (com assinatura_caminho e documento_caminho).
  final Map<String, dynamic> aceite;

  /// Frase de cima (padrão: "Assinado na tela por ...").
  final String? titulo;

  @override
  State<AssinaturaCliente> createState() => _AssinaturaClienteState();
}

class _AssinaturaClienteState extends State<AssinaturaCliente> {
  late final Future<String?> _url = _urlDaImagem();
  bool _abrindo = false;

  Future<String?> _urlDaImagem() async {
    final caminho = widget.aceite['assinatura_caminho'] as String?;
    if (caminho == null) return null;
    try {
      return await Supabase.instance.client.storage.from('assinaturas').createSignedUrl(caminho, 600);
    } catch (_) {
      return null; // sem a imagem, o registro aparece mesmo assim
    }
  }

  Future<void> _resumo() async {
    final caminho = widget.aceite['documento_caminho'] as String?;
    if (caminho == null) return;
    setState(() => _abrindo = true);
    try {
      final bytes = await Supabase.instance.client.storage.from('assinaturas').download(caminho);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'resumo-assinado');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(mensagemDeErro(e)), backgroundColor: Cores.erro));
      }
    } finally {
      if (mounted) setState(() => _abrindo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.aceite;
    final hash = '${a['documento_sha256'] ?? ''}';
    return Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Container(
        width: 200,
        height: 70,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Cores.linha),
          borderRadius: BorderRadius.circular(8),
        ),
        child: FutureBuilder<String?>(
          future: _url,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
            }
            final url = snap.data;
            if (url == null) {
              return const Center(child: Icon(Icons.draw_outlined, color: Cores.neutro));
            }
            return Padding(
              padding: const EdgeInsets.all(4),
              child: Image.network(url, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.draw_outlined, color: Cores.neutro))),
            );
          },
        ),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(widget.titulo ?? 'Assinado na tela por ${a['nome'] ?? '?'}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(
          [
            dataHoraBr(a['criado_em']),
            if (a['documento_pessoa'] != null) 'documento ${a['documento_pessoa']}',
            if (hash.length >= 12) 'resumo ${hash.substring(0, 12)}…',
          ].join(' · '),
          style: const TextStyle(fontSize: 12, color: Cores.neutro),
        ),
        if (a['documento_caminho'] != null)
          TextButton.icon(
            onPressed: _abrindo ? null : _resumo,
            icon: _abrindo
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Resumo que o cliente assinou'),
          ),
      ]),
    ]);
  }
}
