import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'status.dart';

/// Planos de preventiva e PMOC: rótulos (mesmos códigos do banco) e as
/// chamadas das regras (plano_acao, plano_previsao, modelos_atividade_padrao).

const tiposPlano = {
  'preventiva': Rotulo('Preventiva', Cores.info),
  'pmoc': Rotulo('PMOC', Cores.indigo700),
};

const situacoesPlano = {
  'rascunho': Rotulo('Rascunho', Cores.neutro),
  'ativo': Rotulo('Ativo', Cores.sucesso),
  'encerrado': Rotulo('Encerrado', Cores.alerta),
};

const periodicidades = {
  'semanal': 'Semanal',
  'quinzenal': 'Quinzenal (15 dias)',
  'mensal': 'Mensal',
  'bimestral': 'Bimestral',
  'trimestral': 'Trimestral',
  'semestral': 'Semestral',
  'anual': 'Anual',
};

const controlesPrazo = {
  'periodo': 'Por período: cada aparelho uma vez dentro de cada período',
  'ultima_execucao': 'A partir da última execução de cada aparelho (em breve; por ora conta por período)',
};

Future<Map<String, dynamic>> _rpc(String funcao, Map<String, dynamic> p) async {
  final r = await Supabase.instance.client.rpc(funcao, params: {'p': p});
  return r is Map<String, dynamic> ? r : <String, dynamic>{};
}

/// Regras do plano (criar, alterar, equipamentos, atividades, ativar...).
Future<Map<String, dynamic>> acaoPlano(Map<String, dynamic> p) => _rpc('plano_acao', p);

/// Próximos períodos de cada atividade do plano.
Future<List<Map<String, dynamic>>> previsaoPlano(String planoId, {int dias = 60}) async {
  final r = await _rpc('plano_previsao', {'plano_id': planoId, 'dias': dias});
  return ((r['datas'] as List?) ?? const []).cast<Map<String, dynamic>>();
}

/// Carrega as atividades padrão do PMOC (Portaria 3.523/98) para um tipo de
/// equipamento. Devolve quantas criou (0 = já existiam).
Future<int> carregarPadraoPmoc(String tipoEquipamentoId) async {
  final r = await _rpc('modelos_atividade_padrao', {'tipo_equipamento_id': tipoEquipamentoId});
  return (r['criadas'] as num?)?.toInt() ?? 0;
}

// ---------------------------------------------------------------------
// OS do período, checklist e prazos (guia 25)
// ---------------------------------------------------------------------

/// Como os aparelhos são agrupados nas OS do plano.
const lotesPeriodo = {
  'mensal': 'Mensal (um lote por mês)',
  'quinzenal': 'Quinzenal (1 a 15 e 16 ao fim do mês)',
};

/// Nível do aparelho pelo vencimento dele (cards da Início).
const niveisAparelho = {
  'vencido': Rotulo('Vencidos', Cores.erro),
  'a_vencer': Rotulo('Vencem em breve', Color(0xFFE07B00)),
  'em_dia': Rotulo('Em dia', Cores.sucesso),
  'feitos_mes': Rotulo('Feitos no mês', Cores.info),
};

/// Nível de cada lote (cards da Início e andamento do plano).
const niveisPrazo = {
  'vencido': Rotulo('Com aparelho vencido', Cores.erro),
  'atencao': Rotulo('Vencendo', Color(0xFFE07B00)),
  'ok': Rotulo('Em dia', Cores.sucesso),
  'pronto': Rotulo('Tudo feito', Cores.info),
  'encerrado': Rotulo('Encerrado', Cores.neutro),
};

/// Situação de um item do checklist (plano_execucoes).
const statusExecucao = {
  'pendente': Rotulo('Pendente', Cores.neutro),
  'feito': Rotulo('Feito', Cores.sucesso),
  'nao_conforme': Rotulo('Não conforme', Cores.alerta),
  'nao_se_aplica': Rotulo('Não se aplica', Cores.info),
  'nao_feito': Rotulo('Não feito', Cores.erro),
  'cancelada': Rotulo('Saiu do plano', Cores.neutro),
};

/// Situação dos prazos. Sem plano: gera o que faltar e devolve as OS de
/// período abertas (cards da Início). Com plano: todas as OS do plano.
Future<Map<String, dynamic>> situacaoPreventivas({String? planoId}) =>
    _rpc('preventivas_situacao', {if (planoId != null) 'plano_id': planoId});

/// "Gerar agora": cria as OS dos períodos que começam dentro da antecedência.
Future<Map<String, dynamic>> gerarPreventivas({String? planoId}) =>
    _rpc('preventivas_gerar', {if (planoId != null) 'plano_id': planoId});

/// Vencimentos (gestor): { acao: vencimento, unidade_id, data } ou
/// { acao: redistribuir, plano_id } (1º ciclo dos aparelhos sem ciclo feito).
Future<Map<String, dynamic>> acaoUnidade(Map<String, dynamic> p) => _rpc('plano_unidade_acao', p);

/// O gestor marca itens do checklist pelo painel.
/// itens = [{execucao_id, resultado (null = desmarcar), observacao}]
Future<Map<String, dynamic>> marcarPreventiva(String osId, List<Map<String, dynamic>> itens) =>
    _rpc('preventiva_marcar', {'os_id': osId, 'itens': itens});
