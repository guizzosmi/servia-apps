// ServPilot · CAPTCHA do login (guia 87): Cloudflare Turnstile, modo Managed.
// O Flutter chama window.servpilotCaptcha() antes de entrar ou de pedir a senha nova e
// recebe um token de uso único. Na maioria das vezes ninguém vê nada; se o Turnstile
// desconfiar, a caixinha aparece no meio da tela até a pessoa confirmar.
(function () {
  'use strict';
  var CHAVE_DO_SITE = '0x4AAAAAAF1Ea531r6N1nZdR';
  var widget = null;

  // Fundo escuro com a caixinha no meio; só aparece quando o Turnstile pede um clique.
  var fundo = null;
  function caixa() {
    var c = document.getElementById('sp-captcha');
    if (c) return c;
    fundo = document.createElement('div');
    fundo.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:rgba(14,21,48,.45);display:none;' +
      'align-items:center;justify-content:center;font-family:system-ui,sans-serif';
    var cartao = document.createElement('div');
    cartao.setAttribute('role', 'dialog');
    cartao.setAttribute('aria-label', 'Confirme que você não é um robô');
    cartao.style.cssText = 'background:#fff;border-radius:14px;box-shadow:0 20px 60px rgba(5,10,30,.35);padding:16px;' +
      'display:flex;flex-direction:column;gap:10px;align-items:center;color:#121A2B;font-size:15px';
    var texto = document.createElement('div');
    texto.textContent = 'Para entrar, confirme que você não é um robô.';
    c = document.createElement('div');
    c.id = 'sp-captcha';
    cartao.appendChild(texto);
    cartao.appendChild(c);
    fundo.appendChild(cartao);
    document.body.appendChild(fundo);
    return c;
  }

  function esperarScript(limiteMs) {
    return new Promise(function (ok, erro) {
      var inicio = Date.now();
      (function olhar() {
        if (window.turnstile && window.turnstile.render) return ok();
        if (Date.now() - inicio > limiteMs) return erro(new Error('turnstile_indisponivel'));
        setTimeout(olhar, 100);
      })();
    });
  }

  window.servpilotCaptcha = function () {
    return esperarScript(8000).then(function () {
      return new Promise(function (ok, erro) {
        var c = caixa();
        if (widget !== null) { try { window.turnstile.remove(widget); } catch (e) { /* já saiu */ } widget = null; }
        var fim = function (fn, v) { fundo.style.display = 'none'; fn(v); };
        widget = window.turnstile.render(c, {
          sitekey: CHAVE_DO_SITE,
          appearance: 'interaction-only',
          language: 'pt-br',
          'before-interactive-callback': function () { fundo.style.display = 'flex'; },
          callback: function (token) { fim(ok, token); },
          'error-callback': function () { fim(erro, new Error('captcha_erro')); return true; },
          'expired-callback': function () { fim(erro, new Error('captcha_expirou')); },
          'timeout-callback': function () { fim(erro, new Error('captcha_tempo')); },
        });
      });
    });
  };
})();
