import 'package:flutter_test/flutter_test.dart';
import 'package:servia_app/core/filtro_aparelhos.dart';

/// Guia 108: a busca de aparelhos (filtro, ordem natural, grupos por ambiente
/// e a etiqueta lida). Dados de mentira, como os da Refrigeração Modelo.
const _ambientes = {
  'a1': {'id': 'a1', 'nome': 'Câmara fria 1', 'setor_andar': 'Térreo'},
  'a2': {'id': 'a2', 'nome': 'Sala 12', 'setor_andar': '2º andar'},
};

Map<String, dynamic>? _amb(Object? id) => _ambientes[id];

Map<String, dynamic> _ac(String codigo,
        {String? ambiente, num? capacidade, String? serie, String? marca, String? qr, String? descricao}) =>
    {
      'id': codigo,
      'codigo': codigo,
      'descricao': descricao ?? 'Split hi-wall',
      'ambiente_id': ambiente,
      'marca': marca ?? 'Springer',
      'modelo': '42AFCA12M5',
      'capacidade_valor': capacidade ?? 9000,
      'capacidade_unidade': 'btu_h',
      'numero_serie': serie,
      'qr_token': qr,
    };

List<String> _codigos(Iterable<Map> l) => [for (final e in l) '${e['codigo']}'];

void main() {
  final lista = [
    _ac('AC-10', ambiente: 'a1', capacidade: 12000, serie: 'SN778812'),
    _ac('AC-2', ambiente: 'a1', capacidade: 12000),
    _ac('AC-12', ambiente: 'a2', capacidade: 18000, marca: 'LG', qr: 'Qx7KpL92aa'),
    _ac('AC-120', ambiente: 'a2'),
    _ac('AC-1', descricao: 'Cassete da recepção'),
  ];

  test('sem acento e sem maiúscula', () {
    expect(semAcento('Câmara FRIA Recepção'), 'camara fria recepcao');
    expect(_codigos(filtrarAparelhos(lista, 'camara', _amb)), ['AC-10', 'AC-2']);
    expect(_codigos(filtrarAparelhos(lista, 'TÉRREO', _amb)), ['AC-10', 'AC-2']);
    expect(_codigos(filtrarAparelhos(lista, 'recepçao', _amb)), ['AC-1']);
  });

  test('código: AC-12 não acha o AC-120; "12" não acha a capacidade 12000', () {
    expect(_codigos(filtrarAparelhos(lista, 'AC-12', _amb)), ['AC-12']);
    expect(_codigos(filtrarAparelhos(lista, 'ac12', _amb)), ['AC-12']);
    // "12": o AC-12 e a Sala 12 (ambiente), não o 12000 nem o AC-120 fora da sala.
    expect(_codigos(filtrarAparelhos(lista, '12', _amb)), ['AC-12', 'AC-120']);
    // "1": o AC-1 e a "Câmara fria 1" (o número inteiro, não o 1 do AC-10 ou do AC-12).
    expect(_codigos(filtrarAparelhos(lista, '1', _amb)), ['AC-10', 'AC-2', 'AC-1']);
    expect(_codigos(filtrarAparelhos([lista[2], lista[3], lista[4]], '1', _amb)), ['AC-1']);
  });

  test('capacidade (12000 ou 12.000), marca, série e várias palavras', () {
    expect(_codigos(filtrarAparelhos(lista, '12000', _amb)), ['AC-10', 'AC-2']);
    expect(_codigos(filtrarAparelhos(lista, '12.000', _amb)), ['AC-10', 'AC-2']);
    expect(_codigos(filtrarAparelhos(lista, '18000 btu', _amb)), ['AC-12']);
    expect(_codigos(filtrarAparelhos(lista, 'lg', _amb)), ['AC-12']);
    expect(_codigos(filtrarAparelhos(lista, '7788', _amb)), ['AC-10']);
    expect(_codigos(filtrarAparelhos(lista, 'camara 12000 ac-2', _amb)), ['AC-2']);
    expect(filtrarAparelhos(lista, 'daikin', _amb), isEmpty);
    expect(filtrarAparelhos(lista, '  ', _amb).length, lista.length);
  });

  test('ordem natural do código', () {
    final ordem = [...lista]..sort((a, b) => compararCodigo(a['codigo'], b['codigo']));
    expect(_codigos(ordem), ['AC-1', 'AC-2', 'AC-10', 'AC-12', 'AC-120']);
    expect(compararCodigo('AC-02', 'AC-10'), lessThan(0));
    expect(compararCodigo('B-1', 'AC-9'), greaterThan(0));
  });

  test('grupos por ambiente: nome com o setor, ordem do código e os sem ambiente por último', () {
    final grupos = agruparPorAmbiente(lista, _amb);
    expect([for (final g in grupos) g.nome], ['Câmara fria 1 · Térreo', 'Sala 12 · 2º andar', '']);
    expect(_codigos(grupos.first.aparelhos), ['AC-2', 'AC-10']);
    expect(_codigos(grupos[1].aparelhos), ['AC-12', 'AC-120']);
    expect(grupos.last.ambienteId, isNull);
  });

  test('OS com outra equipe: equipe, dia e líder', () {
    expect(textoComOutraEquipe({'equipe': 'Equipe Sul', 'data': '2026-11-09', 'lider': 'Ana (teste)'}),
        'Com a Equipe Sul, dia 09/11 (líder Ana (teste))');
    expect(textoComOutraEquipe({'equipe': 'Equipe Sul', 'data': null}), 'Com a Equipe Sul');
    expect(textoComOutraEquipe({}), 'Com outra equipe');
  });

  test('etiqueta: QR, link, código e código sem sinais', () {
    expect(_codigos(aparelhosDaEtiqueta(lista, 'qx7kpl92AA')), ['AC-12']);
    expect(_codigos(aparelhosDaEtiqueta(lista, 'https://servpilot.com.br/q/Qx7KpL92aa?o=app')), ['AC-12']);
    expect(_codigos(aparelhosDaEtiqueta(lista, ' ac-10 ')), ['AC-10']);
    expect(_codigos(aparelhosDaEtiqueta(lista, 'AC10')), ['AC-10']);
    expect(aparelhosDaEtiqueta(lista, 'ZZ-999'), isEmpty);
    expect(aparelhosDaEtiqueta([...lista, {..._ac('AC-7'), 'excluido_em': '2026-11-01'}], 'AC-7'), isEmpty);
  });
}
