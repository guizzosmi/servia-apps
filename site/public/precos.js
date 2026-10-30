// ServPilot · página de preços: lê os preços da plataforma (os mesmos do painel e das
// faturas) e faz o simulador. Sem internet, ficam os valores escritos no HTML.
(function () {
  const S = window.ServPilot;
  let plano = {
    nome: 'ServPilot', valor_mensal: 199, usuarios_incluidos: 2, minutos_incluidos: 600, mensagens_incluidas: 500,
    valor_usuario_extra: 69, minutos_por_usuario_extra: 300, mensagens_por_usuario_extra: 250, dias_teste: 7,
  };

  function preencher(regras) {
    document.querySelectorAll('[data-v]').forEach((el) => {
      const v = plano[el.dataset.v];
      if (v === undefined || v === null) return;
      const fmt = el.dataset.fmt;
      el.textContent = fmt === 'moeda' ? S.moeda(v)
        : fmt === 'inteiro' ? String(Math.round(Number(v)))
        : fmt === 'milhar' ? S.milhar(v) : String(v);
    });
    if (regras) {
      document.querySelectorAll('[data-r]').forEach((el) => {
        if (regras[el.dataset.r] !== undefined) el.textContent = String(regras[el.dataset.r]);
      });
    }
    const ex5 = document.getElementById('ex5');
    if (ex5) ex5.textContent = S.moeda(valor(5));
    const ex4 = document.getElementById('ex4min');
    if (ex4) ex4.textContent = S.milhar(minutos(4));
  }

  const extras = (n) => Math.max(0, n - plano.usuarios_incluidos);
  const valor = (n) => Number(plano.valor_mensal) + extras(n) * Number(plano.valor_usuario_extra);
  const minutos = (n) => plano.minutos_incluidos + extras(n) * plano.minutos_por_usuario_extra;
  const mensagens = (n) => plano.mensagens_incluidas + extras(n) * plano.mensagens_por_usuario_extra;

  function pacotes(lista) {
    if (!lista || !lista.length) return;
    const icone = { minutos: '🎙️', mensagens: '💬' };
    const dica = { minutos: (q) => `Uns ${S.milhar(Math.round(q / 2))} relatos por áudio a mais.`, mensagens: () => 'Para meses de muito atendimento.' };
    const cartoes = document.getElementById('pacotes-lista');
    if (cartoes) {
      cartoes.innerHTML = '';
      lista.forEach((k) => {
        const d = document.createElement('div');
        d.className = 'pacote';
        d.innerHTML = '<div class="ic"></div><h3></h3><div class="valor"></div><p></p>';
        d.querySelector('.ic').textContent = icone[k.tipo] || '➕';
        d.querySelector('h3').textContent = k.nome;
        d.querySelector('.valor').textContent = S.moeda(k.valor, Number(k.valor) % 1 === 0);
        d.querySelector('p').textContent = (dica[k.tipo] || (() => ''))(k.quantidade);
        cartoes.appendChild(d);
      });
    }
    const tabela = document.getElementById('tabela-pacotes');
    if (tabela) {
      tabela.innerHTML = '';
      lista.forEach((k) => {
        const tr = document.createElement('tr');
        tr.innerHTML = '<td><span></span><small>pagamento único</small></td><td></td>';
        tr.querySelector('span').textContent = 'Pacote: ' + k.nome;
        tr.lastChild.textContent = S.moeda(k.valor);
        tabela.appendChild(tr);
      });
    }
  }

  // ---------------------------------------------------------------- simulador
  const range = document.getElementById('simRange');
  function simular() {
    if (!range) return;
    const n = Number(range.value);
    const ex = extras(n);
    const total = valor(n);
    document.getElementById('simUsuarios').textContent = n;
    document.getElementById('simBase').textContent = S.moeda(plano.valor_mensal);
    document.getElementById('simExtrasRot').textContent = ex
      ? `${ex} usuário${ex > 1 ? 's' : ''} a mais × ${S.moeda(plano.valor_usuario_extra)}`
      : 'Nenhum usuário a mais';
    document.getElementById('simExtras').textContent = S.moeda(ex * plano.valor_usuario_extra);
    document.getElementById('simTotal').textContent = S.moeda(total);
    document.getElementById('simPorUsuario').textContent = S.moeda(total / n);
    document.getElementById('simMinutos').textContent = S.milhar(minutos(n));
    document.getElementById('simRelatos').textContent = '≈ ' + S.milhar(Math.round(minutos(n) / 2));
    document.getElementById('simMensagens').textContent = S.milhar(mensagens(n));
  }
  if (range) {
    range.addEventListener('input', simular);
    document.getElementById('simMenos').addEventListener('click', () => { range.value = Math.max(1, Number(range.value) - 1); simular(); });
    document.getElementById('simMais').addEventListener('click', () => { range.value = Math.min(40, Number(range.value) + 1); simular(); });
  }

  preencher(null);
  simular();

  S.rpc('precos_publicos').then((d) => {
    if (d && d.planos && d.planos.length) {
      plano = Object.assign({}, plano, d.planos[0]);
      ['valor_mensal', 'valor_usuario_extra'].forEach((k) => { plano[k] = Number(plano[k]); });
    }
    preencher(d && d.regras);
    pacotes(d && d.pacotes);
    simular();
  }).catch(() => { /* fica com os valores do HTML */ });
})();
