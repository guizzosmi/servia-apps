import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// WhatsApp nível 1 no painel: monta a mensagem pelo modelo da empresa,
/// abre o WhatsApp (ou copia) e registra na OS.

SupabaseClient get _db => Supabase.instance.client;

/// Contatos ativos do cliente (para escolher quem recebe).
Future<List<Map<String, dynamic>>> contatosDoCliente(String clienteId) async {
  final r = await _db
      .from('contatos')
      .select('id, nome, telefone, aceita_whatsapp, funcoes')
      .eq('cliente_id', clienteId)
      .eq('ativo', true)
      .isFilter('excluido_em', null)
      .order('nome');
  return List<Map<String, dynamic>>.from(r);
}

/// Nome da empresa ativa e os modelos que ela mudou.
Future<(String, Map<String, dynamic>)> _empresaEModelos() async {
  final empresaId = Sessao.atual!.empresaId!;
  final e = await _db.from('empresas').select('razao_social, nome_fantasia').eq('id', empresaId).single();
  final c = await _db.from('empresa_config').select('parametros').eq('empresa_id', empresaId).maybeSingle();
  final m = ((c?['parametros'] as Map?)?['mensagens'] as Map?) ?? const {};
  return ('${e['nome_fantasia'] ?? e['razao_social'] ?? ''}', Map<String, dynamic>.from(m));
}

/// Abre a folha do WhatsApp com o modelo e registra o que foi mandado.
/// [valores]: os campos do modelo (o {contato} e o {empresa} vêm daqui).
/// Devolve true se a mensagem foi aberta no WhatsApp ou copiada.
Future<bool> mandarWhatsApp(
  BuildContext context, {
  required String modelo,
  required String titulo,
  required String osId,
  required String clienteId,
  String? contatoInicialId,
  required Map<String, String?> valores,
  String? entidade,
  String? entidadeId,
  String? linkId,
  String? aviso,
}) async {
  var contatos = <Map<String, dynamic>>[];
  var empresa = '';
  var modelos = <String, dynamic>{};
  try {
    contatos = await contatosDoCliente(clienteId);
    final r = await _empresaEModelos();
    empresa = r.$1;
    modelos = r.$2;
  } catch (e) {
    if (context.mounted) _avisar(context, mensagemDeErro(e), erro: true);
    return false;
  }
  if (!context.mounted) return false;
  final texto = textoDoModelo(modelo, modelos);
  final envio = await compartilharWhatsApp(
    context,
    titulo: titulo,
    contatos: contatos,
    contatoInicialId: contatoInicialId,
    montarTexto: (nome) => montarMensagem(texto, {'empresa': empresa, ...valores, 'contato': nome}),
    link: valores['link'],
    aviso: aviso,
  );
  if (envio == null) return false;
  try {
    await _db.rpc('mensagem_registrar', params: {
      'p': {
        'modelo': modelo,
        'os_id': osId,
        if (entidade != null) 'entidade': entidade,
        if (entidadeId != null) 'entidade_id': entidadeId,
        if (linkId != null) 'link_id': linkId,
        ...envio.paraRegistro(),
      }
    });
  } catch (e) {
    // A mensagem já foi aberta/copiada: só o registro na OS falhou.
    if (context.mounted) _avisar(context, 'A mensagem saiu, mas não ficou registrada na OS: ${mensagemDeErro(e)}', erro: true);
  }
  return true;
}

void _avisar(BuildContext context, String texto, {bool erro = false}) {
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));
}
