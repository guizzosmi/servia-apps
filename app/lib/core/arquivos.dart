import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'banco_local.dart';

/// Arquivos do app no aparelho: as fotos dos atendimentos e as assinaturas
/// do cliente (imagem e resumo em PDF), até subirem para a plataforma.
class Arquivos {
  Arquivos._();

  static String? _pasta;
  static String? _pastaAssinaturas;

  /// Guarda o caminho das pastas (chamado na abertura do app).
  static Future<void> iniciar() async {
    _pasta = (await pastaFotos()).path;
    _pastaAssinaturas = (await pastaAssinaturas()).path;
  }

  /// Pasta das assinaturas (PNG) e dos resumos assinados (PDF).
  static Future<Directory> pastaAssinaturas() async =>
      Directory(p.join((await getApplicationDocumentsDirectory()).path, 'assinaturas'));

  /// Arquivo de uma assinatura do app, pelo nome (como nas fotos).
  static File? assinatura(Object? caminhoGravado) {
    if (caminhoGravado == null) return null;
    final nome = p.basename('$caminhoGravado');
    return File(_pastaAssinaturas == null ? '$caminhoGravado' : p.join(_pastaAssinaturas!, nome));
  }

  /// Pasta das fotos tiradas pelo app (dentro da área privada do app).
  static Future<Directory> pastaFotos() async =>
      Directory(p.join((await getApplicationDocumentsDirectory()).path, 'fotos'));

  /// O arquivo de uma foto do app, pelo nome: no iPhone, a pasta do app
  /// muda de caminho depois de uma atualização, e o caminho gravado antes
  /// deixaria de valer.
  static File? foto(Object? caminhoGravado) {
    if (caminhoGravado == null) return null;
    final nome = p.basename('$caminhoGravado');
    return File(_pasta == null ? '$caminhoGravado' : p.join(_pasta!, nome));
  }

  /// Apaga todas as fotos e assinaturas (sair do app, aparelho mandado apagar).
  static Future<void> apagarFotos() async {
    for (final pasta in [await pastaFotos(), await pastaAssinaturas()]) {
      try {
        if (await pasta.exists()) await pasta.delete(recursive: true);
      } catch (_) {
        // Sem a pasta (ou já apagada): nada a fazer.
      }
    }
  }

  /// Quantas fotos há no aparelho e quanto ocupam (tela de sincronização).
  static Future<(int, int)> resumoFotos() async {
    final pasta = await pastaFotos();
    if (!await pasta.exists()) return (0, 0);
    var n = 0, bytes = 0;
    await for (final e in pasta.list()) {
      if (e is File) {
        n++;
        bytes += await e.length();
      }
    }
    return (n, bytes);
  }

  /// Apaga as fotos que o app não usa mais: as que já subiram e cujo
  /// atendimento saiu do "dia" (ontem a daqui a 2 dias). Ficam sempre as
  /// que ainda estão na fila (não subiram) e as do dia (aparecem na tela
  /// mesmo sem internet). Devolve quantas apagou.
  static Future<int> limparFotos(BancoLocal banco) async {
    final pasta = await pastaFotos();
    if (!await pasta.exists()) return _limparAssinaturas(banco);
    // Pelo nome do arquivo (o caminho da pasta do app pode mudar no iPhone).
    final usados = <String>{
      for (final f in banco.todos('atendimento_fotos'))
        if (f['arquivo_local'] != null) p.basename('${f['arquivo_local']}'),
      for (final o in banco.fila)
        if (o.dados['arquivo_local'] != null) p.basename('${o.dados['arquivo_local']}'),
    };
    var apagadas = 0;
    final agora = DateTime.now();
    await for (final e in pasta.list()) {
      if (e is! File || usados.contains(p.basename(e.path))) continue;
      try {
        // Foto recém-tirada, ainda sendo registrada: fica para a próxima.
        if (agora.difference(await e.lastModified()) < const Duration(minutes: 30)) continue;
        await e.delete();
        apagadas++;
      } catch (_) {
        // Arquivo em uso ou já apagado: tenta de novo na próxima limpeza.
      }
    }
    // Marcas de "foto já subiu" de fotos que não estão mais na fila.
    final naFila = {for (final o in banco.fila) '${o.dados['foto_id']}'};
    for (final chave in banco.chavesMeta('foto_subiu:')) {
      if (!naFila.contains(chave.substring('foto_subiu:'.length))) await banco.gravarMeta(chave, null);
    }
    return apagadas + await _limparAssinaturas(banco);
  }

  /// Assinatura e resumo só ficam no aparelho até a operação subir.
  static Future<int> _limparAssinaturas(BancoLocal banco) async {
    final anexos = [
      for (final o in banco.fila)
        if (o.dados['arquivos'] is List)
          for (final a in (o.dados['arquivos'] as List).cast<Map>()) a,
    ];
    final usados = {for (final a in anexos) p.basename('${a['local']}')};
    final caminhos = {for (final a in anexos) '${a['caminho']}'};
    var apagadas = 0;
    final pasta = await pastaAssinaturas();
    if (await pasta.exists()) {
      final agora = DateTime.now();
      await for (final e in pasta.list()) {
        if (e is! File || usados.contains(p.basename(e.path))) continue;
        try {
          if (agora.difference(await e.lastModified()) < const Duration(minutes: 30)) continue;
          await e.delete();
          apagadas++;
        } catch (_) {
          // Tenta de novo na próxima limpeza.
        }
      }
    }
    for (final chave in banco.chavesMeta('arquivo_subiu:')) {
      if (!caminhos.contains(chave.substring('arquivo_subiu:'.length))) await banco.gravarMeta(chave, null);
    }
    return apagadas;
  }
}
