// Importar planilha no funil (guia 97): o painel pinta de verde as colunas que o banco aproveita.
// Rode com: flutter test
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:servia_painel/widgets/comercial_importar.dart';

/// O corpo da função _com_importar na migration mais nova que a define (null fora da pasta do projeto).
String? _funcaoDoBanco() {
  final pasta = Directory('../../servia-plataforma/supabase/migrations');
  if (!pasta.existsSync()) return null;
  final arquivos = pasta.listSync().whereType<File>().where((f) => f.path.endsWith('.sql')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  String? corpo;
  for (final f in arquivos) {
    final texto = f.readAsStringSync();
    final ini = texto.indexOf('function public._com_importar(');
    if (ini < 0) continue;
    final fim = texto.indexOf(r'end $$;', ini);
    corpo = texto.substring(ini, fim < 0 ? texto.length : fim);
  }
  return corpo;
}

void main() {
  test('chave da coluna igual à do banco', () {
    expect(chaveColunaComercial('Valor (currency)'), 'valor');
    expect(chaveColunaComercial('E-mail'), 'e mail');
    expect(chaveColunaComercial('Próximo passo'), 'proximo passo');
    expect(chaveColunaComercial('  Razão  Social '), 'razao social');
    expect(chaveColunaComercial('WhatsApp (phone) '), 'whatsapp');
  });

  test('colunas do ClickUp e da planilha', () {
    for (final c in ['Task ID', 'Task Name', 'Status', 'Due Date', 'Assignees', 'Date Closed', 'Priority', 'List Name',
        'Motivo da perda', 'MRR', 'Canal', 'Vendedor', 'Nome', 'Valor mensal (currency)', 'CNPJ']) {
      expect(colunaComercialReconhecida(c), isTrue, reason: c);
    }
    for (final c in ['Time Estimated', 'Start Date', 'Space Name']) {
      expect(colunaComercialReconhecida(c), isFalse, reason: c);
    }
  });

  final corpo = _funcaoDoBanco();
  test('a lista do painel tem todas as colunas que a função do banco usa', () {
    final chaves = {for (final m in RegExp(r"\br (?:->>|\?) '([^']+)'").allMatches(corpo!)) m.group(1)!};
    expect(chaves, isNotEmpty);
    expect(chaves.difference(colunasImportacaoComercial), isEmpty);
  }, skip: corpo == null ? 'Fora da pasta do projeto: sem a migration para comparar.' : false);
}
