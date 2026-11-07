// ServPilot · página do parceiro (guia 89): indicados e comissões, pelo link privado ?t=TOKEN.
(function () {
  const S = window.ServPilot;
  const $ = (id) => document.getElementById(id);
  const data = (v) => (v ? String(v).slice(0, 10).split('-').reverse().join('/') : '');
  const situacoes = {
    em_teste: 'em teste grátis', aguardando: 'aguardando o 1º pagamento', cliente: 'cliente',
    cancelou: 'cancelou', nao_valeu: 'não valeu (mesmo CNPJ/CPF)',
  };

  function celula(tr, texto, classe) {
    const td = document.createElement('td');
    td.textContent = texto;
    if (classe) td.className = classe;
    tr.appendChild(td);
  }

  function linhaVazia(tbody, colunas, texto) {
    const tr = document.createElement('tr');
    const td = document.createElement('td');
    td.colSpan = colunas;
    td.className = 'vazio';
    td.textContent = texto;
    tr.appendChild(td);
    tbody.appendChild(tr);
  }

  function mostrar(d) {
    $('nome').textContent = d.nome;
    $('pct').textContent = String(Number(d.comissao_pct)).replace('.', ',') + '%';
    $('meses').textContent = String(d.comissao_meses);
    $('pix').textContent = d.chave_pix ? ' para a chave ' + d.chave_pix : '';
    $('inativo').hidden = d.ativo !== false;
    $('link').textContent = d.link;
    $('codigo').textContent = d.codigo;
    $('aReceber').textContent = S.moeda(d.totais.a_receber);
    $('aLiberar').textContent = S.moeda(d.totais.a_liberar);
    $('recebido').textContent = S.moeda(d.totais.recebido);

    const ind = $('indicados');
    (d.indicados || []).forEach((i) => {
      const tr = document.createElement('tr');
      celula(tr, i.nome);
      celula(tr, data(i.desde));
      celula(tr, situacoes[i.situacao] || i.situacao, 'sit-' + i.situacao);
      celula(tr, data(i.comissao_ate));
      ind.appendChild(tr);
    });
    if (!(d.indicados || []).length) linhaVazia(ind, 4, 'Ninguém ainda. Mande o seu link!');

    const com = $('comissoes');
    (d.comissoes || []).forEach((c) => {
      const tr = document.createElement('tr');
      celula(tr, c.cliente + (c.tipo === 'estorno' ? ' (pagamento devolvido)' : ''));
      celula(tr, c.periodo_inicio ? data(c.periodo_inicio) + ' a ' + data(c.periodo_fim) : '');
      celula(tr, S.moeda(c.base));
      celula(tr, S.moeda(c.valor), Number(c.valor) < 0 ? 'negativo' : '');
      celula(tr, c.situacao === 'paga' ? 'recebida em ' + data(c.pago_em)
        : c.liberada_em > new Date().toISOString().slice(0, 10) ? 'libera em ' + data(c.liberada_em) : 'a receber');
      com.appendChild(tr);
    });
    if (!(d.comissoes || []).length) linhaVazia(com, 5, 'As comissões aparecem aqui quando os indicados pagarem.');

    $('copiar').addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(d.link);
        $('copiar').textContent = 'Copiado';
      } catch (_) {
        $('copiar').textContent = 'Selecione e copie';
      }
    });
    $('pagina').hidden = false;
  }

  const token = new URLSearchParams(location.search).get('t') || '';
  S.rpc('parceiro_extrato', { p_token: token })
    .then((d) => {
      $('carregando').hidden = true;
      if (d && d.ok) mostrar(d);
      else $('invalido').hidden = false;
    })
    .catch(() => {
      $('carregando').textContent = 'Não deu para carregar agora. Tente de novo em instantes.';
    });
})();
