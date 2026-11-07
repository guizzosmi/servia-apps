// ServPilot · Kit PMOC grátis: valida o formulário, registra o lead (Analytics/Pixel) e libera os downloads.
(function () {
  const ZAP = '5545999575500';
  const form = document.getElementById('kit-form');
  if (!form) return;
  const pronto = document.getElementById('kit-pronto');
  const erro = document.getElementById('kit-erro');
  form.addEventListener('submit', (ev) => {
    ev.preventDefault();
    const d = Object.fromEntries(new FormData(form).entries());
    const zapOk = (d.whatsapp || '').replace(/\D/g, '').length >= 10;
    if (!d.nome || !d.cidade || !zapOk || !d.equipe) { erro.hidden = false; return; }
    erro.hidden = true;
    if (window.ServPilotRastreio) window.ServPilotRastreio.evento('kit', { equipe: d.equipe });
    const msg = `Olá! Baixei o Kit PMOC do site. Sou ${d.nome}, de ${d.cidade}. Equipe em campo: ${d.equipe}. Meu WhatsApp: ${d.whatsapp}.`;
    document.getElementById('kit-zap-link').href = `https://wa.me/${ZAP}?text=${encodeURIComponent(msg)}`;
    form.hidden = true;
    pronto.hidden = false;
    pronto.scrollIntoView({ behavior: 'smooth', block: 'center' });
  });
})();
