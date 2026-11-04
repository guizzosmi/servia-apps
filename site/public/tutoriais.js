// ServPilot · central de tutoriais
// Entra pelo link do painel ou do app (#c=código de 10 minutos), troca por uma chave própria
// (guardada neste navegador por 90 dias) e mostra as trilhas do perfil. O player (youtube-nocookie)
// informa onde a pessoa está: o progresso é gravado a cada 10 segundos, ao pausar e ao terminar.
(function () {
  const S = window.ServPilot;
  const $ = (id) => document.getElementById(id);
  const CHAVE_LOCAL = 'servpilot_tutoriais';
  let chave = null;
  let lista = [];          // todos os vídeos, na ordem das trilhas
  let atual = null;        // vídeo aberto
  let player = null;
  let pronto = false;
  let tique = null;
  let assistidoDesdeGravar = 0;
  let ultimoGravar = 0;
  let contagem = null;

  const lerLocal = () => { try { return localStorage.getItem(CHAVE_LOCAL); } catch (_) { return null; } };
  const gravarLocal = (v) => { try { v ? localStorage.setItem(CHAVE_LOCAL, v) : localStorage.removeItem(CHAVE_LOCAL); } catch (_) { /* sem armazenamento */ } };
  const min = (s) => { const m = Math.floor((s || 0) / 60), r = Math.round((s || 0) % 60); return `${m}:${String(r).padStart(2, '0')}`; };
  const pct = (v) => v.concluido ? 100 : Math.min(100, Math.round(100 * (v.maximo_s || 0) / (v.duracao_s || 1)));

  function mostrarAviso(texto) {
    $('conteudo').hidden = true;
    $('aviso').hidden = false;
    if (texto) $('avisoTexto').textContent = texto;
  }

  // ---------------------------------------------------------------- dados
  async function carregar() {
    const codigo = new URLSearchParams(location.hash.slice(1)).get('c');
    let dados = null;
    try {
      if (codigo) {
        history.replaceState(null, '', location.pathname + location.search);
        dados = await S.rpc('tutoriais_entrar', { p_codigo: codigo });
        if (dados && dados.chave) { chave = dados.chave; gravarLocal(chave); }
      }
      if ((!dados || dados.erro) && lerLocal()) {
        chave = lerLocal();
        dados = await S.rpc('tutoriais_dados', { p_chave: chave });
      }
    } catch (e) {
      return mostrarAviso('Não deu para carregar os tutoriais agora. Confira a internet e tente de novo.');
    }
    if (!dados || dados.erro) {
      gravarLocal(null);
      return mostrarAviso(dados && dados.erro);
    }
    montar(dados);
  }

  function montar(d) {
    $('quem').textContent = d.nome ? `Olá, ${d.nome.split(' ')[0]}` : '';
    lista = [];
    (d.trilhas || []).forEach((t) => (t.videos || []).forEach((v) => lista.push(Object.assign(v, { trilha: t }))));
    if (!lista.length) return mostrarAviso('Ainda não há vídeos para o seu perfil.');
    $('conteudo').hidden = false;
    desenharLista(d.trilhas);
    const pedido = Number(new URLSearchParams(location.search).get('v'));
    const inicial = lista.find((v) => v.numero === pedido) || continuarDe() || lista[0];
    abrir(inicial, false);
  }

  // O primeiro começado e não terminado; senão, o primeiro ainda não visto.
  function continuarDe() {
    return lista.find((v) => v.youtube_id && !v.concluido && v.posicao_s > 5)
        || lista.find((v) => v.youtube_id && !v.concluido);
  }

  function desenharLista(trilhas) {
    const caixa = $('trilhas');
    caixa.innerHTML = '';
    trilhas.forEach((t) => {
      const g = document.createElement('div');
      g.className = 'tut-grupo';
      const feitos = t.videos.filter((v) => v.concluido).length;
      g.innerHTML = '<h2><b></b><span></span></h2><p></p>';
      g.querySelector('b').textContent = t.titulo;
      g.querySelector('span').textContent = `${feitos}/${t.videos.length}`;
      g.querySelector('p').textContent = t.descricao || '';
      t.contador = g.querySelector('h2 span');
      t.videos.forEach((v) => {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'tut-item';
        b.dataset.numero = v.numero;
        b.innerHTML = '<span class="st"></span><span class="tt"><span class="nm"></span><small></small></span><span class="mini"><i></i></span>';
        b.querySelector('.nm').textContent = v.titulo;
        b.addEventListener('click', () => abrir(v, true));
        g.appendChild(b);
        v.botao = b;
        pintarItem(v);
      });
      caixa.appendChild(g);
    });
    pintarResumo();
  }

  function pintarItem(v) {
    const b = v.botao;
    if (!b) return;
    const p = pct(v);
    b.classList.toggle('feito', !!v.concluido);
    b.classList.toggle('parcial', !v.concluido && p > 0);
    b.classList.toggle('breve', !v.youtube_id);
    b.classList.toggle('atual', atual === v);
    b.querySelector('.st').textContent = v.concluido ? '✓' : (lista.indexOf(v) + 1);
    b.querySelector('small').textContent = !v.youtube_id ? 'em breve'
      : v.concluido ? `assistido · ${min(v.duracao_s)}`
      : p > 0 ? `parou em ${min(v.posicao_s)} de ${min(v.duracao_s)}` : min(v.duracao_s);
    b.querySelector('.mini i').style.width = p + '%';
  }

  function pintarResumo() {
    const comVideo = lista.filter((v) => v.youtube_id);
    const feitos = comVideo.filter((v) => v.concluido).length;
    $('totalFeitos').textContent = feitos;
    $('totalVideos').textContent = comVideo.length;
    $('totalBarra').style.width = (comVideo.length ? Math.round(100 * feitos / comVideo.length) : 0) + '%';
    const c = continuarDe();
    $('continuar').hidden = !c || c === atual;
    [...new Set(lista.map((v) => v.trilha))].forEach((t) => {
      if (t.contador) t.contador.textContent = `${t.videos.filter((v) => v.concluido).length}/${t.videos.length}`;
    });
  }

  // ---------------------------------------------------------------- player
  function abrir(v, tocar) {
    if (!v) return;
    cancelarProximo();
    if (atual && atual !== v) gravar(true);
    const anterior = atual;
    atual = v;
    if (anterior) pintarItem(anterior);
    pintarItem(v);
    pintarResumo();
    $('atualTrilha').textContent = v.trilha.titulo;
    $('atualTitulo').textContent = v.titulo;
    $('atualDesc').textContent = v.descricao || '';
    const i = lista.indexOf(v);
    $('anterior').disabled = i <= 0;
    $('proximo').disabled = i >= lista.length - 1;
    $('marcar').hidden = !!v.concluido || !v.youtube_id;
    history.replaceState(null, '', `${location.pathname}?v=${v.numero}`);
    $('emBreve').hidden = !!v.youtube_id;
    if (!v.youtube_id) { if (player && pronto) player.stopVideo(); return; }
    const inicio = !v.concluido && v.posicao_s > 5 && v.posicao_s < (v.duracao_s || 1e9) - 5 ? Math.max(0, v.posicao_s - 2) : 0;
    if (player && pronto) {
      if (tocar) player.loadVideoById({ videoId: v.youtube_id, startSeconds: inicio });
      else player.cueVideoById({ videoId: v.youtube_id, startSeconds: inicio });
    } else {
      criarPlayer(v.youtube_id, inicio);
    }
  }

  // Player sem a biblioteca iframe_api: o iframe do youtube-nocookie.com conversa com a página
  // por postMessage (o mesmo protocolo que a biblioteca usa). Assim o vídeo não depende de
  // www.youtube.com, que algumas redes e provedores bloqueiam (a tela ficava preta).
  const YT_ORIGEM = 'https://www.youtube-nocookie.com';
  const ESTADO = { TERMINOU: 0, TOCANDO: 1, PAUSADO: 2 };

  function criarPlayer(id, inicio) {
    const q = new URLSearchParams({
      enablejsapi: '1', origin: location.origin, start: String(inicio || 0), rel: '0',
      modestbranding: '1', playsinline: '1', hl: 'pt-BR', cc_lang_pref: 'pt',
    });
    const f = document.createElement('iframe');
    f.id = 'player';
    f.title = 'Vídeo do tutorial';
    f.allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen';
    f.allowFullscreen = true;
    f.referrerPolicy = 'strict-origin-when-cross-origin';
    f.src = `${YT_ORIGEM}/embed/${encodeURIComponent(id)}?${q}`;
    $('player').replaceWith(f);

    let tempo = 0;
    let estado = -1;
    let chamando = null;
    const postar = (m) => { if (f.contentWindow) f.contentWindow.postMessage(JSON.stringify(m), YT_ORIGEM); };
    const enviar = (func, args) => postar({ event: 'command', func, args: args || [], id: 1, channel: 'widget' });
    const ouvir = () => postar({ event: 'listening', id: 1, channel: 'widget' });
    window.addEventListener('message', (e) => {
      if (e.origin !== YT_ORIGEM || e.source !== f.contentWindow) return;
      let m;
      try { m = typeof e.data === 'string' ? JSON.parse(e.data) : e.data; } catch (_) { return; }
      if (!m || !m.event) return;
      if (m.event === 'onReady') { pronto = true; clearInterval(chamando); }
      const info = m.info && typeof m.info === 'object' ? m.info : {};
      if (typeof info.currentTime === 'number') tempo = info.currentTime;
      const novoEstado = typeof info.playerState === 'number' ? info.playerState
        : (m.event === 'onStateChange' && typeof m.info === 'number' ? m.info : null);
      if (novoEstado !== null && novoEstado !== estado) {
        estado = novoEstado;
        aoMudarEstado({ data: estado });
      }
    });
    f.addEventListener('load', () => {
      ouvir();
      clearInterval(chamando);
      chamando = setInterval(ouvir, 400);
      setTimeout(() => clearInterval(chamando), 15000);
    });
    player = {
      loadVideoById: (o) => enviar('loadVideoById', [o]),
      cueVideoById: (o) => enviar('cueVideoById', [o]),
      stopVideo: () => enviar('stopVideo'),
      getCurrentTime: () => tempo,
    };
  }

  function aoMudarEstado(e) {
    if (e.data === ESTADO.TOCANDO) {
      if (!tique) tique = setInterval(aCadaSegundo, 1000);
    } else {
      clearInterval(tique); tique = null;
      if (e.data === ESTADO.PAUSADO) gravar(true);
      if (e.data === ESTADO.TERMINOU) terminou();
    }
  }

  function aCadaSegundo() {
    if (!atual || !player) return;
    const t = Math.floor(player.getCurrentTime() || 0);
    assistidoDesdeGravar += 1;
    atual.posicao_s = t;
    atual.maximo_s = Math.max(atual.maximo_s || 0, t);
    if (!atual.concluido && atual.duracao_s && atual.maximo_s >= atual.duracao_s * 0.9) {
      atual.concluido = true;
      $('marcar').hidden = true;
      gravar(true);
      pintarResumo();
    }
    pintarItem(atual);
    if (Date.now() - ultimoGravar > 10000) gravar(false);
  }

  async function gravar(agora, concluir) {
    if (!chave || !atual || !atual.youtube_id) return;
    if (!agora && Date.now() - ultimoGravar < 10000) return;
    ultimoGravar = Date.now();
    const v = atual;
    const corpo = { numero: v.numero, posicao: v.posicao_s || 0, maximo: v.maximo_s || 0,
                    assistido: assistidoDesdeGravar, concluido: !!(concluir || v.concluido) };
    assistidoDesdeGravar = 0;
    try {
      const r = await S.rpc('tutoriais_salvar', { p_chave: chave, p: corpo });
      if (r && r.erro === 'sem_acesso') { gravarLocal(null); }
      if (r && r.concluido && !v.concluido) { v.concluido = true; pintarItem(v); pintarResumo(); }
    } catch (_) { /* sem internet: tenta na próxima */ }
  }

  // ---------------------------------------------------------------- próximo vídeo
  function proximoDe(v) {
    for (let i = lista.indexOf(v) + 1; i < lista.length; i++) if (lista[i].youtube_id) return lista[i];
    return null;
  }

  function terminou() {
    atual.concluido = true;
    atual.posicao_s = 0;
    gravar(true, true);
    pintarItem(atual);
    pintarResumo();
    const prox = proximoDe(atual);
    if (!prox) return;
    $('proximoTitulo').textContent = prox.titulo;
    $('proximoAviso').hidden = false;
    let n = 5;
    $('contagem').textContent = n;
    contagem = setInterval(() => {
      n -= 1;
      $('contagem').textContent = n;
      if (n <= 0) abrir(prox, true);
    }, 1000);
  }

  function cancelarProximo() {
    clearInterval(contagem); contagem = null;
    $('proximoAviso').hidden = true;
  }

  // ---------------------------------------------------------------- botões
  $('assistirJa').addEventListener('click', () => abrir(proximoDe(atual), true));
  $('cancelarProximo').addEventListener('click', cancelarProximo);
  $('anterior').addEventListener('click', () => abrir(lista[lista.indexOf(atual) - 1], true));
  $('proximo').addEventListener('click', () => abrir(lista[lista.indexOf(atual) + 1], true));
  $('continuar').addEventListener('click', () => abrir(continuarDe(), true));
  $('marcar').addEventListener('click', () => {
    atual.concluido = true;
    $('marcar').hidden = true;
    gravar(true, true);
    pintarItem(atual);
    pintarResumo();
  });
  // Saindo da página (fechar a aba, trocar de app no celular): grava onde parou.
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') gravar(true); });

  carregar();
})();
