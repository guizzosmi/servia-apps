// ServPilot · medição do site (Google Analytics 4, Google Ads, Meta e TikTok) com consentimento (LGPD).
// Nada é carregado antes de a pessoa aceitar no aviso de cookies. Os IDs abaixo são públicos
// (ficam no navegador de qualquer forma); vazio = aquela ferramenta fica desligada.
(function () {
  const IDS = {
    ga4: '',        // ex.: 'G-ABC123XYZ'   (Google Analytics > Administrador > Fluxos de dados)
    googleAds: '',  // ex.: 'AW-123456789'  (Google Ads > Metas > Conversões > Tag)
    adsCadastro: '', // rótulo da conversão "Cadastro" do Google Ads, ex.: 'AbCdEfGh123'
    metaPixel: '',  // ex.: '1234567890'   (Gerenciador de Eventos da Meta)
    tiktokPixel: '', // ex.: 'CABCDEF123456789' (TikTok Ads > Ferramentas > Eventos > Web)
  };
  const CHAVE = 'servpilot_cookies';   // 'sim' | 'nao'

  const ler = () => { try { return localStorage.getItem(CHAVE); } catch (_) { return null; } };
  const gravar = (v) => { try { localStorage.setItem(CHAVE, v); } catch (_) { /* sem armazenamento */ } };
  const algumId = IDS.ga4 || IDS.googleAds || IDS.metaPixel || IDS.tiktokPixel;

  // ---------------------------------------------------------------- carregar as ferramentas
  let ligado = false;
  function ligar() {
    if (ligado || !algumId) return;
    ligado = true;
    const tagGoogle = IDS.ga4 || IDS.googleAds;
    if (tagGoogle) {
      const s = document.createElement('script');
      s.async = true;
      s.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(tagGoogle);
      document.head.appendChild(s);
      window.dataLayer = window.dataLayer || [];
      window.gtag = function () { window.dataLayer.push(arguments); };
      window.gtag('consent', 'default', { ad_storage: 'granted', analytics_storage: 'granted',
                                          ad_user_data: 'granted', ad_personalization: 'granted' });
      window.gtag('js', new Date());
      if (IDS.ga4) window.gtag('config', IDS.ga4, { anonymize_ip: true });
      if (IDS.googleAds) window.gtag('config', IDS.googleAds);
    }
    if (IDS.metaPixel) {
      /* eslint-disable */
      !function (f, b, e, v, n, t, s) { if (f.fbq) return; n = f.fbq = function () { n.callMethod ? n.callMethod.apply(n, arguments) : n.queue.push(arguments); };
        if (!f._fbq) f._fbq = n; n.push = n; n.loaded = !0; n.version = '2.0'; n.queue = []; t = b.createElement(e); t.async = !0;
        t.src = v; s = b.getElementsByTagName(e)[0]; s.parentNode.insertBefore(t, s); }(window, document, 'script', 'https://connect.facebook.net/en_US/fbevents.js');
      /* eslint-enable */
      window.fbq('init', IDS.metaPixel);
      window.fbq('track', 'PageView');
    }
    if (IDS.tiktokPixel) {
      /* eslint-disable */
      !function (w, d, t) { w.TiktokAnalyticsObject = t; var ttq = w[t] = w[t] || [];
        ttq.methods = ['page', 'track', 'identify', 'instances', 'debug', 'on', 'off', 'once', 'ready', 'alias', 'group', 'enableCookie', 'disableCookie'];
        ttq.setAndDefer = function (t, e) { t[e] = function () { t.push([e].concat(Array.prototype.slice.call(arguments, 0))); }; };
        for (var i = 0; i < ttq.methods.length; i++) ttq.setAndDefer(ttq, ttq.methods[i]);
        ttq.instance = function (t) { for (var e = ttq._i[t] || [], n = 0; n < ttq.methods.length; n++) ttq.setAndDefer(e, ttq.methods[n]); return e; };
        ttq.load = function (e, n) { var r = 'https://analytics.tiktok.com/i18n/pixel/events.js'; ttq._i = ttq._i || {}; ttq._i[e] = []; ttq._i[e]._u = r;
          ttq._t = ttq._t || {}; ttq._t[e] = +new Date(); ttq._o = ttq._o || {}; ttq._o[e] = n || {};
          var s = d.createElement('script'); s.type = 'text/javascript'; s.async = !0; s.src = r + '?sdkid=' + e + '&lib=' + t;
          var x = d.getElementsByTagName('script')[0]; x.parentNode.insertBefore(s, x); };
        ttq.load(IDS.tiktokPixel); ttq.page(); }(window, document, 'ttq');
      /* eslint-enable */
    }
  }

  // ---------------------------------------------------------------- eventos (as conversões)
  //   ServPilotRastreio.evento('cadastro')   conta criada pelo site (a conversão principal)
  //   ServPilotRastreio.evento('whatsapp')   clicou para falar no WhatsApp
  //   ServPilotRastreio.evento('teste')      clicou em "Testar 14 dias grátis"
  function evento(nome, extra) {
    if (!ligado) return;
    const dados = Object.assign({}, extra || {});
    if (window.gtag) {
      const ga = { cadastro: 'sign_up', whatsapp: 'contact', teste: 'begin_checkout', precos: 'view_item' }[nome] || nome;
      window.gtag('event', ga, dados);
      if (nome === 'cadastro' && IDS.googleAds && IDS.adsCadastro) {
        window.gtag('event', 'conversion', { send_to: IDS.googleAds + '/' + IDS.adsCadastro });
      }
    }
    if (window.fbq) {
      const fb = { cadastro: 'StartTrial', whatsapp: 'Contact', teste: 'Lead', precos: 'ViewContent' }[nome];
      if (fb) window.fbq('track', fb, nome === 'cadastro' ? { value: 199, currency: 'BRL' } : {});
    }
    if (window.ttq && IDS.tiktokPixel) {
      const tt = { cadastro: 'CompleteRegistration', whatsapp: 'Contact', teste: 'ClickButton', precos: 'ViewContent' }[nome];
      if (tt) window.ttq.track(tt, nome === 'cadastro' ? { value: 199, currency: 'BRL', content_id: 'servpilot', content_type: 'product' } : {});
    }
  }
  window.ServPilotRastreio = { evento };

  // Cliques que contam sozinhos.
  document.addEventListener('click', (e) => {
    const a = e.target.closest && e.target.closest('a');
    if (!a) return;
    if (a.hasAttribute('data-whatsapp') || /wa\.me\//.test(a.href)) evento('whatsapp');
    else if (/\/assinar(\?|$)/.test(a.getAttribute('href') || '')) evento('teste', { origem: location.pathname });
  });

  // ---------------------------------------------------------------- aviso de cookies
  function aviso() {
    const caixa = document.createElement('div');
    caixa.className = 'cookies';
    caixa.setAttribute('role', 'dialog');
    caixa.setAttribute('aria-label', 'Aviso de cookies');
    caixa.innerHTML = '<p>Usamos cookies para medir as visitas e melhorar os anúncios do ServPilot. ' +
      'Você escolhe. <a href="/privacidade">Política de privacidade</a></p>' +
      '<div><button type="button" class="botao" data-c="nao">Só os necessários</button>' +
      '<button type="button" class="botao primario" data-c="sim">Aceitar</button></div>';
    caixa.addEventListener('click', (e) => {
      const v = e.target.getAttribute && e.target.getAttribute('data-c');
      if (!v) return;
      gravar(v);
      caixa.remove();
      if (v === 'sim') ligar();
    });
    document.body.appendChild(caixa);
  }

  const escolha = ler();
  if (escolha === 'sim') ligar();
  else if (escolha !== 'nao' && algumId) {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', aviso);
    else aviso();
  }
  // Rodapé: "Cookies" reabre a escolha.
  document.addEventListener('click', (e) => {
    if (e.target.closest && e.target.closest('[data-cookies]')) {
      e.preventDefault();
      try { localStorage.removeItem(CHAVE); } catch (_) { /* nada */ }
      location.reload();
    }
  });
})();
