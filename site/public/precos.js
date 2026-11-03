// ServPilot · página de preços: lê os preços da plataforma (os mesmos do painel e das
// faturas) e faz o simulador. Sem internet, ficam os valores escritos no HTML.
//   data-v="campo"  -> plano Equipe (código servpilot)
//   data-a="campo"  -> plano Autônomo (código autonomo)
//   data-fmt: moeda | inteiro | milhar | reais (parte inteira) | centavos (",99"; some se for ",00")
(function () {
  const S = window.ServPilot;
  const planos = {
    servpilot: {
      codigo: 'servpilot', nome: 'Equipe', valor_mensal: 199, usuarios_incluidos: 2, minutos_incluidos: 600, mensagens_incluidas: 500,
      valor_usuario_extra: 69, minutos_por_usuario_extra: 300, mensagens_por_usuario_extra: 250, dias_teste: 7,
    },
    autonomo: {
      codigo: 'autonomo', nome: 'Autônomo', valor_mensal: 99.99, usuarios_incluidos: 1, minutos_incluidos: 300, mensagens_incluidas: 250,
      valor_usuario_extra: 99.99, minutos_por_usuario_extra: 300, mensagens_por_usuario_extra: 250, dias_teste: 7,
    },
  };
  const equipe = () => planos.servpilot;

  function formatar(v, fmt) {
    const n = Number(v);
    if (fmt === 'moeda') return S.moeda(n);
    if (fmt === 'inteiro') return String(Math.round(n));
    if (fmt === 'milhar') return S.milhar(n);
    if (fmt === 'reais') return String(Math.floor(n + 1e-9));
    if (fmt === 'centavos') {
      const c = Math.round((n - Math.floor(n + 1e-9)) * 100);
      return c ? ',' + String(c).padStart(2, '0') : '';
    }
    return String(v);
  }

  function preencher(regras) {
    Object.values(planos).forEach((pl) => { pl.minutos_relatos = Math.round(pl.minutos_incluidos / 2); });
    [['v', planos.servpilot], ['a', planos.autonomo]].forEach(([attr, pl]) => {
      document.querySelectorAll(`[data-${attr}]`).forEach((el) => {
        const v = pl[el.dataset[attr]];
        if (v === undefined || v === null) return;
        el.textContent = formatar(v, el.dataset.fmt);
      });
    });
    if (regras) {
      document.querySelectorAll('[data-r]').forEach((el) => {
        if (regras[el.dataset.r] !== undefined) el.textContent = String(regras[el.dataset.r]);
      });
    }
    const ex5 = document.getElementById('ex5');
    if (ex5) ex5.textContent = S.moeda(valor(equipe(), 5));
    const ex4 = document.getElementById('ex4min');
    if (ex4) ex4.textContent = S.milhar(minutos(equipe(), 4));
  }

  const extras = (pl, n) => Math.max(0, n - pl.usuarios_incluidos);
  const valor = (pl, n) => Number(pl.valor_mensal) + extras(pl, n) * Number(pl.valor_usuario_extra);
  const minutos = (pl, n) => pl.minutos_incluidos + extras(pl, n) * pl.minutos_por_usuario_extra;
  const mensagens = (pl, n) => pl.mensagens_incluidas + extras(pl, n) * pl.mensagens_por_usuario_extra;
  // O plano mais em conta para n usuários (empate: o de mais usuários incluídos).
  const indicado = (n) => Object.values(planos).reduce((melhor, pl) => {
    const a = valor(pl, n), b = valor(melhor, n);
    return a < b - 0.001 || (Math.abs(a - b) < 0.001 && pl.usuarios_incluidos > melhor.usuarios_incluidos) ? pl : melhor;
  });

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
    const pl = indicado(n);
    const ex = extras(pl, n);
    const total = valor(pl, n);
    document.getElementById('simUsuarios').textContent = n;
    document.getElementById('simPlano').textContent = pl.nome;
    const ir = document.getElementById('simAssinar');
    if (ir) ir.href = '/assinar?plano=' + pl.codigo;
    document.getElementById('simBaseRot').textContent =
      `Plano ${pl.nome} (${pl.usuarios_incluidos} usuário${pl.usuarios_incluidos > 1 ? 's' : ''} incluído${pl.usuarios_incluidos > 1 ? 's' : ''})`;
    document.getElementById('simBase').textContent = S.moeda(pl.valor_mensal);
    document.getElementById('simExtrasRot').textContent = ex
      ? `${ex} usuário${ex > 1 ? 's' : ''} a mais × ${S.moeda(pl.valor_usuario_extra)}`
      : 'Nenhum usuário a mais';
    document.getElementById('simExtras').textContent = S.moeda(ex * pl.valor_usuario_extra);
    document.getElementById('simTotal').textContent = S.moeda(total);
    document.getElementById('simPorUsuario').textContent = S.moeda(total / n);
    document.getElementById('simMinutos').textContent = S.milhar(minutos(pl, n));
    document.getElementById('simRelatos').textContent = '≈ ' + S.milhar(Math.round(minutos(pl, n) / 2));
    document.getElementById('simMensagens').textContent = S.milhar(mensagens(pl, n));
  }
  if (range) {
    range.addEventListener('input', simular);
    document.getElementById('simMenos').addEventListener('click', () => { range.value = Math.max(1, Number(range.value) - 1); simular(); });
    document.getElementById('simMais').addEventListener('click', () => { range.value = Math.min(40, Number(range.value) + 1); simular(); });
  }

  preencher(null);
  simular();

  S.rpc('precos_publicos').then((d) => {
    ((d && d.planos) || []).forEach((p) => {
      if (!planos[p.codigo]) return;
      const pl = Object.assign({}, planos[p.codigo], p);
      ['valor_mensal', 'valor_usuario_extra'].forEach((k) => { pl[k] = Number(pl[k]); });
      planos[p.codigo] = pl;
    });
    preencher(d && d.regras);
    pacotes(d && d.pacotes);
    simular();
  }).catch(() => { /* fica com os valores do HTML */ });
})();
