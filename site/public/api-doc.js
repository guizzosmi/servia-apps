// ServPilot · referência da API (guia 85).
// Lê GET /api/referencia (o modelo inteiro, sem dados), monta a referência de todas as entidades
// e o console para testar com a credencial da empresa. A credencial e o token ficam só na memória
// desta aba: nada é salvo no navegador.
(function () {
  'use strict';
  const API = 'https://srtokvosnwtyewiempyw.supabase.co/functions/v1/api';
  const $ = (id) => document.getElementById(id);
  let ref = null;
  let sessao = null; // { access, refresh, expira }

  // ------------------------------------------------------------ utilidades
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  function el(tag, attrs, ...filhos) {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v == null || v === false) continue;
      if (k === 'class') e.className = v;
      else if (k === 'text') e.textContent = v;
      else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
      else e.setAttribute(k, v === true ? '' : v);
    }
    for (const f of filhos.flat()) if (f != null) e.append(f.nodeType ? f : document.createTextNode(String(f)));
    return e;
  }

  // JSON com cores: escapa tudo antes e só depois envolve os pedaços em <span>.
  function jsonColorido(obj) {
    const txt = typeof obj === 'string' ? obj : JSON.stringify(obj, null, 2);
    const seguro = esc(txt);
    return seguro.replace(/(&quot;(?:(?!&quot;).)*?&quot;)(\s*:)?|\b(true|false|null)\b|-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b/g,
      (m, str, dois, lit) => {
        if (str) return dois ? `<span class="j-chave">${str}</span>${dois}` : `<span class="j-texto">${str}</span>`;
        if (lit) return `<span class="j-lit">${lit}</span>`;
        return `<span class="j-num">${m}</span>`;
      });
  }

  function exemploValor(c) {
    const t = c.tipo || '';
    if (t.startsWith('Collection(')) return [];
    if (c.nome === 'id' || t === 'Edm.Guid') return '00000000-0000-4000-8000-000000000000';
    switch (t) {
      case 'Edm.Boolean': return true;
      case 'Edm.Int16': case 'Edm.Int32': case 'Edm.Int64': return 0;
      case 'Edm.Decimal': case 'Edm.Double': case 'Edm.Single': return 0;
      case 'Edm.Date': return '2026-11-05';
      case 'Edm.DateTimeOffset': return '2026-11-05T10:00:00Z';
      case 'Edm.TimeOfDay': return '08:00:00';
      default: return 'texto';
    }
  }

  function registroExemplo(e) {
    const o = {};
    if (e.etag) o['@odata.etag'] = 'W/"1"';
    for (const c of e.campos) o[c.nome] = exemploValor(c);
    return o;
  }

  // Corpo de exemplo de uma gravação: o da ação documentada, ou montado pelos campos.
  function corpoExemplo(e, uso) {
    const a = (e.acoes || []).find((x) => x.uso === uso);
    if (a && a.exemplo) {
      const x = Object.assign({}, a.exemplo);
      if (uso !== 'acao') delete x.acao;
      return x;
    }
    const gravaveis = e.campos.filter((c) => !c.somente_leitura && c.nome !== 'id');
    const o = {};
    if (uso === 'incluir') {
      for (const c of gravaveis) if (c.obrigatorio) o[c.nome] = exemploValor(c);
      if (!Object.keys(o).length && gravaveis[0]) o[gravaveis[0].nome] = exemploValor(gravaveis[0]);
    } else if (gravaveis[0]) {
      const c = gravaveis.find((x) => (x.tipo || '') === 'Edm.String') || gravaveis[0];
      o[c.nome] = exemploValor(c);
    }
    return o;
  }

  const nomeApp = (codigo) => codigo ? ((ref && ref.aplicacoes && ref.aplicacoes[codigo]) || codigo) : 'Núcleo (todas as aplicações)';

  // ------------------------------------------------------------ referência
  function endpoints(e) {
    const n = e.nome;
    const op = e.operacoes;
    const lista = [];
    const regra = e.escrita === 'regra';
    const acaoDe = (uso) => (e.acoes || []).find((a) => a.uso === uso);
    if (op.consultar) {
      lista.push({ m: 'GET', rota: n, txt: 'Listar, com $filter, $select, $orderby, $top, $skip, $count e $expand', caminho: `${n}?$top=5` });
      lista.push({ m: 'GET', rota: `${n}({id})`, txt: 'Um registro pelo id (com ETag)', caminho: `${n}(COLE_O_ID)` });
      lista.push({ m: 'GET', rota: `${n}/$count`, txt: 'Só a quantidade', caminho: `${n}/$count` });
    }
    if (op.incluir) {
      const a = acaoDe('incluir');
      lista.push({ m: 'POST', rota: n, txt: regra && a ? `Incluir: ${a.titulo}` : 'Incluir', caminho: n, corpo: corpoExemplo(e, 'incluir') });
    }
    if (op.alterar) {
      const a = acaoDe('alterar');
      lista.push({ m: 'PATCH', rota: `${n}({id})`, txt: regra && a ? `Alterar: ${a.titulo}` : 'Alterar só os campos enviados',
        caminho: `${n}(COLE_O_ID)`, corpo: corpoExemplo(e, 'alterar') });
      if (!regra) {
        lista.push({ m: 'PUT', rota: `${n}({id})`, txt: 'Substituir o registro inteiro', caminho: `${n}(COLE_O_ID)`, corpo: corpoExemplo(e, 'incluir') });
      }
    }
    if (op.excluir) {
      const a = acaoDe('excluir');
      const motivo = a && (a.campos || []).some((c) => c.nome === 'motivo');
      lista.push({ m: 'DELETE', rota: `${n}({id})${motivo ? '?motivo=…' : ''}`,
        txt: regra && a ? `Excluir: ${a.titulo}` : (e.exclusao_logica ? 'Excluir (exclusão lógica)' : 'Excluir'),
        caminho: `${n}(COLE_O_ID)${motivo ? '?motivo=Informe%20o%20motivo' : ''}` });
    }
    if (op.acoes) {
      const primeira = (e.acoes || []).find((a) => a.uso === 'acao');
      lista.push({ m: 'POST', rota: `${n}({id})/${ref.namespace}.Acao`, txt: 'Ações do sistema (lista abaixo)',
        caminho: `${n}(COLE_O_ID)/${ref.namespace}.Acao`, corpo: primeira && primeira.exemplo ? primeira.exemplo : { acao: '…' } });
    }
    return lista;
  }

  function tabelaCampos(e) {
    const linhas = e.campos.map((c) => {
      const obs = [
        c.somente_leitura ? 'só leitura' : '',
        c.nulo ? 'pode ser vazio' : '',
        c.tipo_banco && c.tipo_banco.startsWith('numeric(') ? c.tipo_banco.replace('numeric', 'decimal') : '',
      ].filter(Boolean).join(' · ');
      return el('tr', null,
        el('td', null, el('code', { text: c.nome })),
        el('td', null, el('code', { text: c.tipo })),
        el('td', { text: c.obrigatorio ? 'sim' : '' }),
        el('td', { class: 'ad-campo-obs', text: obs }));
    });
    return el('div', { class: 'ad-tabela' }, el('table', null,
      el('tr', null, el('th', { text: 'Campo' }), el('th', { text: 'Tipo' }), el('th', { text: 'Obrigatório ao incluir' }), el('th', { text: 'Observação' })),
      linhas));
  }

  function blocoAcoes(e) {
    const caixa = el('div');
    for (const a of e.acoes || []) {
      const via = a.uso === 'incluir' ? 'POST' : a.uso === 'alterar' ? 'PATCH' : a.uso === 'excluir' ? 'DELETE' : 'Acao';
      const campos = (a.campos || []).length
        ? el('div', { class: 'ad-tabela' }, el('table', null,
          el('tr', null, el('th', { text: 'Campo' }), el('th', { text: 'Tipo' }), el('th', { text: 'Obrig.' }), el('th', { text: 'Descrição' })),
          a.campos.map((c) => el('tr', null,
            el('td', null, el('code', { text: c.nome })),
            el('td', null, el('code', { text: c.tipo })),
            el('td', { text: c.obrigatorio ? 'sim' : '' }),
            el('td', { text: c.descricao || '' })))))
        : el('p', { class: 'ad-vazio', text: via === 'Acao' ? 'Sem campos além da ação.' : 'Os mesmos campos da inclusão.' });
      const ex = el('pre', { class: 'ad-codigo' });
      ex.innerHTML = '<code>' + jsonColorido(a.exemplo || {}) + '</code>';
      const testar = () => {
        const corpo = Object.assign({}, a.exemplo || {});
        if (via === 'Acao') levarAoConsole('POST', `${e.nome}(COLE_O_ID)/${ref.namespace}.Acao`, corpo);
        else if (via === 'POST') { delete corpo.acao; levarAoConsole('POST', e.nome, corpo); }
        else if (via === 'PATCH') { delete corpo.acao; levarAoConsole('PATCH', `${e.nome}(COLE_O_ID)`, corpo); }
        else levarAoConsole('DELETE', `${e.nome}(COLE_O_ID)?motivo=${encodeURIComponent((a.exemplo && a.exemplo.motivo) || 'motivo')}`, null);
      };
      const permitido = via === 'Acao' ? e.operacoes.acoes : via === 'POST' ? e.operacoes.incluir : via === 'PATCH' ? e.operacoes.alterar : e.operacoes.excluir;
      caixa.append(el('div', { class: 'ad-acao' },
        el('h4', null, el('code', { text: a.acao }), a.titulo || '', el('span', { class: 'chip', text: via === 'Acao' ? 'ação' : via }),
          permitido ? el('button', { class: 'ad-testar', type: 'button', text: 'Testar', onclick: testar }) : el('span', { class: 'chip', text: 'desabilitada' })),
        a.descricao ? el('p', { class: 'ad-ent-desc', text: a.descricao }) : null,
        campos, ex));
    }
    return caixa;
  }

  function montarEntidade(e) {
    const sec = el('article', { class: 'ad-entidade', id: 'e-' + e.nome });
    sec.append(el('div', { class: 'ad-ent-topo' },
      el('h2', { text: e.nome }),
      el('span', { class: 'chip app', text: nomeApp(e.aplicacao) }),
      el('span', { class: 'chip', text: e.tipo === 'movimento' ? 'movimento' : 'cadastro' }),
      e.escrita === 'leitura' ? el('span', { class: 'chip', text: 'só consulta' }) : null));
    if (e.descricao) sec.append(el('p', { class: 'ad-ent-desc', text: e.descricao }));

    const eps = endpoints(e);
    if (eps.length) {
      sec.append(el('div', { class: 'ad-endpoints' }, eps.map((p) => el('div', { class: 'ad-ep' },
        el('span', { class: 'metodo ' + p.m, text: p.m }),
        el('span', { class: 'rota' }, '/odata/' + p.rota, el('small', { text: p.txt })),
        el('button', { class: 'ad-testar', type: 'button', text: 'Testar', onclick: () => levarAoConsole(p.m, p.caminho, p.corpo || null) })))));
    } else {
      sec.append(el('p', { class: 'ad-vazio', text: 'Desabilitada no momento.' }));
    }

    sec.append(el('details', { class: 'ad-det' }, el('summary', { text: `Campos (${e.campos.length})` }), tabelaCampos(e)));
    if (e.navegacoes.length) {
      sec.append(el('details', { class: 'ad-det' }, el('summary', { text: `Navegações para $expand (${e.navegacoes.length})` }),
        el('div', { class: 'ad-tabela' }, el('table', null,
          el('tr', null, el('th', { text: 'Nome' }), el('th', { text: 'Leva a' }), el('th', { text: 'Exemplo' })),
          e.navegacoes.map((n) => el('tr', null,
            el('td', null, el('code', { text: n.nome })),
            el('td', null, el('a', { href: '#e-' + n.alvo, text: n.alvo }), n.muitos ? ' (vários)' : ' (um)'),
            el('td', null, el('code', { text: `$expand=${n.nome}($select=id)` }))))))));
    }
    if ((e.acoes || []).length) {
      sec.append(el('details', { class: 'ad-det', open: e.operacoes.acoes ? true : null },
        el('summary', { text: `Ações e corpo das gravações (${e.acoes.length})` }), blocoAcoes(e)));
    }
    if (e.operacoes.consultar) {
      const lista = { '@odata.context': `${ref.odata}/$metadata#${e.nome}`, '@odata.count': 1, value: [registroExemplo(e)] };
      const pre = el('pre', { class: 'ad-codigo' });
      pre.innerHTML = '<code>' + jsonColorido(lista) + '</code>';
      sec.append(el('details', { class: 'ad-det' }, el('summary', { text: 'Exemplo de retorno (GET com $count=true)' }), pre));
    }
    return sec;
  }

  function montarReferencia() {
    const raiz = $('referencia');
    const menu = $('menuEntidades');
    raiz.replaceChildren();
    menu.replaceChildren();
    const grupos = new Map();
    for (const e of ref.entidades) {
      const k = e.aplicacao || '';
      if (!grupos.has(k)) grupos.set(k, []);
      grupos.get(k).push(e);
    }
    for (const [app, lista] of grupos) {
      // data-grupo: a busca esconde o título do grupo quando nenhuma entidade dele sobra.
      const g = app || 'nucleo';
      menu.append(el('div', { class: 'ad-app', 'data-grupo': g, text: nomeApp(app || null) }));
      raiz.append(el('h3', { 'data-grupo': g, text: nomeApp(app || null) }));
      for (const e of lista) {
        menu.append(el('a', { href: '#e-' + e.nome, 'data-nome': e.nome.toLowerCase(), 'data-grupo': g, text: e.nome }));
        const sec = montarEntidade(e);
        sec.dataset.grupo = g;
        raiz.append(sec);
      }
    }
    $('urlToken').textContent = ref.token;
    $('urlOdata').textContent = ref.odata;
    $('urlRef').textContent = API + '/referencia';
    const L = ref.limites || {};
    const por = (cls, v) => document.querySelectorAll(cls).forEach((x) => { if (v != null) x.textContent = Number(v).toLocaleString('pt-BR'); });
    por('.lim-access', L.access_minutos);
    por('.lim-refresh', L.refresh_dias);
    por('.lim-pagina', L.pagina_padrao);
    por('.lim-max', L.pagina_maxima);
    por('.lim-minuto', L.por_minuto);
    $('baixarOpenapi').disabled = false;
    if (location.hash) {
      const alvo = document.getElementById(location.hash.slice(1));
      if (alvo) alvo.scrollIntoView();
    }
  }

  $('busca').addEventListener('input', () => {
    const q = $('busca').value.trim().toLowerCase();
    document.querySelectorAll('#menuEntidades a').forEach((a) => { a.hidden = !!q && !a.dataset.nome.includes(q); });
    document.querySelectorAll('.ad-entidade').forEach((s) => { s.hidden = !!q && !s.id.slice(2).toLowerCase().includes(q); });
    // Título do grupo (no menu e na referência) só quando sobra alguma entidade dele.
    document.querySelectorAll('#menuEntidades .ad-app, #referencia > h3').forEach((t) => {
      const g = t.dataset.grupo;
      t.hidden = !!q && ![...document.querySelectorAll('#menuEntidades a')].some((a) => a.dataset.grupo === g && !a.hidden);
    });
  });

  // ------------------------------------------------------------ OpenAPI (Postman, Insomnia)
  function tipoOpenapi(t) {
    if ((t || '').startsWith('Collection(')) return { type: 'array', items: tipoOpenapi(t.slice(11, -1)) };
    switch (t) {
      case 'Edm.Guid': return { type: 'string', format: 'uuid' };
      case 'Edm.Boolean': return { type: 'boolean' };
      case 'Edm.Int16': case 'Edm.Int32': return { type: 'integer', format: 'int32' };
      case 'Edm.Int64': return { type: 'integer', format: 'int64' };
      case 'Edm.Decimal': case 'Edm.Double': case 'Edm.Single': return { type: 'number' };
      case 'Edm.Date': return { type: 'string', format: 'date' };
      case 'Edm.DateTimeOffset': return { type: 'string', format: 'date-time' };
      default: return { type: 'string' };
    }
  }

  function openapi() {
    const doc = {
      openapi: '3.0.3',
      info: { title: 'ServPilot API (OData v4)', version: '1.0', description: 'Gerado de https://servpilot.com.br/api' },
      servers: [{ url: ref.odata }],
      components: {
        schemas: {},
        securitySchemes: {
          oauth: { type: 'oauth2', flows: { clientCredentials: { tokenUrl: ref.token, scopes: {} } } },
          bearer: { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' },
        },
        parameters: {
          TenantId: { name: 'TenantId', in: 'header', required: false, schema: { type: 'string' }, example: '01,0101' },
          id: { name: 'id', in: 'path', required: true, schema: { type: 'string', format: 'uuid' } },
        },
      },
      security: [{ oauth: [] }, { bearer: [] }],
      paths: {},
    };
    const consulta = ['filter', 'select', 'orderby', 'top', 'skip', 'count', 'expand'].map((n) => ({
      name: '$' + n, in: 'query', required: false,
      schema: { type: n === 'top' || n === 'skip' ? 'integer' : n === 'count' ? 'boolean' : 'string' },
    }));
    const tenant = { $ref: '#/components/parameters/TenantId' };
    const pid = { $ref: '#/components/parameters/id' };
    for (const e of ref.entidades) {
      const props = {};
      const obrig = [];
      for (const c of e.campos) {
        props[c.nome] = Object.assign(tipoOpenapi(c.tipo), c.somente_leitura ? { readOnly: true } : {}, c.nulo ? { nullable: true } : {});
        if (c.obrigatorio) obrig.push(c.nome);
      }
      doc.components.schemas[e.nome] = Object.assign({ type: 'object', properties: props, description: e.descricao || '' }, obrig.length ? { required: obrig } : {});
      const s = { $ref: '#/components/schemas/' + e.nome };
      const corpoDe = (uso) => {
        const a = (e.acoes || []).find((x) => x.uso === uso);
        if (!a) return { content: { 'application/json': { schema: s } } };
        const ex = Object.assign({}, a.exemplo || {});
        delete ex.acao;
        return { content: { 'application/json': { schema: { type: 'object' }, example: ex } } };
      };
      const col = {};
      const um = {};
      if (e.operacoes.consultar) {
        col.get = { tags: [e.nome], summary: 'Listar ' + e.nome, parameters: [tenant, ...consulta],
          responses: { 200: { description: 'OK', content: { 'application/json': { schema: { type: 'object', properties: { value: { type: 'array', items: s } } } } } } } };
        um.get = { tags: [e.nome], summary: 'Um registro', parameters: [tenant, pid],
          responses: { 200: { description: 'OK', content: { 'application/json': { schema: s } } }, 404: { description: 'Não encontrado' } } };
      }
      if (e.operacoes.incluir) col.post = { tags: [e.nome], summary: 'Incluir', parameters: [tenant], requestBody: corpoDe('incluir'), responses: { 201: { description: 'Incluído' } } };
      if (e.operacoes.alterar) {
        um.patch = { tags: [e.nome], summary: 'Alterar', parameters: [tenant, pid], requestBody: corpoDe('alterar'), responses: { 204: { description: 'Alterado' } } };
        if (e.escrita !== 'regra') {
          um.put = { tags: [e.nome], summary: 'Substituir', parameters: [tenant, pid], requestBody: { content: { 'application/json': { schema: s } } }, responses: { 204: { description: 'Substituído' } } };
        }
      }
      if (e.operacoes.excluir) {
        um.delete = { tags: [e.nome], summary: 'Excluir', parameters: [tenant, pid, { name: 'motivo', in: 'query', required: false, schema: { type: 'string' } }],
          responses: { 204: { description: 'Excluído' } } };
      }
      if (Object.keys(col).length) doc.paths['/' + e.nome] = col;
      if (Object.keys(um).length) doc.paths['/' + e.nome + '({id})'] = um;
      if (e.operacoes.acoes) {
        const acoes = (e.acoes || []).filter((a) => a.uso === 'acao');
        doc.paths['/' + e.nome + '({id})/' + ref.namespace + '.Acao'] = {
          post: {
            tags: [e.nome], summary: 'Ações: ' + acoes.map((a) => a.acao).join(', '), parameters: [tenant, pid],
            requestBody: { content: { 'application/json': {
              schema: { type: 'object', required: ['acao'], properties: { acao: { type: 'string', enum: (e.acoes || []).map((a) => a.acao) } } },
              examples: Object.fromEntries(acoes.map((a) => [a.acao, { summary: a.titulo, value: a.exemplo }])),
            } } },
            responses: { 200: { description: 'Resultado da ação' } },
          },
        };
      }
    }
    return doc;
  }

  $('baixarOpenapi').addEventListener('click', () => {
    if (!ref) return;
    const blob = new Blob([JSON.stringify(openapi(), null, 2)], { type: 'application/json' });
    const a = el('a', { href: URL.createObjectURL(blob), download: 'servpilot-openapi.json' });
    document.body.append(a);
    a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  });

  // ------------------------------------------------------------ console
  const metodosComCorpo = new Set(['POST', 'PATCH', 'PUT']);

  function atualizarFormulario() {
    const m = $('metodo').value;
    $('campoCorpo').hidden = !metodosComCorpo.has(m);
    $('campoGrava').hidden = m === 'GET';
  }
  $('metodo').addEventListener('change', atualizarFormulario);

  function abrirConsole() { $('console').classList.add('aberto'); }
  $('abrirConsole').addEventListener('click', abrirConsole);
  $('fecharConsole').addEventListener('click', () => $('console').classList.remove('aberto'));

  function estadoChamada(t, tipo) {
    const s = $('estadoChamada');
    s.textContent = t;
    s.className = 'ad-estado' + (tipo ? ' ' + tipo : '');
  }

  function levarAoConsole(metodo, caminho, corpo) {
    $('metodo').value = metodo;
    $('caminho').value = caminho;
    $('corpo').value = corpo ? JSON.stringify(corpo, null, 2) : '';
    $('confirmaGrava').checked = false;
    $('ifMatch').value = '';
    atualizarFormulario();
    abrirConsole();
    estadoChamada(caminho.includes('COLE_O_ID') ? 'Troque COLE_O_ID pelo id de um registro (pegue um na listagem).' : '');
    $('caminho').focus();
  }

  function estadoToken(texto, tipo) {
    const s = $('estadoToken');
    s.textContent = texto;
    s.className = 'ad-estado' + (tipo ? ' ' + tipo : '');
  }

  async function pedirToken(campos) {
    const r = await fetch(API + '/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(campos).toString(),
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j.error_description || j.error || ('HTTP ' + r.status));
    sessao = { access: j.access_token, refresh: j.refresh_token, expira: Date.now() + (j.expires_in || 900) * 1000 };
    const h = new Date(sessao.expira).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
    estadoToken('Token válido até ' + h + '. Renova sozinho com o refresh token.', 'ok');
  }

  $('obterToken').addEventListener('click', async () => {
    const id = $('clientId').value.trim();
    const segredo = $('clientSecret').value;
    if (!id || !segredo) { estadoToken('Preencha o client_id e o client_secret.', 'erro'); return; }
    $('obterToken').disabled = true;
    estadoToken('Pedindo o token…');
    try {
      await pedirToken({ grant_type: 'client_credentials', client_id: id, client_secret: segredo });
      $('clientSecret').value = '';
    } catch (e) {
      sessao = null;
      estadoToken('Não deu: ' + e.message, 'erro');
    } finally {
      $('obterToken').disabled = false;
    }
  });

  $('esquecer').addEventListener('click', () => {
    sessao = null;
    $('clientId').value = '';
    $('clientSecret').value = '';
    estadoToken('Credencial e token apagados desta aba.');
  });

  async function garantirToken() {
    if (!sessao) throw new Error('Obtenha o token no passo 1.');
    if (Date.now() > sessao.expira - 30000) {
      try {
        await pedirToken({ grant_type: 'refresh_token', refresh_token: sessao.refresh });
      } catch (e) {
        sessao = null;
        throw new Error('O token venceu e não deu para renovar: obtenha outro no passo 1.');
      }
    }
    return sessao.access;
  }

  function montarChamada() {
    const m = $('metodo').value;
    const caminho = $('caminho').value.trim().replace(/^\/+/, '').replace(/^odata\/?/, '');
    const cab = { Accept: 'application/json' };
    if ($('tenant').value.trim()) cab.TenantId = $('tenant').value.trim();
    if ($('preferRep').checked && m !== 'GET') cab.Prefer = 'return=representation';
    if ($('ifMatch').value.trim()) cab['If-Match'] = $('ifMatch').value.trim();
    let corpo = null;
    if (metodosComCorpo.has(m)) {
      const txt = $('corpo').value.trim();
      if (txt) {
        try { corpo = JSON.stringify(JSON.parse(txt)); } catch (e) { throw new Error('O corpo não é um JSON válido: ' + e.message); }
      }
      cab['Content-Type'] = 'application/json';
    }
    return { m, url: API + '/odata/' + caminho, cab, corpo };
  }

  let ultimaResposta = '';

  function mostrarResposta(r, texto, ms) {
    $('resposta').hidden = false;
    const st = $('respStatus');
    st.textContent = r.status + (r.statusText ? ' ' + r.statusText : '');
    st.className = 'status s' + String(r.status)[0];
    $('respTempo').textContent = ms + ' ms';
    const cabs = ['etag', 'location', 'odata-entityid', 'preference-applied', 'retry-after']
      .map((h) => (r.headers.get(h) ? `${h}: ${r.headers.get(h)}` : null)).filter(Boolean);
    $('respCab').textContent = cabs.join('\n');
    let corpo = texto || '(sem corpo)';
    let ehJson = false;
    try { if (texto) { corpo = JSON.stringify(JSON.parse(texto), null, 2); ehJson = true; } } catch (_) { /* texto puro, ex.: $count */ }
    ultimaResposta = corpo;
    $('respCorpo').innerHTML = ehJson ? jsonColorido(corpo) : esc(corpo);
  }

  $('enviar').addEventListener('click', async () => {
    let ch;
    try { ch = montarChamada(); } catch (e) { estadoChamada(e.message, 'erro'); return; }
    if (ch.url.includes('COLE_O_ID')) { estadoChamada('Troque COLE_O_ID pelo id de um registro.', 'erro'); return; }
    if (ch.m !== 'GET' && !$('confirmaGrava').checked) { estadoChamada('Marque a confirmação: esta chamada grava dados reais.', 'erro'); return; }
    $('enviar').disabled = true;
    estadoChamada('Enviando…');
    const t0 = performance.now();
    try {
      const token = await garantirToken();
      const r = await fetch(ch.url, { method: ch.m, headers: Object.assign({ Authorization: 'Bearer ' + token }, ch.cab), body: ch.corpo });
      const texto = await r.text();
      mostrarResposta(r, texto, Math.round(performance.now() - t0));
      estadoChamada('');
    } catch (e) {
      estadoChamada(e.message || 'Falha na chamada.', 'erro');
    } finally {
      $('enviar').disabled = false;
    }
  });

  async function copiar(texto, botao) {
    const antes = botao.textContent;
    try { await navigator.clipboard.writeText(texto); botao.textContent = 'Copiado'; } catch (_) { botao.textContent = 'Não deu para copiar'; }
    setTimeout(() => { botao.textContent = antes; }, 1500);
  }

  $('copiarResp').addEventListener('click', (ev) => copiar(ultimaResposta, ev.currentTarget));

  $('copiarCurl').addEventListener('click', (ev) => {
    let ch;
    try { ch = montarChamada(); } catch (e) { estadoChamada(e.message, 'erro'); return; }
    const q = (s) => "'" + s.replace(/'/g, "'\\''") + "'";
    const partes = ['curl -s -X ' + ch.m + ' ' + q(ch.url), "-H 'Authorization: Bearer SEU_ACCESS_TOKEN'"];
    for (const [k, v] of Object.entries(ch.cab)) partes.push('-H ' + q(k + ': ' + v));
    if (ch.corpo) partes.push('--data ' + q(ch.corpo));
    copiar(partes.join(' \\\n  '), ev.currentTarget);
  });

  atualizarFormulario();

  // ------------------------------------------------------------ carregar
  fetch(API + '/referencia')
    .then((r) => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
    .then((j) => { ref = j; montarReferencia(); })
    .catch(() => {
      $('referencia').replaceChildren(el('p', { class: 'ad-aviso', text: 'Não deu para carregar a referência agora. Recarregue a página em instantes.' }));
      $('menuEntidades').replaceChildren();
    });
})();
