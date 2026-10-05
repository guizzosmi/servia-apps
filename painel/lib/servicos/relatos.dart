import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'arquivo_web.dart';
import 'funcoes.dart';
import 'status.dart';

/// Relato por áudio (guia 15): o arquivo sobe para o bucket "audios", é
/// registrado (relato_registrar) e a função relato-processar transcreve e
/// organiza. No painel serve para testar; no app, é o técnico quem grava.

const statusRelato = {
  'enviado': Rotulo('Na fila', Cores.neutro),
  'processando': Rotulo('Processando', Cores.info),
  'pronto': Rotulo('Pronto para revisar', Cores.sucesso),
  'erro': Rotulo('Erro', Cores.erro),
  'revisado': Rotulo('Revisado', Cores.indigo700),
  'descartado': Rotulo('Descartado', Cores.neutro),
};

/// O que o app vai propor para o equipamento.
const decisoesEquipamento = {
  'identificado': Rotulo('Identificado', Cores.sucesso),
  'sugerido': Rotulo('Sugerido', Cores.info),
  'escolher': Rotulo('Escolher', Cores.alerta),
  'confirmar': Rotulo('Confirmar o ambiente', Cores.alerta),
  'cadastrar': Rotulo('Cadastrar', Cores.erro),
};

/// Aviso com a frase pronta para a tela.
class AvisoRelato implements Exception {
  const AvisoRelato(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// Tipo de cada extensão, dentro dos aceitos pelo bucket "audios".
const _tiposAudio = {
  'm4a': 'audio/mp4',
  'mp4': 'video/mp4',
  'aac': 'audio/aac',
  'mp3': 'audio/mpeg',
  'ogg': 'audio/ogg',
  'oga': 'audio/ogg',
  'opus': 'audio/ogg',
  'wav': 'audio/wav',
  'webm': 'audio/webm',
};

/// Sobe o arquivo, registra e processa. Devolve o id do áudio.
Future<String> enviarRelato({
  required String osId,
  required ArquivoEscolhido arquivo,
  String? atendimentoId,
}) async {
  final s = Sessao.atual!;
  // Desligado na empresa: avisa antes de subir o arquivo (senão ele ficaria
  // no bucket sem registro).
  final par = await Supabase.instance.client.rpc('relato_parametros');
  if (par is Map && par['relato_audio'] == false) {
    throw const AvisoRelato('O relato por áudio está desligado em Configurações > Relato por áudio (IA).');
  }
  final id = novoUuid();
  final agora = DateTime.now();
  final ext = arquivo.nome.contains('.') ? arquivo.nome.split('.').last.toLowerCase() : 'm4a';
  final caminho = '${s.contaId}/${s.empresaId}/${agora.year}/${agora.month.toString().padLeft(2, '0')}/$id.$ext';
  // O bucket só aceita alguns tipos; o navegador às vezes manda outro nome para
  // o mesmo formato (audio/mp3, audio/opus, vazio...). Vale a extensão.
  final tipo = _tiposAudio[ext] ?? (arquivo.tipo.isNotEmpty ? arquivo.tipo : 'audio/mp4');
  await Supabase.instance.client.storage
      .from('audios')
      .uploadBinary(caminho, arquivo.bytes, fileOptions: FileOptions(contentType: tipo));
  await Supabase.instance.client.rpc('relato_registrar', params: {
    'p': {
      'audio_id': id,
      'os_id': osId,
      if (atendimentoId != null) 'atendimento_id': atendimentoId,
      'caminho': caminho,
      'mime': tipo,
      'tamanho_bytes': arquivo.bytes.length,
      'origem': 'painel',
    },
  });
  await processarRelato(id);
  return id;
}

/// Transcreve e organiza (ou devolve o que já foi feito).
Future<Map<String, dynamic>> processarRelato(String audioId) =>
    chamarFuncao('relato-processar', {'audio_id': audioId});

/// Link temporário (10 minutos) para ouvir o áudio.
Future<String> linkDoAudio(String caminho) =>
    Supabase.instance.client.storage.from('audios').createSignedUrl(caminho, 600);
