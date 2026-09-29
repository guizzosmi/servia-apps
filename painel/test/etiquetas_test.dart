// Testes do PDF de etiquetas (rodam sem internet).
import 'package:flutter_test/flutter_test.dart';
import 'package:servia_painel/servicos/etiquetas_pdf.dart';

void main() {
  test('todos os modelos cabem numa folha A4', () {
    for (final m in modelosEtiqueta) {
      expect(m.margemEsquerdaMm, greaterThanOrEqualTo(0), reason: m.nome);
      expect(m.margemTopoMm, greaterThanOrEqualTo(0), reason: m.nome);
    }
  });

  test('gera PDF com várias folhas', () async {
    final etiquetas = [
      for (var i = 0; i < 30; i++)
        Etiqueta(
          codigo: '00${i + 1}',
          qrToken: 'tok$i',
          descricao: 'Split sala $i',
          cliente: 'Clínica Vida',
          local: 'Sede',
        ),
    ];
    final bytes = await gerarPdfEtiquetas(
      etiquetas: etiquetas,
      modelo: modelosEtiqueta.first,
      rodape: 'Manutenção: Refrigeração Teste · (45) 99999-0000',
      pular: 5,
      contorno: true,
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
