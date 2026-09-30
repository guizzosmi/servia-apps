import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'banco_local.dart';

/// Arquivos do app no aparelho (por enquanto, as fotos dos atendimentos).
class Arquivos {
  Arquivos._();

  static String? _pasta;

  /// Guarda o caminho da pasta das fotos (chamado na abertura do app).
  static Future<void> iniciar() async {
    _pasta = (await pastaFotos()).path;
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

  /// Apaga todas as fotos (sair do app, aparelho mandado apagar).
  static Future<void> apagarFotos() async {
    try {
      final pasta = await pastaFotos();
      if (await pasta.exists()) await pasta.delete(recursive: true);
    } catch (_) {
      // Sem a pasta (ou já apagada): nada a fazer.
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
    if (!await pasta.exists()) return 0;
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
    return apagadas;
  }
}
