// Guia 87: no navegador (painel e admin), pede o token do Cloudflare Turnstile à função
// window.servpilotCaptcha (web/captcha.js). Sem a função ou sem resposta, segue sem token:
// enquanto o CAPTCHA estiver desligado no Supabase, o login funciona igual.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

Future<String?> obterCaptcha() async {
  try {
    if (!globalContext.has('servpilotCaptcha')) return null;
    final promessa = globalContext.callMethod<JSPromise<JSString?>>('servpilotCaptcha'.toJS);
    // Se a pessoa não confirmar em 2 minutos, segue sem token (o Supabase recusa e a tela mostra o erro).
    final token = await promessa.toDart.timeout(const Duration(minutes: 2), onTimeout: () => null);
    return token?.toDart;
  } catch (_) {
    return null;
  }
}
