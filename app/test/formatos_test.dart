import 'package:flutter_test/flutter_test.dart';
import 'package:servia_app/core/banco_local.dart';
import 'package:servia_app/core/cofre.dart';
import 'package:servia_app/core/formatos.dart';

void main() {
  test('datas no formato do Brasil', () {
    expect(dataBr('2026-11-05'), '05/11/2026');
    expect(somarDias('2026-12-31', 1), '2027-01-01');
    expect(somarDias('2026-03-01', -1), '2026-02-28');
    expect(dataComDia('2026-11-05'), 'quinta, 05/11');
  });

  test('janela de horário', () {
    expect(janela('08:00:00', '12:00:00'), '08:00–12:00');
    expect(janela('08:00:00', null), 'a partir de 08:00');
    expect(janela(null, null), '');
  });

  test('operação no formato que a plataforma espera', () {
    const op = Operacao(opId: 'x', tipo: 'item_status', em: '2026-11-05T10:00:00Z', dados: {'status': 'em_deslocamento'});
    expect(op.paraEnvio(), {
      'op_id': 'x',
      'tipo': 'item_status',
      'em': '2026-11-05T10:00:00Z',
      'dados': {'status': 'em_deslocamento'},
    });
  });

  test('conta local vai e volta do cofre (JSON)', () {
    const c = ContaLocal(
      usuarioId: 'u', email: 'e@x', contaId: 'c', empresaId: 'e', colaboradorId: 'k', dispositivoId: 'd');
    final volta = ContaLocal.deJson('{"usuario_id":"u","email":"e@x","conta_id":"c","empresa_id":"e",'
        '"colaborador_id":"k","dispositivo_id":"d"}');
    expect(volta?.toJson(), c.toJson());
    expect(ContaLocal.deJson('lixo'), isNull);
  });
}
