# Gera as páginas de assunto e do blog do site ServPilot (cabeçalho, rodapé, SEO e dados estruturados iguais).
import json, html, os

SITE = 'https://servpilot.com.br'
OUT = os.path.join(os.path.dirname(__file__), 'servia-apps/site/public')

def e(t):
    return html.escape(t, quote=True)

def cabeca(titulo, descricao, caminho, jsonld, extra_css='conteudo.css', tipo='website'):
    blocos = ''.join(f'<script type="application/ld+json">{json.dumps(j, ensure_ascii=False)}</script>\n' for j in jsonld)
    return f'''<!doctype html>
<html lang="pt-BR" class="sem-js">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(titulo)}</title>
<meta name="description" content="{e(descricao)}">
<meta name="theme-color" content="#121A2B">
<link rel="canonical" href="{SITE}{caminho}">
<meta property="og:type" content="{tipo}">
<meta property="og:locale" content="pt_BR">
<meta property="og:site_name" content="ServPilot">
<meta property="og:title" content="{e(titulo)}">
<meta property="og:description" content="{e(descricao)}">
<meta property="og:url" content="{SITE}{caminho}">
<meta property="og:image" content="{SITE}/img/compartilhar.png">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="icon" type="image/png" href="/favicon-32.png">
<link rel="apple-touch-icon" href="/img/apple-touch-icon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/estilo.css">
<link rel="stylesheet" href="/{extra_css}">
{blocos}</head>
<body>

<a class="pular" href="#conteudo">Pular para o conteúdo</a>

<header class="topo" id="topo">
  <div class="faixa topo-dentro">
    <a href="/" class="marca" aria-label="ServPilot, início">
      <img class="marca-escura" src="/img/logo-escuro.svg" alt="ServPilot" width="150" height="40">
      <img class="marca-clara" src="/img/logo.svg" alt="" width="150" height="40">
    </a>
    <nav class="menu" aria-label="Seções">
      <a href="/sistema-para-refrigeracao">Para refrigeração</a>
      <a href="/software-pmoc">PMOC</a>
      <a href="/precos">Preços</a>
      <a href="/blog">Blog</a>
    </nav>
    <div class="topo-acoes">
      <a class="botao fantasma" href="https://painel.servpilot.com.br" rel="noopener">Entrar no painel</a>
      <a class="botao primario so-largo" href="/assinar">Testar 14 dias grátis</a>
    </div>
  </div>
</header>

<main id="conteudo">
'''

RODAPE = '''
</main>

<footer class="rodape">
  <div class="faixa rodape-dentro">
    <div>
      <img src="/img/logo-escuro.svg" alt="ServPilot" width="140" height="38">
      <p>Gestão inteligente de serviços de campo para refrigeração e climatização.</p>
    </div>
    <nav aria-label="Rodapé">
      <a href="/sistema-para-refrigeracao">Sistema para refrigeração</a>
      <a href="/software-pmoc">Software de PMOC</a>
      <a href="/app-tecnico-refrigeracao">App do técnico</a>
      <a href="/ordem-de-servico-ar-condicionado">Ordem de serviço</a>
      <a href="/precos">Preços</a>
      <a href="/blog">Blog</a>
      <a href="/termos">Termos de uso</a>
      <a href="/privacidade">Privacidade</a>
      <a href="#" data-cookies>Cookies</a> <a href="https://www.instagram.com/servpilot" target="_blank" rel="noopener">Instagram</a> <a href="https://www.tiktok.com/@servpilot" target="_blank" rel="noopener">TikTok</a> <a href="https://www.facebook.com/1345149045355955" target="_blank" rel="noopener">Facebook</a>
      <a href="mailto:contato@servpilot.com.br">contato@servpilot.com.br</a>
    </nav>
    <p class="direitos">© <span id="ano">2026</span> ServPilot. Todos os direitos reservados.</p>
  </div>
</footer>

<script src="/site.js" defer></script>
<script src="/rastreio.js" defer></script>
</body>
</html>
'''

ORG = {"@context": "https://schema.org", "@type": "Organization", "name": "ServPilot", "url": SITE,
       "logo": f"{SITE}/img/logo.svg", "email": "contato@servpilot.com.br",
       "legalName": "Ana DG Tecnologia da Informação Ltda", "taxID": "43.904.201/0001-26",
       "address": {"@type": "PostalAddress", "addressLocality": "São Miguel do Iguaçu", "addressRegion": "PR", "addressCountry": "BR"},
       "sameAs": ["https://www.instagram.com/servpilot", "https://www.tiktok.com/@servpilot", "https://www.facebook.com/1345149045355955"]}

APP = {"@context": "https://schema.org", "@type": "SoftwareApplication", "name": "ServPilot",
       "applicationCategory": "BusinessApplication", "applicationSubCategory": "Gestão de serviços de campo",
       "operatingSystem": "Android, Web", "url": SITE, "inLanguage": "pt-BR",
       "description": ("Sistema para empresas de refrigeração e climatização: ordens de serviço, quadro do dia das "
                       "equipes, app do técnico que funciona sem internet, relato por áudio com inteligência artificial, "
                       "orçamento com assinatura do cliente, preventivas e PMOC."),
       "offers": [{"@type": "Offer", "name": "Plano Autônomo", "price": "99.99", "priceCurrency": "BRL", "url": f"{SITE}/precos",
                   "description": "1 usuário, 300 minutos de IA e 250 mensagens; tudo incluso, inclusive PMOC; 14 dias grátis."},
                  {"@type": "Offer", "name": "Plano Equipe", "price": "199.00", "priceCurrency": "BRL", "url": f"{SITE}/precos",
                   "description": "Plano mensal com 2 usuários, 600 minutos de IA e 500 mensagens; usuário extra R$ 69/mês; 14 dias grátis."}],
       "publisher": {"@type": "Organization", "name": "ServPilot", "url": SITE}}

def faq_jsonld(perguntas):
    return {"@context": "https://schema.org", "@type": "FAQPage",
            "mainEntity": [{"@type": "Question", "name": p,
                            "acceptedAnswer": {"@type": "Answer", "text": r}} for p, r in perguntas]}

def migalhas(itens):
    return {"@context": "https://schema.org", "@type": "BreadcrumbList",
            "itemListElement": [{"@type": "ListItem", "position": i + 1, "name": n, "item": SITE + c}
                                for i, (n, c) in enumerate(itens)]}

def perguntas_html(perguntas):
    itens = ''.join(f'      <details class="revelar"><summary>{e(p)}</summary>\n        <p>{e(r)}</p></details>\n' for p, r in perguntas)
    return f'''<section class="secao clara" id="perguntas">
  <div class="faixa estreita">
    <div class="titulo-secao revelar"><p class="sobretitulo">Perguntas frequentes</p><h2>Dúvidas comuns</h2></div>
    <div class="perguntas">
{itens}    </div>
  </div>
</section>
'''

CHAMADA = '''<section class="chamada">
  <div class="faixa chamada-dentro revelar">
    <img src="/img/simbolo-escuro.svg" alt="" width="72" height="72" class="chamada-simbolo">
    <h2>Teste com a sua equipe, num serviço de verdade.</h2>
    <p>14 dias grátis, sem cartão. Depois, R$ 99,99 por mês para quem trabalha sozinho ou R$ 199 com 2 usuários, com preço aberto para o resto.</p>
    <div class="abertura-acoes centro">
      <a class="botao coral grande" href="/assinar">Começar o teste grátis</a>
      <a class="botao contorno-claro grande" href="/precos">Ver preços</a>
    </div>
  </div>
</section>
'''

def gravar(caminho_arquivo, conteudo):
    p = os.path.join(OUT, caminho_arquivo)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8') as f:
        f.write(conteudo)
    print('gravado', caminho_arquivo)
