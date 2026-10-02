// ServPilot · página inicial

// Número do WhatsApp comercial: só números, com 55 e DDD (ex.: '5545999998888').
// Vazio: os botões levam para a seção de contato.
const WHATSAPP = '5545999575500';
const MENSAGEM = 'Olá! Vi o site do ServPilot e quero conhecer o sistema para a minha empresa.';

(function () {
  document.documentElement.classList.remove('sem-js');

  // Botões do WhatsApp
  if (WHATSAPP) {
    const link = `https://wa.me/${WHATSAPP}?text=${encodeURIComponent(MENSAGEM)}`;
    document.querySelectorAll('[data-whatsapp]').forEach((a) => {
      a.href = link;
      a.target = '_blank';
      a.rel = 'noopener';
    });
  }

  // Topo: fica branco depois que a página rola
  const topo = document.getElementById('topo');
  const aoRolar = () => topo.classList.toggle('rolou', window.scrollY > 40);
  aoRolar();
  window.addEventListener('scroll', aoRolar, { passive: true });

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

  // Ano no rodapé
  const ano = document.getElementById('ano');
  if (ano) ano.textContent = String(new Date().getFullYear());
})();
