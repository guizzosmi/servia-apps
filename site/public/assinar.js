// ServPilot · cadastro com teste grátis (função "assinar" da plataforma).
(function () {
  const S = window.ServPilot;
  const $ = (id) => document.getElementById(id);
  const form = $('form');
  const erro = $('erro');

  // Cupom vindo no link: /assinar?cupom=AMIGO20
  const cupomUrl = new URLSearchParams(location.search).get('cupom');
  if (cupomUrl) $('cupom').value = cupomUrl.toUpperCase();

  // Preços do lado (mesmos da página de preços).
  S.rpc('precos_publicos').then((d) => {
    const p = d && d.planos && d.planos[0];
    if (!p) return;
    document.querySelectorAll('[data-v]').forEach((el) => {
      const v = p[el.dataset.v];
      if (v === undefined) return;
      el.textContent = el.dataset.v.startsWith('valor') ? S.moeda(v) : String(v);
    });
  }).catch(() => {});

  // Máscara simples do CNPJ/CPF.
  $('documento').addEventListener('input', (e) => {
    const n = e.target.value.replace(/\D/g, '').slice(0, 14);
    e.target.value = n.length <= 11
      ? n.replace(/(\d{3})(\d)/, '$1.$2').replace(/(\d{3})(\d)/, '$1.$2').replace(/(\d{3})(\d{1,2})$/, '$1-$2')
      : n.replace(/^(\d{2})(\d)/, '$1.$2').replace(/^(\d{2})\.(\d{3})(\d)/, '$1.$2.$3').replace(/\.(\d{3})(\d)/, '.$1/$2').replace(/(\d{4})(\d)/, '$1-$2');
  });

  async function conferirCupom() {
    const msg = $('cupomMsg');
    const codigo = $('cupom').value.trim().toUpperCase();
    msg.className = '';
    msg.textContent = '';
    if (!codigo) return true;
    try {
      const r = await S.rpc('cupom_conferir', { p_codigo: codigo });
      msg.className = r && r.valido ? 'cupom-ok' : 'cupom-erro';
      msg.textContent = r && r.valido ? `✓ ${r.resumo}` : (r && r.mensagem) || 'Cupom não encontrado.';
      return !!(r && r.valido);
    } catch (e) {
      msg.className = 'cupom-erro';
      msg.textContent = e.message;
      return false;
    }
  }
  $('conferirCupom').addEventListener('click', conferirCupom);

  function mostrarErro(texto) {
    erro.textContent = texto;
    erro.classList.add('ver');
    erro.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    erro.classList.remove('ver');
    const v = (id) => $(id).value.trim();
    if (!form.checkValidity()) {
      form.reportValidity();
      return;
    }
    if ($('senha').value !== $('senha2').value) return mostrarErro('As duas senhas não são iguais.');
    if (!$('aceite').checked) return mostrarErro('Para criar a conta, aceite os termos de uso e a política de privacidade.');
    if (v('cupom') && !(await conferirCupom())) return mostrarErro('Confira o cupom ou deixe o campo vazio.');

    const botao = $('enviar');
    botao.disabled = true;
    botao.textContent = 'Criando a sua conta...';
    try {
      const r = await S.funcao('assinar', {
        empresa: { razao_social: v('razao'), nome_fantasia: v('fantasia'), documento: v('documento'), cidade: v('cidade'), uf: v('uf') },
        dono: { nome: v('nome'), email: v('email'), telefone: v('whatsapp'), senha: $('senha').value },
        cupom: v('cupom'),
        aceite: true,
        site: $('site').value,
      });
      $('okTeste').textContent = r.teste_ate ? r.teste_ate.split('-').reverse().join('/') : '';
      $('okCodigo').textContent = r.codigo || '';
      $('okPainel').href = r.painel || S.PAINEL;
      form.style.display = 'none';
      $('sucesso').classList.add('ver');
      window.scrollTo({ top: 0, behavior: 'smooth' });
    } catch (err) {
      mostrarErro(err.message);
    } finally {
      botao.disabled = false;
      botao.textContent = 'Criar conta e começar o teste';
    }
  });
})();
