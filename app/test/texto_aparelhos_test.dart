import 'package:flutter_test/flutter_test.dart';
import 'package:servia_app/core/filtro_aparelhos.dart';

void main() {
  final ambientes = {
    'a1': {'nome': 'Câmara fria 2', 'setor_andar': 'Expedição'},
    'a2': {'nome': 'Recepção'},
  };
  Map? amb(Object? id) => ambientes[id];

  test('sem aparelho: vazio (a linha some da mensagem)', () {
    expect(textoDosAparelhos([], amb), '');
  });

  test('um aparelho: código, descrição e ambiente numa linha', () {
    expect(
      textoDosAparelhos([
        {'codigo': 'AC-03', 'descricao': 'Split TCL 12.000 BTU/h', 'ambiente_id': 'a1'},
      ], amb),
      'Aparelho: AC-03 · Split TCL 12.000 BTU/h · Câmara fria 2 · Expedição',
    );
  });

  test('até 3: um por linha, em ordem de código', () {
    final t = textoDosAparelhos([
      {'codigo': 'AC-10', 'marca': 'Elgin'},
      {'codigo': 'AC-2', 'marca': 'Elgin', 'ambiente_id': 'a2'},
    ], amb);
    expect(t, 'Aparelhos:\n- AC-2 · Elgin · Recepção\n- AC-10 · Elgin');
  });

  test('mais de 3 (ex.: OS do PMOC): a linha some', () {
    expect(textoDosAparelhos([for (var n = 1; n <= 4; n++) {'codigo': 'AC-$n'}], amb), '');
  });
}
