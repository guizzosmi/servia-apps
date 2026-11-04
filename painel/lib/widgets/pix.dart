import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/whatsapp.dart';
import 'itens_os.dart' show dinheiro;

/// Receber por Pix (guia 73): o QR Code e o "copia e cola" com o valor da
/// cobrança dentro. Pix estático do Banco Central: cai direto na conta da
/// chave cadastrada em Configurações, sem taxa. A baixa continua no "Recebi".
Future<void> mostrarPix(BuildContext context, {String? cobrancaId, num? valor, String? descricao}) async {
  Map<String, dynamic> r;
  try {
    r = Map<String, dynamic>.from(await Supabase.instance.client.rpc('pix_cobrar', params: {
      'p': {
        if (cobrancaId != null) 'cobranca_id': cobrancaId,
        if (cobrancaId == null) 'valor': valor,
        if (descricao != null) 'descricao': descricao,
      }
    }) as Map);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagemDeErro(e)), backgroundColor: Cores.erro));
    }
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (_) => _Pix(r: r));
}

class _Pix extends StatelessWidget {
  const _Pix({required this.r});

  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final cc = '${r['copia_e_cola']}';
    final clienteId = r['cliente_id'] as String?;
    return AlertDialog(
      title: Text('Pix · ${dinheiro(r['valor'])}'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (r['cliente'] != null) Text('${r['cliente']}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: SizedBox(width: 240, height: 240, child: CustomPaint(painter: _QrPintor(cc))),
            ),
            const SizedBox(height: 8),
            Text('Recebedor: ${r['nome']} · chave ${r['chave']}',
                textAlign: TextAlign.center, style: const TextStyle(color: Cores.neutro, fontSize: 12)),
            const SizedBox(height: 12),
            SelectableText(cc, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            const SizedBox(height: 8),
            const Text('O dinheiro cai direto na conta da chave. Confira no banco e dê baixa em "Recebi".',
                textAlign: TextAlign.center, style: TextStyle(color: Cores.neutro, fontSize: 12)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: cc));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pix copia e cola copiado.')));
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copiar'),
        ),
        if (clienteId != null)
          FilledButton.icon(
            onPressed: () => mandarWhatsAppSemOs(context,
                modelo: 'cobranca_pix',
                titulo: 'Mandar o Pix',
                clienteId: clienteId,
                valores: {
                  'cliente': '${r['cliente'] ?? ''}',
                  'valor': dinheiro(r['valor']),
                  'referencia': '${r['referencia'] ?? 'serviço'}',
                  'chave': '${r['chave']}',
                  'pix': cc,
                }),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('WhatsApp'),
          ),
      ],
    );
  }
}

/// Desenha o QR Code (pacote qr, já usado pelo pdf).
class _QrPintor extends CustomPainter {
  _QrPintor(String dados) : _img = QrImage(QrCode.fromData(data: dados, errorCorrectLevel: QrErrorCorrectLevel.M));

  final QrImage _img;

  @override
  void paint(Canvas canvas, Size size) {
    final n = _img.moduleCount;
    final lado = size.shortestSide / n;
    final tinta = Paint()..color = Colors.black;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (_img.isDark(y, x)) canvas.drawRect(Rect.fromLTWH(x * lado, y * lado, lado + .5, lado + .5), tinta);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPintor old) => false;
}
