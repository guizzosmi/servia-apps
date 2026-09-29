import 'package:flutter/material.dart';

/// "Motor" de cadastros: cada tela de cadastro é só uma DESCRIÇÃO
/// (CadastroDef) de tabela, colunas da lista e campos do formulário.
/// Lista, busca, paginação, formulário, validação, gravação e exclusão
/// lógica são feitos uma vez só, para todos (ideia parecida com a tabela
/// dinâmica do PO UI).

enum TipoCampo {
  texto,
  textoLongo,
  numero, // aceita vírgula; grava como número
  inteiro,
  data, // grava 'aaaa-mm-dd'
  simNao,
  opcoes, // uma escolha entre Opcao
  multiOpcoes, // várias escolhas (coluna text[])
  lookup, // escolhe um registro de outra tabela
  listaTexto, // coluna text[] digitada separando por vírgula
  email,
  telefone, // só números
  documento, // CPF/CNPJ, só números
  cor, // '#RRGGBB'
}

class Opcao {
  const Opcao(this.valor, this.rotulo);
  final String valor;
  final String rotulo;
}

/// Busca de registro em outra tabela (ex.: escolher o cliente).
class Lookup {
  const Lookup({
    required this.tabela,
    this.colunaRotulo = 'nome',
    this.colunaDetalhe,
    this.colunaAtivo = 'ativo',
    this.colunaFiltro,
    this.campoPai,
  });

  final String tabela;
  final String colunaRotulo;

  /// Segunda linha na lista de escolha (opcional).
  final String? colunaDetalhe;

  /// Se informada, só mostra registros com esta coluna = true.
  final String? colunaAtivo;

  /// Filtra a busca por outro campo do formulário:
  /// ex.: local_id só mostra locais onde cliente_id = valor do campo cliente_id.
  final String? colunaFiltro;
  final String? campoPai;
}

class CampoDef {
  const CampoDef(
    this.nome,
    this.rotulo, {
    this.tipo = TipoCampo.texto,
    this.obrigatorio = false,
    this.opcoes = const [],
    this.lookup,
    this.ajuda,
    this.padrao,
    this.metade = false,
    this.somenteLeitura = false,
    this.somenteNaEdicao = false,
    this.validar,
  });

  /// Nome da coluna no banco.
  final String nome;
  final String rotulo;
  final TipoCampo tipo;
  final bool obrigatorio;
  final List<Opcao> opcoes;
  final Lookup? lookup;
  final String? ajuda;
  final Object? padrao;

  /// Ocupa meia linha (em telas largas).
  final bool metade;

  /// Só mostra; nunca é enviado ao banco (ex.: código do QR).
  final bool somenteLeitura;

  /// Só aparece depois que o registro existe.
  final bool somenteNaEdicao;

  /// Validação extra; devolve a mensagem de erro ou null.
  final String? Function(Object? valor)? validar;
}

/// Coluna da lista. [caminho] aceita pontos para dados embutidos:
/// 'clientes.nome' lê registro['clientes']['nome'].
class ColunaDef {
  const ColunaDef(this.caminho, this.rotulo,
      {this.tipo = TipoCampo.texto, this.opcoes = const [], this.flex = 2});

  final String caminho;
  final String rotulo;
  final TipoCampo tipo;
  final List<Opcao> opcoes;
  final int flex;
}

/// Lista filha exibida dentro do formulário do pai
/// (ex.: locais dentro do cliente).
class FilhoDef {
  const FilhoDef(this.cadastro, this.colunaPai, {this.herdar = const {}});

  /// Chave do cadastro filho (CadastroDef.chave).
  final String cadastro;

  /// Coluna do filho que aponta para o pai (ex.: 'cliente_id').
  final String colunaPai;

  /// Outros valores copiados do pai para um filho novo:
  /// {'coluna_no_filho': 'coluna_no_pai'}.
  final Map<String, String> herdar;
}

typedef AntesDeSalvar = void Function(
    Map<String, dynamic> dados, Map<String, dynamic>? original);

class CadastroDef {
  const CadastroDef({
    required this.chave,
    required this.tabela,
    required this.titulo,
    required this.singular,
    required this.icone,
    required this.colunas,
    required this.campos,
    this.select = '*',
    this.colunasBusca = const ['nome'],
    this.ordem = 'nome',
    this.ordemCrescente = true,
    this.filhos = const [],
    this.noMenu = true,
    this.colunaTitulo = 'nome',
    this.podeExcluir,
    this.antesDeSalvar,
    this.aviso,
  });

  /// Usada na rota: `/c/<chave>`
  final String chave;
  final String tabela;
  final String titulo;
  final String singular;
  final IconData icone;

  /// select do PostgREST (pode trazer dados de outras tabelas).
  final String select;
  final List<String> colunasBusca;
  final String ordem;
  final bool ordemCrescente;
  final List<ColunaDef> colunas;
  final List<CampoDef> campos;
  final List<FilhoDef> filhos;
  final bool noMenu;

  /// Coluna usada como título do registro no formulário.
  final String colunaTitulo;

  /// Regra extra para esconder o botão Excluir (ex.: cliente interno).
  final bool Function(Map<String, dynamic> registro)? podeExcluir;

  /// Ajuste final dos dados antes de gravar.
  final AntesDeSalvar? antesDeSalvar;

  /// Texto de orientação exibido no topo da lista.
  final String? aviso;
}

/// Lê um valor por caminho com pontos ('clientes.nome').
Object? valorPorCaminho(Map<String, dynamic> registro, String caminho) {
  Object? atual = registro;
  for (final parte in caminho.split('.')) {
    if (atual is Map) {
      atual = atual[parte];
    } else {
      return null;
    }
  }
  return atual;
}

String _doisDigitos(int n) => n.toString().padLeft(2, '0');

/// Formata um valor do banco para exibição.
String formatarValor(Object? v, TipoCampo tipo, [List<Opcao> opcoes = const []]) {
  if (v == null) return '';
  switch (tipo) {
    case TipoCampo.simNao:
      return v == true ? 'Sim' : 'Não';
    case TipoCampo.data:
      final d = DateTime.tryParse(v.toString());
      if (d == null) return v.toString();
      return '${_doisDigitos(d.day)}/${_doisDigitos(d.month)}/${d.year}';
    case TipoCampo.numero:
      return v.toString().replaceAll('.', ',');
    case TipoCampo.opcoes:
      return opcoes
              .where((o) => o.valor == v.toString())
              .map((o) => o.rotulo)
              .firstOrNull ??
          v.toString();
    case TipoCampo.multiOpcoes:
    case TipoCampo.listaTexto:
      if (v is List) {
        return v.map((x) {
          final s = x.toString();
          return opcoes.where((o) => o.valor == s).map((o) => o.rotulo).firstOrNull ?? s;
        }).join(', ');
      }
      return v.toString();
    case TipoCampo.documento:
      final s = v.toString();
      if (s.length == 11) {
        return '${s.substring(0, 3)}.${s.substring(3, 6)}.${s.substring(6, 9)}-${s.substring(9)}';
      }
      if (s.length == 14) {
        return '${s.substring(0, 2)}.${s.substring(2, 5)}.${s.substring(5, 8)}/${s.substring(8, 12)}-${s.substring(12)}';
      }
      return s;
    case TipoCampo.telefone:
      final s = v.toString();
      if (s.length == 11) return '(${s.substring(0, 2)}) ${s.substring(2, 7)}-${s.substring(7)}';
      if (s.length == 10) return '(${s.substring(0, 2)}) ${s.substring(2, 6)}-${s.substring(6)}';
      return s;
    default:
      return v.toString();
  }
}

/// Converte '#RRGGBB' em Color (cinza se inválido).
Color corDeTexto(Object? v) {
  final s = (v ?? '').toString().replaceAll('#', '');
  final n = int.tryParse(s, radix: 16);
  if (s.length != 6 || n == null) return Colors.grey;
  return Color(0xFF000000 | n);
}
