import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Acesso ao banco (todas as funções admin_* conferem se você é o dono).
SupabaseClient get db => Supabase.instance.client;

Future<Map<String, dynamic>> rpcMapa(String nome, [Map<String, dynamic>? params]) async {
  final r = await db.rpc(nome, params: params);
  return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
}

Future<List<Map<String, dynamic>>> rpcLista(String nome, [Map<String, dynamic>? params]) async {
  final r = await db.rpc(nome, params: params);
  return r is List ? r.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];
}

/// Lista de um campo JSON.
List<Map<String, dynamic>> lista(dynamic v) =>
    v is List ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];

Map<String, dynamic> mapa(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

num numero(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}'.replaceAll(',', '.')) ?? 0;

/// R$ 1.234,56
String moeda(dynamic v) {
  final n = numero(v).toDouble();
  final neg = n < 0;
  final partes = n.abs().toStringAsFixed(2).split('.');
  final inteiro = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${neg ? '- ' : ''}R\$ $inteiro,${partes[1]}';
}

/// 2026-11-03 (ou data e hora) -> 03/11/2026
String dataBr(dynamic v, {bool hora = false}) {
  if (v == null || '$v'.isEmpty) return '';
  final d = DateTime.tryParse('$v');
  if (d == null) return '$v';
  final l = '$v'.length > 10 ? d.toLocal() : d;
  String dois(int x) => x.toString().padLeft(2, '0');
  final dia = '${dois(l.day)}/${dois(l.month)}/${l.year}';
  return hora ? '$dia ${dois(l.hour)}:${dois(l.minute)}' : dia;
}

/// 03/11/2026 -> 2026-11-03 (null se inválida)
String? dataIso(String texto) {
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(texto.trim());
  if (m == null) return null;
  final d = DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  if (d.day != int.parse(m[1]!) || d.month != int.parse(m[2]!)) return null;
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

const rotulosSituacao = {
  'teste': 'Teste grátis',
  'ativa': 'Ativa',
  'atrasada': 'Atrasada',
  'cancelada': 'Cancelada',
  'cortesia': 'Cortesia',
  'bloqueada': 'Bloqueada',
  'aberta': 'Em aberto',
  'vencida': 'Vencida',
  'paga': 'Paga',
};

Color corSituacao(String s) => switch (s) {
      'teste' => Cores.info,
      'ativa' || 'paga' => Cores.sucesso,
      'atrasada' || 'vencida' || 'bloqueada' => Cores.erro,
      'aberta' => Cores.alerta,
      'cortesia' => Cores.andamento,
      _ => Cores.neutro,
    };

const rotulosTipoFatura = {'mensalidade': 'Mensalidade', 'pacote': 'Pacote', 'avulsa': 'Avulsa'};

/// Link de pagamento do Mercado Pago (cria ou reaproveita) e copia.
Future<String> copiarLinkPagamento(String faturaId) async {
  final r = await db.functions.invoke('cobranca', body: {'acao': 'pagar', 'fatura_id': faturaId});
  final link = (r.data is Map ? r.data['link'] : null) as String?;
  if (link == null) throw Exception('O Mercado Pago não devolveu o link.');
  await Clipboard.setData(ClipboardData(text: link));
  return link;
}

void avisar(BuildContext context, String texto, {bool erro = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(texto),
    backgroundColor: erro ? Cores.erro : null,
  ));
}

void avisarErro(BuildContext context, Object e) => avisar(context, mensagemDeErro(e), erro: true);
