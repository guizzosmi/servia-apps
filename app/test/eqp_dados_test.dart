import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:servia_app/core/eqp_dados.dart';
import 'package:servia_app/core/posicao.dart';

/// Token falso (só o miolo importa: a assinatura é conferida pela plataforma).
String _token(Map<String, dynamic> meta) {
  String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b64({'alg': 'HS256'})}.${b64({'sub': 'u1', 'app_metadata': meta})}.assinatura';
}

void main() {
  test('aplicações do token: com a lista, token antigo e token ilegível', () {
    expect(EqpDados.aplicacoesDoToken(_token({'aplicacoes': ['refrigeracao', 'equipamentos']})),
        ['refrigeracao', 'equipamentos']);
    expect(EqpDados.aplicacoesDoToken(_token({'empresa_id': 'e1'})), ['refrigeracao']);
    expect(EqpDados.aplicacoesDoToken(_token({'nome': 'Gestão', 'aplicacoes': ['equipamentos']})), ['equipamentos']);
    expect(EqpDados.aplicacoesDoToken('não é token'), isNull);
  });

  test('eventos do app pelo status (como a plataforma)', () {
    expect(eventosPermitidos({'status': 'disponivel'}), ['mover', 'iniciar_manutencao']);
    expect(eventosPermitidos({'status': 'reservado'}, temReserva: true), ['saida', 'mover', 'iniciar_manutencao']);
    expect(eventosPermitidos({'status': 'em_transito'}, temAtiva: true), ['chegada', 'recolher', 'retorno']);
    expect(eventosPermitidos({'status': 'em_uso'}, temAtiva: true),
        ['transferencia', 'recolher', 'retorno', 'iniciar_manutencao']);
    expect(eventosPermitidos({'status': 'em_manutencao'}, temAtiva: true), ['recolher', 'retorno']);
    expect(eventosPermitidos({'status': 'retornado'}), ['mover', 'iniciar_manutencao']);
    expect(eventosPermitidos({'status': 'baixado'}), isEmpty);
  });

  test('leitura com a unidade do medidor', () {
    expect(leituraEqp(1262.0, 'horas'), '1262 h');
    expect(leituraEqp(12.5, 'km'), '12,5 km');
    expect(leituraEqp(null, 'horas'), '—');
  });

  test('parâmetros: padrões da plataforma quando não vierem', () {
    const vazio = EqpParametros({});
    expect(vazio.fotosMinimas, 1);
    expect(vazio.gpsObrigatorio, isTrue);
    expect(vazio.aceiteObrigatorio, isTrue);
    expect(vazio.fotosObrigatoriasOs, isTrue);
    const desligados = EqpParametros({'gps_entrega': false, 'fotos_minimas_entrega': 2, 'fotos_obrigatorias_os': false});
    expect(desligados.gpsObrigatorio, isFalse);
    expect(desligados.fotosMinimas, 2);
    expect(desligados.fotosObrigatoriasOs, isFalse);
  });

  test('ponto do GPS no formato da plataforma (6 casas, precisão em metros, hora UTC)', () {
    final p = Posicao(latitude: -24.9555123456, longitude: -53.4553011, precisaoM: 8.44, em: DateTime.utc(2026, 11, 8, 15, 30));
    expect(p.paraEnvio(), {
      'latitude': -24.955512,
      'longitude': -53.455301,
      'precisao_m': 8.4,
      'em': '2026-11-08T15:30:00.000Z',
    });
    expect(p.precisaoTexto, '± 8 m');
  });
}
