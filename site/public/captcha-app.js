// ServPilot · desafio do CAPTCHA para o app do técnico (guia 87).
// O app abre /captcha numa tela web; o Turnstile gera o token e ele volta para o app pelo
// canal ServPilotCaptcha (JavaScriptChannel do webview_flutter).
(function () {
  'use strict';
  var CHAVE_DO_SITE = '0x4AAAAAAF1Ea531r6N1nZdR';

  function enviar(obj) {
    var texto = JSON.stringify(obj);
    if (window.ServPilotCaptcha && typeof window.ServPilotCaptcha.postMessage === 'function') {
      window.ServPilotCaptcha.postMessage(texto);
    }
  }
  function estado(t) {
    var e = document.getElementById('estado');
    if (e) e.textContent = t;
  }

  window.spCaptchaPronto = function () {
    window.turnstile.render('#widget', {
      sitekey: CHAVE_DO_SITE,
      language: 'pt-br',
      callback: function (token) { estado('Pronto.'); enviar({ ok: true, token: token }); },
      'error-callback': function (codigo) { estado('Não deu para confirmar agora.'); enviar({ ok: false, erro: String(codigo || '') }); return true; },
      'expired-callback': function () { estado('Expirou. Toque de novo.'); },
      'timeout-callback': function () { estado('Demorou demais. Tente de novo.'); enviar({ ok: false, erro: 'tempo' }); },
    });
  };
})();
