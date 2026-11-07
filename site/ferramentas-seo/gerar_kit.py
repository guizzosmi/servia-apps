from gerar_base import *

caminho = '/modelo-pmoc'
titulo = 'Modelo de PMOC grátis: planilha completa e checklist mensal'
descricao = 'Baixe grátis o Kit PMOC: planilha com ambientes, equipamentos, atividades da Portaria 3.523/98, cronograma anual, registro mensal e calculadora de quanto cobrar, mais checklist mensal em PDF.'
perguntas = [
  ('O kit é grátis mesmo?', 'Sim. Você preenche nome, cidade e WhatsApp e baixa na hora a planilha e o checklist.'),
  ('A planilha serve para qualquer tipo de aparelho?', 'Ela traz atividades de referência para split, cassete, piso-teto, self contained, fan coil e dutos. Ajuste a lista e a periodicidade com o seu responsável técnico.'),
  ('A planilha substitui o responsável técnico?', 'Não. O PMOC é assinado por um responsável técnico habilitado, com ART ou documento equivalente. O kit organiza o plano e o registro do dia a dia.'),
]
jsonld = [ORG, faq_jsonld(perguntas), migalhas([('ServPilot', '/'), ('Kit PMOC grátis', caminho)])]
pagina = cabeca(f'{titulo} | ServPilot', descricao, caminho, jsonld, extra_css='kit.css') + '''<section class="abertura lp-abertura">
  <div class="abertura-fundo" aria-hidden="true"></div>
  <div class="faixa"><div class="abertura-texto">
    <p class="lp-trilha"><a href="/">ServPilot</a> › <a href="/software-pmoc">PMOC</a> › Kit grátis</p>
    <h1>Kit PMOC grátis: <span class="destaque">planilha completa e checklist mensal.</span></h1>
    <p class="lead">Tudo o que você precisa para montar o plano, cumprir as preventivas e provar ao cliente o que foi feito. Pronto para usar no próximo contrato.</p>
  </div></div>
</section>

<section class="secao clara"><div class="faixa kit-grade">
  <div class="kit-conteudo">
    <h2>O que vem no kit</h2>
    <ul class="lista-check">
      <li><b>Planilha do PMOC</b> com identificação, ambientes (ar externo mínimo calculado sozinho), relação dos equipamentos e atividades de referência da Portaria 3.523/98.</li>
      <li><b>Cronograma anual</b> que marca sozinho os meses de cada atividade pela periodicidade.</li>
      <li><b>Registro mensal</b> de execução: o que foi feito, por quem, o que ficou não conforme e pendente.</li>
      <li><b>Calculadora de quanto cobrar</b> pelo contrato: horas, deslocamento, materiais, RT e margem.</li>
      <li><b>Checklist mensal em PDF</b> para imprimir e levar para o cliente.</li>
    </ul>
    <p class="kit-nota">Material de referência. Confirme o plano com um responsável técnico habilitado. Quer entender o PMOC antes? Leia <a href="/blog/pmoc-o-que-e-quem-precisa">o que é e quem precisa</a> e <a href="/blog/quanto-cobrar-pmoc">quanto cobrar</a>.</p>
  </div>

  <div class="formulario kit-form">
    <form id="kit-form" novalidate>
      <h2>Receba o kit agora</h2>
      <div class="campos">
        <div class="campo largo"><label for="kit-nome">Seu nome</label><input id="kit-nome" name="nome" autocomplete="name" required maxlength="80"></div>
        <div class="campo"><label for="kit-cidade">Cidade</label><input id="kit-cidade" name="cidade" autocomplete="address-level2" required maxlength="60"></div>
        <div class="campo"><label for="kit-zap">WhatsApp</label><input id="kit-zap" name="whatsapp" inputmode="tel" autocomplete="tel" required maxlength="20" placeholder="(45) 99999-9999"></div>
        <div class="campo largo"><label for="kit-equipe">Quantas pessoas trabalham em campo?</label>
          <select id="kit-equipe" name="equipe" required><option value="">Escolha</option><option>Só eu</option><option>2 a 3</option><option>4 a 10</option><option>Mais de 10</option></select></div>
      </div>
      <p class="kit-erro" id="kit-erro" hidden>Preencha nome, cidade, WhatsApp e o tamanho da equipe.</p>
      <button class="botao coral grande" type="submit">Quero o kit grátis</button>
      <p class="kit-privacidade">Usamos seus dados só para enviar o kit e falar sobre o ServPilot. Sem spam. <a href="/privacidade">Privacidade</a>.</p>
    </form>
    <div class="kit-pronto" id="kit-pronto" hidden>
      <h2>Pronto, é seu!</h2>
      <p>Baixe os arquivos abaixo. Se quiser, mande uma mensagem no WhatsApp que a gente tira suas dúvidas sobre PMOC.</p>
      <a class="botao coral grande" href="/modelos/Kit-PMOC-ServPilot.xlsx" download>Baixar a planilha (Excel)</a>
      <a class="botao grande kit-sec" href="/modelos/Checklist-mensal-PMOC-ServPilot.pdf" download>Baixar o checklist (PDF)</a>
      <a class="botao grande kit-sec" id="kit-zap-link" href="#" target="_blank" rel="noopener">Falar no WhatsApp</a>
    </div>
  </div>
</div></section>

<section class="secao"><div class="faixa kit-faq">
<h2>Perguntas frequentes</h2>
''' + ''.join(f'<h3>{e(p)}</h3>\n<p>{e(r)}</p>\n' for p, r in perguntas) + '''</div></section>
<script src="/modelo-pmoc.js" defer></script>
''' + CHAMADA + RODAPE
gravar('modelo-pmoc.html', pagina)
