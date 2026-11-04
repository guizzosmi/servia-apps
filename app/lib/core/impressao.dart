import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:servia_comum/servia_comum.dart';

import 'acoes_orcamento.dart';
import 'resumo.dart';

/// Imprimir ou compartilhar o recibo da OS no local (sem internet).
/// Imprimir abre o serviço de impressão do celular: impressora Wi-Fi, ou a
/// térmica bluetooth pelo app dela (ex.: RawBT), com o papel escolhido em
/// Configurações > Impressão da OS (A4 ou bobina de 80/58 mm).
class Impressao {
  Impressao._();

  static Future<Uint8List> recibo(ConteudoResumo c, Decisao? d) => ResumoPdf.gerar(
        c,
        d == null || d.png == null
            ? null
            : RegistroAssinatura(
                nome: d.nome.trim(),
                documento: d.documento,
                png: d.png,
                decisao: d.decisao,
                motivo: d.motivo,
                em: DateTime.now(),
                tecnico: AcoesOrcamento.nomeDoTecnico,
              ),
        formato: AcoesOrcamento.config.osPapel,
      );

  /// Pergunta se imprime ou compartilha e faz.
  static Future<void> oferecer(BuildContext context, ConteudoResumo c, Decisao? d, String nomeArquivo) async {
    final escolha = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recibo do serviço'),
        content: Text(d?.png != null
            ? 'Imprimir ou mandar ao cliente o recibo com a assinatura dele?'
            : 'Imprimir o recibo para o cliente assinar no papel, ou mandar a ele?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Agora não')),
          TextButton(onPressed: () => Navigator.of(ctx).pop('compartilhar'), child: const Text('Compartilhar')),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop('imprimir'),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimir'),
          ),
        ],
      ),
    );
    if (escolha == null) return;
    try {
      final bytes = await recibo(c, d);
      if (escolha == 'imprimir') {
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: nomeArquivo,
          format: ResumoPdf.papel(AcoesOrcamento.config.osPapel),
        );
      } else {
        await Printing.sharePdf(bytes: bytes, filename: '$nomeArquivo.pdf');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Não deu para ${escolha == 'imprimir' ? 'imprimir' : 'compartilhar'}: $e'),
                backgroundColor: Cores.erro));
      }
    }
  }

  /// Valores no recibo: pergunta quando a empresa escolheu "perguntar na hora".
  /// null = voltou.
  static Future<bool?> perguntarValores(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Valores no recibo'),
          content: const Text('Mostrar o preço das peças e serviços e o total no recibo que o cliente vê e assina?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Voltar')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Sem valores')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Com valores')),
          ],
        ),
      );
}
