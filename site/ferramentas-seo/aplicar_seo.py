# Ajusta as páginas que já existem no site (rodar na pasta servia-apps/site do computador).
import json, re, sys
sys.path.insert(0, sys.argv[1] if len(sys.argv) > 1 else '.')
from gerar_base import APP, ORG

def editar(p, trocas, opcional=False):
    s = open(p, encoding='utf-8').read()
    for v, n in trocas:
        if n in s:
            continue
        c = s.count(v)
        if c != 1:
            if opcional:
                print(f'AVISO {p}: trecho não encontrado, pulei (me avise): {v[:70]}')
                continue
            raise SystemExit(f'{p}: esperado 1, achei {c}: {v[:70]}')
        s = s.replace(v, n)
    open(p, 'w', encoding='utf-8', newline='').write(s)
    print('ok', p)

LD = lambda j: f'<script type="application/ld+json">{json.dumps(j, ensure_ascii=False)}</script>\n'
SCRIPTS = '<script src="/site.js" defer></script>'
RASTREIO = '<script src="/site.js" defer></script>\n<script src="/rastreio.js" defer></script>'

editar('public/index.html', [
  ('<title>ServPilot · Gestão inteligente de serviços de campo</title>',
   '<title>ServPilot · Sistema para empresas de refrigeração e ar-condicionado</title>'),
  ('<meta property="og:title" content="ServPilot · Gestão inteligente de serviços de campo">',
   '<meta property="og:title" content="ServPilot · Sistema para empresas de refrigeração e ar-condicionado">'),
  ('<link rel="stylesheet" href="/estilo.css">\n</head>',
   '<link rel="stylesheet" href="/estilo.css">\n<link rel="stylesheet" href="/conteudo.css">\n' + LD(ORG) + LD(APP) + '</head>'),
  ('      <a href="/precos">Preços</a>\n    </nav>\n    <div class="topo-acoes">',
   '      <a href="/precos">Preços</a>\n      <a href="/blog">Blog</a>\n    </nav>\n    <div class="topo-acoes">'),
  ('      <a href="/privacidade">Privacidade</a>\n    </nav>',
   '      <a href="/sistema-para-refrigeracao">Sistema para refrigeração</a>\n      <a href="/software-pmoc">Software de PMOC</a>\n'
   '      <a href="/blog">Blog</a>\n      <a href="/privacidade">Privacidade</a>\n      <a href="#" data-cookies>Cookies</a>\n    </nav>'),
  (SCRIPTS, RASTREIO),
])
editar('public/precos.html', [
  ('<link rel="stylesheet" href="/precos.css">\n</head>',
   '<link rel="stylesheet" href="/precos.css">\n<link rel="stylesheet" href="/conteudo.css">\n' + LD(APP) + '</head>'),
  ('      <a href="/privacidade">Privacidade</a>\n    </nav>',
   '      <a href="/blog">Blog</a>\n      <a href="/privacidade">Privacidade</a>\n      <a href="#" data-cookies>Cookies</a>\n    </nav>'),
  (SCRIPTS, RASTREIO),
])
editar('public/assinar.html', [
  ('<link rel="stylesheet" href="/precos.css">\n</head>',
   '<link rel="stylesheet" href="/precos.css">\n<link rel="stylesheet" href="/conteudo.css">\n</head>'),
  (SCRIPTS, RASTREIO),
])
editar('public/assinar.js', [
  ("      $('sucesso').classList.add('ver');\n",
   "      $('sucesso').classList.add('ver');\n"
   "      if (window.ServPilotRastreio) window.ServPilotRastreio.evento('cadastro');   // conversão (guia 48)\n"),
])

# Privacidade: as ferramentas de medição e anúncios (só com o aceite dos cookies).
editar('public/privacidade.html', [
  ('</table>\n<p>Não vendemos dados pessoais.',
   '  <tr><td>Google Analytics e Google Ads</td><td>Medir as visitas ao site e os anúncios, só se a pessoa aceitar os cookies</td></tr>\n'
   '  <tr><td>Meta (Facebook e Instagram) e TikTok</td><td>Medir os anúncios nessas redes, só se a pessoa aceitar os cookies</td></tr>\n'
   '</table>\n<p>Não vendemos dados pessoais.'),
], opcional=True)

# CSP: Google Analytics, Google Ads, Meta e TikTok (só carregam depois do aceite dos cookies).
p = 'firebase.json'
s = open(p, encoding='utf-8').read()
if 'googletagmanager' not in s:
    s = s.replace("script-src 'self' https://www.youtube.com;",
                  "script-src 'self' https://www.youtube.com https://www.googletagmanager.com https://connect.facebook.net https://www.googleadservices.com https://googleads.g.doubleclick.net;")
    s = s.replace("img-src 'self' data: https://i.ytimg.com;",
                  "img-src 'self' data: https://i.ytimg.com https://www.googletagmanager.com https://*.google-analytics.com https://www.google.com https://www.google.com.br https://*.doubleclick.net https://www.facebook.com;")
    s = s.replace("frame-src https://www.youtube-nocookie.com https://www.youtube.com;",
                  "frame-src https://www.youtube-nocookie.com https://www.youtube.com https://www.googletagmanager.com https://td.doubleclick.net https://www.facebook.com;")
    s = s.replace("connect-src 'self' https://srtokvosnwtyewiempyw.supabase.co;",
                  "connect-src 'self' https://srtokvosnwtyewiempyw.supabase.co https://*.google-analytics.com https://*.analytics.google.com https://www.googletagmanager.com https://www.google.com https://*.doubleclick.net https://www.facebook.com https://connect.facebook.net;")
    assert s.count('googletagmanager') == 4, 'CSP: alguma parte não foi encontrada'
if 'analytics.tiktok.com' not in s:
    for diretiva in ('script-src', 'connect-src', 'img-src'):
        i = s.index(diretiva + " 'self'")
        f = s.index(';', i)
        s = s[:f] + ' https://analytics.tiktok.com' + s[f:]
    assert s.count('analytics.tiktok.com') == 3, 'CSP: TikTok não entrou'
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok', p)
