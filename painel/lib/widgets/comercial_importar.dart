import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/arquivo_web.dart';
import '../servicos/comercial.dart';
import '../servicos/planilha.dart';

/// Importar planilha no funil (guia 97): a exportação do ClickUp (Configurações › Importar/Exportar ›
/// Exportar, CSV) ou qualquer planilha com uma linha de títulos. O banco reconhece as colunas
/// (Task Name, Status, Due date, Assignees, Valor, Telefone...) e, importando de novo, atualiza em vez
/// de duplicar (pelo Task ID). Devolve true se gravou alguma coisa.
Future<bool> importarPlanilhaComercial(BuildContext context) async =>
    (await showDialog<bool>(context: context, builder: (_) => const _DialogoImportar())) == true;

/// Lê o CSV respeitando aspas, inclusive com quebra de linha dentro (a descrição do ClickUp vem assim).
List<List<String>> lerCsvComercial(String texto) {
  if (texto.startsWith('﻿')) texto = texto.substring(1);
  final fimCab = texto.indexOf('\n');
  final sep = separadorDaLinha(fimCab < 0 ? texto : texto.substring(0, fimCab));
  final linhas = <List<String>>[];
  final campo = StringBuffer();
  var linha = <String>[];
  var aspas = false;
  void fecharLinha() {
    linha.add(campo.toString().trim());
    campo.clear();
    if (linha.any((x) => x.isNotEmpty)) linhas.add(linha);
    linha = <String>[];
  }

  for (var i = 0; i < texto.length; i++) {
    final c = texto[i];
    if (aspas) {
      if (c == '"' && i + 1 < texto.length && texto[i + 1] == '"') {
        campo.write('"');
        i++;
      } else if (c == '"') {
        aspas = false;
      } else {
        campo.write(c);
      }
    } else if (c == '"') {
      aspas = true;
    } else if (c == sep) {
      linha.add(campo.toString().trim());
      campo.clear();
    } else if (c == '\n') {
      fecharLinha();
    } else if (c != '\r') {
      campo.write(c);
    }
  }
  fecharLinha();
  return linhas;
}

/// Primeira linha = títulos; as outras viram {título: valor} (só as células preenchidas).
List<Map<String, String>> linhasComTitulos(List<List<String>> l) {
  if (l.length < 2) return [];
  final cab = l.first;
  return [
    for (final linha in l.skip(1))
      {
        for (var i = 0; i < cab.length && i < linha.length; i++)
          if (cab[i].trim().isNotEmpty && linha[i].trim().isNotEmpty) cab[i].trim(): linha[i].trim(),
      },
  ].where((m) => m.isNotEmpty).toList();
}

List<List<String>> _lerArquivo(String nome, Uint8List bytes) {
  final n = nome.toLowerCase();
  if (n.endsWith('.xlsx') || n.endsWith('.xlsm') || n.endsWith('.xls')) return lerPlanilha(nome, bytes);
  String texto;
  try {
    texto = utf8.decode(bytes);
  } on FormatException {
    texto = latin1.decode(bytes); // CSV do Excel em português (Windows-1252)
  }
  return lerCsvComercial(texto);
}

/// Colunas que o banco aproveita na importação (função _com_importar, guia 97), já no formato da chave
/// que o banco usa (veja [chaveColunaComercial]). Manter igual à função SQL: o teste
/// test/comercial_importar_test.dart confere a lista com a migration.
const colunasImportacaoComercial = <String>{
  // identificação: importar de novo atualiza em vez de duplicar
  'task id', 'id', 'codigo',
  // título (e o nome, se não houver empresa nem contato)
  'task name', 'titulo', 'oportunidade', 'negocio', 'nome',
  // etapa
  'status', 'etapa', 'fase',
  // próxima tarefa
  'due date', 'prazo', 'proximo passo em', 'data da tarefa', 'proximo passo', 'next step',
  // responsável
  'assignees', 'responsavel', 'vendedor',
  // observações e anotação
  'task content', 'descricao', 'observacoes', 'observacao', 'comments', 'comentarios',
  // valores
  'valor', 'valor total', 'preco', 'value', 'amount', 'valor mensal', 'mensal', 'mensalidade', 'mrr',
  // previsão de fechamento
  'previsao', 'previsao de fechamento', 'close date',
  // contato e cliente
  'empresa', 'cliente', 'razao social', 'contato', 'pessoa', 'nome do contato', 'telefone', 'whatsapp', 'celular', 'fone',
  'e mail', 'email', 'cidade', 'uf', 'cnpj', 'cpf', 'documento',
  // origem
  'origem', 'canal', 'fonte', 'tags',
  // datas (criada e fechada)
  'date created', 'criado em', 'data', 'date closed', 'date done', 'fechado em', 'date updated',
  // perda
  'motivo', 'motivo da perda',
  // guardadas junto da oportunidade
  'list name', 'folder name', 'priority', 'task link',
};

/// A chave da coluna como o banco calcula: minúsculas, sem acento, sem o "(currency)" e afins do fim e
/// com o que não é letra ou número virando espaço. Ex.: "E-mail" vira "e mail"; "Valor (currency)", "valor".
String chaveColunaComercial(String coluna) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñµ';
  const para = 'aaaaaeeeeiiiiooooouuuucnu';
  final b = StringBuffer();
  for (final ch in coluna.toLowerCase().split('')) {
    final i = de.indexOf(ch);
    b.write(i < 0 ? ch : para[i]);
  }
  return b
      .toString()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '')
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .trim();
}

/// A coluna entra no funil (aparece em verde no diálogo).
bool colunaComercialReconhecida(String coluna) => colunasImportacaoComercial.contains(chaveColunaComercial(coluna));

class _DialogoImportar extends StatefulWidget {
  const _DialogoImportar();

  @override
  State<_DialogoImportar> createState() => _DialogoImportarState();
}

class _DialogoImportarState extends State<_DialogoImportar> {
  String? _arquivo;
  List<Map<String, String>> _linhas = [];
  List<String> _colunas = [];
  bool _ocupado = false;
  String? _erro;
  Map<String, dynamic>? _resultado;

  Future<void> _escolher() async {
    final a = await escolherArquivo(aceitar: '.csv,.txt,.xlsx,.xlsm');
    if (a == null) return;
    try {
      final l = _lerArquivo(a.nome, a.bytes);
      setState(() {
        _arquivo = a.nome;
        _colunas = l.isEmpty ? [] : l.first.where((c) => c.trim().isNotEmpty).toList();
        _linhas = linhasComTitulos(l);
        _resultado = null;
        _erro = _linhas.isEmpty ? 'A planilha precisa de uma linha de títulos e pelo menos uma linha de dados.' : null;
      });
    } catch (e) {
      setState(() => _erro = e is FormatException ? e.message : mensagemDeErro(e));
    }
  }

  Future<void> _importar() async {
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    final total = <String, dynamic>{'criadas': 0, 'atualizadas': 0, 'ignoradas': 0, 'erros': <dynamic>[]};
    try {
      for (var i = 0; i < _linhas.length; i += 500) {
        final lote = _linhas.sublist(i, i + 500 > _linhas.length ? _linhas.length : i + 500);
        final r = await acaoComercial({'acao': 'importar', 'linhas': lote});
        for (final k in ['criadas', 'atualizadas', 'ignoradas']) {
          total[k] = (total[k] as int) + (num.tryParse('${r[k] ?? 0}') ?? 0).toInt();
        }
        for (final e in (r['erros'] as List? ?? const [])) {
          final m = Map<String, dynamic>.from(e as Map);
          (total['erros'] as List).add({'linha': (num.tryParse('${m['linha']}') ?? 0) + i + 1, 'motivo': m['motivo']});
        }
      }
      if (mounted) setState(() => _resultado = total);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _resultado;
    final erros = (r?['erros'] as List?) ?? const [];
    final gravou = r != null && ((r['criadas'] as int) + (r['atualizadas'] as int)) > 0;
    return AlertDialog(
      title: const Text('Importar planilha no funil'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'Do ClickUp: Configurações › Importar/Exportar › Exportar, escolha a lista de vendas e baixe o CSV. '
              'Também serve qualquer planilha com títulos como Título, Etapa, Valor, Valor mensal, Empresa, Contato, '
              'WhatsApp, E-mail, Responsável, Próximo passo e Prazo.',
              style: TextStyle(color: Cores.neutro),
            ),
            const SizedBox(height: 6),
            const Text(
              'O Status vira a etapa pelo nome (complete/fechado = Ganho; perdido = Perdido; o resto entra na 1ª etapa). '
              'O Due date vira a próxima tarefa. Importar de novo o mesmo arquivo atualiza, não duplica.',
              style: TextStyle(fontSize: 12, color: Cores.neutro),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _ocupado ? null : _escolher,
              icon: const Icon(Icons.upload_file),
              label: Text(_arquivo ?? 'Escolher o arquivo (.csv ou .xlsx)'),
            ),
            if (_linhas.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('${_linhas.length} linhas. Colunas aproveitadas:', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in _colunas)
                  Chip(
                    label: Text(c, style: const TextStyle(fontSize: 12)),
                    backgroundColor: colunaComercialReconhecida(c) ? Cores.sucesso.withValues(alpha: .12) : null,
                    visualDensity: VisualDensity.compact,
                  ),
              ]),
              const SizedBox(height: 4),
              const Text('As colunas em verde entram no funil; as outras ficam de fora.', style: TextStyle(fontSize: 12, color: Cores.neutro)),
            ],
            if (_ocupado) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator(minHeight: 2)),
            if (r != null) ...[
              const SizedBox(height: 12),
              Text('Pronto: ${r['criadas']} novas, ${r['atualizadas']} atualizadas, ${r['ignoradas']} ignoradas.',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Cores.sucesso)),
              for (final e in erros.take(8)) Text('Linha ${(e as Map)['linha']}: ${e['motivo']}', style: const TextStyle(color: Cores.erro, fontSize: 12)),
              if (erros.length > 8) Text('... e mais ${erros.length - 8}.', style: const TextStyle(color: Cores.erro, fontSize: 12)),
            ],
            if (_erro != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_erro!, style: const TextStyle(color: Cores.erro))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _ocupado ? null : () => Navigator.of(context).pop(gravou), child: Text(r == null ? 'Voltar' : 'Fechar')),
        if (r == null)
          FilledButton(
            onPressed: _ocupado || _linhas.isEmpty ? null : _importar,
            child: Text(_linhas.isEmpty ? 'Importar' : 'Importar ${_linhas.length} linhas'),
          ),
      ],
    );
  }
}
