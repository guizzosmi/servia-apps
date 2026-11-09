import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:servia_app/core/regras_reabrir.dart';

/// Token falso (só o miolo importa: a assinatura é conferida pela plataforma).
String _token(Map<String, dynamic> meta) {
  String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b64({'alg': 'HS256'})}.${b64({'sub': 'u1', 'app_metadata': meta})}.assinatura';
}

void main() {
  test('papéis do token e o gestor (o administrador vale como gestor)', () {
    expect(papeisDoToken(_token({'papeis': ['tecnico']})), ['tecnico']);
    expect(papeisDoToken(_token({})), <String>[]);
    expect(papeisDoToken('não é token'), null);
    expect(ehGestor(papeisDoToken(_token({'papeis': ['gestor']}))), true);
    expect(ehGestor(papeisDoToken(_token({'papeis': ['admin']}))), true);
    expect(ehGestor(papeisDoToken(_token({'papeis': ['tecnico']}))), false);
    expect(ehGestor(null), false);
  });

  test('quem vê o "Reabrir OS"', () {
    bool pode({Object? item = 'concluido', Object? os = 'em_andamento', Object? plano, bool gestor = false, bool lider = true}) =>
        podeReabrirServico(itemStatus: item, osStatus: os, planoPapel: plano, gestor: gestor, lider: lider);
    expect(pode(), true);
    expect(pode(os: 'concluida'), true);
    expect(pode(lider: false), false);
    expect(pode(lider: false, gestor: true), true);
    expect(pode(item: 'nao_realizado'), false);
    expect(pode(item: 'em_atendimento'), false);
    expect(pode(os: 'cancelada', gestor: true), false);
    expect(pode(plano: 'ciclo', gestor: true), false);
  });

  test('o que acontece (texto da confirmação)', () {
    expect(textoDaReabertura(osConcluida: false, equipeHoje: 'Equipe Norte'),
        'O serviço volta para o fim da parte de hoje da Equipe Norte, para refazer. O escritório vê quem reabriu e o motivo.');
    expect(textoDaReabertura(osConcluida: true),
        startsWith('A OS volta para "em andamento" e a garantia é zerada'));
    expect(textoDaReabertura(osConcluida: true), contains('fila do escritório'));
    // Guia 62: no modo simples, a fila é o "Para agendar" da Agenda.
    expect(textoDaReabertura(osConcluida: false, modoSimples: true),
        'Uma visita nova vai para "Para agendar" (Agenda), onde o escritório escolhe o dia. '
        'O escritório vê quem reabriu e o motivo.');
    expect(textoDaReabertura(osConcluida: false, equipeHoje: 'Equipe Ana', modoSimples: true), contains('Equipe Ana'));
  });
}
