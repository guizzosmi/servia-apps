import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Leitor da etiqueta do equipamento (QR ou código de barras).
/// Devolve o texto lido (ou digitado) para a tela que abriu.
class LeitorQrTela extends StatefulWidget {
  const LeitorQrTela({super.key});

  @override
  State<LeitorQrTela> createState() => _LeitorQrTelaState();
}

class _LeitorQrTelaState extends State<LeitorQrTela> {
  final _controle = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _devolvido = false;

  /// Com o diálogo de digitar aberto, a câmera não devolve nada (senão o
  /// pop fecharia o diálogo em vez desta tela).
  bool _digitando = false;

  @override
  void dispose() {
    _controle.dispose();
    super.dispose();
  }

  void _devolver(String? valor) {
    if (_devolvido || valor == null || valor.trim().isEmpty) return;
    _devolvido = true;
    context.pop(valor.trim());
  }

  Future<void> _digitar() async {
    final texto = TextEditingController();
    _digitando = true;
    final valor = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Código do equipamento'),
        content: TextField(
          controller: texto,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ex.: 004512'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(texto.text), child: const Text('OK')),
        ],
      ),
    );
    // Sem dispose: o diálogo ainda anima a saída usando o campo.
    _digitando = false;
    if (mounted) _devolver(valor);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ler etiqueta'),
        actions: [
          IconButton(
            tooltip: 'Lanterna',
            // Antes de a câmera iniciar (ou sem permissão), toggleTorch lança erro.
            onPressed: () {
              if (_controle.value.isInitialized) _controle.toggleTorch();
            },
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controle,
          onDetect: (captura) {
            if (_digitando) return;
            for (final b in captura.barcodes) {
              if (b.rawValue != null) {
                _devolver(b.rawValue);
                return;
              }
            }
          },
        ),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: Column(children: [
            const Text('Aponte para o QR da etiqueta.',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _digitar,
              icon: const Icon(Icons.keyboard),
              label: const Text('Digitar o código'),
            ),
          ]),
        ),
      ]),
    );
  }
}
