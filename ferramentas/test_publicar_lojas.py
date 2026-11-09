"""Testes do publicar_lojas.py com respostas falsas do Google Play e do Codemagic (sem internet, sem chaves).

Rodar nesta pasta:  py -3 -m unittest test_publicar_lojas -v
"""

import contextlib
import io
import json
import os
import tempfile
import unittest
from unittest import mock

import publicar_lojas as pl

TOKEN_FALSO = 'tok-FALSO-123'
EMAIL = 'esteira@projeto-ficticio.iam.gserviceaccount.com'


class Resposta:
    def __init__(self, status=200, corpo=None, texto=''):
        self.status_code = status
        self._corpo = corpo
        self.text = texto or (json.dumps(corpo) if corpo is not None else '')

    def json(self):
        if self._corpo is None:
            raise ValueError('sem json')
        return self._corpo


def erro_google(status, mensagem):
    return Resposta(status, {'error': {'code': status, 'message': mensagem, 'status': 'X'}})


class SessaoFalsa:
    """Responde por (método, trecho da URL), na ordem; guarda as chamadas."""

    def __init__(self, regras):
        self.regras = [list(r) for r in regras]  # [metodo, trecho, resposta_ou_lista]
        self.chamadas = []

    def request(self, metodo, url, **kw):
        self.chamadas.append((metodo, url, kw))
        for regra in self.regras:
            if regra[0] == metodo and regra[1] in url:
                resp = regra[2]
                if isinstance(resp, list):
                    resp = resp.pop(0) if len(resp) > 1 else resp[0]
                if isinstance(resp, Exception):
                    raise resp
                return resp
        raise AssertionError('chamada inesperada: %s %s' % (metodo, url))

    def metodos(self):
        return [(m, u.split('/applications/')[-1]) for m, u, _ in self.chamadas]


def rodar(argv):
    saida = io.StringIO()
    with contextlib.redirect_stdout(saida):
        codigo = pl.main(argv)
    return codigo, saida.getvalue()


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.aab = self.arquivo('app-release.aab', b'PK-aab-falso')
        self.notas = self.arquivo('notas.txt', '# comentário\nLer etiqueta na tela Hoje.\n\n# outro\nBusca de aparelhos.\n'
                                  .encode('utf-8'))
        self.conta = self.arquivo('conta.json', b'{}')
        self.token = self.arquivo('token.txt', (TOKEN_FALSO + '\r\n').encode('utf-8'))

    def arquivo(self, nome, conteudo):
        caminho = os.path.join(self.tmp.name, nome)
        with open(caminho, 'wb') as f:
            f.write(conteudo)
        return caminho

    def com_play(self, regras):
        sessao = SessaoFalsa(regras)
        p = mock.patch.object(pl, '_sessao_google', lambda arquivo: (sessao, EMAIL))
        p.start()
        self.addCleanup(p.stop)
        return sessao

    def com_codemagic(self, regras):
        sessao = SessaoFalsa(regras)
        p = mock.patch.object(pl, '_codemagic', lambda token: pl.Codemagic(token, sessao))
        p.start()
        self.addCleanup(p.stop)
        return sessao

    def publicar(self, *extra):
        return rodar(['play-publicar', '--conta', self.conta, '--pacote', 'br.com.servpilot.app', '--aab', self.aab,
                      '--notas', self.notas, '--nome', '0.21.0 (22)', '--version-code', '22'] + list(extra))


class TestRegras(unittest.TestCase):
    def test_versao_interna(self):
        v = pl.montar_versao(22, '0.21.0 (22)', 'Novidades', 'pt-BR', 'internal')
        self.assertEqual(v, {'name': '0.21.0 (22)', 'versionCodes': ['22'], 'status': 'completed',
                             'releaseNotes': [{'language': 'pt-BR', 'text': 'Novidades'}]})

    def test_producao_gradual(self):
        v = pl.montar_versao(22, 'x', 'n', 'pt-BR', 'production', pl.fracao_rollout('20'))
        self.assertEqual((v['status'], v['userFraction']), ('inProgress', 0.2))
        v = pl.montar_versao(22, 'x', 'n', 'pt-BR', 'production', pl.fracao_rollout('100'))
        self.assertEqual(v['status'], 'completed')
        self.assertNotIn('userFraction', v)

    def test_rollout_invalido(self):
        for valor in ('0', '-5', '150'):
            with self.assertRaises(pl.ErroLoja):
                pl.fracao_rollout(valor)
        self.assertEqual(pl.fracao_rollout('0.5'), 0.5)

    def test_notas(self):
        with tempfile.TemporaryDirectory() as d:
            arq = os.path.join(d, 'n.txt')
            with open(arq, 'w', encoding='utf-8-sig') as f:
                f.write('# Revise antes\nLinha 1\n  # indentado também é comentário\nLinha 2\n')
            self.assertEqual(pl.ler_notas(arq), 'Linha 1\nLinha 2')
            with open(arq, 'w', encoding='utf-8') as f:
                f.write('# só comentário\n\n')
            with self.assertRaisesRegex(pl.ErroLoja, 'vazias'):
                pl.ler_notas(arq)
            with open(arq, 'w', encoding='utf-8') as f:
                f.write('a' * 501)
            with self.assertRaisesRegex(pl.ErroLoja, '501 caracteres'):
                pl.ler_notas(arq)
            with self.assertRaisesRegex(pl.ErroLoja, 'Não achei'):
                pl.ler_notas(os.path.join(d, 'nao-existe.txt'))


class TestPlay(Base):
    def regras_ok(self, commit=None):
        return [
            ('POST', '/upload/', Resposta(200, {'versionCode': 22, 'sha1': 'x'})),
            ('POST', ':commit', commit or Resposta(200, {'id': 'E1'})),
            ('POST', '/edits', Resposta(200, {'id': 'E1', 'expiryTimeSeconds': '9'})),
            ('PUT', '/tracks/', Resposta(200, {'track': 'internal'})),
            ('DELETE', '/edits/', Resposta(204)),
        ]

    def test_publica_no_teste_interno(self):
        sessao = self.com_play(self.regras_ok())
        codigo, saida = self.publicar()
        self.assertEqual(codigo, 0, saida)
        self.assertEqual([m for m, _ in sessao.metodos()], ['POST', 'POST', 'PUT', 'POST'])
        _, url, kw = sessao.chamadas[1]
        self.assertTrue(url.startswith(pl.UPLOAD_PLAY + '/br.com.servpilot.app/edits/E1/bundles'))
        self.assertEqual(kw['params'], {'uploadType': 'media'})
        self.assertEqual(kw['data'], b'PK-aab-falso')
        _, url, kw = sessao.chamadas[2]
        self.assertTrue(url.endswith('/edits/E1/tracks/internal'))
        self.assertEqual(kw['json'], {'track': 'internal', 'releases': [{
            'name': '0.21.0 (22)', 'versionCodes': ['22'], 'status': 'completed',
            'releaseNotes': [{'language': 'pt-BR', 'text': 'Ler etiqueta na tela Hoje.\n\nBusca de aparelhos.'}]}]})
        self.assertTrue(sessao.chamadas[3][1].endswith('/edits/E1:commit'))
        self.assertIn('@@PLAY_VERSION_CODE=22', saida)
        self.assertIn('teste interno', saida)

    def test_producao_com_rollout(self):
        sessao = self.com_play(self.regras_ok())
        codigo, saida = self.publicar('--faixa', 'production', '--rollout-pct', '20')
        self.assertEqual(codigo, 0, saida)
        versao = sessao.chamadas[2][2]['json']['releases'][0]
        self.assertEqual((versao['status'], versao['userFraction']), ('inProgress', 0.2))
        self.assertIn('20% dos usuários', saida)

    def test_build_ja_usado(self):
        regras = self.regras_ok()
        regras[0] = ('POST', '/upload/', erro_google(403, 'APK specifies a version code that has already been used.'))
        sessao = self.com_play(regras)
        codigo, saida = self.publicar()
        self.assertEqual(codigo, 1)
        self.assertIn('subir o build', saida)
        self.assertEqual(sessao.chamadas[-1][0], 'DELETE')  # descartou a edição
        self.assertNotIn('PUT', [m for m, _ in sessao.metodos()])

    def test_sem_permissao_mostra_o_email(self):
        sessao = self.com_play([('POST', '/edits', erro_google(403, 'The caller does not have permission'))])
        codigo, saida = self.publicar()
        self.assertEqual(codigo, 1)
        self.assertIn(EMAIL, saida)
        self.assertIn('Usuários e permissões', saida)
        self.assertEqual(len(sessao.chamadas), 1)

    def test_api_desativada(self):
        self.com_play([('POST', '/edits', erro_google(
            403, 'Google Play Android Developer API has not been used in project 123 before or it is disabled.'))])
        codigo, saida = self.publicar()
        self.assertEqual(codigo, 1)
        self.assertIn('não está ativada', saida)

    def test_build_diferente_do_pubspec(self):
        regras = self.regras_ok()
        regras[0] = ('POST', '/upload/', Resposta(200, {'versionCode': 21}))
        sessao = self.com_play(regras)
        codigo, saida = self.publicar()
        self.assertEqual(codigo, 1)
        self.assertIn('o pubspec diz 22', saida)
        self.assertEqual(sessao.chamadas[-1][0], 'DELETE')

    def test_app_rascunho_vira_draft(self):
        regras = self.regras_ok()
        regras[3] = ('PUT', '/tracks/', [erro_google(400, 'Only releases with status draft may be created on draft app.'),
                                         Resposta(200, {})])
        sessao = self.com_play(regras)
        codigo, saida = self.publicar()
        self.assertEqual(codigo, 0, saida)
        puts = [kw['json']['releases'][0]['status'] for m, _, kw in sessao.chamadas if m == 'PUT']
        self.assertEqual(puts, ['completed', 'draft'])
        self.assertIn('RASCUNHO', saida)
        self.assertIn('@@PLAY_RASCUNHO=1', saida)

    def test_commit_sem_revisao_automatica(self):
        commit = [erro_google(400, 'Changes cannot be sent for review automatically. Please set the query parameter '
                                   'changesNotSentForReview to true.'), Resposta(200, {'id': 'E1'})]
        sessao = self.com_play(self.regras_ok(commit=commit))
        codigo, saida = self.publicar()
        self.assertEqual(codigo, 0, saida)
        commits = [kw for m, u, kw in sessao.chamadas if u.endswith(':commit')]
        self.assertEqual(commits[1]['params'], {'changesNotSentForReview': 'true'})
        self.assertIn('Enviar alterações para revisão', saida)

    def test_chave_recusada(self):
        class RefreshError(Exception):
            pass
        self.com_play([('POST', '/edits', RefreshError('invalid_grant: Invalid JWT Signature.'))])
        codigo, saida = self.publicar()
        self.assertEqual(codigo, 1)
        self.assertIn('recusou a chave', saida)

    def test_conferir_maior_build(self):
        sessao = self.com_play([
            ('POST', '/edits', Resposta(200, {'id': 'E9'})),
            ('GET', '/bundles', Resposta(200, {'bundles': [{'versionCode': 19}, {'versionCode': 21}]})),
            ('GET', '/apks', Resposta(200, {})),
            ('GET', '/tracks', Resposta(200, {'tracks': [
                {'track': 'internal', 'releases': [{'versionCodes': ['20']}]},
                {'track': 'production', 'releases': [{'status': 'draft'}]}]})),
            ('DELETE', '/edits/E9', Resposta(204)),
        ])
        codigo, saida = rodar(['play-conferir', '--conta', self.conta, '--pacote', 'br.com.servpilot.app'])
        self.assertEqual(codigo, 0, saida)
        self.assertIn('@@VERSION_CODE_MAX=21', saida)
        self.assertEqual(sessao.chamadas[-1][0], 'DELETE')

    def test_sem_aab(self):
        os.remove(self.aab)
        codigo, saida = self.publicar()
        self.assertEqual(codigo, 1)
        self.assertIn('Não achei o .aab', saida)

    def test_sem_arquivo_da_conta(self):
        codigo, saida = rodar(['play-conferir', '--conta', os.path.join(self.tmp.name, 'nada.json'),
                               '--pacote', 'br.com.servpilot.app'])
        self.assertEqual(codigo, 1)
        self.assertIn('Não achei a chave da conta de serviço', saida)


class TestCodemagic(Base):
    def test_disparar(self):
        sessao = self.com_codemagic([('POST', '/builds', Resposta(200, {'buildId': 'B42'}))])
        codigo, saida = rodar(['codemagic-disparar', '--token', self.token, '--app-id', 'A1',
                               '--workflow', 'ios-testflight', '--branch', 'main'])
        self.assertEqual(codigo, 0, saida)
        metodo, url, kw = sessao.chamadas[0]
        self.assertEqual(url, 'https://api.codemagic.io/builds')
        self.assertEqual(kw['json'], {'appId': 'A1', 'workflowId': 'ios-testflight', 'branch': 'main'})
        self.assertEqual(kw['headers']['x-auth-token'], TOKEN_FALSO)  # sem o \r\n do arquivo
        self.assertIn('@@CODEMAGIC_BUILD_ID=B42', saida)
        self.assertIn('https://codemagic.io/app/A1/build/B42', saida)
        self.assertNotIn(TOKEN_FALSO, saida)

    def test_token_recusado_nao_imprime_o_token(self):
        self.com_codemagic([('POST', '/builds', Resposta(401, {'error': 'Unauthorized'}))])
        codigo, saida = rodar(['codemagic-disparar', '--token', self.token, '--app-id', 'A1'])
        self.assertEqual(codigo, 1)
        self.assertIn('recusou o token', saida)
        self.assertNotIn(TOKEN_FALSO, saida)

    def test_achar_app_id_e_gravar(self):
        config = self.arquivo('apps-deploy.json', json.dumps(
            {'android': {'pacote': 'br.com.servpilot.app'}, 'ios': {'appId': '', 'workflowId': 'ios-testflight'}},
            ensure_ascii=False).encode('utf-8'))
        self.com_codemagic([('GET', '/apps', Resposta(200, {'applications': [
            {'_id': 'X1', 'appName': 'outro-app'}, {'_id': 'A77', 'appName': 'servia-apps'}]}))])
        codigo, saida = rodar(['codemagic-conferir', '--token', self.token, '--nome', 'servia-apps', '--config', config])
        self.assertEqual(codigo, 0, saida)
        self.assertIn('@@CODEMAGIC_APP_ID=A77', saida)
        with open(config, encoding='utf-8') as f:
            gravado = json.load(f)
        self.assertEqual(gravado['ios'], {'appId': 'A77', 'workflowId': 'ios-testflight'})
        self.assertEqual(gravado['android']['pacote'], 'br.com.servpilot.app')

    def test_app_nao_achado_lista_os_apps(self):
        self.com_codemagic([('GET', '/apps', Resposta(200, {'applications': [{'_id': 'X1', 'appName': 'outro'}]}))])
        codigo, saida = rodar(['codemagic-conferir', '--token', self.token, '--nome', 'servia-apps'])
        self.assertEqual(codigo, 1)
        self.assertIn('outro  ->  appId X1', saida)

    def test_app_id_conferido(self):
        self.com_codemagic([('GET', '/apps', Resposta(200, {'applications': [{'_id': 'A77', 'appName': 'servia-apps'}]}))])
        codigo, saida = rodar(['codemagic-conferir', '--token', self.token, '--app-id', 'A77'])
        self.assertEqual(codigo, 0, saida)
        codigo, saida = rodar(['codemagic-conferir', '--token', self.token, '--app-id', 'ERRADO'])
        self.assertEqual(codigo, 1)

    def test_token_vazio(self):
        vazio = self.arquivo('vazio.txt', b'\n')
        codigo, saida = rodar(['codemagic-conferir', '--token', vazio])
        self.assertEqual(codigo, 1)
        self.assertIn('só o token', saida)


class Relogio:
    def __init__(self):
        self.t = 0.0

    def agora(self):
        return self.t

    def dormir(self, s):
        self.t += s


class TestAcompanhar(unittest.TestCase):
    def cm(self, respostas):
        return pl.Codemagic('t', SessaoFalsa([('GET', '/builds/B1', respostas)]))

    def acompanhar(self, respostas, limite=90):
        relogio = Relogio()
        saida = io.StringIO()
        with contextlib.redirect_stdout(saida):
            codigo = pl.acompanhar(self.cm(respostas), 'A1', 'B1', limite, 30, relogio.dormir, relogio.agora)
        return codigo, saida.getvalue()

    def test_terminou_e_publicou(self):
        final = {'build': {'status': 'finished', 'index': 12, 'buildActions': [
            {'name': 'Build', 'type': 'script', 'status': 'success'},
            {'name': 'Publishing', 'type': 'publishing', 'status': 'success'}],
            'artefacts': [{'name': 'servia_app.ipa', 'versionName': '0.21.0'}]}}
        codigo, saida = self.acompanhar([Resposta(200, {'build': {'status': 'queued'}}),
                                         Resposta(200, {'build': {'status': 'building'}}),
                                         Resposta(200, {'build': {'status': 'building'}}),
                                         Resposta(200, final)])
        self.assertEqual(codigo, 0, saida)
        self.assertIn('enviado ao App Store Connect', saida)
        self.assertIn('112 (100 + execução 12)', saida)
        self.assertIn('@@CODEMAGIC_APP_STORE=enviado', saida)
        self.assertEqual(saida.count('building:'), 1)  # só avisa quando muda

    def test_falhou(self):
        final = {'build': {'status': 'failed', 'message': 'Xcode build error', 'buildActions': [
            {'name': 'Build', 'status': 'failed'}]}}
        codigo, saida = self.acompanhar([Resposta(200, final)])
        self.assertEqual(codigo, 1)
        self.assertIn('passo com problema: Build', saida)
        self.assertIn('https://codemagic.io/app/A1/build/B1', saida)

    def test_publicacao_falhou(self):
        final = {'build': {'status': 'finished', 'buildActions': [
            {'name': 'App Store Connect', 'type': 'publishing', 'status': 'failed'}]}}
        codigo, saida = self.acompanhar([Resposta(200, final)])
        self.assertEqual(codigo, 1)
        self.assertIn('@@CODEMAGIC_APP_STORE=falhou', saida)

    def test_tempo_limite(self):
        codigo, saida = self.acompanhar([Resposta(200, {'build': {'status': 'building'}})], limite=5)
        self.assertEqual(codigo, 3)
        self.assertIn('não terminou em 5 minutos', saida)

    def test_rede_instavel(self):
        final = {'build': {'status': 'finished', 'buildActions': []}}
        codigo, saida = self.acompanhar([ConnectionError('x'), Resposta(502, texto='bad gateway'), Resposta(200, final)])
        self.assertEqual(codigo, 0, saida)
        self.assertIn('confira no TestFlight', saida)


if __name__ == '__main__':
    unittest.main()
