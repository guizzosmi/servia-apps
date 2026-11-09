import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:web/web.dart' as web;

/// Gestão de Equipamentos, sprints 5 a 7 (guia 103): textos e ajudantes da manutenção, da preventiva,
/// dos indicadores e do fechamento.

const causasFalha = {
  'desgaste': 'Desgaste',
  'mau_uso': 'Mau uso',
  'operacao': 'Operação',
  'falta_manutencao': 'Falta de manutenção',
  'defeito_fabrica': 'Defeito de fábrica',
  'acidente': 'Acidente',
  'outra': 'Outra',
};

const origensFalha = {
  'app': 'App',
  'painel': 'Painel',
  'api': 'API',
  'retorno': 'Retorno',
  'checklist': 'Checklist',
  'preventiva': 'Preventiva',
};

const estadosPreventiva = {'vencida': 'Vencida', 'a_vencer': 'A vencer', 'em_dia': 'Em dia'};

Color corDoEstado(String? e) => switch (e) {
      'vencida' => Cores.erro,
      'a_vencer' => Cores.alerta,
      _ => Cores.sucesso,
    };

const unidadesMedidor = {'horas': 'h', 'km': 'km', 'ciclos': 'ciclos'};

/// Número no formato brasileiro, sem casas desnecessárias: 1262 / 12,5 / 1.234,5.
String numBr(Object? v, {int casas = 1}) {
  final n = num.tryParse('${v ?? ''}');
  if (n == null) return '–';
  final t = n.toStringAsFixed(casas);
  final partes = t.split('.');
  final inteiro = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  final dec = partes.length > 1 ? partes[1].replaceFirst(RegExp(r'0+$'), '') : '';
  return dec.isEmpty ? inteiro : '$inteiro,$dec';
}

/// Percentual (51,6%) ou traço.
String pctBr(Object? v) => v == null ? '–' : '${numBr(v)}%';

/// Mês por extenso curto: 2026-10-01 -> "10/2026".
String mesBr(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  if (d == null) return '';
  return '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Os últimos [n] meses (o primeiro é o passado), como AAAA-MM-01.
List<String> mesesRecentes({int n = 12}) {
  final hoje = DateTime.now();
  return List.generate(n, (i) {
    final d = DateTime(hoje.year, hoje.month - i - 1, 1);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-01';
  });
}

/// Baixa um texto como arquivo (CSV com BOM, para o Excel abrir com acentos).
void baixarTextoEqp(String nome, String conteudo, {String tipo = 'text/csv;charset=utf-8'}) {
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

/// Etiqueta pequena colorida (estado da preventiva, pendência).
class EtiquetaEqp extends StatelessWidget {
  const EtiquetaEqp(this.texto, {super.key, this.cor = Cores.neutro});

  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: .08),
          border: Border.all(color: cor.withValues(alpha: .5)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(texto, style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}
