import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Leitura de planilhas escolhidas no computador (guia 55): .xlsx (Excel,
/// Google Planilhas > Baixar > .xlsx, LibreOffice) e .csv. Devolve as linhas
/// da primeira aba como texto, do jeito que o gestor vê na planilha.
///
/// Números saem no formato brasileiro (42,5) para o servidor não confundir
/// o ponto decimal com o separador de milhar.
List<List<String>> lerPlanilha(String nome, Uint8List bytes) {
  final n = nome.toLowerCase();
  if (n.endsWith('.xlsx') || n.endsWith('.xlsm')) return _xlsx(bytes);
  if (n.endsWith('.xls')) {
    throw const FormatException('Planilha .xls antiga: no Excel, use "Salvar como" > .xlsx e escolha de novo.');
  }
  return _csv(bytes);
}

/// Converte as linhas em texto separado por tabulação (o mesmo de copiar do Excel).
String linhasComoTexto(List<List<String>> linhas) =>
    linhas.map((l) => l.map((c) => c.replaceAll(RegExp(r'[\t\r\n]+'), ' ')).join('\t')).join('\n');

List<List<String>> _csv(Uint8List bytes) {
  String texto;
  try {
    texto = utf8.decode(bytes);
  } on FormatException {
    texto = latin1.decode(bytes); // CSV do Excel em português (Windows-1252)
  }
  if (texto.startsWith('﻿')) texto = texto.substring(1);
  final linhas = texto.replaceAll('\r', '').split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (linhas.isEmpty) return [];
  final sep = separadorDaLinha(linhas.first);
  return [for (final l in linhas) camposDaLinha(l, sep)];
}

/// Tabulação (copiado do Excel), ponto e vírgula (CSV em português) ou vírgula.
String separadorDaLinha(String cab) =>
    cab.contains('\t') ? '\t' : (';'.allMatches(cab).length >= ','.allMatches(cab).length ? ';' : ',');

/// Divide uma linha respeitando aspas ("Rua A, 10" fica num campo só).
List<String> camposDaLinha(String linha, String sep) {
  final out = <String>[];
  final atual = StringBuffer();
  var aspas = false;
  for (var i = 0; i < linha.length; i++) {
    final c = linha[i];
    if (c == '"') {
      if (aspas && i + 1 < linha.length && linha[i + 1] == '"') {
        atual.write('"');
        i++;
      } else {
        aspas = !aspas;
      }
    } else if (c == sep && !aspas) {
      out.add(atual.toString().trim());
      atual.clear();
    } else {
      atual.write(c);
    }
  }
  out.add(atual.toString().trim());
  return out;
}

List<List<String>> _xlsx(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('Não consegui abrir a planilha. Confira se é um arquivo .xlsx.');
  }
  String? ler(String caminho) {
    final f = zip.findFile(caminho);
    return f == null ? null : utf8.decode(f.content);
  }

  // Textos compartilhados (a maior parte das células de texto fica aqui).
  final compartilhados = <String>[];
  final ss = ler('xl/sharedStrings.xml');
  if (ss != null) {
    for (final si in XmlDocument.parse(ss).findAllElements('si')) {
      compartilhados.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }

  // A primeira aba: pela ordem do workbook (a "sheet1.xml" nem sempre é a primeira).
  var caminhoAba = 'xl/worksheets/sheet1.xml';
  final wb = ler('xl/workbook.xml');
  final rels = ler('xl/_rels/workbook.xml.rels');
  if (wb != null && rels != null) {
    final primeira = XmlDocument.parse(wb).findAllElements('sheet').firstOrNull;
    final rid = primeira?.getAttribute('r:id') ??
        primeira?.attributes.where((a) => a.name.local == 'id').firstOrNull?.value;
    if (rid != null) {
      for (final r in XmlDocument.parse(rels).findAllElements('Relationship')) {
        if (r.getAttribute('Id') == rid) {
          final alvo = r.getAttribute('Target') ?? '';
          caminhoAba = alvo.startsWith('/') ? alvo.substring(1) : 'xl/$alvo';
        }
      }
    }
  }
  final aba = ler(caminhoAba);
  if (aba == null) throw const FormatException('A planilha não tem nenhuma aba com dados.');

  final linhas = <List<String>>[];
  for (final row in XmlDocument.parse(aba).findAllElements('row')) {
    final celulas = <int, String>{};
    var proxima = 0;
    for (final c in row.findElements('c')) {
      final ref = c.getAttribute('r');
      final col = ref == null ? proxima : _coluna(ref);
      proxima = col + 1;
      final tipo = c.getAttribute('t');
      final v = c.findElements('v').firstOrNull?.innerText ?? '';
      String valor;
      switch (tipo) {
        case 's':
          final i = int.tryParse(v);
          valor = i != null && i < compartilhados.length ? compartilhados[i] : '';
        case 'inlineStr':
          valor = c.findAllElements('t').map((t) => t.innerText).join();
        case 'str':
          valor = v;
        case 'b':
          valor = v == '1' ? 'sim' : 'não';
        case 'e':
          valor = '';
        default:
          valor = _numeroBr(v);
      }
      celulas[col] = valor.trim();
    }
    if (celulas.values.every((x) => x.isEmpty)) continue;
    final ultima = celulas.keys.reduce((a, b) => a > b ? a : b);
    linhas.add([for (var i = 0; i <= ultima; i++) celulas[i] ?? '']);
  }
  return linhas;
}

/// "AB12" -> 27 (coluna a partir de 0).
int _coluna(String ref) {
  var n = 0;
  for (final ch in ref.toUpperCase().codeUnits) {
    if (ch < 65 || ch > 90) break;
    n = n * 26 + (ch - 64);
  }
  return n - 1;
}

/// 42.5 -> "42,5"; 12000 -> "12000"; 0.30000000000000004 -> "0,3".
String _numeroBr(String v) {
  final d = double.tryParse(v);
  if (d == null) return v;
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
  var t = d.toStringAsFixed(6).replaceAll(RegExp(r'0+$'), '');
  if (t.endsWith('.')) t = t.substring(0, t.length - 1);
  return t.replaceAll('.', ',');
}

/// Data do Excel (número de dias desde 30/12/1899) em dd/mm/aaaa.
/// Devolve o próprio texto quando não é um número de data.
String dataDoExcel(String v) {
  final n = int.tryParse(v);
  if (n == null || n < 20000 || n > 80000) return v;
  final d = DateTime.utc(1899, 12, 30).add(Duration(days: n));
  String dois(int x) => x.toString().padLeft(2, '0');
  return '${dois(d.day)}/${dois(d.month)}/${d.year}';
}
