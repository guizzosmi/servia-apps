import 'package:supabase_flutter/supabase_flutter.dart';

/// Módulo Comercial (guias 90 e 97): funil, oportunidades, tarefas e metas.

/// De onde veio a oportunidade.
const origensComercial = {
  'indicacao': 'Indicação',
  'whatsapp': 'WhatsApp',
  'telefone': 'Telefone',
  'site': 'Site',
  'visita': 'Visita',
  'instagram': 'Instagram',
  'anuncio': 'Anúncio',
  'outro': 'Outro',
};

/// Tipos de atividade (a nota é um registro; os outros são tarefas com data).
const tiposAtividade = {
  'tarefa': 'Tarefa',
  'ligacao': 'Ligação',
  'whatsapp': 'WhatsApp',
  'visita': 'Visita',
  'reuniao': 'Reunião',
  'email': 'E-mail',
  'nota': 'Anotação',
};

/// Tipos de tarefa (com data): todos menos a anotação (guia 97).
const tiposTarefa = {
  'ligacao': 'Ligação',
  'whatsapp': 'WhatsApp',
  'visita': 'Visita',
  'reuniao': 'Reunião',
  'email': 'E-mail',
  'tarefa': 'Tarefa',
};

/// Motivos de perda mais comuns (o campo aceita texto livre).
const motivosPerda = ['Preço', 'Fechou com concorrente', 'Sem retorno', 'Adiou a compra', 'Não era o perfil'];

/// Chama uma ação do comercial (comercial_acao) e devolve o resultado.
Future<Map<String, dynamic>> acaoComercial(Map<String, dynamic> p) async {
  final r = await Supabase.instance.client.rpc('comercial_acao', params: {'p': p});
  return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
}

/// R$ 1.234,56
String reais(Object? v) {
  final n = num.tryParse('${v ?? 0}') ?? 0;
  final partes = n.abs().toStringAsFixed(2).split('.');
  final inteiro = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${n < 0 ? '- ' : ''}R\$ $inteiro,${partes[1]}';
}

/// "R$ 1.500,00 + R$ 400,00/mês", só o que tiver valor.
String valorOportunidade(Map<String, dynamic> o) {
  final v = num.tryParse('${o['valor'] ?? 0}') ?? 0;
  final m = num.tryParse('${o['valor_mensal'] ?? 0}') ?? 0;
  return [if (v > 0) reais(v), if (m > 0) '${reais(m)}/mês'].join(' + ');
}

/// Nome que aparece no cartão: cliente, empresa do contato ou o contato.
String quemOportunidade(Map<String, dynamic> o) =>
    [o['cliente'], o['empresa_nome'], o['contato_nome']].firstWhere((x) => '${x ?? ''}'.trim().isNotEmpty, orElse: () => '') as String;

/// Link do WhatsApp para um telefone brasileiro (só números, com 55).
String? linkWhatsapp(Object? telefone) {
  final n = '${telefone ?? ''}'.replaceAll(RegExp(r'\D'), '');
  if (n.length < 10) return null;
  return 'https://wa.me/${n.startsWith('55') ? n : '55$n'}';
}

/// Lista de mapas a partir da resposta do banco (guia 97).
List<Map<String, dynamic>> listaDeMapas(Object? v) =>
    v is List ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];
