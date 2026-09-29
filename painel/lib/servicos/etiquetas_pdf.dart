import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Formatos de folha A4 de etiquetas adesivas. As medidas seguem os modelos
/// mais comuns do mercado; confira na embalagem do seu papel.
class ModeloEtiqueta {
  const ModeloEtiqueta({
    required this.nome,
    required this.colunas,
    required this.linhas,
    required this.larguraMm,
    required this.alturaMm,
    this.espacoColunasMm = 0,
    this.espacoLinhasMm = 0,
  });

  final String nome;
  final int colunas;
  final int linhas;
  final double larguraMm;
  final double alturaMm;
  final double espacoColunasMm;
  final double espacoLinhasMm;

  int get porFolha => colunas * linhas;

  // A grade fica centralizada na folha A4 (210 x 297 mm).
  double get margemEsquerdaMm =>
      (210 - colunas * larguraMm - (colunas - 1) * espacoColunasMm) / 2;
  double get margemTopoMm =>
      (297 - linhas * alturaMm - (linhas - 1) * espacoLinhasMm) / 2;
}

const modelosEtiqueta = [
  ModeloEtiqueta(
      nome: '24 por folha · 70 x 37 mm (3 x 8)',
      colunas: 3, linhas: 8, larguraMm: 70, alturaMm: 37),
  ModeloEtiqueta(
      nome: '21 por folha · 63,5 x 38,1 mm (3 x 7)',
      colunas: 3, linhas: 7, larguraMm: 63.5, alturaMm: 38.1, espacoColunasMm: 2.5),
  ModeloEtiqueta(
      nome: '14 por folha · 99,1 x 38,1 mm (2 x 7)',
      colunas: 2, linhas: 7, larguraMm: 99.1, alturaMm: 38.1, espacoColunasMm: 2.5),
];

/// Dados de uma etiqueta.
class Etiqueta {
  const Etiqueta({
    required this.codigo,
    required this.qrToken,
    this.descricao,
    this.cliente,
    this.local,
  });

  final String codigo;

  /// O que vai dentro do QR: o qr_token do equipamento (único no sistema).
  final String qrToken;
  final String? descricao;
  final String? cliente;
  final String? local;
}

/// Monta o PDF A4. [pular] deixa em branco as primeiras posições da primeira
/// folha (para aproveitar uma folha já usada pela metade).
Future<Uint8List> gerarPdfEtiquetas({
  required List<Etiqueta> etiquetas,
  required ModeloEtiqueta modelo,
  required String rodape,
  int pular = 0,
  bool contorno = false,
}) async {
  const mm = PdfPageFormat.mm;
  final doc = pw.Document(title: 'Etiquetas QR', author: 'ServIA');

  // Posições: primeiro as puladas (null), depois as etiquetas.
  final vazias = pular < 0 ? 0 : (pular >= modelo.porFolha ? modelo.porFolha - 1 : pular);
  final posicoes = <Etiqueta?>[
    ...List<Etiqueta?>.filled(vazias, null),
    ...etiquetas,
  ];

  for (var inicio = 0; inicio < posicoes.length; inicio += modelo.porFolha) {
    final folha = posicoes.skip(inicio).take(modelo.porFolha).toList();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Stack(children: [
        for (var i = 0; i < folha.length; i++)
          if (folha[i] != null)
            pw.Positioned(
              left: (modelo.margemEsquerdaMm +
                      (i % modelo.colunas) * (modelo.larguraMm + modelo.espacoColunasMm)) *
                  mm,
              top: (modelo.margemTopoMm +
                      (i ~/ modelo.colunas) * (modelo.alturaMm + modelo.espacoLinhasMm)) *
                  mm,
              child: _etiqueta(folha[i]!, modelo, rodape, contorno),
            ),
      ]),
    ));
  }
  return doc.save();
}

/// A fonte padrão do PDF só tem os caracteres latinos (acentos incluídos).
/// Troca os símbolos tipográficos mais comuns pelos equivalentes simples.
String _latin(String? v) {
  const trocas = {'–': '-', '—': '-', '…': '...', '“': '"', '”': '"', '‘': "'", '’': "'", '•': '·'};
  var t = v ?? '';
  trocas.forEach((de, para) => t = t.replaceAll(de, para));
  return t.replaceAll(RegExp(r'[^\u0000-\u00FF]'), '?');
}

pw.Widget _etiqueta(Etiqueta e, ModeloEtiqueta modelo, String rodape, bool contorno) {
  const mm = PdfPageFormat.mm;
  const folga = 3.0; // mm de respiro nas bordas (o corte da etiqueta nunca é exato)
  final qr = (modelo.alturaMm - 2 * folga) * mm;
  final localCliente = _latin([e.cliente, e.local]
      .where((x) => x != null && x.trim().isNotEmpty)
      .join(' · '));
  return pw.Container(
    width: modelo.larguraMm * mm,
    height: modelo.alturaMm * mm,
    padding: const pw.EdgeInsets.all(folga * mm),
    decoration: contorno
        ? pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.3))
        : null,
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: e.qrToken,
          width: qr,
          height: qr,
          drawText: false,
        ),
        pw.SizedBox(width: 2.5 * mm),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(_latin(e.codigo),
                  maxLines: 1,
                  style: const pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
              if ((e.descricao ?? '').isNotEmpty)
                pw.Text(_latin(e.descricao), maxLines: 2, style: const pw.TextStyle(fontSize: 7)),
              if (localCliente.isNotEmpty)
                pw.Text(localCliente,
                    maxLines: 1,
                    style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700)),
              pw.Text(_latin(rodape),
                  maxLines: 2,
                  style: const pw.TextStyle(fontSize: 5.5, color: PdfColors.grey700)),
            ],
          ),
        ),
      ],
    ),
  );
}
