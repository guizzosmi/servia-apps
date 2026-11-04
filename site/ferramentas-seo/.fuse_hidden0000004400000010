from gerar_base import *

def pagina(arquivo, caminho, titulo, descricao, trilha, h1, h1_destaque, lead, garantias, secoes, tabela, perguntas, veja):
    blocos = []
    for sec in secoes:
        cartoes = ''.join(
            f'      <div class="lp-bloco revelar"><h3>{e(t)}</h3><p>{e(p)}</p>'
            + (('<ul>' + ''.join(f'<li>{e(i)}</li>' for i in itens) + '</ul>') if itens else '') + '</div>\n'
            for t, p, itens in sec['cartoes'])
        blocos.append(f'''<section class="secao{' clara' if sec.get('clara') else ''}">
  <div class="faixa">
    <div class="titulo-secao revelar"><p class="sobretitulo">{e(sec['sobre'])}</p><h2>{e(sec['titulo'])}</h2>
      {f"<p>{e(sec['texto'])}</p>" if sec.get('texto') else ''}</div>
    <div class="lp-grade">
{cartoes}    </div>
  </div>
</section>
''')
    linhas = ''.join(f'        <tr><td>{e(a)}</td><td>{e(b)}</td></tr>\n' for a, b in tabela['linhas'])
    tab = f'''<section class="secao">
  <div class="faixa estreita">
    <div class="titulo-secao revelar"><p class="sobretitulo">{e(tabela['sobre'])}</p><h2>{e(tabela['titulo'])}</h2></div>
    <table class="lp-tabela revelar">
      <thead><tr><th>{e(tabela['col'][0])}</th><th>{e(tabela['col'][1])}</th></tr></thead>
      <tbody>
{linhas}      </tbody>
    </table>
    <div class="lp-cta"><a class="botao coral grande" href="/assinar">Testar 7 dias grátis</a>
      <a class="botao primario grande" href="/precos">Ver preços e simulador</a></div>
  </div>
</section>
'''
    veja_html = '<div class="faixa"><div class="lp-veja">' + ''.join(f'<a href="{c}">{e(n)}</a>' for n, c in veja) + '</div></div>\n'
    gar = ''.join(f'<li>{e(g)}</li>' for g in garantias)
    corpo = f'''<section class="abertura lp-abertura">
  <div class="abertura-fundo" aria-hidden="true"></div>
  <div class="faixa">
    <div class="abertura-texto">
      <p class="lp-trilha"><a href="/">ServPilot</a> › {e(trilha)}</p>
      <h1>{e(h1)} <span class="destaque">{e(h1_destaque)}</span></h1>
      <p class="lead">{e(lead)}</p>
      <div class="abertura-acoes">
        <a class="botao coral grande" href="/assinar">Testar 7 dias grátis</a>
        <a class="botao contorno-claro grande" href="/precos">Ver preços</a>
      </div>
      <ul class="abertura-garantias">{gar}</ul>
    </div>
  </div>
</section>
'''
    jsonld = [APP, faq_jsonld(perguntas), migalhas([('ServPilot', '/'), (trilha, caminho)])]
    html_ = (cabeca(titulo, descricao, caminho, jsonld) + corpo + ''.join(blocos) + tab
             + perguntas_html(perguntas) + veja_html + CHAMADA + RODAPE)
    gravar(arquivo, html_)

GAR = ['7 dias grátis, sem cartão', 'A partir de R$ 99,99/mês', 'Sem fidelidade', 'Funciona sem internet']

# ================================================================= sistema para refrigeração
pagina('sistema-para-refrigeracao.html', '/sistema-para-refrigeracao',
  'Sistema para empresa de refrigeração e ar-condicionado | ServPilot',
  'Sistema para empresas de refrigeração e climatização: ordem de serviço, app do técnico sem internet, relato por áudio com IA, orçamento com assinatura, PMOC e preventivas. 7 dias grátis.',
  'Sistema para refrigeração',
  'Sistema para empresas de refrigeração', 'e ar-condicionado.',
  'Feito para quem instala e mantém ar-condicionado e câmaras frias: a ordem de serviço nasce no escritório ou no '
  'celular do técnico, a equipe é programada num quadro do dia, o técnico fala o que fez e a IA escreve o relato, '
  'o cliente aprova o orçamento na hora e o PMOC sai organizado por aparelho.',
  GAR,
  [
    {'sobre': 'Do chamado ao serviço pago', 'titulo': 'Tudo o que a empresa de refrigeração precisa, num lugar só',
     'cartoes': [
       ('Ordens de serviço', 'Corretiva, preventiva, instalação. Cliente, local, equipamentos, histórico e garantia na mesma tela.', []),
       ('Quadro do dia das equipes', 'Arraste da fila para a equipe, defina a ordem e acompanhe ao vivo quem está em cada serviço.', []),
       ('App do técnico sem internet', 'Check-in, fotos, medições (pressão, corrente, temperatura), checklist e assinatura do cliente, mesmo sem sinal.', []),
       ('Relato por áudio com IA', 'O técnico fala do jeito dele; a IA organiza o relato, as peças e as medições, e ele confere antes de salvar.', []),
       ('Orçamento com aceite', 'Monte no local ou no escritório; o cliente aprova assinando na tela ou por link no WhatsApp.', []),
       ('PMOC e preventivas', 'Planos por aparelho, visitas geradas sozinhas, checklist com as atividades do PMOC e o histórico de cada equipamento.', []),
     ]},
    {'sobre': 'Para quem é', 'titulo': 'Feito para o dia a dia da refrigeração', 'clara': True,
     'cartoes': [
       ('Empresas de climatização', 'De 1 a dezenas de técnicos, com instalação, manutenção corretiva e contratos de preventiva.', []),
       ('Contratos de PMOC', 'Clínicas, escolas, lojas, escritórios e indústrias com sistemas que exigem plano de manutenção.', []),
       ('Refrigeração comercial', 'Câmaras frias, balcões e equipamentos de supermercados e restaurantes, com o histórico por aparelho.', []),
       ('Técnico autônomo que está crescendo', 'Comece com 2 usuários e adicione técnicos quando a equipe aumentar (R$ 69 por usuário).', []),
     ]},
  ],
  {'sobre': 'Comparação', 'titulo': 'Papel, WhatsApp e planilha x ServPilot', 'col': ['Hoje', 'Com o ServPilot'],
   'linhas': [
     ('OS no papel ou no bloco', 'OS digital com fotos, medições e assinatura, pronta para o cliente em PDF'),
     ('Programação pelo WhatsApp', 'Quadro do dia com a ordem dos serviços e o técnico vendo tudo no app'),
     ('Relato escrito no fim do dia (ou esquecido)', 'Relato falado no local e organizado pela IA'),
     ('Orçamento que demora a voltar', 'Aceite na hora, na tela, ou por link no WhatsApp'),
     ('PMOC numa planilha', 'Plano por aparelho, vencimentos e histórico no sistema'),
     ('"Quanto eu tenho para cobrar?"', 'Lista do que cobrar por cliente, com o texto da nota pronto'),
   ]},
  [
    ('Qual é o melhor sistema para empresa de refrigeração?',
     'O que atende o trabalho de campo: OS no celular que funciona sem internet, histórico por equipamento, PMOC e orçamento com aceite do cliente. O ServPilot foi feito para refrigeração e climatização e pode ser testado 7 dias grátis.'),
    ('Quanto custa um sistema para refrigeração?',
     'No ServPilot, o plano Autônomo custa R$ 99,99 por mês (1 usuário, 300 minutos de IA e 250 mensagens de WhatsApp) e o plano Equipe, R$ 199 por mês (2 usuários, 600 minutos e 500 mensagens; cada usuário a mais custa R$ 69). Os valores completos estão na página de preços.'),
    ('O app do técnico funciona sem internet?',
     'Sim. O app baixa o dia da equipe e registra check-in, fotos, medições, relato, orçamento e assinatura sem sinal; tudo sobe quando a conexão volta.'),
    ('Dá para fazer o PMOC no sistema?',
     'Sim. O ServPilot tem planos de preventiva e PMOC por aparelho, com as atividades padrão, os vencimentos e o histórico de cada equipamento.'),
    ('Preciso instalar alguma coisa no computador?',
     'Não. O painel do gestor funciona no navegador e o app do técnico é instalado pela loja do celular.'),
  ],
  [('Software de PMOC', '/software-pmoc'), ('App para técnico de refrigeração', '/app-tecnico-refrigeracao'),
   ('Ordem de serviço para ar-condicionado', '/ordem-de-servico-ar-condicionado'), ('Preços', '/precos'), ('Blog', '/blog')])

# ================================================================= software de PMOC
pagina('software-pmoc.html', '/software-pmoc',
  'Software de PMOC para ar-condicionado | ServPilot',
  'Software de PMOC: plano por aparelho, atividades padrão, visitas geradas sozinhas, checklist no app do técnico, fotos e histórico de cada equipamento. Teste 7 dias grátis.',
  'Software de PMOC',
  'Software de PMOC', 'que se organiza sozinho.',
  'Cadastre os aparelhos do cliente, escolha as atividades do plano e o ServPilot gera as visitas no prazo, '
  'leva o checklist para o celular do técnico e guarda o que foi feito em cada equipamento, com fotos.',
  GAR,
  [
    {'sobre': 'Como funciona', 'titulo': 'Do cadastro do aparelho ao histórico do PMOC',
     'cartoes': [
       ('Plano por cliente e local', 'Responsável técnico, equipamentos do local e a periodicidade de cada atividade.', []),
       ('Atividades padrão', 'Biblioteca com as atividades mais usadas no PMOC (limpeza de filtros, bandeja e dreno, serpentinas, verificações elétricas), editável.', []),
       ('Visitas no prazo', 'O sistema gera as OS de preventiva na janela certa e avisa o que está vencendo ou vencido.', []),
       ('Checklist no celular', 'O técnico marca feito, não conforme ou não se aplica, com foto, mesmo sem internet.', []),
       ('Etiqueta QR no aparelho', 'O técnico lê a etiqueta e abre o equipamento certo, com o histórico.', []),
       ('Histórico por equipamento', 'O que foi feito, quando e por quem, para mostrar ao cliente e à fiscalização.', []),
     ]},
    {'sobre': 'Por que importa', 'titulo': 'PMOC organizado é contrato renovado', 'clara': True,
     'texto': 'A Lei 13.589/2018 exige PMOC nos edifícios de uso público e coletivo com ar interior climatizado. Quem presta o serviço precisa provar o que fez.',
     'cartoes': [
       ('Para a empresa de climatização', 'Nada de esquecer visita: os vencimentos aparecem na tela inicial, por aparelho.', []),
       ('Para o cliente', 'Relatório com as atividades, fotos e assinatura, entregue pelo WhatsApp.', []),
     ]},
  ],
  {'sobre': 'Resumo', 'titulo': 'O que o software de PMOC do ServPilot faz', 'col': ['Recurso', 'Como funciona'],
   'linhas': [
     ('Plano por aparelho', 'Cada equipamento com o próprio vencimento e histórico'),
     ('Atividades', 'Padrão do PMOC, com periodicidade e foto obrigatória quando você quiser'),
     ('Geração das visitas', 'Automática, na janela do período, com continuação se faltou aparelho'),
     ('Execução', 'Checklist no app do técnico, sem internet'),
     ('Comprovação', 'Relatório com atividades, fotos, data e assinatura do cliente'),
     ('Preço', 'Incluso nos dois planos (a partir de R$ 99,99/mês), sem módulo à parte'),
   ]},
  [
    ('O que é um software de PMOC?',
     'É um sistema que organiza o Plano de Manutenção, Operação e Controle: os equipamentos, as atividades de cada um, os prazos, a execução e o histórico, no lugar de planilhas e papel.'),
    ('O PMOC é obrigatório?',
     'A Lei 13.589/2018 tornou o PMOC obrigatório para edifícios de uso público e coletivo com ar interior climatizado artificialmente. Os detalhes técnicos seguem a Portaria 3.523/98 do Ministério da Saúde e as normas da ANVISA e da ABNT.'),
    ('O ServPilot assina o PMOC?',
     'Não. O PMOC é assinado pelo responsável técnico habilitado. O ServPilot organiza o plano, as visitas, o checklist e o histórico.'),
    ('O software de PMOC é pago à parte?',
     'Não. Preventivas e PMOC fazem parte do plano do ServPilot, a partir de R$ 99,99 por mês.'),
  ],
  [('Sistema para refrigeração', '/sistema-para-refrigeracao'), ('O que é PMOC (blog)', '/blog/pmoc-o-que-e-quem-precisa'),
   ('Checklist de preventiva', '/blog/checklist-manutencao-preventiva-ar-condicionado'), ('Preços', '/precos')])

# ================================================================= app do técnico
pagina('app-tecnico-refrigeracao.html', '/app-tecnico-refrigeracao',
  'App para técnico de refrigeração: OS no celular, sem internet | ServPilot',
  'App para técnico de refrigeração e ar-condicionado: parte do dia, check-in, fotos, medições, relato por áudio com IA, orçamento e assinatura do cliente, mesmo sem internet.',
  'App para técnico de refrigeração',
  'App para técnico de refrigeração:', 'o técnico fala, a OS se escreve.',
  'No telhado, na casa de máquinas ou no subsolo sem sinal: o app do ServPilot funciona offline e envia tudo quando a '
  'internet volta. O técnico grava o relato falando e a IA organiza peças, medições e o texto da OS.',
  ['Android (iPhone em breve)', 'Funciona sem internet', 'Login por matrícula e PIN', '7 dias grátis'],
  [
    {'sobre': 'No celular do técnico', 'titulo': 'Do "a caminho" à assinatura do cliente',
     'cartoes': [
       ('Parte do dia', 'Os serviços da equipe em ordem, com endereço, contato e instruções de acesso.', []),
       ('A caminho e check-in', 'Aviso ao cliente pelo WhatsApp e registro de quem entrou no serviço.', []),
       ('Relato por áudio', 'Até 10 minutos de fala; a IA transforma em relato, peças, medições e mão de obra.', []),
       ('Medições e fotos', 'Pressão, corrente, tensão, temperatura e fluido, com fotos de antes e depois.', []),
       ('Orçamento e assinatura', 'Monta o orçamento no local e o cliente assina na tela do celular.', []),
       ('Sem internet', 'Tudo fica no celular, criptografado, e sobe sozinho quando a conexão volta.', []),
     ]},
  ],
  {'sobre': 'Resumo', 'titulo': 'O que o técnico faz pelo app', 'col': ['Momento', 'No app do ServPilot'],
   'linhas': [
     ('Antes de sair', 'Vê a parte do dia e a ordem dos serviços'),
     ('No caminho', '"A caminho": o cliente recebe o aviso'),
     ('No local', 'Check-in, equipamento pela etiqueta QR, fotos e medições'),
     ('Relato', 'Fala; a IA escreve e ele confere'),
     ('Fechamento', 'Orçamento ou conclusão com a assinatura do cliente'),
   ]},
  [
    ('Qual o melhor aplicativo para técnico de refrigeração?',
     'Um que funcione sem internet, registre fotos e medições e não obrigue o técnico a digitar muito. No ServPilot, o técnico fala o relato e a IA preenche a OS.'),
    ('O app funciona no iPhone?',
     'O app é para Android e a versão para iPhone está a caminho. O painel do gestor funciona no navegador, em qualquer computador ou celular.'),
    ('O técnico precisa de e-mail para entrar?',
     'Não. O técnico entra com o código da empresa, a matrícula e um PIN de 6 números.'),
  ],
  [('Sistema para refrigeração', '/sistema-para-refrigeracao'), ('Ordem de serviço para ar-condicionado', '/ordem-de-servico-ar-condicionado'),
   ('Software de PMOC', '/software-pmoc'), ('Preços', '/precos')])

# ================================================================= ordem de serviço
pagina('ordem-de-servico-ar-condicionado.html', '/ordem-de-servico-ar-condicionado',
  'Ordem de serviço para ar-condicionado e refrigeração | ServPilot',
  'Ordem de serviço digital para ar-condicionado: cliente, local, equipamentos, medições, fotos, peças, relato e assinatura, com PDF para o cliente e o que cobrar. Teste grátis.',
  'Ordem de serviço para ar-condicionado',
  'Ordem de serviço para ar-condicionado', 'completa, sem papel.',
  'Cada OS do ServPilot já nasce com o cliente, o local e os equipamentos, e volta do campo com o relato, as medições, '
  'as peças, as fotos e a assinatura. O relatório vai para o cliente pelo WhatsApp e o valor entra no "a cobrar".',
  GAR,
  [
    {'sobre': 'O que vai na OS', 'titulo': 'Uma OS de refrigeração que não deixa nada de fora',
     'cartoes': [
       ('Cliente, local e contato', 'Endereço, instruções de acesso e quem acompanha o serviço.', []),
       ('Equipamentos', 'Marca, modelo, capacidade, fluido e o histórico de cada aparelho.', []),
       ('Medições', 'Pressões, correntes, tensões e temperaturas do tipo do equipamento.', []),
       ('Peças e mão de obra', 'Do catálogo, com preço e desconto, ou fora dele quando a empresa permitir.', []),
       ('Fotos e relato', 'Antes e depois, e o relato falado pelo técnico e organizado pela IA.', []),
       ('Assinatura e PDF', 'Assinatura do cliente na tela e o relatório em PDF pelo WhatsApp.', []),
     ]},
  ],
  {'sobre': 'Modelo', 'titulo': 'Os campos de uma boa OS de ar-condicionado', 'col': ['Campo', 'Por que importa'],
   'linhas': [
     ('Tipo (corretiva, preventiva, instalação)', 'Define o checklist e a garantia'),
     ('Problema relatado', 'O que o cliente disse, para conferir no fim'),
     ('Equipamentos atendidos', 'Histórico por aparelho e PMOC'),
     ('Medições', 'Prova técnica do serviço e base para o próximo atendimento'),
     ('Peças, serviços e valores', 'O que cobrar, sem esquecer nada'),
     ('Assinatura do cliente', 'Comprova a execução e o aceite'),
   ]},
  [
    ('Como fazer uma ordem de serviço de ar-condicionado?',
     'Registre o cliente, o local, os equipamentos e o problema; no atendimento, inclua as medições, as peças, as fotos, o relato e a assinatura do cliente. No ServPilot, o técnico preenche pelo celular e o relato pode ser falado.'),
    ('Tem modelo de OS de ar-condicionado?',
     'O ServPilot já traz a OS com os campos de refrigeração (equipamento, capacidade, fluido, medições e checklist) e gera o PDF para o cliente.'),
    ('A OS digital tem validade?',
     'A OS registra data, hora, quem fez e a assinatura do cliente, e serve como comprovante do serviço prestado. Para valores altos, use também o aceite do orçamento.'),
  ],
  [('Sistema para refrigeração', '/sistema-para-refrigeracao'), ('O que não pode faltar na OS (blog)', '/blog/ordem-de-servico-refrigeracao'),
   ('App do técnico', '/app-tecnico-refrigeracao'), ('Preços', '/precos')])
