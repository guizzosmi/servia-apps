import 'package:flutter_test/flutter_test.dart';
import 'package:servia_app/core/regras_encerrar.dart';

/// Guia 111: quando a opção "Encerrar a OS também" liga e o que ela diz.
void main() {
  test('outra visita na agenda bloqueia (com o dia)', () {
    expect(bloqueioDoEncerramento(const []), null);
    expect(bloqueioDoEncerramento(const [
      {'data': '2026-11-10'}
    ]), 'Esta OS tem outra visita na agenda (dia 10/11): encerre a OS depois dela.');
  });

  test('ligada por padrão só sem outra visita em aberto', () {
    expect(encerrarPorPadrao(bloqueado: false, naFila: 0), true);
    expect(encerrarPorPadrao(bloqueado: false, naFila: 1), false);
    expect(encerrarPorPadrao(bloqueado: true, naFila: 0), false);
  });

  test('o que acontece', () {
    expect(textoDoEncerramento(naFila: 0), contains('"A cobrar"'));
    expect(textoDoEncerramento(naFila: 0), isNot(contains('fila')));
    expect(textoDoEncerramento(naFila: 2), endsWith('A visita que ainda estava na fila é cancelada.'));
  });
}
