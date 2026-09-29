// Testes rápidos das regras de formatação (não precisam de internet nem de login).
// Rode com: flutter test
import 'package:flutter_test/flutter_test.dart';
import 'package:servia_painel/cadastros/catalogo.dart';
import 'package:servia_painel/cadastros/definicoes.dart';
import 'package:servia_painel/cadastros/servico.dart';

void main() {
  test('documento e telefone formatados', () {
    expect(formatarValor('12345678000199', TipoCampo.documento), '12.345.678/0001-99');
    expect(formatarValor('12345678901', TipoCampo.documento), '123.456.789-01');
    expect(formatarValor('54999998888', TipoCampo.telefone), '(54) 99999-8888');
  });

  test('data, número, sim/não e opções', () {
    expect(formatarValor('2026-11-05', TipoCampo.data), '05/11/2026');
    expect(formatarValor(12.5, TipoCampo.numero), '12,5');
    expect(formatarValor(true, TipoCampo.simNao), 'Sim');
    expect(formatarValor('pj', TipoCampo.opcoes, const [Opcao('pj', 'Pessoa jurídica')]),
        'Pessoa jurídica');
  });

  test('valor por caminho com pontos', () {
    final r = {'clientes': {'nome': 'Friella'}};
    expect(valorPorCaminho(r, 'clientes.nome'), 'Friella');
    expect(valorPorCaminho(r, 'locais.nome'), isNull);
  });

  test('busca sem caracteres especiais', () {
    expect(CadastroServico.limparBusca('ab,c(d)*"e'), 'ab c d   e');
  });

  test('catálogo consistente', () {
    for (final def in catalogo) {
      // toda coluna pai de um filho precisa ser campo do filho
      for (final f in def.filhos) {
        final filho = cadastroPorChave(f.cadastro);
        expect(filho, isNotNull, reason: '${def.chave} -> ${f.cadastro}');
        expect(filho!.campos.any((c) => c.nome == f.colunaPai), isTrue,
            reason: '${f.cadastro}.${f.colunaPai}');
      }
      // todo campo dependente aponta para um campo que existe
      for (final c in def.campos) {
        final pai = c.lookup?.campoPai;
        if (pai != null) {
          expect(def.campos.any((x) => x.nome == pai), isTrue, reason: '${def.chave}.${c.nome}');
        }
      }
    }
  });
}
