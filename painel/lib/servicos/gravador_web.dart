// Gravação de voz no navegador (assistente, guia 93): MediaRecorder do próprio
// navegador, sem pacote extra. O áudio fica só na memória e vai para a função.
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Áudio gravado: os bytes, o tipo (ex.: audio/webm) e quanto durou.
class AudioGravado {
  const AudioGravado(this.bytes, this.tipo, this.duracao);
  final Uint8List bytes;
  final String tipo;
  final Duration duracao;
}

/// Erro com a frase pronta para a tela (sem microfone, permissão negada...).
class ErroGravacao implements Exception {
  const ErroGravacao(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// Um gravador por vez: começar() pede o microfone; parar() devolve o áudio.
class GravadorWeb {
  web.MediaStream? _stream;
  web.MediaRecorder? _gravador;
  final List<web.Blob> _partes = [];
  Completer<void>? _parou;
  final Stopwatch _relogio = Stopwatch();

  bool get gravando => _gravador != null;
  Duration get duracao => _relogio.elapsed;

  /// O tipo que o navegador grava (Chrome/Edge/Firefox: webm/opus; Safari: mp4).
  static String _tipoSuportado() {
    for (final t in const ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg;codecs=opus']) {
      if (web.MediaRecorder.isTypeSupported(t)) return t;
    }
    return '';
  }

  Future<void> comecar() async {
    if (gravando) return;
    final dispositivos = web.window.navigator.mediaDevices;
    try {
      _stream = await dispositivos.getUserMedia(web.MediaStreamConstraints(audio: true.toJS)).toDart;
    } catch (_) {
      throw const ErroGravacao(
          'O navegador não liberou o microfone. Clique no cadeado da barra de endereço e permita o microfone.');
    }
    final tipo = _tipoSuportado();
    final gravador = tipo.isEmpty
        ? web.MediaRecorder(_stream!)
        : web.MediaRecorder(_stream!, web.MediaRecorderOptions(mimeType: tipo, audioBitsPerSecond: 32000));
    _partes.clear();
    _parou = Completer<void>();
    gravador.addEventListener(
        'dataavailable',
        ((web.BlobEvent e) {
          if (e.data.size > 0) _partes.add(e.data);
        }).toJS);
    gravador.addEventListener(
        'stop',
        ((web.Event _) {
          final c = _parou;
          if (c != null && !c.isCompleted) c.complete();
        }).toJS);
    gravador.start();
    _gravador = gravador;
    _relogio
      ..reset()
      ..start();
  }

  /// Para e devolve o áudio (null = nada gravado).
  Future<AudioGravado?> parar() async {
    final gravador = _gravador;
    if (gravador == null) return null;
    _relogio.stop();
    if (gravador.state != 'inactive') gravador.stop();
    await _parou?.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    _soltarMicrofone();
    _gravador = null;
    if (_partes.isEmpty) return null;
    final tipo = gravador.mimeType.isEmpty ? 'audio/webm' : gravador.mimeType.split(';').first;
    final blob = web.Blob(_partes.map((p) => p as JSAny).toList().toJS, web.BlobPropertyBag(type: tipo));
    _partes.clear();
    final buffer = await blob.arrayBuffer().toDart;
    return AudioGravado(buffer.toDart.asUint8List(), tipo, _relogio.elapsed);
  }

  /// Desiste da gravação (sai da tela, cancela).
  void cancelar() {
    final gravador = _gravador;
    _gravador = null;
    _relogio.stop();
    if (gravador != null && gravador.state != 'inactive') gravador.stop();
    _partes.clear();
    _soltarMicrofone();
  }

  void _soltarMicrofone() {
    final s = _stream;
    _stream = null;
    if (s == null) return;
    for (final t in s.getTracks().toDart) {
      t.stop();
    }
  }
}
