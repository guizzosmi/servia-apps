// ServPilot · acesso à plataforma a partir do site (só o que é público).
// A chave abaixo é a chave PUBLICÁVEL do Supabase (feita para ficar no navegador).
window.ServPilot = (function () {
  const URL_BASE = 'https://srtokvosnwtyewiempyw.supabase.co';
  const CHAVE = 'sb_publishable_qUKXkM5nd3KhUgOc8Auk9A_g9K2xxrH';
  const PAINEL = 'https://painel.servpilot.com.br';

  async function postar(caminho, corpo) {
    const r = await fetch(URL_BASE + caminho, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: CHAVE },
      body: JSON.stringify(corpo || {}),
    });
    let dados = null;
    try { dados = await r.json(); } catch (_) { /* sem corpo */ }
    if (!r.ok) {
      const msg = (dados && (dados.message || dados.msg)) || 'Não deu para falar com o servidor. Tente de novo em instantes.';
      const erro = new Error(msg);
      erro.codigo = dados && (dados.code || dados.hint);
      throw erro;
    }
    return dados;
  }

  const rpc = (nome, params) => postar('/rest/v1/rpc/' + nome, params);
  const funcao = (nome, corpo) => postar('/functions/v1/' + nome, corpo);

  function moeda(v, semCentavos) {
    const n = Number(v) || 0;
    return n.toLocaleString('pt-BR', {
      style: 'currency', currency: 'BRL',
      minimumFractionDigits: semCentavos ? 0 : 2, maximumFractionDigits: semCentavos ? 0 : 2,
    });
  }
  const milhar = (v) => (Number(v) || 0).toLocaleString('pt-BR');

  return { rpc, funcao, moeda, milhar, PAINEL };
})();
