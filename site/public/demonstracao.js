// ServPilot · formulário "Quero uma demonstração" (função "contato", guia 90).
(function () {
  const S = window.ServPilot;
  const $ = (id) => document.getElementById(id);
  const form = $('form');
  const erro = $('erro');

  // Campanha e 1ª página da visita (site.js guarda; guia 97). Vazio se não houver.
  function origemDaVisita() {
    try {
      return JSON.parse(sessionStorage.getItem('servpilot_origem') || '{}');
    } catch (_) {
      return {};
    }
  }

  function mostrarErro(texto) {
    erro.textContent = texto;
    erro.classList.add('ver');
    erro.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    erro.classList.remove('ver');
    const v = (id) => $(id).value.trim();
    if (!v('nome')) return mostrarErro('Diga o seu nome.');
    if (v('whatsapp').replace(/\D/g, '').length < 10) return mostrarErro('Confira o WhatsApp com DDD.');
    const botao = $('enviar');
    botao.disabled = true;
    botao.textContent = 'Enviando...';
    try {
      await S.funcao('contato', {
        nome: v('nome'), telefone: v('whatsapp'), empresa: v('empresa'), cidade: v('cidade'), uf: v('uf').toUpperCase(),
        tecnicos: v('tecnicos'), email: v('email'), mensagem: v('mensagem'),
        pagina: document.referrer ? new URL(document.referrer).pathname : '', site: $('site').value,
        utm: origemDaVisita(),
      });
      form.style.display = 'none';
      $('sucesso').classList.add('ver');
      if (window.ServPilotRastreio) window.ServPilotRastreio.evento('demonstracao');   // lead (guia 90)
      window.scrollTo({ top: 0, behavior: 'smooth' });
    } catch (err) {
      mostrarErro(err.message);
    } finally {
      botao.disabled = false;
      botao.textContent = 'Quero uma demonstração';
    }
  });
})();
