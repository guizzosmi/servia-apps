// ServPilot · cadastro com teste grátis (função "assinar" da plataforma).
(function () {
  const S = window.ServPilot;
  const $ = (id) => document.getElementById(id);
  const form = $('form');
  const erro = $('erro');

  // Cupom vindo no link: /assinar?cupom=AMIGO20
  const cupomUrl = new URLSearchParams(location.search).get('cupom');
  if (cupomUrl) $('cupom').value = cupomUrl.toUpperCase();

  // Guia 89: código de indicação (do link desta página ou guardado pelo site em outra página).
  let indicacao = (new URLSearchParams(location.search).get('indicacao') || '').trim().toUpperCase();
  if (!indicacao) {
    try {
      const g = JSON.parse(localStorage.getItem('sp_indicacao') || 'null');
      if (g && g.codigo && g.ate > Date.now()) indicacao = String(g.codigo);
    } catch (_) { /* sem armazenamento */ }
  }
  if (indicacao) {
    S.rpc('indicacao_conferir', { p_codigo: indicacao }).then((r) => {
      if (r && r.valido) $('indicacaoMsg').hidden = false;
      else indicacao = '';
    }).catch(() => {});
  }

  // Plano: vem da página de preços (/assinar?plano=autonomo) ou fica o Equipe.
  const planos = {
    autonomo: { nome: 'Autônomo', valor_mensal: 99.99, usuarios_incluidos: 1, valor_usuario_extra: 99.99 },
    servpilot: { nome: 'Equipe', valor_mensal: 199, usuarios_incluidos: 2, valor_usuario_extra: 69 },
  };
  const radios = () => Array.from(document.querySelectorAll('input[name="plano"]'));
  const planoEscolhido = () => (radios().find((r) => r.checked) || {}).value || 'servpilot';
  const planoUrl = new URLSearchParams(location.search).get('plano');
  radios().forEach((r) => { if (r.value === planoUrl) r.checked = true; r.addEventListener('change', resumo); });

  function resumo() {
    document.querySelectorAll('[data-p]').forEach((el) => {
      const p = planos[el.dataset.p];
      if (p && p[el.dataset.c] !== undefined) el.textContent = S.moeda(p[el.dataset.c]);
    });
    const p = planos[planoEscolhido()];
    if (!p) return;
    $('resumoNome').textContent = p.nome;
    $('resumoValor').textContent = S.moeda(p.valor_mensal) + '/mês';
    $('resumoUsuarios').textContent = p.usuarios_incluidos === 1 ? '1 usuário' : `${p.usuarios_incluidos} usuários`;
    $('resumoExtra').innerHTML = p.usuarios_incluidos === 1 ? ' (contratou alguém? troque para o Equipe pelo painel)'
      : `, e <b>${S.moeda(p.valor_usuario_extra)}</b> por usuário a mais`;
  }
  resumo();

  // Preços atualizados (mesmos da página de preços).
  S.rpc('precos_publicos').then((d) => {
    ((d && d.planos) || []).forEach((p) => {
      if (planos[p.codigo]) Object.assign(planos[p.codigo], p, { valor_mensal: Number(p.valor_mensal), valor_usuario_extra: Number(p.valor_usuario_extra) });
    });
    resumo();
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
        plano: planoEscolhido(),
        cupom: v('cupom'),
        indicacao,
        aceite: true,
        site: $('site').value,
      });
      $('okTeste').textContent = r.teste_ate ? r.teste_ate.split('-').reverse().join('/') : '';
      $('okCodigo').textContent = r.codigo || '';
      $('okPainel').href = r.painel || S.PAINEL;
      form.style.display = 'none';
      $('sucesso').classList.add('ver');
      if (window.ServPilotRastreio) window.ServPilotRastreio.evento('cadastro');   // conversão (guia 48)
      try { localStorage.removeItem('sp_indicacao'); } catch (_) { /* sem armazenamento */ }
      window.scrollTo({ top: 0, behavior: 'smooth' });
    } catch (err) {
      mostrarErro(err.message);
    } finally {
      botao.disabled = false;
      botao.textContent = 'Criar conta e começar o teste';
    }
  });
})();
