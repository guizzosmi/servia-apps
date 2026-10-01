import 'dart:async';

import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Nome e cor de cada status (mesmos códigos do banco).
class Rotulo {
  const Rotulo(this.texto, this.cor);
  final String texto;
  final Color cor;
}

const statusOs = {
  'aberta': Rotulo('Aberta', Cores.neutro),
  'agendada': Rotulo('Agendada', Cores.info),
  'em_andamento': Rotulo('Em andamento', Cores.andamento),
  'aguardando_aprovacao': Rotulo('Aguardando aprovação', Cores.alerta),
  'aguardando_peca': Rotulo('Aguardando peça', Cores.alerta),
  'aguardando_cliente': Rotulo('Aguardando cliente', Cores.alerta),
  'concluida': Rotulo('Concluída', Cores.sucesso),
  'cancelada': Rotulo('Cancelada', Cores.erro),
};

const statusAgendamento = {
  'pendente': Rotulo('Na fila', Cores.neutro),
  'programado': Rotulo('Programado', Cores.info),
  'em_andamento': Rotulo('Em andamento', Cores.andamento),
  'suspenso': Rotulo('Suspenso', Cores.alerta),
  'concluido': Rotulo('Concluído', Cores.sucesso),
  'cancelado': Rotulo('Cancelado', Cores.erro),
};

const statusItem = {
  'programado': Rotulo('Programado', Cores.info),
  'em_deslocamento': Rotulo('A caminho', Cores.andamento),
  'em_atendimento': Rotulo('Em atendimento', Cores.andamento),
  'pausado': Rotulo('Pausado', Cores.alerta),
  'concluido': Rotulo('Concluído', Cores.sucesso),
  'nao_realizado': Rotulo('Não realizado', Cores.erro),
  'removido': Rotulo('Removido', Cores.neutro),
};

const statusParte = {
  'rascunho': Rotulo('Rascunho', Cores.neutro),
  'publicada': Rotulo('Publicada', Cores.info),
  'em_andamento': Rotulo('Em andamento', Cores.andamento),
  'encerrada': Rotulo('Encerrada', Cores.sucesso),
};

const statusOrcamento = {
  'rascunho': Rotulo('Rascunho', Cores.neutro),
  'enviado': Rotulo('Aguardando o cliente', Cores.info),
  'vencido': Rotulo('Vencido', Cores.alerta),
  'aprovado': Rotulo('Aprovado', Cores.sucesso),
  'reprovado': Rotulo('Reprovado', Cores.erro),
  'expirado': Rotulo('Vencido', Cores.alerta),
  'substituido': Rotulo('Substituído', Cores.neutro),
  'cancelado': Rotulo('Cancelado', Cores.neutro),
};

/// Status para mostrar: o enviado que passou da validade aparece "Vencido".
String? statusOrcamentoVisivel(Map<String, dynamic> o) {
  final status = o['status'] as String?;
  final validade = DateTime.tryParse('${o['validade_ate'] ?? ''}');
  if (status == 'enviado' && validade != null) {
    final hoje = DateTime.now();
    if (validade.isBefore(DateTime(hoje.year, hoje.month, hoje.day))) return 'vencido';
  }
  return status;
}

const tiposItemOrcamento = {
  'produto': 'Peça / produto',
  'servico': 'Serviço',
  'mao_de_obra': 'Mão de obra',
  'deslocamento': 'Deslocamento',
};

const formasAceite = {
  'telefone': 'Por telefone',
  'presencial': 'Pessoalmente',
  'link': 'Pelo link',
  'contrato': 'Pelo contrato',
};

const prioridades = {
  'urgente': Rotulo('Urgente', Cores.erro),
  'alta': Rotulo('Alta', Cores.alerta),
  'media': Rotulo('Média', Cores.info),
  'baixa': Rotulo('Baixa', Cores.neutro),
};

/// Ordem para classificar a fila (urgente primeiro).
int pesoPrioridade(String? p) => switch (p) {
      'urgente' => 0,
      'alta' => 1,
      'media' => 2,
      _ => 3,
    };

const tiposOs = {
  'corretiva': 'Corretiva',
  'preventiva': 'Preventiva',
  'instalacao': 'Instalação',
  'outro': 'Outro',
};

const tiposAgendamento = {
  'visita_tecnica': 'Visita técnica',
  'analise': 'Análise',
  'reparo': 'Reparo',
  'retorno': 'Retorno',
  'preventiva': 'Preventiva',
  'retirada': 'Retirada',
  'entrega': 'Entrega',
  'outro': 'Outro',
};

const motivosNaoRealizado = {
  'cliente_ausente': 'Cliente ausente',
  'falta_peca': 'Falta de peça',
  'aguardando_orcamento': 'Aguardando orçamento',
  'tempo': 'Faltou tempo',
  'clima': 'Clima',
  'outro': 'Outro',
};

const motivosSuspensao = {
  'falta_peca': 'Falta de peça',
  'aguardando_orcamento': 'Aguardando orçamento',
  'outro': 'Outro',
};

String _dd(int n) => n.toString().padLeft(2, '0');

/// '2026-11-05' -> '05/11/2026'
String dataBr(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  if (d == null) return '';
  return '${_dd(d.day)}/${_dd(d.month)}/${d.year}';
}

/// Data e hora local: '05/11/2026 14:30'
String dataHoraBr(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
  if (d == null) return '';
  return '${_dd(d.day)}/${_dd(d.month)}/${d.year} ${_dd(d.hour)}:${_dd(d.minute)}';
}

/// '08:00:00' -> '08:00'
String horaCurta(Object? v) {
  final s = '${v ?? ''}';
  return s.length >= 5 ? s.substring(0, 5) : s;
}

/// Janela de horário: '08:00–12:00', 'a partir de 08:00' ou ''.
String janela(Object? inicio, Object? fim) {
  final i = horaCurta(inicio), f = horaCurta(fim);
  if (i.isNotEmpty && f.isNotEmpty) return '$i–$f';
  if (i.isNotEmpty) return 'a partir de $i';
  if (f.isNotEmpty) return 'até $f';
  return '';
}

/// Data no formato do banco (aaaa-mm-dd).
String dataIso(DateTime d) => '${d.year}-${_dd(d.month)}-${_dd(d.day)}';

/// Chama as regras do banco (os_acao / parte_acao) e devolve a resposta.
/// Erros de regra chegam como PostgrestException com a frase em português.
Future<Map<String, dynamic>> acaoOs(Map<String, dynamic> p) => _rpc('os_acao', p);
Future<Map<String, dynamic>> acaoParte(Map<String, dynamic> p) async {
  final r = await _rpc('parte_acao', p);
  // Mudanças que a equipe precisa saber: envia os avisos para os celulares.
  if (const {'publicar', 'programar', 'encaixar', 'remover', 'mover'}.contains(p['acao'])) {
    unawaited(avisarEquipe());
  }
  return r;
}

/// Envia os avisos pendentes para os celulares (função "notificar").
/// Sem configuração ou sem internet, não atrapalha o painel: os avisos
/// ficam na fila e vão na próxima chamada.
Future<void> avisarEquipe() async {
  try {
    await Supabase.instance.client.functions.invoke('notificar');
  } catch (e) {
    debugPrint('Avisos para os celulares: $e');
  }
}
Future<Map<String, dynamic>> acaoOrcamento(Map<String, dynamic> p) => _rpc('orcamento_acao', p);
Future<Map<String, dynamic>> acaoAtendimento(Map<String, dynamic> p) => _rpc('atendimento_acao', p);

Future<Map<String, dynamic>> _rpc(String funcao, Map<String, dynamic> p) async {
  final r = await Supabase.instance.client.rpc(funcao, params: {'p': p});
  return r is Map<String, dynamic> ? r : <String, dynamic>{};
}
