import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_opcoes.dart';

/// Notificações no celular (Firebase Cloud Messaging).
///
/// A plataforma avisa quando a parte é publicada, quando entra um encaixe
/// e quando um serviço sai da parte. Com o app fechado ou em segundo
/// plano, o Android mostra o aviso na barra; com o app aberto, aparece
/// embaixo da tela. Nos dois casos o app sincroniza para trazer a mudança.
class Notificacoes {
  Notificacoes._();

  /// Mostra o aviso com o app aberto (ligado no MaterialApp).
  static final mensageiro = GlobalKey<ScaffoldMessengerState>();

  static bool _ligado = false;
  static StreamSubscription<String>? _renovacao;

  /// Firebase configurado e iniciado neste aparelho.
  static bool get ligado => _ligado;

  /// Na abertura do app. Sem configuração (ou no iPhone, por enquanto),
  /// o app segue sem notificações.
  static Future<void> iniciar({required VoidCallback aoChegar}) async {
    final opcoes = opcoesFirebase;
    if (opcoes == null || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Firebase.initializeApp(options: opcoes);
      _ligado = true;
    } catch (e) {
      debugPrint('Firebase: $e');
      return;
    }
    FirebaseMessaging.onMessage.listen((m) {
      aoChegar();
      final n = m.notification;
      if (n == null) return;
      mensageiro.currentState?.showSnackBar(SnackBar(
        content: Text([n.title, n.body].whereType<String>().join('\n')),
        duration: const Duration(seconds: 6),
      ));
    });
    // Tocou no aviso da barra: o app abre e sincroniza.
    FirebaseMessaging.onMessageOpenedApp.listen((_) => aoChegar());
  }

  /// Pede a permissão (Android 13 ou mais novo) e devolve o endereço deste
  /// aparelho no Firebase. Sem internet na primeira vez, devolve null.
  static Future<String?> token() async {
    if (!_ligado) return null;
    try {
      await FirebaseMessaging.instance.requestPermission();
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('Token das notificações: $e');
      return null;
    }
  }

  /// Grava na plataforma o endereço deste aparelho (null = parar de avisar).
  static Future<void> enviarToken(String dispositivoId, String? token) async {
    await Supabase.instance.client.functions.invoke('dispositivo-acao', body: {
      'acao': 'token',
      'dispositivo_id': dispositivoId,
      'fcm_token': token,
    });
  }

  /// O Firebase troca o endereço de vez em quando: avisa a plataforma.
  static void aoRenovar(void Function(String) aoMudar) {
    _renovacao?.cancel();
    _renovacao = _ligado ? FirebaseMessaging.instance.onTokenRefresh.listen(aoMudar) : null;
  }

  /// Ao sair do app: o endereço antigo deixa de valer (outra pessoa que
  /// entrar neste celular não recebe os avisos de quem saiu).
  static Future<void> desligar() async {
    await _renovacao?.cancel();
    _renovacao = null;
    if (!_ligado) return;
    try {
      await FirebaseMessaging.instance.deleteToken().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Sem internet: o endereço velho será recusado pelo Firebase depois.
    }
  }
}
