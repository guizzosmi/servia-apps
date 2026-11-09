import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/arquivo_web.dart';

/// Gestão de Equipamentos (guia 98): a segunda aplicação do hub. Locação, obra
/// própria, uso próprio, manutenção e custo por equipamento.

/// A aplicação "equipamentos" está no token deste usuário? (o admin liga na conta;
/// o banco confere de novo em todas as funções e tabelas).
bool temEquipamentos() {
  final token = Supabase.instance.client.auth.currentSession?.accessToken;
  if (token == null) return false;
  try {
    final partes = token.split('.');
    if (partes.length != 3) return false;
    final dados = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1])))) as Map<String, dynamic>;
    final apps = (dados['app_metadata'] as Map?)?['aplicacoes'];
    return apps is List && apps.contains('equipamentos');
  } catch (_) {
    return false;
  }
}

/// Chama uma função eqp_* do banco (sempre com um objeto "p").
Future<Map<String, dynamic>> eqp(String funcao, [Map<String, dynamic> p = const {}]) async {
  final r = await Supabase.instance.client.rpc(funcao, params: {'p': p});
  return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
}

/// Listas para os formulários: locais da empresa, obras, setores, tipos.
Future<Map<String, dynamic>> eqpApoio() async {
  final r = await Supabase.instance.client.rpc('eqp_apoio');
  return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
}

/// Lista de mapas de um campo do resultado.
List<Map<String, dynamic>> listaDe(Object? v) =>
    v is List ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];

const statusEquipamento = {
  'disponivel': 'Disponível',
  'reservado': 'Reservado',
  'em_transito': 'Em trânsito',
  'em_uso': 'Em uso',
  'retornado': 'Aguardando conferência',
  'em_manutencao': 'Em manutenção',
  'bloqueado': 'Bloqueado',
  'baixado': 'Baixado',
};

Color corDoStatus(String? s) => switch (s) {
      'disponivel' => Cores.sucesso,
      'reservado' => Cores.info,
      'em_transito' || 'em_uso' => Cores.andamento,
      'retornado' => Cores.alerta,
      'em_manutencao' => Cores.coral500,
      'bloqueado' || 'baixado' => Cores.erro,
      _ => Cores.neutro,
    };

const destinos = {'locacao': 'Locação', 'obra_propria': 'Obra própria', 'uso_proprio': 'Uso próprio'};

const situacoesLocacao = {
  'rascunho': 'Rascunho',
  'confirmada': 'Confirmada',
  'em_andamento': 'Em andamento',
  'encerrada': 'Encerrada',
  'cancelada': 'Cancelada',
};

const situacoesItem = {
  'previsto': 'Previsto',
  'reservado': 'Reservado',
  'em_campo': 'Em campo',
  'devolvido': 'Devolvido',
  'cancelado': 'Cancelado',
};

/// Situação da reserva ou uso (eqp_alocacoes).
const situacoesAlocacao = {'reservada': 'Reservada', 'ativa': 'Em andamento', 'encerrada': 'Encerrada', 'cancelada': 'Cancelada'};

/// Situação da obra (eqp_obras).
const situacoesObra = {'planejada': 'Planejada', 'ativa': 'Em andamento', 'encerrada': 'Encerrada'};

/// Com quem está a reserva, sem repetir "Obra" depois de "Obra própria" (o banco manda "Obra OB-00001 · nome").
String quemSemObra(Map<String, dynamic> a) {
  final com = '${a['com'] ?? ''}';
  return a['destino'] == 'obra_propria' ? com.replaceFirst(RegExp('^Obra '), '') : com;
}

const periodicidades = {'dia': 'por dia', 'semana': 'por semana', 'mes': 'por mês'};

const condicoes = {'ok': 'Em ordem', 'avariado': 'Avariado', 'incompleto': 'Faltando peça', 'sujo': 'Sujo'};

const naturezasManutencao = {
  'corretiva': 'Corretiva',
  'preventiva': 'Preventiva',
  'preparacao': 'Preparação para a próxima saída',
  'reparo': 'Reparo',
  'retrofit': 'Retrofit',
};

const naturezasCusto = {
  'preventiva': 'Preventiva',
  'corretiva': 'Corretiva',
  'retrofit': 'Retrofit',
  'reparo': 'Reparo',
  'preparacao': 'Preparação',
  'frete': 'Frete',
  'outros': 'Outros',
};

const categoriasLocal = {
  'deposito': 'Depósito',
  'oficina': 'Oficina',
  'filial': 'Filial',
  'obra': 'Obra',
  'setor': 'Setor',
  'outro': 'Outro',
};

/// Eventos que o painel oferece em cada status (o banco confere de novo).
const eventosPorStatus = {
  // Saída direto do disponível: o banco usa a reserva (a próxima ou a escolhida), como na retirada da locação.
  'disponivel': ['reservar', 'saida', 'iniciar_manutencao', 'mover', 'bloquear', 'baixar'],
  'reservado': ['saida', 'cancelar_reserva', 'iniciar_manutencao', 'mover', 'bloquear'],
  'em_transito': ['chegada', 'retorno'],
  'em_uso': ['transferencia', 'recolher', 'retorno', 'iniciar_manutencao'],
  'retornado': ['liberar', 'iniciar_manutencao', 'mover', 'bloquear', 'baixar'],
  'em_manutencao': ['liberar', 'mover', 'bloquear', 'baixar'],
  'bloqueado': ['desbloquear', 'iniciar_manutencao', 'mover', 'baixar'],
};

const nomesEvento = {
  'entrada': 'Entrada',
  'reservar': 'Separar para a reserva',
  'cancelar_reserva': 'Cancelar separação',
  'saida': 'Saída',
  'chegada': 'Chegada',
  'transferencia': 'Transferência',
  'recolher': 'Recolher (volta em trânsito)',
  'retorno': 'Retorno ao depósito',
  'liberar': 'Liberar (conferido, pronto)',
  'iniciar_manutencao': 'Iniciar manutenção',
  'mover': 'Mover entre locais da empresa',
  'bloquear': 'Bloquear',
  'desbloquear': 'Desbloquear',
  'baixar': 'Dar baixa',
  'corrigir': 'Correção',
};

/// Sobe uma foto (JPEG) para o bucket "fotos", na pasta da conta e da empresa. Devolve o caminho.
Future<String> enviarFoto(ArquivoEscolhido arquivo) async {
  final s = Sessao.atual!;
  final agora = DateTime.now();
  final caminho = '${s.contaId}/${s.empresaId}/${agora.year}/${agora.month.toString().padLeft(2, '0')}/${novoUuid()}.jpg';
  await Supabase.instance.client.storage
      .from('fotos')
      .uploadBinary(caminho, arquivo.bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
  return caminho;
}

/// Link temporário (10 minutos) de uma foto.
Future<String> linkDaFoto(String caminho) => Supabase.instance.client.storage.from('fotos').createSignedUrl(caminho, 600);

/// AAAA-MM-DD de uma data local.
String iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
