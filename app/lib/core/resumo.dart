import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'formatos.dart';

/// Uma linha de item no resumo (valores só no orçamento).
class LinhaResumo {
  const LinhaResumo({required this.descricao, required this.quantidade, this.unitario, this.desconto, this.total});

  final String descricao;
  final String quantidade; // "2 un"
  final num? unitario;
  final num? desconto;
  final num? total;

  Map<String, dynamic> toJson() =>
      {'descricao': descricao, 'quantidade': quantidade, 'unitario': unitario, 'desconto': desconto, 'total': total};
}

/// O que o cliente vê e assina: o mesmo conteúdo vai para a tela de
/// assinatura e para o PDF gerado no aparelho.
class ConteudoResumo {
  const ConteudoResumo({
    required this.titulo,
    required this.subtitulo,
    required this.empresa,
    this.campos = const [],
    this.blocos = const [],
    this.itens = const [],
    this.comValores = false,
    this.totais = const [],
    this.termo,
    this.recibo = false,
  });

  final String titulo; // ORÇAMENTO, RECIBO DE SERVIÇO
  final String subtitulo; // ORC-000012 v1 · 05/11/2026
  final Map<String, dynamic> empresa; // nome, razao_social, documento, telefone, email, endereco
  final List<(String, String)> campos;
  final List<(String, String)> blocos; // textos longos (diagnóstico, solução...)
  final List<LinhaResumo> itens;
  final bool comValores;
  final List<(String, String)> totais; // o último é o total
  final String? termo;

  /// Recibo de serviço (conclusão) em vez de orçamento: muda só os títulos
  /// ("Declaração", "Recebido por"), com ou sem valores.
  final bool recibo;

  Map<String, dynamic> toJson() => {
        'titulo': titulo,
        'subtitulo': subtitulo,
        'empresa': empresa['nome'],
        'campos': [for (final c in campos) [c.$1, c.$2]],
        'blocos': [for (final b in blocos) [b.$1, b.$2]],
        'itens': [for (final i in itens) i.toJson()],
        'totais': [for (final t in totais) [t.$1, t.$2]],
        'termo': termo,
      };

  /// Identificação do conteúdo (vai no rodapé do PDF).
  String get hash => sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();
}

/// Quem assinou (ou recusou) e como.
class RegistroAssinatura {
  const RegistroAssinatura({
    required this.nome,
    this.documento,
    this.png,
    required this.decisao,
    this.motivo,
    required this.em,
    required this.tecnico,
  });

  final String nome;
  final String? documento;
  final Uint8List? png;
  final String decisao; // aprovado | reprovado | ciente
  final String? motivo;
  final DateTime em;
  final String tecnico;
}

/// Gera o PDF do resumo assinado, no próprio aparelho (sem internet).
class ResumoPdf {
  ResumoPdf._();

  static const _indigo = PdfColor.fromInt(0xFF1E2A5A);
  static const _neutro = PdfColor.fromInt(0xFF5B6474);
  static const _linha = PdfColor.fromInt(0xFFDCE1EA);
  static const _fundo = PdfColor.fromInt(0xFFE6E9F6);

  /// As fontes padrão do PDF cobrem o português; o resto vira um parecido.
  static String _t(Object? v) {
    final s = '${v ?? ''}'
        .replaceAll(RegExp('[–—]'), '-')
        .replaceAll('…', '...')
        .replaceAll(RegExp('[“”]'), '"')
        .replaceAll(RegExp('[‘’]'), "'")
        .replaceAll('•', '-');
    return String.fromCharCodes(s.runes.map((r) => r == 10 || (r >= 32 && r <= 255) ? r : 63));
  }

  /// Papel: A4 (padrão), bobina de 80 mm ou de 58 mm (impressora térmica).
  static PdfPageFormat papel(String codigo) => switch (codigo) {
        '80mm' => PdfPageFormat.roll80,
        '58mm' => PdfPageFormat.roll57,
        _ => PdfPageFormat.a4,
      };

  /// [a] null = ainda sem assinatura (sai a linha para assinar no papel).
  /// [formato]: 'a4', '80mm' ou '58mm'.
  static Future<Uint8List> gerar(ConteudoResumo c, RegistroAssinatura? a, {String formato = 'a4'}) async {
    final doc = pw.Document(title: _t('${c.titulo} ${c.subtitulo}'), author: _t(c.empresa['nome']), creator: 'ServPilot');
    final e = c.empresa;
    final bobina = formato == '80mm' || formato == '58mm';
    final f = bobina ? .9 : 1.0; // letras um pouco menores na bobina
    final aprovado = a == null || a.decisao != 'reprovado';
    final orcamento = !c.recibo && c.comValores;
    pw.TextStyle est(double t, {bool negrito = false, PdfColor? cor}) =>
        pw.TextStyle(fontSize: t * f, fontWeight: negrito ? pw.FontWeight.bold : null, color: cor);
    pw.Widget secao(String t) => pw.Container(
          alignment: pw.Alignment.centerLeft, // ocupa a largura toda
          margin: const pw.EdgeInsets.only(top: 10, bottom: 5),
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          color: _fundo,
          child: pw.Text(_t(t.toUpperCase()), style: est(8.5, negrito: true, cor: _indigo)),
        );
    pw.Widget campo(String r, String v) => bobina
        ? pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text(_t('$r: $v'), style: est(9)),
          )
        : pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(width: 95, child: pw.Text(_t(r), style: est(9, cor: _neutro))),
              pw.Expanded(child: pw.Text(_t(v), style: est(9))),
            ]),
          );

    final dadosEmpresa = [e['razao_social'], e['documento'], e['telefone'], e['email']]
        .where((x) => x != null && '$x'.isNotEmpty)
        .join(' · ');
    final cabecalho = bobina
        ? pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
            pw.Text(_t(e['nome'] ?? e['razao_social'] ?? ''), style: est(12, negrito: true, cor: _indigo), textAlign: pw.TextAlign.center),
            pw.Text(_t(dadosEmpresa), style: est(7.5, cor: _neutro), textAlign: pw.TextAlign.center),
            if (e['endereco'] != null) pw.Text(_t(e['endereco']), style: est(7.5, cor: _neutro), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 6),
            pw.Text(_t(c.titulo), style: est(11, negrito: true, cor: _indigo)),
            pw.Text(_t(c.subtitulo), style: est(8, cor: _neutro)),
            pw.Divider(color: _indigo, thickness: .8),
          ])
        : pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 6),
            margin: const pw.EdgeInsets.only(bottom: 6),
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _indigo, width: 1))),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(_t(e['nome'] ?? e['razao_social'] ?? ''), style: est(13, negrito: true, cor: _indigo)),
                  pw.Text(_t(dadosEmpresa), style: est(7.5, cor: _neutro)),
                  if (e['endereco'] != null) pw.Text(_t(e['endereco']), style: est(7.5, cor: _neutro)),
                ]),
              ),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text(_t(c.titulo), style: est(12, negrito: true, cor: _indigo)),
                pw.Text(_t(c.subtitulo), style: est(8, cor: _neutro)),
              ]),
            ]),
          );
    String rodape(String pagina) => _t('${a == null ? 'Recibo gerado no aparelho' : 'Resumo assinado no aparelho'}'
        ' · conteúdo ${c.hash.substring(0, 16)}$pagina');

    // Itens: tabela no A4; na bobina, uma linha de texto por item (cabe em 58 mm).
    final List<pw.Widget> itens = [];
    if (c.itens.isNotEmpty) {
      itens.add(secao(orcamento ? 'Itens' : 'Peças e serviços'));
      if (bobina) {
        for (final i in c.itens) {
          itens.add(pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(_t(i.descricao), style: est(9)),
              pw.Row(children: [
                pw.Expanded(
                  child: pw.Text(
                      _t('${i.quantidade}${c.comValores ? ' x ${dinheiro(i.unitario)}' : ''}'
                          '${c.comValores && (i.desconto ?? 0) > 0 ? ' - desc. ${dinheiro(i.desconto)}' : ''}'),
                      style: est(8, cor: _neutro)),
                ),
                if (c.comValores) pw.Text(_t(dinheiro(i.total)), style: est(9)),
              ]),
            ]),
          ));
        }
      } else {
        itens.add(pw.TableHelper.fromTextArray(
          headers: c.comValores ? ['Descrição', 'Qtd.', 'Unitário', 'Desconto', 'Total'] : ['Descrição', 'Qtd.'],
          data: [
            for (final i in c.itens)
              [
                _t(i.descricao),
                _t(i.quantidade),
                if (c.comValores) ...[
                  _t(dinheiro(i.unitario)),
                  _t((i.desconto ?? 0) == 0 ? '-' : dinheiro(i.desconto)),
                  _t(dinheiro(i.total)),
                ],
              ],
          ],
          headerStyle: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: _indigo),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          cellAlignments: {
            for (var k = 1; k < (c.comValores ? 5 : 2); k++) k: pw.Alignment.centerRight,
          },
          columnWidths: c.comValores
              ? {0: const pw.FlexColumnWidth(4.6), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1.4),
                 3: const pw.FlexColumnWidth(1.2), 4: const pw.FlexColumnWidth(1.4)}
              : {0: const pw.FlexColumnWidth(5), 1: const pw.FlexColumnWidth(1)},
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _linha, width: .5)),
        ));
      }
    }

    final corpo = <pw.Widget>[
      for (final (r, v) in c.campos)
        if (v.trim().isNotEmpty) campo(r, v),
      for (final (t, txt) in c.blocos)
        if (txt.trim().isNotEmpty) ...[secao(t), pw.Text(_t(txt), style: est(9.5))],
      ...itens,
      if (c.totais.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            for (var k = 0; k < c.totais.length; k++)
              pw.Text(
                _t('${c.totais[k].$1}:  ${c.totais[k].$2}'),
                style: k == c.totais.length - 1 ? est(11.5, negrito: true, cor: _indigo) : est(9),
              ),
          ]),
        ),
      if (c.termo != null && c.termo!.trim().isNotEmpty) ...[
        secao(orcamento ? 'Termo de aceite' : 'Declaração'),
        pw.Text(_t(c.termo), style: est(8.5)),
      ],
      secao(!aprovado ? 'Recusa do cliente' : (orcamento ? 'Aprovação do cliente' : 'Recebido por')),
      if (a?.png != null)
        pw.Container(
          height: 70,
          alignment: pw.Alignment.bottomLeft,
          child: pw.Image(pw.MemoryImage(a!.png!), height: 66, fit: pw.BoxFit.contain),
        ),
      if (a == null) pw.SizedBox(height: 46),
      if (a?.png != null || a == null) pw.Container(width: bobina ? double.infinity : 240, height: .7, color: PdfColors.black),
      pw.SizedBox(height: 4),
      if (a == null)
        pw.Text(_t('Nome:  ______________________________   Data: ____/____/______'), style: est(9))
      else ...[
        pw.Text(
          _t('${aprovado ? (orcamento ? 'Aprovado' : 'Assinado') : 'Recusado'} por ${a.nome}'
              '${a.documento != null && a.documento!.isNotEmpty ? ' (documento ${a.documento})' : ''}'
              ' em ${dataHoraBr(a.em.toUtc().toIso8601String())}'
              '${a.png != null ? ', com assinatura na tela.' : '.'}'),
          style: est(9),
        ),
        if (a.motivo != null && a.motivo!.trim().isNotEmpty) pw.Text(_t('Motivo: ${a.motivo}'), style: est(9)),
        pw.Text(_t('Registrado no app por ${a.tecnico}.'), style: est(8, cor: _neutro)),
      ],
    ];

    if (bobina) {
      // Bobina: uma página contínua, do tamanho do conteúdo.
      final base = papel(formato);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(base.width, double.infinity, marginAll: 3 * PdfPageFormat.mm),
        build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          cabecalho,
          ...corpo,
          pw.SizedBox(height: 8),
          pw.Text(rodape(''), style: est(6.5, cor: _neutro), textAlign: pw.TextAlign.center),
          pw.SizedBox(height: 12), // folga para o corte do papel
        ]),
      ));
    } else {
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 36),
        header: (ctx) => cabecalho,
        footer: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 4),
          decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _linha, width: .5))),
          child: pw.Text(rodape(' · página ${ctx.pageNumber} de ${ctx.pagesCount}'), style: est(7, cor: _neutro)),
        ),
        build: (ctx) => corpo,
      ));
    }
    return doc.save();
  }
}
