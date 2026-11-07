from gerar_base import *

DATA = '2026-10-30'
ARTIGOS = []

def artigo(slug, titulo, descricao, tema, resumo, corpo, perguntas, data=DATA):
    caminho = f'/blog/{slug}'
    ARTIGOS.append((slug, titulo, descricao, tema, data))
    publicado = '/'.join(reversed(data.split('-')))
    post = {"@context": "https://schema.org", "@type": "BlogPosting", "headline": titulo, "description": descricao,
            "datePublished": data, "dateModified": data, "inLanguage": "pt-BR", "mainEntityOfPage": SITE + caminho,
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
<p class="meta" style="margin-top:28px">Publicado em {publicado} · ServPilot</p>
<div class="resumo"><b>Resumo:</b> {resumo}</div>
{corpo}
<h2>Perguntas frequentes</h2>
{faq}
<div class="artigo-chamada">
  <h3>Organize isso no ServPilot</h3>
  <p>OS no celular do técnico (mesmo sem internet), relato por áudio com IA, orçamento com assinatura e PMOC por aparelho. 14 dias grátis.</p>
  <a class="botao coral grande" href="/assinar">Testar 14 dias grátis</a>
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

# ================================================================= quanto cobrar PMOC
artigo('quanto-cobrar-pmoc',
  'Quanto cobrar por PMOC: como calcular o preço do contrato',
  'Como calcular o preço de um contrato de PMOC: horas por aparelho, deslocamento, materiais, responsável técnico e margem. Com exemplo de uma clínica com 12 aparelhos.',
  'PMOC',
  'não existe tabela oficial de preço de PMOC. O valor justo do contrato é a soma de cinco custos (horas de técnico, '
  'deslocamento, materiais, responsável técnico e documentação) mais a sua margem, dividida pelos 12 meses. Abaixo, o '
  'passo a passo e um exemplo de uma clínica com 12 aparelhos.',
  '''<h2>Por que não dá para copiar o preço do concorrente</h2>
<p>O PMOC não é uma limpeza de split: é um compromisso de 12 meses. Levantar o local, montar o plano, cumprir as
atividades no prazo, registrar tudo e entregar o relatório ao contratante. Dois prédios com o mesmo número de aparelhos
podem dar trabalhos muito diferentes:</p>
<ul>
  <li>um prédio térreo com os aparelhos acessíveis, ou outro com as condensadoras no telhado;</li>
  <li>um cliente a 5 km da sua base, ou outro a 60 km;</li>
  <li>splits de 9.000 BTU/h, ou cassetes e piso-teto, que tomam mais tempo por visita.</li>
</ul>
<p>Por isso o preço precisa sair da sua operação, não de uma tabela da internet.</p>

<h2>Passo 1: conte as horas por aparelho</h2>
<p>Liste os aparelhos e as atividades do plano para cada tipo (filtros, dreno, serpentina, medições) e estime quanto
tempo cada visita leva.</p>
<table>
  <tr><th>Aparelho</th><th>Visita mensal</th><th>Limpeza completa</th></tr>
  <tr><td>Split até 24.000 BTU/h</td><td>20 a 30 min</td><td>1h30 a 2h</td></tr>
  <tr><td>Cassete ou piso-teto</td><td>30 a 45 min</td><td>2h a 3h</td></tr>
  <tr><td>Equipamentos maiores</td><td>medir</td><td>medir</td></tr>
</table>
<p>Os tempos são uma referência para começar; os equipamentos maiores, meça no levantamento. Troque pelos seus depois das primeiras visitas.</p>

<h2>Passo 2: dê preço à hora do técnico</h2>
<p>A hora não é só o salário. Some salário, encargos, ferramentas, celular, uniforme e as horas que ninguém paga
(deslocamento, espera, retrabalho), e divida pelas horas realmente faturadas no mês. Um técnico que custa R$&nbsp;6.000 por
mês e fatura 120 horas sai a <b>R$&nbsp;50 por hora de custo</b>.</p>

<h2>Passo 3: some o deslocamento</h2>
<p>Para cada visita: quilômetros de ida e volta vezes o custo por km (combustível, desgaste e manutenção do veículo),
mais o tempo do técnico dirigindo. Contrato longe da base precisa mostrar isso no preço.</p>

<h2>Passo 4: materiais</h2>
<p>Filtros de reposição, produtos de limpeza, material de dreno e o que mais o plano prever. Deixe claro no contrato o
que está incluso e o que é cobrado à parte: peças e reparos corretivos quase sempre ficam fora do valor mensal.</p>

<h2>Passo 5: responsável técnico e documentação</h2>
<p>O PMOC é assinado por um responsável técnico habilitado, com a ART ou o documento equivalente do conselho dele.
Coloque no preço o custo da ART e do RT (se não for você) e as horas para montar o plano e o relatório mensal de
execução. É aqui que muita gente perde dinheiro: o relatório feito "de cabeça" toma uma noite inteira por cliente.</p>

<h2>Passo 6: margem e valor mensal</h2>
<p>Some tudo para os 12 meses, aplique a sua margem e divida por 12. Esse é o valor mensal do contrato.</p>

<h2>Exemplo: clínica com 12 splits, a 15 km da base</h2>
<p>Valores ilustrativos, só para mostrar a conta. Use os seus.</p>
<table>
  <tr><th>Item</th><th>Conta</th><th>Ano</th></tr>
  <tr><td>Visitas mensais</td><td>60 h (12 × 25 min × 12 meses) × R$&nbsp;50</td><td>R$&nbsp;3.000</td></tr>
  <tr><td>Limpezas completas (2 por ano)</td><td>42 h (12 × 1h45 × 2) × R$&nbsp;50</td><td>R$&nbsp;2.100</td></tr>
  <tr><td>Deslocamento</td><td>420 km × R$&nbsp;1,50 + 14 h × R$&nbsp;50</td><td>R$&nbsp;1.330</td></tr>
  <tr><td>Materiais</td><td>filtros e produtos (estimativa)</td><td>R$&nbsp;900</td></tr>
  <tr><td>RT, ART e documentação</td><td>ART + 12 h de relatório</td><td>R$&nbsp;900</td></tr>
  <tr><td><b>Custo total</b></td><td></td><td><b>R$&nbsp;8.230</b></td></tr>
  <tr><td>Com margem de 35%</td><td>R$&nbsp;8.230 ÷ 0,65</td><td>R$&nbsp;12.660</td></tr>
  <tr><td><b>Valor mensal do contrato</b></td><td>R$&nbsp;12.660 ÷ 12</td><td><b>R$&nbsp;1.055</b></td></tr>
</table>
<p>Neste exemplo, o contrato sai a cerca de <b>R$&nbsp;88 por aparelho por mês</b>. Se o prédio tiver condensadoras no
telhado ou ficar a 60 km, o número muda, e é justamente por isso que vale fazer a conta.</p>

<h2>Como cobrar melhor sem perder o cliente</h2>
<ol>
  <li><b>Mostre o que você entrega.</b> Relatório mensal por prédio, com fotos e não conformidades, vale mais do que
  "fiz a limpeza".</li>
  <li><b>Separe preventiva de corretiva.</b> O valor mensal cobre o plano; reparo e peça são orçados à parte, com a
  aprovação do cliente.</li>
  <li><b>Reajuste anual no contrato,</b> com o índice definido desde o início.</li>
  <li><b>Prazo de atendimento.</b> Atendimento de urgência em 24 horas pode ser um adicional.</li>
</ol>

<h2>Onde o tempo some, e como recuperar</h2>
<p>O maior custo escondido do PMOC é a papelada: montar o plano, lembrar das preventivas de cada mês e fazer o
relatório de execução. No <a href="/software-pmoc">ServPilot</a>, o técnico levanta os ambientes pelo app, as
atividades da Portaria 3.523/98 já vêm prontas por tipo de aparelho, as OS preventivas de cada mês nascem sozinhas e o
relatório do mês sai por prédio, pronto para entregar. Essa noite por cliente volta para a sua margem.</p>
<p>Para começar, baixe o <a href="/modelo-pmoc">Kit PMOC grátis</a>: planilha com o plano, cronograma, registro mensal e esta calculadora de preço, mais o checklist em PDF.</p>
<div class="aviso-legal">Os valores do exemplo são ilustrativos. Confirme as exigências do contratante, principalmente
em licitações, e a habilitação do responsável técnico no conselho dele.</div>''',
  [('Existe tabela oficial de preço de PMOC?', 'Não. O valor é livre e depende do número e do tipo de aparelhos, da distância e do que o contrato inclui.'),
   ('Cobro por aparelho ou por contrato?', 'Calcule pelo contrato e, se o cliente preferir, mostre o valor equivalente por aparelho. Assim o preço fecha nos dois formatos.'),
   ('Peças entram no valor mensal?', 'Normalmente não. Deixe claro no contrato que peças e reparos corretivos são orçados à parte, com aprovação do cliente.'),
   ('Quem pode ser o responsável técnico do PMOC?', 'Um profissional habilitado pelo seu conselho, com ART ou documento equivalente: engenheiros (CREA) e técnicos industriais de refrigeração e climatização (CFT), conforme as regras de cada conselho.')],
  data='2026-11-06')

# ================================================================= como escolher software de PMOC
artigo('software-pmoc-quanto-custa-como-escolher',
  'Software de PMOC: quanto custa e como escolher (checklist de 10 pontos)',
  'Quanto custa um sistema de PMOC e o que conferir antes de assinar: plano em PDF com RT e ART, preventivas automáticas, app sem internet, relatório mensal, preço aberto e teste grátis.',
  'PMOC',
  'os sistemas de PMOC no Brasil vão de planos grátis com limites até mais de R$ 500 por mês, e muitos nem mostram o preço no site. '
  'Mais importante que o valor é conferir se o sistema faz o PMOC inteiro: o plano em PDF com responsável técnico e ART, as preventivas que nascem sozinhas, '
  'o registro no celular (inclusive sem internet) e o relatório mensal para o contratante. Abaixo, os 10 pontos para comparar.',
  '''<h2>Quanto custa um software de PMOC</h2>
<p>Pesquisando os sistemas oferecidos para empresas de ar-condicionado em novembro de 2026, o mercado se divide em três faixas:</p>
<table>
  <tr><th>Faixa</th><th>O que costuma incluir</th></tr>
  <tr><td>Grátis a R$&nbsp;50/mês</td><td>Ordem de serviço e orçamento. O PMOC, quando existe, é simples ou fica em plano pago.</td></tr>
  <tr><td>R$&nbsp;80 a R$&nbsp;300/mês</td><td>OS, preventivas e PMOC para empresas pequenas, com limite de usuários.</td></tr>
  <tr><td>Acima de R$&nbsp;500/mês</td><td>Plataformas para equipes grandes, quase sempre com implantação paga e preço só por demonstração.</td></tr>
</table>
<p>Desconfie de dois extremos: o grátis que não entrega o documento do PMOC e o caro que não diz o preço. Se o site pede "fale com um consultor", o valor costuma vir com implantação e fidelidade.</p>

<h2>Os 10 pontos para conferir antes de assinar</h2>
<ol>
  <li><b>Gera o plano do PMOC em PDF?</b> Com identificação do local, ambientes, equipamentos, atividades, cronograma e espaço para assinaturas.</li>
  <li><b>Tem campo para o responsável técnico e a ART?</b> Sem isso, o documento não serve para o contratante.</li>
  <li><b>As preventivas nascem sozinhas?</b> O sistema deve gerar as visitas do mês pela periodicidade de cada atividade, sem alguém lembrar.</li>
  <li><b>As atividades vêm prontas por tipo de aparelho?</b> Split, cassete, self contained e câmara fria têm checklists diferentes.</li>
  <li><b>O app funciona sem internet?</b> Casa de máquinas, subsolo e zona rural não têm sinal. O registro precisa ficar no celular e subir depois.</li>
  <li><b>Tem etiqueta QR por aparelho?</b> O técnico lê a etiqueta e abre o histórico e o checklist do aparelho certo.</li>
  <li><b>Sai o relatório mensal por prédio?</b> O que foi feito, por quem, não conformidades e pendências. É o que o contratante cobra.</li>
  <li><b>O preço está no site?</b> Conta por usuário, por técnico ou por empresa? Tem taxa de implantação, fidelidade, cobrança por Pix?</li>
  <li><b>Dá para testar com um contrato de verdade?</b> Teste grátis sem cartão, com todos os recursos.</li>
  <li><b>Importa a sua planilha?</b> Se você já tem a lista de aparelhos do cliente, não deveria digitar tudo de novo.</li>
</ol>

<h2>Quanto o sistema precisa economizar para se pagar</h2>
<p>Faça a conta pela hora. Se montar o relatório do mês e organizar as preventivas toma 1 hora por cliente, e a sua hora custa R$&nbsp;50, um sistema de R$&nbsp;100 por mês se paga a partir do segundo contrato de PMOC. Veja <a href="/blog/quanto-cobrar-pmoc">como calcular o preço do contrato</a>.</p>

<h2>Onde o ServPilot se encaixa</h2>
<p>O <a href="/software-pmoc">ServPilot</a> faz o PMOC inteiro: levantamento dos ambientes pelo app, atividades da Portaria 3.523/98 por tipo de aparelho, RT e ART no documento em PDF, OS preventivas automáticas, etiqueta QR, app sem internet e relatório do mês por prédio. O técnico registra o atendimento falando no celular e a IA organiza a OS. O preço está no site: R$&nbsp;99,99 por mês para quem trabalha sozinho, com tudo incluso e 14 dias grátis.</p>
<p>Ainda no papel? Baixe o <a href="/modelo-pmoc">Kit PMOC grátis</a> com planilha e checklist.</p>
<div class="aviso-legal">Faixas de preço levantadas nos sites de sistemas de PMOC e ordem de serviço em novembro de 2026. Preços mudam; confira sempre na página de cada fornecedor.</div>''',
  [('Existe software de PMOC grátis?', 'Existem planos grátis, em geral com limite de aparelhos, usuários ou sem o documento completo do PMOC. Confira se o plano grátis gera o PDF com RT e ART e o relatório mensal.'),
   ('O software substitui o responsável técnico?', 'Não. O PMOC é assinado por um responsável técnico habilitado. O sistema organiza o plano, as visitas e os registros que ele assina.'),
   ('Preciso de internet no local do serviço?', 'Depende do sistema. Prefira um app que funcione sem sinal e sincronize depois, porque muitos aparelhos ficam em subsolos e casas de máquinas.'),
   ('Quanto custa o ServPilot?', 'O plano Autônomo custa R$ 99,99 por mês para 1 usuário, com PMOC incluso. O plano Equipe custa R$ 199 por mês com 2 usuários e R$ 69 por usuário a mais. São 14 dias grátis, sem cartão.')],
  data='2026-11-06')

# ================================================================= índice do blog
lista = ''.join(f'''  <a class="cartao-artigo revelar" href="/blog/{s}"><small>{e(t)}</small><h2>{e(ti)}</h2><p>{e(d)}</p></a>
''' for s, ti, d, t, _ in sorted(ARTIGOS, key=lambda a: a[4], reverse=True))
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
