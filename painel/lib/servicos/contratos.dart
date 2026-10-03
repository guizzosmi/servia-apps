import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'status.dart';

/// Contratos do cliente (guia 26): rótulos (mesmos códigos do banco) e as
/// chamadas das regras (contrato_acao, contrato_situacao, contratos_avisos).

const modalidadesContrato = {
  'por_execucao': Rotulo('Por execução', Cores.info),
  'mensalidade': Rotulo('Mensalidade', Cores.indigo700),
  'franquia': Rotulo('Franquia', Cores.andamento),
};

/// O que cada modalidade quer dizer (ajuda no formulário).
const explicacaoModalidade = {
  'por_execucao': 'Cada ciclo de preventiva feito tem preço (tabela abaixo). Peças e serviços avulsos à parte.',
  'mensalidade': 'Valor fixo por mês. Os ciclos de preventiva saem "cobertos pelo contrato".',
  'franquia': 'Valor fixo com visitas e/ou horas incluídas no mês. O que passar é cobrado como excedente. '
      'Os ciclos de preventiva saem "cobertos pelo contrato".',
};

const situacoesContrato = {
  'rascunho': Rotulo('Rascunho', Cores.neutro),
  'ativo': Rotulo('Ativo', Cores.sucesso),
  'encerrado': Rotulo('Encerrado', Cores.alerta),
};

const indicesReajuste = {
  'ipca': 'IPCA',
  'igpm': 'IGP-M',
  'inpc': 'INPC',
  'fixo': 'Percentual fixo',
  'nenhum': 'Sem reajuste',
};

const alvosPreco = {
  'aparelho': 'Ciclo de cada aparelho',
  'geral': 'Ciclo de atividade geral do plano',
};

Future<Map<String, dynamic>> _rpc(String funcao, Map<String, dynamic> p) async {
  final r = await Supabase.instance.client.rpc(funcao, params: {'p': p});
  return r is Map<String, dynamic> ? r : <String, dynamic>{};
}

/// Regras do contrato (criar, alterar, preços, ativar, encerrar, reajustar...).
Future<Map<String, dynamic>> acaoContrato(Map<String, dynamic> p) => _rpc('contrato_acao', p);

/// Consumo da competência, conferência dos preços e aviso de reajuste.
Future<Map<String, dynamic>> situacaoContrato(String contratoId, {String? data}) =>
    _rpc('contrato_situacao', {'contrato_id': contratoId, if (data != null) 'data': data});

/// Avisos da Início: reajuste perto, franquia passada, OS sem preço.
Future<List<Map<String, dynamic>>> avisosContratos() async {
  final r = await _rpc('contratos_avisos', {});
  return ((r['avisos'] as List?) ?? const []).cast<Map<String, dynamic>>();
}

/// 12000 -> "12.000"
String milhar(Object? v) {
  final n = num.tryParse('${v ?? ''}');
  if (n == null) return '';
  final s = n.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Faixa de capacidade de uma linha da tabela: "até 12.000 BTU/h".
String faixaCapacidade(Object? min, Object? max) {
  final a = num.tryParse('${min ?? ''}');
  final b = num.tryParse('${max ?? ''}');
  if (a == null && b == null) return 'qualquer capacidade';
  if (a == null) return 'até ${milhar(b)} BTU/h';
  if (b == null) return 'a partir de ${milhar(a)} BTU/h';
  return '${milhar(a)} a ${milhar(b)} BTU/h';
}
