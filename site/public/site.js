// ServPilot · site (início, aplicações e páginas de assunto)

// Número do WhatsApp comercial: só números, com 55 e DDD (ex.: '5545999998888').
// Vazio: os botões levam para a seção de contato.
const WHATSAPP = '5545999575500';
const MENSAGEM = 'Olá! Vi o site do ServPilot e quero conhecer o sistema para a minha empresa.';

(function () {
  document.documentElement.classList.remove('sem-js');

  // Botões do WhatsApp
  //   <a data-whatsapp>                       usa a MENSAGEM padrão acima
  //   <a data-whatsapp="Olá! Quero ...">      usa o texto do próprio botão
  if (WHATSAPP) {
    document.querySelectorAll('[data-whatsapp]').forEach((a) => {
      const texto = (a.getAttribute('data-whatsapp') || '').trim() || MENSAGEM;
      a.href = `https://wa.me/${WHATSAPP}?text=${encodeURIComponent(texto)}`;
      a.target = '_blank';
      a.rel = 'noopener';
    });
  }

  // Topo: fica branco depois que a página rola
  const topo = document.getElementById('topo');
  if (topo) {
    const aoRolar = () => topo.classList.toggle('rolou', window.scrollY > 40);
    aoRolar();
    window.addEventListener('scroll', aoRolar, { passive: true });
  }

  // Aparecer ao rolar
  const itens = document.querySelectorAll('.revelar');
  if ('IntersectionObserver' in window) {
    const obs = new IntersectionObserver((entradas) => {
      entradas.forEach((e) => {
        if (e.isIntersecting) {
          e.target.classList.add('visivel');
          obs.unobserve(e.target);
        }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    itens.forEach((el) => obs.observe(el));
  } else {
    itens.forEach((el) => el.classList.add('visivel'));
  }

  // Guia 89: link de indicação (?indicacao=SP...): guarda por 90 dias para o cadastro usar.
  try {
    const cod = (new URLSearchParams(location.search).get('indicacao') || '').trim().toUpperCase();
    if (/^[A-Z0-9-]{4,30}$/.test(cod)) {
      localStorage.setItem('sp_indicacao', JSON.stringify({ codigo: cod, ate: Date.now() + 90 * 864e5 }));
    }
  } catch (_) { /* sem armazenamento: o cadastro lê o próprio link */ }

  // Ano no rodapé
  const ano = document.getElementById('ano');
  if (ano) ano.textContent = String(new Date().getFullYear());
})();

// Origem da visita (guia 97): guarda a 1ª página e a campanha (utm_*, gclid, fbclid) e o site de onde
// veio, só nesta aba (sessionStorage, sem cookie), para o pedido de demonstração dizer de onde a pessoa veio.
(function () {
  try {
    if (sessionStorage.getItem('servpilot_origem')) return;
    const q = new URLSearchParams(location.search);
    const o = { entrada: location.pathname };
    ['utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content', 'gclid', 'fbclid'].forEach((k) => {
      const v = q.get(k);
      if (v) o[k] = v.slice(0, 200);
    });
    if (document.referrer) {
      const r = new URL(document.referrer);
      if (r.host !== location.host) o.referencia = r.host;
    }
    sessionStorage.setItem('servpilot_origem', JSON.stringify(o));
  } catch (_) { /* sem armazenamento: o pedido vai sem a origem */ }
})();
