import 'dart:convert';
import 'dart:js_interop';

import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

/// Consentimento do OAuth do Supabase (guia 91): o Claude (ou outro app) pede acesso,
/// o Supabase manda o usuário para /oauth/consent?authorization_id=... e esta tela
/// mostra quem pede e aprova ou recusa.
///   GET  /auth/v1/oauth/authorizations/{id}            detalhes (ou redirect_url, se já aprovou antes)
///   POST /auth/v1/oauth/authorizations/{id}/consent    { action: approve | deny } -> { redirect_url }
Future<Map<String, dynamic>> _chamar(String metodo, String caminho, [Map<String, dynamic>? corpo]) async {
  final token = Supabase.instance.client.auth.currentSession?.accessToken;
  if (token == null) throw Exception('Entre de novo no painel.');
  final headers = web.Headers()
    ..append('Authorization', 'Bearer $token')
    ..append('apikey', Config.supabaseChavePublica)
    ..append('Content-Type', 'application/json');
  final r = await web.window
      .fetch('${Config.supabaseUrl}/auth/v1$caminho'.toJS,
          web.RequestInit(method: metodo, headers: headers, body: corpo == null ? null : jsonEncode(corpo).toJS))
      .toDart;
  final texto = (await r.text().toDart).toDart;
  final dados = texto.isEmpty ? <String, dynamic>{} : jsonDecode(texto);
  final mapa = dados is Map ? Map<String, dynamic>.from(dados) : <String, dynamic>{};
  if (!r.ok) {
    throw Exception('${mapa['msg'] ?? mapa['message'] ?? mapa['error_description'] ?? 'O pedido de acesso não vale mais (${r.status}).'}');
  }
  return mapa;
}

/// Detalhes do pedido de acesso. Com 'redirect_url' (sem 'authorization_id'), o usuário já tinha aprovado.
Future<Map<String, dynamic>> detalhesDoPedido(String id) => _chamar('GET', '/oauth/authorizations/${Uri.encodeComponent(id)}');

/// Aprova (true) ou recusa (false). Devolve o endereço de volta para o app que pediu.
Future<String> responderPedido(String id, {required bool aprovar}) async {
  final r = await _chamar('POST', '/oauth/authorizations/${Uri.encodeComponent(id)}/consent',
      {'action': aprovar ? 'approve' : 'deny'});
  final url = r['redirect_url'] ?? r['redirect_to'];
  if (url is! String || url.isEmpty) throw Exception('O Supabase não devolveu o endereço de volta.');
  return url;
}

/// Sai do painel e volta para o app que pediu o acesso (o Claude).
void voltarPara(String url) => web.window.location.assign(url);
