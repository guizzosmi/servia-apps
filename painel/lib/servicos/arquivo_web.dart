// O painel é só web: aqui é o lugar das APIs do navegador.
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Arquivo escolhido no computador (painel web).
class ArquivoEscolhido {
  const ArquivoEscolhido(this.nome, this.bytes, this.tipo);
  final String nome;
  final Uint8List bytes;
  final String tipo;
}

/// Abre o "escolher arquivo" do navegador. null = cancelou.
Future<ArquivoEscolhido?> escolherArquivo({String aceitar = '*/*'}) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = aceitar;
  final escolha = Completer<web.File?>();
  void escolheu(web.Event _) {
    if (!escolha.isCompleted) escolha.complete(input.files?.item(0));
  }

  void cancelou(web.Event _) {
    if (!escolha.isCompleted) escolha.complete(null);
  }

  input.addEventListener('change', escolheu.toJS);
  input.addEventListener('cancel', cancelou.toJS);
  input.click();
  final f = await escolha.future;
  if (f == null) return null;
  final buffer = await f.arrayBuffer().toDart;
  return ArquivoEscolhido(f.name, buffer.toDart.asUint8List(), f.type);
}

/// Guia 114: reduz uma imagem (PNG ou JPG) para no máximo [maxLado] pixels no
/// lado maior e devolve em PNG (mantém a transparência). null = o navegador não
/// conseguiu abrir a imagem.
Future<Uint8List?> reduzirImagem(Uint8List bytes, String tipo, {int maxLado = 600}) async {
  final blob = web.Blob(<web.BlobPart>[bytes.toJS].toJS, web.BlobPropertyBag(type: tipo));
  final url = web.URL.createObjectURL(blob);
  try {
    final img = web.HTMLImageElement();
    final carregou = Completer<bool>();
    img.addEventListener(
        'load',
        ((web.Event _) {
          if (!carregou.isCompleted) carregou.complete(true);
        }).toJS);
    img.addEventListener(
        'error',
        ((web.Event _) {
          if (!carregou.isCompleted) carregou.complete(false);
        }).toJS);
    img.src = url;
    final ok = await carregou.future.timeout(const Duration(seconds: 10), onTimeout: () => false);
    if (!ok || img.naturalWidth == 0 || img.naturalHeight == 0) return null;
    final escala = min(1.0, maxLado / max(img.naturalWidth, img.naturalHeight));
    final largura = max(1, (img.naturalWidth * escala).round());
    final altura = max(1, (img.naturalHeight * escala).round());
    final canvas = web.HTMLCanvasElement()
      ..width = largura
      ..height = altura;
    final ctx = canvas.getContext('2d');
    if (ctx == null) return null;
    (ctx as web.CanvasRenderingContext2D).drawImage(img, 0, 0, largura, altura);
    final dados = canvas.toDataURL('image/png');
    final virgula = dados.indexOf(',');
    if (virgula < 0) return null;
    return base64Decode(dados.substring(virgula + 1));
  } finally {
    web.URL.revokeObjectURL(url);
  }
}

/// Abre um endereço numa aba nova (ex.: ouvir o áudio).
void abrirEmNovaAba(String url) => web.window.open(url, '_blank');

/// UUID v4 (o mesmo formato que o app gera).
String novoUuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
