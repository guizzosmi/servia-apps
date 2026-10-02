import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import 'acoes_atendimento.dart';
import 'acoes_orcamento.dart';
import 'estado.dart';

/// Link que vai na mensagem, criado no aparelho (funciona sem internet):
/// o token fica só no link; a plataforma recebe o hash na sincronização e
/// só então o link passa a abrir.
class LinkPreparado {
  LinkPreparado._(this.id, this.entidade, this.token, this.osId, this.orcamentoId);

  /// entidade: orcamento (link de aprovação) ou os_relatorio (relatório da OS).
  factory LinkPreparado.novo({required String entidade, required String osId, String? orcamentoId}) {
    final r = Random.secure();
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    final token = base64Url.encode(bytes).replaceAll('=', '');
    return LinkPreparado._(AcoesAtendimento.novoId(), entidade, token, osId, orcamentoId);
  }

  final String id;
  final String entidade;
  final String token;
  final String osId;
  final String? orcamentoId;

  String get url => '${Config.linkAceite}/${entidade == 'orcamento' ? 'a' : 'r'}/$token';
}

/// WhatsApp nível 1 no app: a mensagem sai pelo modelo da empresa, o
/// WhatsApp do aparelho abre com o texto, e a fila registra o que foi
/// mandado (e o link, se houver).
class AcoesMensagens {
  AcoesMensagens._();

  static EstadoApp get _estado => EstadoApp.instancia;

  static List<Map<String, dynamic>> contatosDoCliente(Object? clienteId) => _estado.banco!
      .todos('contatos')
      .where((c) => c['cliente_id'] == clienteId && c['ativo'] != false && c['excluido_em'] == null)
      .toList()
    ..sort((a, b) => '${a['nome']}'.compareTo('${b['nome']}'));

  /// Campos que valem para qualquer mensagem da OS.
  static Map<String, String?> valoresDaOs(Map<String, dynamic> os) {
    final banco = _estado.banco!;
    final local = banco.um('locais', os['local_id']) ?? const {};
    final endereco = [
      [local['logradouro'], local['numero']].where((x) => x != null && '$x'.isNotEmpty).join(', '),
      local['bairro'],
      [local['cidade'], local['uf']].where((x) => x != null && '$x'.isNotEmpty).join('/'),
    ].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
    return {
      'empresa': '${AcoesOrcamento.empresa['nome'] ?? ''}',
      'tecnico': AcoesOrcamento.nomeDoTecnico,
      'os': '${os['codigo'] ?? ''}',
      'cliente': '${banco.um('clientes', os['cliente_id'])?['nome'] ?? ''}',
      'local': '${local['nome'] ?? ''}',
      'endereco': endereco,
    };
  }

  /// Abre a folha do WhatsApp e, se a pessoa mandou (ou copiou), coloca na
  /// fila o link (se houver) e o registro da mensagem. true = mandou.
  static Future<bool> mandar(
    BuildContext context, {
    required String modelo,
    required String titulo,
    required Map<String, dynamic> os,
    String? contatoInicialId,
    Map<String, String?> valores = const {},
    LinkPreparado? link,
    String? entidade,
    String? entidadeId,
  }) async {
    final texto = textoDoModelo(modelo, AcoesOrcamento.config.mensagens);
    final base = {...valoresDaOs(os), ...valores, if (link != null) 'link': link.url};
    final envio = await compartilharWhatsApp(
      context,
      titulo: titulo,
      contatos: contatosDoCliente(os['cliente_id']),
      contatoInicialId: contatoInicialId ?? os['solicitante_contato_id'] as String?,
      montarTexto: (nome) => montarMensagem(texto, {...base, 'contato': nome}),
      link: link?.url,
      aviso: link == null
          ? null
          : 'O link passa a abrir quando o aparelho sincronizar (com internet, na hora).',
    );
    if (envio == null) return false;
    final sync = _estado.sync!;
    if (link != null) {
      await sync.registrar('link_app', {
        'link_id': link.id,
        'entidade': link.entidade,
        'os_id': link.osId,
        if (link.orcamentoId != null) 'orcamento_id': link.orcamentoId,
        'token_hash': sha256.convert(utf8.encode(link.token)).toString(),
        if (envio.contatoId != null) 'contato_id': envio.contatoId,
      });
    }
    await sync.registrar('mensagem', {
      'mensagem_id': AcoesAtendimento.novoId(),
      'modelo': modelo,
      'os_id': os['id'],
      if (entidade != null) 'entidade': entidade,
      if (entidadeId != null) 'entidade_id': entidadeId,
      if (link != null) 'link_id': link.id,
      ...envio.paraRegistro(),
    });
    return true;
  }
}
