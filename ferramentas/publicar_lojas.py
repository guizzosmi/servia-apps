#!/usr/bin/env python3
"""ServPilot - publica o app do técnico nas lojas (guia 110).

Quem chama é a esteira dos apps (esteira-apps.ps1, na raiz do projeto). Dá para rodar à mão também:

    py -3 publicar_lojas.py play-conferir --conta C:\\dev\\chaves\\play-conta-servico.json --pacote br.com.servpilot.app

Comandos:
  play-conferir         confere a conta de serviço e mostra o maior número de build (versionCode) já enviado à Play
  play-publicar         envia o .aab e cria a versão na faixa (internal, alpha, beta ou production) com as notas
  codemagic-conferir    confere o token e acha o ID do app no Codemagic (grava no apps-deploy.json se estiver vazio)
  codemagic-disparar    inicia o build do iPhone (o workflow do codemagic.yaml, na branch pedida)
  codemagic-acompanhar  acompanha o build até terminar e diz se foi para o App Store Connect

Segredos: a chave da conta de serviço do Google Play e o token do Codemagic ficam em C:\\dev\\chaves (fora do Git).
Este script só os lê para autenticar: nunca os imprime nem os grava em outro lugar.

As linhas que começam com @@ são para a esteira ler (ex.: @@VERSION_CODE_MAX=21).

Dependências: google-auth e requests (a esteira instala com  py -3 -m pip install --user google-auth requests).
Testes: py -3 -m unittest test_publicar_lojas (nesta pasta; não precisam de internet nem das chaves).
"""

import argparse
import json
import os
import sys
import time

API_PLAY = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications'
UPLOAD_PLAY = 'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications'
ESCOPO_PLAY = 'https://www.googleapis.com/auth/androidpublisher'
API_CODEMAGIC = 'https://api.codemagic.io'

FAIXAS = {
    'internal': 'teste interno',
    'alpha': 'teste fechado',
    'beta': 'teste aberto',
    'production': 'produção',
}
LIMITE_NOTAS = 500  # a Play aceita até 500 caracteres por idioma

# Situações do build no Codemagic (docs.codemagic.io/yaml-running-builds/build-statuses).
SITUACOES = {
    'initializing': 'criando o build',
    'queued': 'na fila (outro build da equipe está rodando)',
    'waiting': 'esperando uma máquina',
    'preparing': 'preparando o Mac',
    'fetching': 'baixando o código do GitHub',
    'testing': 'rodando testes',
    'building': 'compilando',
    'publishing': 'publicando (App Store Connect)',
    'finishing': 'terminando',
    'finished': 'terminou com sucesso',
    'failed': 'falhou',
    'canceled': 'cancelado',
    'timeout': 'passou do tempo máximo do workflow',
    'skipped': 'não rodou',
}
FINAIS = {'finished', 'failed', 'canceled', 'timeout', 'skipped'}


class ErroLoja(Exception):
    """Erro com a mensagem pronta para o dono (vai para a tela e para o problemas.txt)."""

    def __init__(self, mensagem, transitorio=False):
        super().__init__(mensagem)
        self.transitorio = transitorio


class ErroAppRascunho(ErroLoja):
    """A Play só aceita versões em rascunho enquanto o app nunca foi publicado."""


def dizer(texto=''):
    print(texto, flush=True)


def marcar(chave, valor):
    print('@@%s=%s' % (chave, valor), flush=True)


def chamar(sessao, metodo, url, contexto, **kw):
    """Faz a chamada HTTP e traduz as falhas de conexão/autenticação em ErroLoja."""
    try:
        return sessao.request(metodo, url, **kw)
    except Exception as e:  # noqa: BLE001 - qualquer falha da biblioteca vira mensagem para o dono
        nome = type(e).__name__
        if nome == 'RefreshError':
            raise ErroLoja(
                '%s: o Google recusou a chave da conta de serviço (%s). A chave foi apagada ou é de outra conta? '
                'Gere uma chave nova e grave por cima do arquivo (guia 110, Parte 1.3).' % (contexto, str(e)[:200]))
        raise ErroLoja('%s: falha de conexão (%s). Confira a internet e rode de novo.' % (contexto, nome),
                       transitorio=True)


def mensagem_da_resposta(resp):
    try:
        corpo = resp.json()
    except Exception:  # noqa: BLE001
        return (getattr(resp, 'text', '') or '')[:300]
    if isinstance(corpo, dict):
        erro = corpo.get('error')
        if isinstance(erro, dict):
            return str(erro.get('message') or erro)
        if erro:
            return str(erro)
        if corpo.get('message'):
            return str(corpo['message'])
    return str(corpo)[:300]


# ------------------------------------------------------------------ Google Play

def sessao_google(arquivo_conta):
    """Sessão autenticada com a conta de serviço. Devolve (sessao, e-mail da conta)."""
    if not os.path.isfile(arquivo_conta):
        raise ErroLoja('Não achei a chave da conta de serviço do Google Play: %s (guia 110, Parte 1).' % arquivo_conta)
    try:
        from google.auth.transport.requests import AuthorizedSession
        from google.oauth2 import service_account
    except ImportError:
        raise ErroLoja('Falta o pacote google-auth: rode  py -3 -m pip install --user google-auth requests')
    try:
        cred = service_account.Credentials.from_service_account_file(arquivo_conta, scopes=[ESCOPO_PLAY])
    except Exception:  # noqa: BLE001 - não mostra o conteúdo do arquivo
        raise ErroLoja('O arquivo %s não é uma chave de conta de serviço válida (JSON). Baixe de novo no Google Cloud '
                       '(guia 110, Parte 1.3).' % arquivo_conta)
    return AuthorizedSession(cred), cred.service_account_email


def erro_play(resp, contexto, email=''):
    msg = mensagem_da_resposta(resp)
    baixo = msg.lower()
    codigo = resp.status_code
    if 'only releases with status draft' in baixo:
        return ErroAppRascunho('%s: HTTP %s - %s' % (contexto, codigo, msg))
    if 'has not been used in project' in baixo or 'is disabled' in baixo or 'service_disabled' in baixo:
        dica = ('A "Google Play Android Developer API" não está ativada no projeto do Google Cloud da conta de serviço: '
                'ative (guia 110, Parte 1.1) e espere uns minutos.')
    elif 'version code' in baixo and 'already' in baixo:
        dica = ('Este número de build (versionCode) já foi usado na Play: rode a esteira de novo e aceite subir o build '
                '(ou use -SubirBuild).')
    elif 'signed with the wrong key' in baixo or 'wrong key' in baixo or 'different key' in baixo:
        dica = ('O .aab foi assinado com outra chave, não a chave de upload da Play: confira o storeFile do '
                'app\\android\\key.properties (guia 41).')
    elif 'debug' in baixo and 'sign' in baixo:
        dica = ('O .aab saiu assinado com a chave de depuração: falta o app\\android\\key.properties ou o .jks '
                '(guia 41).')
    elif codigo == 401:
        dica = 'O Google recusou a chave da conta de serviço: gere uma chave nova (guia 110, Parte 1.3).'
    elif codigo == 403 or 'permission' in baixo:
        dica = ('A conta de serviço %s não tem permissão neste app no Play Console: Usuários e permissões > Convidar '
                'novos usuários, com as permissões de lançar versões (guia 110, Parte 1.4). Se acabou de convidar, '
                'pode levar algumas horas para valer.' % (email or '(e-mail do JSON)'))
    elif codigo == 404 or 'package not found' in baixo:
        dica = ('O app não foi achado: confira o "pacote" no apps-deploy.json (br.com.servpilot.app) e se a conta de '
                'serviço foi convidada para este app.')
    else:
        dica = ''
    texto = '%s: HTTP %s - %s' % (contexto, codigo, msg)
    if dica:
        texto += '\n' + dica
    return ErroLoja(texto, transitorio=codigo >= 500)


class Play:
    def __init__(self, sessao, pacote, email=''):
        self.sessao = sessao
        self.pacote = pacote
        self.email = email

    def _url(self, *partes):
        return '/'.join([API_PLAY, self.pacote] + list(partes))

    def _chamar(self, metodo, url, contexto, **kw):
        kw.setdefault('timeout', 120)
        resp = chamar(self.sessao, metodo, url, contexto, **kw)
        if resp.status_code >= 400:
            raise erro_play(resp, contexto, self.email)
        return resp

    def abrir_edicao(self):
        resp = self._chamar('POST', self._url('edits'), 'Abrir a edição na Play', json={})
        return resp.json()['id']

    def apagar_edicao(self, edicao):
        """Sem efeito na loja: só descarta a edição (melhor esforço)."""
        try:
            chamar(self.sessao, 'DELETE', self._url('edits', edicao), 'Descartar a edição', timeout=60)
        except ErroLoja:
            pass

    def maior_version_code(self, edicao):
        codigos = [0]
        corpo = self._chamar('GET', self._url('edits', edicao, 'bundles'), 'Listar os .aab da Play').json()
        codigos += [int(b['versionCode']) for b in corpo.get('bundles', []) if 'versionCode' in b]
        corpo = self._chamar('GET', self._url('edits', edicao, 'apks'), 'Listar os .apk da Play').json()
        codigos += [int(a['versionCode']) for a in corpo.get('apks', []) if 'versionCode' in a]
        corpo = self._chamar('GET', self._url('edits', edicao, 'tracks'), 'Listar as faixas da Play').json()
        for faixa in corpo.get('tracks', []):
            for versao in faixa.get('releases', []) or []:
                codigos += [int(c) for c in versao.get('versionCodes', []) or []]
        return max(codigos)

    def enviar_bundle(self, edicao, caminho_aab):
        with open(caminho_aab, 'rb') as f:
            dados = f.read()
        url = '/'.join([UPLOAD_PLAY, self.pacote, 'edits', edicao, 'bundles'])
        resp = self._chamar('POST', url, 'Enviar o .aab', params={'uploadType': 'media'}, data=dados,
                            headers={'Content-Type': 'application/octet-stream'}, timeout=(30, 1800))
        return int(resp.json()['versionCode'])

    def atualizar_faixa(self, edicao, faixa, versao):
        self._chamar('PUT', self._url('edits', edicao, 'tracks', faixa), 'Criar a versão na faixa %s' % faixa,
                     json={'track': faixa, 'releases': [versao]})

    def confirmar(self, edicao):
        """Confirma a edição (commit). Devolve True se foi para a revisão/publicação, False se ficou para enviar
        pelo Play Console (changesNotSentForReview)."""
        url = self._url('edits', edicao + ':commit')
        resp = chamar(self.sessao, 'POST', url, 'Confirmar a edição', timeout=120)
        if resp.status_code < 400:
            return True
        msg = mensagem_da_resposta(resp)
        if 'changesnotsentforreview' in msg.lower().replace('_', ''):
            resp = chamar(self.sessao, 'POST', url, 'Confirmar a edição', params={'changesNotSentForReview': 'true'},
                          timeout=120)
            if resp.status_code < 400:
                return False
        raise erro_play(resp, 'Confirmar a edição', self.email)


def ler_notas(arquivo):
    """Notas da versão: o arquivo inteiro, sem as linhas que começam com #."""
    if not os.path.isfile(arquivo):
        raise ErroLoja('Não achei as notas da versão: %s. Escreva o que mudou (até %d caracteres).'
                       % (arquivo, LIMITE_NOTAS))
    with open(arquivo, encoding='utf-8-sig') as f:
        linhas = [linha.rstrip() for linha in f if not linha.lstrip().startswith('#')]
    texto = '\n'.join(linhas).strip()
    if not texto:
        raise ErroLoja('As notas da versão estão vazias: %s. Escreva o que mudou (até %d caracteres).'
                       % (arquivo, LIMITE_NOTAS))
    if len(texto) > LIMITE_NOTAS:
        raise ErroLoja('As notas da versão têm %d caracteres; a Play aceita até %d. Encurte o %s.'
                       % (len(texto), LIMITE_NOTAS, arquivo))
    return texto


def fracao_rollout(valor):
    """Aceita 20 (porcento) ou 0.2. 100 (ou 1) = todos."""
    v = float(valor)
    if v > 1:
        v = v / 100.0
    if v <= 0 or v > 1:
        raise ErroLoja('Rollout inválido: %s. Use de 1 a 100 (porcento).' % valor)
    return round(v, 4)


def montar_versao(version_code, nome, notas, idioma, faixa, rollout=1.0):
    versao = {'name': nome, 'versionCodes': [str(version_code)], 'status': 'completed'}
    if notas:
        versao['releaseNotes'] = [{'language': idioma, 'text': notas}]
    if faixa == 'production' and rollout < 1:
        versao['status'] = 'inProgress'
        versao['userFraction'] = rollout
    return versao


def play_conferir(args):
    sessao, email = _sessao_google(args.conta)
    play = Play(sessao, args.pacote, email)
    dizer('Conta de serviço: %s' % email)
    edicao = play.abrir_edicao()
    try:
        maior = play.maior_version_code(edicao)
    finally:
        play.apagar_edicao(edicao)
    dizer('Acesso ao app %s na Play: OK. Maior número de build já enviado: %s' % (args.pacote, maior or 'nenhum'))
    marcar('VERSION_CODE_MAX', maior)
    return 0


def play_publicar(args):
    if args.faixa not in FAIXAS:
        raise ErroLoja('Faixa inválida: %s (use %s).' % (args.faixa, ', '.join(FAIXAS)))
    if not os.path.isfile(args.aab):
        raise ErroLoja('Não achei o .aab: %s (o flutter build appbundle rodou?).' % args.aab)
    rollout = fracao_rollout(args.rollout_pct) if args.faixa == 'production' else 1.0
    notas = ler_notas(args.notas)
    sessao, email = _sessao_google(args.conta)
    play = Play(sessao, args.pacote, email)
    dizer('Conta de serviço: %s' % email)
    edicao = play.abrir_edicao()
    try:
        tamanho = os.path.getsize(args.aab) / (1024 * 1024)
        dizer('Enviando o .aab (%.1f MB; pode levar alguns minutos)...' % tamanho)
        codigo = play.enviar_bundle(edicao, args.aab)
        dizer('  a Play recebeu o build %s' % codigo)
        if args.version_code and codigo != args.version_code:
            raise ErroLoja('O .aab enviado tem o build %s, mas o pubspec diz %s: rode a esteira de novo (o .aab é '
                           'refeito).' % (codigo, args.version_code))
        nome = args.nome or str(codigo)
        versao = montar_versao(codigo, nome, notas, args.idioma, args.faixa, rollout)
        rascunho = False
        try:
            play.atualizar_faixa(edicao, args.faixa, versao)
        except ErroAppRascunho:
            # App que ainda não foi publicado: a Play só aceita a versão como rascunho.
            versao = montar_versao(codigo, nome, notas, args.idioma, args.faixa)
            versao['status'] = 'draft'
            play.atualizar_faixa(edicao, args.faixa, versao)
            rascunho = True
        enviado = play.confirmar(edicao)
    except Exception:
        play.apagar_edicao(edicao)
        raise
    alvo = '%s (%s)' % (args.faixa, FAIXAS[args.faixa])
    if rascunho:
        dizer('Versão %s criada como RASCUNHO na faixa %s: a Play só aceita rascunho enquanto o app não foi publicado. '
              'Termine no Play Console > %s > Editar versão > Revisar > Iniciar lançamento.'
              % (nome, alvo, FAIXAS[args.faixa]))
        marcar('PLAY_RASCUNHO', 1)
    elif versao['status'] == 'inProgress':
        dizer('Versão %s publicada em produção para %d%% dos usuários (lançamento gradual). Para ampliar: Play Console > '
              'Produção > Aumentar lançamento.' % (nome, round(rollout * 100)))
    else:
        dizer('Versão %s publicada na faixa %s.' % (nome, alvo))
    if not enviado:
        dizer('ATENÇÃO: a Play não deixou mandar para a revisão automaticamente. Abra o Play Console > Visão geral da '
              'publicação > Enviar alterações para revisão.')
        marcar('PLAY_REVISAO_MANUAL', 1)
    marcar('PLAY_VERSION_CODE', codigo)
    return 0


# ------------------------------------------------------------------ Codemagic

def ler_token(arquivo):
    if not os.path.isfile(arquivo):
        raise ErroLoja('Não achei o token da API do Codemagic: %s (guia 110, Parte 2).' % arquivo)
    with open(arquivo, encoding='utf-8-sig') as f:
        token = f.read().strip()
    if not token or len(token.split()) != 1:
        raise ErroLoja('O arquivo %s deve ter só o token do Codemagic, numa linha (guia 110, Parte 2).' % arquivo)
    return token


def link_build(app_id, build_id):
    return 'https://codemagic.io/app/%s/build/%s' % (app_id, build_id)


def erro_codemagic(resp, contexto):
    msg = mensagem_da_resposta(resp)
    codigo = resp.status_code
    if codigo in (401, 403):
        dica = ('O Codemagic recusou o token: copie de novo em Codemagic > Account settings > API token > Show e '
                'grave por cima do arquivo (guia 110, Parte 2).')
    elif codigo == 404:
        dica = ('Não achado: confira o appId no apps-deploy.json (rode a esteira com a opção "Achar o ID do app no '
                'Codemagic").')
    else:
        dica = ''
    texto = '%s: HTTP %s - %s' % (contexto, codigo, msg)
    if dica:
        texto += '\n' + dica
    return ErroLoja(texto, transitorio=codigo >= 500 or codigo == 429)


class Codemagic:
    def __init__(self, token, sessao=None):
        if sessao is None:
            import requests
            sessao = requests.Session()
        self.sessao = sessao
        self._cabecalho = {'x-auth-token': token, 'Content-Type': 'application/json'}

    def _chamar(self, metodo, caminho, contexto, **kw):
        resp = chamar(self.sessao, metodo, API_CODEMAGIC + caminho, contexto, headers=self._cabecalho, timeout=60,
                      **kw)
        if resp.status_code >= 400:
            raise erro_codemagic(resp, contexto)
        return resp

    def apps(self):
        return self._chamar('GET', '/apps', 'Listar os apps do Codemagic').json().get('applications', []) or []

    def disparar(self, app_id, workflow, branch):
        corpo = {'appId': app_id, 'workflowId': workflow, 'branch': branch}
        return self._chamar('POST', '/builds', 'Iniciar o build no Codemagic', json=corpo).json()['buildId']

    def build(self, build_id):
        corpo = self._chamar('GET', '/builds/%s' % build_id, 'Consultar o build').json()
        if isinstance(corpo, dict):
            for chave in ('build', 'data'):
                if isinstance(corpo.get(chave), dict):
                    return corpo[chave]
        return corpo


def gravar_app_id(arquivo_config, app_id):
    with open(arquivo_config, encoding='utf-8-sig') as f:
        config = json.load(f)
    config.setdefault('ios', {})['appId'] = app_id
    with open(arquivo_config, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(config, f, ensure_ascii=False, indent=2)
        f.write('\n')


def codemagic_conferir(args):
    cm = _codemagic(ler_token(args.token))
    apps = cm.apps()
    dizer('Token do Codemagic: OK (%d app(s) na conta).' % len(apps))
    lista = '\n'.join('  %s  ->  appId %s' % (a.get('appName', '?'), a.get('_id', '?')) for a in apps)
    if args.app_id:
        achado = [a for a in apps if a.get('_id') == args.app_id]
        if not achado:
            raise ErroLoja('O appId %s do apps-deploy.json não está na conta do token. Apps que o token vê:\n%s'
                           % (args.app_id, lista or '  (nenhum)'))
        dizer('App no Codemagic: %s (appId %s).' % (achado[0].get('appName', '?'), args.app_id))
        marcar('CODEMAGIC_APP_ID', args.app_id)
        return 0
    nome = (args.nome or '').lower()
    achados = [a for a in apps if (a.get('appName') or '').lower() == nome]
    if len(achados) != 1:
        raise ErroLoja('Não consegui escolher o app "%s" no Codemagic (%d com esse nome). Copie o appId certo para o '
                       '"appId" do apps-deploy.json. Apps que o token vê:\n%s'
                       % (args.nome, len(achados), lista or '  (nenhum)'))
    app_id = achados[0]['_id']
    if args.config:
        gravar_app_id(args.config, app_id)
        dizer('Achei o app "%s": appId %s (gravado em %s).' % (args.nome, app_id, args.config))
    else:
        dizer('Achei o app "%s": appId %s.' % (args.nome, app_id))
    marcar('CODEMAGIC_APP_ID', app_id)
    return 0


def codemagic_disparar(args):
    if not args.app_id:
        raise ErroLoja('Falta o appId do Codemagic no apps-deploy.json (guia 110, Parte 2.3).')
    cm = _codemagic(ler_token(args.token))
    build_id = cm.disparar(args.app_id, args.workflow, args.branch)
    dizer('Build do iPhone iniciado no Codemagic (workflow %s, branch %s).' % (args.workflow, args.branch))
    dizer('Acompanhe em: %s' % link_build(args.app_id, build_id))
    marcar('CODEMAGIC_BUILD_ID', build_id)
    marcar('CODEMAGIC_LINK', link_build(args.app_id, build_id))
    return 0


def _acoes(build):
    acoes = build.get('buildActions') or build.get('actions') or []
    return [a for a in acoes if isinstance(a, dict)]


def _e_publicacao(acao):
    nome = (acao.get('name') or '').lower()
    return acao.get('type') == 'publishing' or 'publish' in nome or 'app store connect' in nome


def acompanhar(cm, app_id, build_id, limite_min=90.0, intervalo_s=30.0, dormir=time.sleep, agora=time.monotonic):
    """Acompanha até o fim. Devolve 0 (foi para o App Store Connect), 1 (falhou) ou 3 (passou do tempo limite)."""
    link = link_build(app_id, build_id)
    inicio = agora()
    ultimo_status = None
    ultimo_aviso = inicio
    falhas_seguidas = 0
    build = {}
    while True:
        try:
            build = cm.build(build_id)
            falhas_seguidas = 0
        except ErroLoja as e:
            if e.transitorio and falhas_seguidas < 5:
                falhas_seguidas += 1
                dizer('  (sem resposta do Codemagic; tento de novo em %d s)' % intervalo_s)
                dormir(intervalo_s)
                continue
            raise
        status = str(build.get('status') or '?').lower()
        minutos = (agora() - inicio) / 60.0
        if status != ultimo_status:
            dizer('  %s  %s: %s' % (time.strftime('%H:%M'), status, SITUACOES.get(status, '')))
            ultimo_status = status
            ultimo_aviso = agora()
        elif agora() - ultimo_aviso >= 300:
            dizer('  ... ainda %s (%d min)' % (status, minutos))
            ultimo_aviso = agora()
        if status in FINAIS:
            break
        if minutos >= limite_min:
            dizer('O build não terminou em %d minutos: ele continua no Codemagic. Acompanhe em %s' % (limite_min, link))
            marcar('CODEMAGIC_STATUS', status)
            return 3
        dormir(intervalo_s)

    marcar('CODEMAGIC_STATUS', status)
    acoes = _acoes(build)
    indice = build.get('index')
    if status != 'finished':
        falhas = [a for a in acoes if str(a.get('status', '')).lower() in ('failed', 'failure', 'error', 'timeout')]
        dizer('O build do iPhone %s.' % SITUACOES.get(status, status))
        for a in falhas:
            dizer('  passo com problema: %s (%s)' % (a.get('name', '?'), a.get('status')))
        if build.get('message'):
            dizer('  mensagem: %s' % build['message'])
        dizer('Veja o log em %s' % link)
        return 1
    publicacoes = [a for a in acoes if _e_publicacao(a)]
    ruins = [a for a in publicacoes if str(a.get('status', '')).lower() not in ('success', 'finished', 'succeeded')]
    if ruins:
        dizer('O build compilou, mas a publicação no App Store Connect não deu certo:')
        for a in ruins:
            dizer('  %s: %s' % (a.get('name', '?'), a.get('status')))
        dizer('Veja o log em %s' % link)
        marcar('CODEMAGIC_APP_STORE', 'falhou')
        return 1
    for art in build.get('artefacts') or build.get('artifacts') or []:
        if isinstance(art, dict) and str(art.get('name', '')).endswith('.ipa'):
            versao = art.get('versionName') or art.get('version_name') or ''
            dizer('  .ipa: %s %s' % (art.get('name'), ('(versão %s)' % versao) if versao else ''))
    numero = (' Número do build no TestFlight: %d (100 + execução %s).' % (100 + int(indice), indice)
              if isinstance(indice, int) else '')
    if publicacoes:
        dizer('O build do iPhone foi enviado ao App Store Connect.%s' % numero)
        marcar('CODEMAGIC_APP_STORE', 'enviado')
    else:
        dizer('O build do iPhone terminou.%s O codemagic.yaml envia para o App Store Connect; confira no TestFlight.'
              % numero)
        marcar('CODEMAGIC_APP_STORE', 'confira')
    dizer('A Apple processa o build (em geral 10 a 30 minutos) e ele aparece no TestFlight para o grupo de teste '
          'interno. Link do build: %s' % link)
    return 0


def codemagic_acompanhar(args):
    cm = _codemagic(ler_token(args.token))
    return acompanhar(cm, args.app_id, args.build_id, args.limite_min, args.intervalo_s)


# Pontos de troca para os testes (sessões falsas, sem internet).
_sessao_google = sessao_google


def _codemagic(token):
    return Codemagic(token)


def criar_parser():
    p = argparse.ArgumentParser(description='ServPilot - publica o app nas lojas (guia 110).')
    sub = p.add_subparsers(dest='comando', required=True)

    s = sub.add_parser('play-conferir')
    s.add_argument('--conta', required=True, help='JSON da conta de serviço')
    s.add_argument('--pacote', required=True)
    s.set_defaults(funcao=play_conferir)

    s = sub.add_parser('play-publicar')
    s.add_argument('--conta', required=True)
    s.add_argument('--pacote', required=True)
    s.add_argument('--aab', required=True)
    s.add_argument('--faixa', default='internal')
    s.add_argument('--notas', required=True, help='arquivo de texto com as notas da versão')
    s.add_argument('--idioma', default='pt-BR')
    s.add_argument('--rollout-pct', default='100', help='só produção: porcento dos usuários (1 a 100)')
    s.add_argument('--nome', default='', help='nome da versão na Play, ex.: "0.21.0 (22)"')
    s.add_argument('--version-code', type=int, default=0, help='o build esperado (confere com o .aab)')
    s.set_defaults(funcao=play_publicar)

    s = sub.add_parser('codemagic-conferir')
    s.add_argument('--token', required=True, help='arquivo com o token da API')
    s.add_argument('--app-id', default='')
    s.add_argument('--nome', default='servia-apps', help='nome do app no Codemagic, para achar o appId')
    s.add_argument('--config', default='', help='apps-deploy.json para gravar o appId achado')
    s.set_defaults(funcao=codemagic_conferir)

    s = sub.add_parser('codemagic-disparar')
    s.add_argument('--token', required=True)
    s.add_argument('--app-id', required=True)
    s.add_argument('--workflow', default='ios-testflight')
    s.add_argument('--branch', default='main')
    s.set_defaults(funcao=codemagic_disparar)

    s = sub.add_parser('codemagic-acompanhar')
    s.add_argument('--token', required=True)
    s.add_argument('--app-id', required=True)
    s.add_argument('--build-id', required=True)
    s.add_argument('--limite-min', type=float, default=90)
    s.add_argument('--intervalo-s', type=float, default=30)
    s.set_defaults(funcao=codemagic_acompanhar)
    return p


def main(argv=None):
    args = criar_parser().parse_args(argv)
    try:
        return args.funcao(args)
    except ErroLoja as e:
        dizer('ERRO: %s' % e)
        return 1
    except KeyboardInterrupt:
        dizer('Interrompido.')
        return 130


if __name__ == '__main__':
    sys.exit(main())
