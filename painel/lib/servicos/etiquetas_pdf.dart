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
    this.ambiente,
    this.serie,
  });

  final String codigo;

  /// O que vai dentro do QR: o qr_token do equipamento (único no sistema).
  final String qrToken;
  final String? descricao;
  final String? cliente;
  final String? local;

  /// Onde o aparelho fica no local (ambiente e setor/andar): é o que diz em qual
  /// aparelho colar quando há vários iguais.
  final String? ambiente;
  final String? serie;
}

/// Monta o PDF A4. [pular] deixa em branco as primeiras posições da primeira
/// folha (para aproveitar uma folha já usada pela metade).
Future<Uint8List> gerarPdfEtiquetas({
  required List<Etiqueta> etiquetas,
  required ModeloEtiqueta modelo,
  required String rodape,
  int pular = 0,
  bool contorno = false,
  bool listaDeColagem = false,
}) async {
  const mm = PdfPageFormat.mm;
  final doc = pw.Document(title: 'Etiquetas QR', author: 'ServPilot');
  if (listaDeColagem) _listaDeColagem(doc, etiquetas);

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
  final temAmbiente = (e.ambiente ?? '').trim().isNotEmpty;
  final onde = temAmbiente ? _latin(e.ambiente) : 'Ambiente não informado';
  final descricao = _latin([e.descricao, if ((e.serie ?? '').trim().isNotEmpty) 'S/N ${e.serie!.trim()}']
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
              // Onde colar: o ambiente vem logo abaixo do código, em destaque.
              pw.Text(onde,
                  maxLines: 2,
                  style: pw.TextStyle(
                      fontSize: temAmbiente ? 9 : 7,
                      fontWeight: pw.FontWeight.bold,
                      color: temAmbiente ? PdfColors.black : PdfColors.grey600)),
              if (descricao.isNotEmpty)
                pw.Text(descricao, maxLines: 2, style: const pw.TextStyle(fontSize: 6.5)),
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

/// Primeira folha: a lista de colagem, na mesma ordem das etiquetas (por cliente, local e ambiente),
/// para o técnico conferir onde vai cada uma e marcar o que já colou.
void _listaDeColagem(pw.Document doc, List<Etiqueta> etiquetas) {
  const mm = PdfPageFormat.mm;
  final semAmbiente = etiquetas.where((e) => (e.ambiente ?? '').trim().isEmpty).length;
  const cab = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
  const cel = pw.TextStyle(fontSize: 8);
  pw.Widget c(String v, {pw.TextStyle estilo = cel}) =>
      pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5), child: pw.Text(_latin(v), style: estilo));
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(12 * mm),
    header: (_) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Lista de colagem das etiquetas', style: const pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.Text(
            _latin('${etiquetas.length} etiquetas, na ordem da impressão (por local e ambiente). '
                'Confira o nº de série na plaqueta do aparelho antes de colar.'
                '${semAmbiente > 0 ? ' $semAmbiente sem ambiente: confira pelo nº de série ou cadastre o ambiente.' : ''}'),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ]),
    ),
    build: (_) => [
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
        columnWidths: const {
          0: pw.FixedColumnWidth(30),
          1: pw.FlexColumnWidth(3),
          2: pw.FlexColumnWidth(3),
          3: pw.FlexColumnWidth(4),
          4: pw.FlexColumnWidth(2),
          5: pw.FixedColumnWidth(22),
        },
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
            c('Código', estilo: cab), c('Ambiente', estilo: cab), c('Local', estilo: cab),
            c('Aparelho', estilo: cab), c('Nº de série', estilo: cab), c('Colou', estilo: cab),
          ]),
          for (final e in etiquetas)
            pw.TableRow(children: [
              c(e.codigo, estilo: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              c((e.ambiente ?? '').trim().isEmpty ? '-' : e.ambiente!),
              c([e.cliente, e.local].where((x) => x != null && x.trim().isNotEmpty).join(' · ')),
              c(e.descricao ?? ''),
              c(e.serie ?? ''),
              pw.Center(child: pw.Container(width: 9, height: 9, margin: const pw.EdgeInsets.all(2),
                  decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6)))),
            ]),
        ],
      ),
    ],
  ));
}
