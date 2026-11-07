import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Página do site que mostra o desafio e devolve o token pelo canal ServPilotCaptcha.
const _urlCaptcha = 'https://servpilot.com.br/captcha?app=1';

/// Guia 87: o desafio do CAPTCHA (Cloudflare Turnstile) antes do login.
/// Devolve o token; '' se a pessoa cancelou; null se não deu para carregar
/// (aí o login segue sem token e o servidor decide).
Future<String?> pedirCaptcha(BuildContext context) => showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CaptchaDialogo(),
    );

class _CaptchaDialogo extends StatefulWidget {
  const _CaptchaDialogo();

  @override
  State<_CaptchaDialogo> createState() => _CaptchaDialogoState();
}

class _CaptchaDialogoState extends State<_CaptchaDialogo> {
  late final WebViewController _web;
  Timer? _limite;
  bool _fechado = false;

  void _fechar(String? valor) {
    if (_fechado || !mounted) return;
    _fechado = true;
    _limite?.cancel();
    Navigator.of(context).pop(valor);
  }

  void _mensagem(JavaScriptMessage m) {
    try {
      final r = jsonDecode(m.message) as Map<String, dynamic>;
      _fechar(r['ok'] == true && (r['token'] ?? '') != '' ? '${r['token']}' : null);
    } catch (_) {
      _fechar(null);
    }
  }

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel('ServPilotCaptcha', onMessageReceived: _mensagem)
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? false) _fechar(null);
        },
        onNavigationRequest: (r) {
          if (!r.isMainFrame) return NavigationDecision.navigate;
          final host = Uri.tryParse(r.url)?.host ?? '';
          return host == 'servpilot.com.br' ? NavigationDecision.navigate : NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse(_urlCaptcha));
    // Sem resposta em 90 segundos, segue sem token.
    _limite = Timer(const Duration(seconds: 90), () => _fechar(null));
  }

  @override
  void dispose() {
    _limite?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Confirmando que é você'),
        contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
        content: SizedBox(width: 320, height: 150, child: WebViewWidget(controller: _web)),
        actions: [TextButton(onPressed: () => _fechar(''), child: const Text('Cancelar'))],
      );
}
