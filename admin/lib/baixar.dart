import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Baixa um texto como arquivo (CSV com BOM, para o Excel abrir com acentos).
void baixarTexto(String nome, String conteudo, {String tipo = 'text/csv;charset=utf-8'}) {
  final bytes = utf8.encode('﻿$conteudo');
  final blob = web.Blob(<web.BlobPart>[bytes.toJS].toJS, web.BlobPropertyBag(type: tipo));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = nome;
  web.document.body!.appendChild(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}

/// Monta um CSV com ponto e vírgula (o Excel em português abre direto).
String csv(List<String> cabecalho, List<List<Object?>> linhas) {
  String celula(Object? v) {
    final s = v == null ? '' : '$v';
    return (s.contains(';') || s.contains('"') || s.contains('\n')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  return [cabecalho, ...linhas].map((l) => l.map(celula).join(';')).join('\r\n');
}
