from gerar_base import *

DATA = '2026-10-30'
ARTIGOS = []

def artigo(slug, titulo, descricao, tema, resumo, corpo, perguntas):
    caminho = f'/blog/{slug}'
    ARTIGOS.append((slug, titulo, descricao, tema))
    post = {"@context": "https://schema.org", "@type": "BlogPosting", "headline": titulo, "description": descricao,
            "datePublished": DATA, "dateModified": DATA, "inLanguage": "pt-BR", "mainEntityOfPage": SITE + caminho,
            "image": f"{SITE}/img/compartilhar.png",
            "author": {"@type": "Organization", "name": "ServPilot", "url": SITE},
            "publisher": {"@type": "Organization", "name": "ServPilot", "logo": {"@type": "ImageObject", "url": f"{SITE}/img/logo.svg"}}}
    jsonld = [post, faq_jsonld(perguntas), migalhas([('ServPilot', '/'), ('Blog', '/blog'), (titulo, caminho)])]
    faq = ''.join(f'<h3>{e(p)}</h3>\n<p>{e(r)}</p>\n' for p, r in perguntas)
    pagina = cabeca(f'{titulo} | ServPilot', descricao, caminho, jsonld, tipo='article') + f'''<section class="abertura lp-abertura">
  <div class="abertura-fundo" aria-hidden="true"></div>
  <div class="faixa"><div class="abertura-texto">
    <p class="lp-trilha"><a href="/">ServPilot</a> › <a href="/blog">Blog</a> › {e(tema)}</p>
    <h1>{e(titulo)}</h1>
  </div></div>
</section>
<article class="artigo">
<p class="meta" style="margin-top:28px">Publicado em 30/10/2026 · ServPilot</p>
<div class="resumo"><b>Resumo:</b> {resumo}</div>
{corpo}
<h2>Perguntas frequentes</h2>
{faq}
<div class="artigo-chamada">
  <h3>Organize isso no ServPilot</h3>
  <p>OS no celular do técnico (mesmo sem internet), relato por áudio com IA, orçamento com assinatura e PMOC por aparelho. 7 dias grátis.</p>
  <a class="botao coral grande" href="/assinar">Testar 7 dias grátis</a>
</div>
</article>
''' + RODAPE
    gravar(f'blog/{slug}.html', pagina)

# ================================================================= PMOC
artigo('pmoc-o-que-e-quem-precisa',
  'PMOC: o que é, quem precisa e como organizar',
  'O que é o PMOC (Plano de Manutenção, Operação e Controle), quem é obrigado pela Lei 13.589/2018, o que o plano deve conter e como organizar as visitas e o histórico por aparelho.',
  'PMOC',
  'o PMOC é o Plano de Manutenção, Operação e Controle dos sistemas de ar-condicionado. A Lei 13.589/2018 o tornou obrigatório '
  'nos edifícios de uso público e coletivo com ar climatizado artificialmente. Ele lista os equipamentos, as atividades de '
  'manutenção e a periodicidade de cada uma, e é assinado por um responsável técnico habilitado.',
  '''<h2>O que é o PMOC</h2>
<p>PMOC é a sigla de <b>Plano de Manutenção, Operação e Controle</b>. É o documento que define como os sistemas de
climatização de um edifício são mantidos para garantir a qualidade do ar interior: quais equipamentos existem, quais
atividades de limpeza e verificação são feitas em cada um, com que frequência, e quem é o responsável técnico.</p>

<h2>Quem é obrigado a ter PMOC</h2>
<p>A <b>Lei 13.589, de 4 de janeiro de 2018</b>, determina que os edifícios de uso público e coletivo que possuem
ambientes de ar interior climatizado artificialmente disponham de um PMOC. Na prática, isso alcança escritórios, lojas,
shoppings, clínicas, hospitais, escolas, academias, hotéis, restaurantes e prédios públicos, entre outros.</p>
<p>Os detalhes técnicos vêm da <b>Portaria 3.523/1998 do Ministério da Saúde</b>, que fala em plano de manutenção para
sistemas com capacidade acima de 5 TR (60.000 BTU/h), das orientações da ANVISA sobre a qualidade do ar interior e das
normas técnicas da ABNT.</p>
<div class="aviso-legal">Este texto é informativo. Confirme o enquadramento de cada edifício com um responsável técnico
habilitado e com a vigilância sanitária da sua cidade.</div>

<h2>O que o PMOC deve conter</h2>
<ul>
  <li>Identificação do edifício, do proprietário ou responsável e do responsável técnico;</li>
  <li>Relação dos ambientes climatizados e dos equipamentos (tipo, marca, modelo, capacidade);</li>
  <li>As atividades de manutenção de cada equipamento e a periodicidade (mensal, trimestral, semestral, anual);</li>
  <li>O registro das execuções: o que foi feito, quando e por quem;</li>
  <li>As recomendações para falhas e emergências.</li>
</ul>

<h2>Quem pode ser o responsável técnico</h2>
<p>O PMOC é assinado por um profissional habilitado pelo seu conselho: engenheiros (CREA) e, desde 2019, também técnicos
industriais de refrigeração e climatização (CFT), conforme as regras de cada conselho.</p>

<h2>Como organizar o PMOC no dia a dia</h2>
<p>O desafio da empresa de climatização não é escrever o plano, é <b>cumprir</b>: lembrar das visitas de dezenas de
aparelhos, levar o checklist certo para o técnico e guardar a prova do que foi feito. O que funciona:</p>
<ol>
  <li><b>Cadastrar cada aparelho</b> com local, ambiente, capacidade e fluido, e colar uma etiqueta QR;</li>
  <li><b>Definir as atividades</b> e a periodicidade de cada uma, por tipo de equipamento;</li>
  <li><b>Gerar as visitas</b> com antecedência, dentro da janela do período;</li>
  <li><b>Executar pelo checklist</b> no celular, com foto, marcando feito, não conforme ou não se aplica;</li>
  <li><b>Guardar o histórico por aparelho</b> e entregar ao cliente o relatório com fotos e assinatura.</li>
</ol>
<p>Num <a href="/software-pmoc">software de PMOC</a> como o ServPilot, os passos 3 a 5 acontecem sozinhos: as visitas
nascem no prazo, o checklist vai para o app do técnico e o histórico fica pronto para mostrar ao cliente.</p>''',
  [
    ('PMOC é obrigatório para residência?', 'A Lei 13.589/2018 trata de edifícios de uso público e coletivo. Residências não são o foco da lei, mas a manutenção preventiva continua recomendada pelos fabricantes.'),
    ('Qual é a multa por não ter PMOC?', 'O descumprimento é infração sanitária, sujeita às penalidades da Lei 6.437/1977, aplicadas pela vigilância sanitária conforme a gravidade e o porte do estabelecimento.'),
    ('De quanto em quanto tempo o PMOC é executado?', 'Cada atividade tem a sua periodicidade, definida no plano conforme o equipamento, o uso do ambiente, o manual do fabricante e as normas.'),
  ])

# ================================================================= checklist
artigo('checklist-manutencao-preventiva-ar-condicionado',
  'Checklist de manutenção preventiva de ar-condicionado',
  'Checklist prático de manutenção preventiva de ar-condicionado split e sistemas comerciais: limpeza, verificações elétricas, medições e o que registrar na ordem de serviço.',
  'Manutenção preventiva',
  'a preventiva bem feita junta limpeza (filtros, serpentinas, bandeja e dreno), verificações elétricas e mecânicas e '
  '<b>medições registradas</b> (pressões, correntes, tensão e temperaturas). Sem registro, não há como comparar com a '
  'visita anterior nem provar o serviço ao cliente.',
  '''<h2>Antes de começar</h2>
<ul>
  <li>Confirme o equipamento certo (etiqueta QR, número de série ou ambiente) e veja o histórico da última visita;</li>
  <li>Desligue o equipamento e o disjuntor antes de abrir;</li>
  <li>Fotografe o estado inicial (filtros, serpentinas, bandeja).</li>
</ul>

<h2>Unidade interna (evaporadora)</h2>
<table>
  <tr><th>Item</th><th>O que fazer</th></tr>
  <tr><td>Filtros de ar</td><td>Retirar, lavar ou trocar; conferir se não estão rasgados</td></tr>
  <tr><td>Serpentina</td><td>Limpar com produto adequado; verificar aletas amassadas</td></tr>
  <tr><td>Bandeja e dreno</td><td>Limpar, desobstruir e testar o escoamento; aplicar bactericida se previsto no plano</td></tr>
  <tr><td>Turbina e motor do ventilador</td><td>Limpar; verificar ruído, folga e fixação</td></tr>
  <tr><td>Gabinete e grelhas</td><td>Limpeza externa e fixação</td></tr>
</table>

<h2>Unidade externa (condensadora)</h2>
<table>
  <tr><th>Item</th><th>O que fazer</th></tr>
  <tr><td>Serpentina</td><td>Limpar; retirar folhas e sujeira; checar obstruções ao redor</td></tr>
  <tr><td>Ventilador</td><td>Verificar hélice, ruído e fixação</td></tr>
  <tr><td>Compressor</td><td>Verificar ruído, vibração e aquecimento anormal</td></tr>
  <tr><td>Tubulação e isolamento</td><td>Isolamento térmico íntegro; sinais de óleo (vazamento)</td></tr>
  <tr><td>Suportes</td><td>Fixação, corrosão e nivelamento</td></tr>
</table>

<h2>Parte elétrica e comando</h2>
<ul>
  <li>Reapertar conexões e verificar sinais de aquecimento;</li>
  <li>Medir a <b>tensão</b> de alimentação e a <b>corrente</b> do compressor e dos ventiladores;</li>
  <li>Testar controle remoto, termostato e sensores.</li>
</ul>

<h2>Medições para registrar</h2>
<table>
  <tr><th>Medição</th><th>Para quê</th></tr>
  <tr><td>Pressão de sucção e de descarga</td><td>Avaliar a carga de fluido e o funcionamento do ciclo</td></tr>
  <tr><td>Corrente (A) e tensão (V)</td><td>Detectar sobrecarga e problemas elétricos</td></tr>
  <tr><td>Temperatura de insuflamento e de retorno</td><td>Avaliar o desempenho (diferencial de temperatura)</td></tr>
</table>
<p>Compare sempre com a visita anterior e com os valores do fabricante. A recarga de fluido só deve ser feita com o
diagnóstico de vazamento resolvido.</p>

<h2>O que registrar na ordem de serviço</h2>
<ul>
  <li>Cada item do checklist como feito, não conforme ou não se aplica;</li>
  <li>As medições, com unidade;</li>
  <li>Fotos de antes e depois;</li>
  <li>Peças trocadas e recomendações ao cliente;</li>
  <li>A assinatura de quem acompanhou.</li>
</ul>
<p>No <a href="/app-tecnico-refrigeracao">app do técnico do ServPilot</a>, esse checklist vem do plano do aparelho, as
medições ficam no tipo do equipamento e o técnico pode falar o relato, que a IA organiza.</p>''',
  [
    ('Com que frequência fazer a preventiva do ar-condicionado?', 'Depende do uso e do ambiente. Em ambientes de uso coletivo, o PMOC define a periodicidade de cada atividade; os filtros costumam ser os itens mais frequentes. Siga também o manual do fabricante.'),
    ('O que é medido na manutenção preventiva?', 'Normalmente pressões de sucção e descarga, corrente, tensão e as temperaturas de insuflamento e retorno, comparadas com a visita anterior.'),
    ('Preciso registrar a preventiva?', 'Sim. O registro com data, medições e fotos é a prova do serviço para o cliente e, nos casos de PMOC, para a fiscalização.'),
  ])

# ================================================================= OS
artigo('ordem-de-servico-refrigeracao',
  'Ordem de serviço de refrigeração: o que não pode faltar',
  'Os campos essenciais de uma ordem de serviço de refrigeração e ar-condicionado, do chamado à assinatura do cliente, e como evitar retrabalho e serviço sem cobrar.',
  'Ordem de serviço',
  'uma boa OS de refrigeração tem o cliente e o local certos, os equipamentos atendidos, o problema relatado, o que foi '
  'feito, as medições, as peças e a mão de obra, as fotos e a assinatura do cliente. É isso que evita retrabalho, '
  'discussão de garantia e serviço esquecido na hora de cobrar.',
  '''<h2>1. Cliente, local e contato</h2>
<p>Endereço completo, instruções de acesso (portaria, chave, horário) e quem acompanha o serviço. Em clientes com
várias lojas, o local certo evita a viagem perdida.</p>

<h2>2. Tipo e problema relatado</h2>
<p>Corretiva, preventiva ou instalação, e o que o cliente disse com as palavras dele. No fim, o técnico confere se
resolveu exatamente isso.</p>

<h2>3. Equipamentos atendidos</h2>
<p>Marca, modelo, capacidade, fluido e um código (de preferência numa etiqueta QR). Sem isso, não existe histórico por
aparelho nem PMOC.</p>

<h2>4. O que foi feito e as medições</h2>
<p>O relato do técnico e as medições do tipo do equipamento: pressões, correntes, tensão e temperaturas. Relato ruim é
o maior motivo de retrabalho; por isso o ServPilot deixa o técnico <b>falar</b> o relato, e a IA organiza.</p>

<h2>5. Peças, serviços e valores</h2>
<p>Cada peça e cada serviço com quantidade e preço. Se for preciso orçamento, o cliente aprova antes da execução.</p>

<h2>6. Fotos</h2>
<p>Antes e depois: protegem a empresa em discussões de garantia e mostram o valor do serviço ao cliente.</p>

<h2>7. Assinatura e entrega</h2>
<p>A assinatura de quem acompanhou, com data e hora, e o relatório entregue ao cliente (em PDF ou por link).</p>

<h2>8. Depois da OS: cobrar</h2>
<p>OS concluída com valor precisa virar cobrança. Uma lista do "a cobrar" por cliente evita o serviço feito e esquecido.</p>

<p>Veja como a <a href="/ordem-de-servico-ar-condicionado">ordem de serviço para ar-condicionado do ServPilot</a>
junta tudo isso, do escritório ao celular do técnico.</p>''',
  [
    ('Ordem de serviço digital vale como comprovante?', 'Sim, como registro do serviço: tem data, hora, quem fez, o que foi feito e a assinatura do cliente. Para orçamentos de valor alto, guarde também o aceite.'),
    ('Qual a diferença entre OS e orçamento?', 'O orçamento é a proposta que o cliente aprova antes; a OS é o registro do serviço executado.'),
  ])

# ================================================================= índice do blog
lista = ''.join(f'''  <a class="cartao-artigo revelar" href="/blog/{s}"><small>{e(t)}</small><h2>{e(ti)}</h2><p>{e(d)}</p></a>
''' for s, ti, d, t in ARTIGOS)
indice = cabeca('Blog do ServPilot: refrigeração, PMOC e gestão de serviços',
                'Artigos práticos para empresas de refrigeração e climatização: PMOC, manutenção preventiva, ordem de serviço e gestão das equipes.',
                '/blog', [ORG, migalhas([('ServPilot', '/'), ('Blog', '/blog')])]) + f'''<section class="abertura lp-abertura">
  <div class="abertura-fundo" aria-hidden="true"></div>
  <div class="faixa"><div class="abertura-texto">
    <p class="lp-trilha"><a href="/">ServPilot</a> › Blog</p>
    <h1>Blog do <span class="destaque">ServPilot</span></h1>
    <p class="lead">Conteúdo prático para quem vive de refrigeração e climatização: PMOC, preventiva, ordem de serviço e equipe.</p>
  </div></div>
</section>
<section class="secao clara"><div class="faixa">
<div class="lista-artigos">
{lista}</div>
</div></section>
''' + CHAMADA + RODAPE
gravar('blog/index.html', indice)
