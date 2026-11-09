import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';
import 'package:servia_comum/servia_comum.dart';

/// O ponto marcado pelo GPS do celular num registro (entrega, retirada,
/// retorno, check-in da manutenção).
///
/// A localização é lida SÓ no momento em que a pessoa registra, com o app
/// aberto ("durante o uso"). O app não pede permissão de segundo plano e não
/// acompanha o celular: não há rastreamento.
class Posicao {
  const Posicao({required this.latitude, required this.longitude, required this.precisaoM, required this.em});

  final double latitude;
  final double longitude;

  /// Raio de incerteza informado pelo GPS, em metros.
  final double precisaoM;

  /// Hora da leitura (do celular).
  final DateTime em;

  Map<String, dynamic> paraEnvio() => {
        'latitude': double.parse(latitude.toStringAsFixed(6)),
        'longitude': double.parse(longitude.toStringAsFixed(6)),
        'precisao_m': double.parse(precisaoM.toStringAsFixed(1)),
        'em': em.toUtc().toIso8601String(),
      };

  /// '-24,955512, -53,455301'
  String get texto => '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

  String get precisaoTexto => '± ${precisaoM.round()} m';

  /// Abre o mapa do celular no ponto, para conferir (Apple Mapas no iPhone, Google Maps no Android).
  Future<bool> abrirNoMapa() {
    final lat = latitude.toStringAsFixed(6), lng = longitude.toStringAsFixed(6);
    return abrirLink(Platform.isIOS
        ? 'https://maps.apple.com/?ll=$lat,$lng&q=$lat,$lng'
        : 'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
  }
}

/// Resultado de "marcar o ponto": a posição ou o motivo (para a tela mostrar
/// e, se a pessoa seguir sem GPS, ir junto com o registro).
class LeituraPosicao {
  const LeituraPosicao._(this.posicao, this.motivo, {this.abrirConfiguracoes = false, this.servicoDesligado = false});

  final Posicao? posicao;
  final String? motivo;

  /// A permissão foi negada de vez: só nas configurações do celular.
  final bool abrirConfiguracoes;

  /// A localização do celular inteira está desligada (não só a do app).
  final bool servicoDesligado;

  bool get ok => posicao != null;
}

class Gps {
  Gps._();

  /// Lê a posição atual uma vez (alta precisão, até [limite]). Pede a
  /// permissão "durante o uso" se ainda não foi dada.
  static Future<LeituraPosicao> ler({Duration limite = const Duration(seconds: 25)}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LeituraPosicao._(null, 'A localização do celular está desligada.',
            abrirConfiguracoes: true, servicoDesligado: true);
      }
      var permissao = await Geolocator.checkPermission();
      if (permissao == LocationPermission.denied) permissao = await Geolocator.requestPermission();
      if (permissao == LocationPermission.deniedForever) {
        return const LeituraPosicao._(null, 'A permissão de localização foi negada para o ServPilot.',
            abrirConfiguracoes: true);
      }
      if (permissao == LocationPermission.denied || permissao == LocationPermission.unableToDetermine) {
        return const LeituraPosicao._(null, 'Sem permissão de localização.');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.best, timeLimit: limite),
      );
      return LeituraPosicao._(
        Posicao(latitude: p.latitude, longitude: p.longitude, precisaoM: p.accuracy, em: p.timestamp.toLocal()),
        null,
      );
    } on TimeoutException {
      return const LeituraPosicao._(null, 'O GPS não respondeu a tempo (sem sinal aqui).');
    } catch (e) {
      return LeituraPosicao._(null, 'Não foi possível ler o GPS: $e');
    }
  }

  /// Abre a tela do celular onde se liga a localização ou a permissão do app.
  static Future<void> abrirConfiguracoes({bool doApp = true}) async {
    try {
      if (doApp) {
        await Geolocator.openAppSettings();
      } else {
        await Geolocator.openLocationSettings();
      }
    } catch (_) {
      // Sem a tela no aparelho: a pessoa liga pelo menu.
    }
  }
}
