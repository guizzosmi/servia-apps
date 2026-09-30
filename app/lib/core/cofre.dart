import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cofre do aparelho (Keystore no Android, Keychain no iOS).
/// Guarda a sessão de login, a chave do banco local, o id do aparelho
/// e quem está usando o app.
class Cofre {
  static const _cofre = FlutterSecureStorage();

  static const chaveSessao = 'servia_sessao';
  static const chaveBanco = 'servia_chave_banco';
  static const chaveDispositivo = 'servia_dispositivo';
  static const chaveConta = 'servia_conta';

  static Future<String?> ler(String chave) => _cofre.read(key: chave);
  static Future<void> gravar(String chave, String valor) => _cofre.write(key: chave, value: valor);
  static Future<void> apagar(String chave) => _cofre.delete(key: chave);

  /// Texto aleatório forte (32 bytes em base64), para chaves.
  static String aleatorio() {
    final r = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => r.nextInt(256)));
  }
}

/// Onde o Supabase guarda a sessão de login: no cofre, e não nas
/// preferências comuns do aparelho.
class ArmazenamentoSessao extends LocalStorage {
  const ArmazenamentoSessao();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await Cofre.ler(Cofre.chaveSessao)) != null;

  /// Apesar do nome, devolve a sessão inteira (em JSON), como o Supabase espera.
  @override
  Future<String?> accessToken() => Cofre.ler(Cofre.chaveSessao);

  @override
  Future<void> removePersistedSession() => Cofre.apagar(Cofre.chaveSessao);

  @override
  Future<void> persistSession(String persistSessionString) =>
      Cofre.gravar(Cofre.chaveSessao, persistSessionString);
}

/// Quem está usando o app neste aparelho. Fica salvo para o app abrir
/// sem internet (a sessão de login pode ter vencido; os dados, não).
class ContaLocal {
  const ContaLocal({
    required this.usuarioId,
    required this.email,
    required this.contaId,
    required this.empresaId,
    required this.colaboradorId,
    required this.dispositivoId,
  });

  final String usuarioId;
  final String email;
  final String contaId;
  final String empresaId;
  final String colaboradorId;
  final String dispositivoId;

  Map<String, dynamic> toJson() => {
        'usuario_id': usuarioId,
        'email': email,
        'conta_id': contaId,
        'empresa_id': empresaId,
        'colaborador_id': colaboradorId,
        'dispositivo_id': dispositivoId,
      };

  static ContaLocal? deJson(String? texto) {
    if (texto == null) return null;
    try {
      final m = jsonDecode(texto) as Map<String, dynamic>;
      return ContaLocal(
        usuarioId: m['usuario_id'] as String,
        email: m['email'] as String,
        contaId: m['conta_id'] as String,
        empresaId: m['empresa_id'] as String,
        colaboradorId: m['colaborador_id'] as String,
        dispositivoId: m['dispositivo_id'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<ContaLocal?> carregar() async => deJson(await Cofre.ler(Cofre.chaveConta));
  Future<void> salvar() => Cofre.gravar(Cofre.chaveConta, jsonEncode(toJson()));
}
