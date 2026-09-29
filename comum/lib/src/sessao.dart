import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Papéis possíveis de um usuário dentro de uma empresa
/// (mesma lista do check em usuario_empresas.papeis).
/// "Líder" não é papel: é uma posição dentro da equipe.
class Papel {
  static const admin = 'admin';
  static const gestor = 'gestor';
  static const financeiro = 'financeiro';
  static const tecnico = 'tecnico';
  static const cliente = 'cliente';
}

/// Dados de quem está usando o sistema, lidos do "crachá" (token) que o
/// Supabase entrega no login. Quem preenche esses dados é a função
/// `gerar_claims` do banco (Custom Access Token Hook).
class SessaoInfo {
  final String usuarioId;
  final String email;
  final String? contaId;
  final String? empresaId;
  final String? colaboradorId;
  final List<String> papeis;
  final bool plataformaAdmin;

  const SessaoInfo({
    required this.usuarioId,
    required this.email,
    required this.contaId,
    required this.empresaId,
    required this.colaboradorId,
    required this.papeis,
    required this.plataformaAdmin,
  });

  /// Tem o papel pedido? O admin da empresa passa em todos.
  bool tem(String papel) =>
      papeis.contains(Papel.admin) || papeis.contains(papel);

  /// Tem pelo menos um dos papéis?
  bool temAlgum(Iterable<String> lista) => lista.any(tem);

  /// Tem empresa ativa no token? (sem isso o banco não mostra nada)
  bool get temEmpresa => empresaId != null && contaId != null;

  static SessaoInfo? daSessao(Session? sessao) {
    if (sessao == null) return null;
    final dados = _lerToken(sessao.accessToken);
    final meta = (dados['app_metadata'] as Map?) ?? const {};
    return SessaoInfo(
      usuarioId: sessao.user.id,
      email: sessao.user.email ?? '',
      contaId: meta['conta_id'] as String?,
      empresaId: meta['empresa_id'] as String?,
      colaboradorId: meta['colaborador_id'] as String?,
      papeis: ((meta['papeis'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      plataformaAdmin: meta['plataforma_admin'] == true,
    );
  }

  static Map<String, dynamic> _lerToken(String token) {
    try {
      final partes = token.split('.');
      if (partes.length != 3) return const {};
      final texto =
          utf8.decode(base64Url.decode(base64Url.normalize(partes[1])));
      return jsonDecode(texto) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }
}

/// Atalhos para login, troca de empresa e saída.
class Sessao {
  static SupabaseClient get _db => Supabase.instance.client;

  /// Sessão atual (ou null se ninguém entrou).
  static SessaoInfo? get atual =>
      SessaoInfo.daSessao(_db.auth.currentSession);

  static Future<void> entrar(String email, String senha) async {
    await _db.auth.signInWithPassword(email: email.trim(), password: senha);
  }

  /// Troca a empresa ativa e renova o token para o banco enxergar a nova.
  static Future<void> trocarEmpresa(String empresaId) async {
    await _db.functions
        .invoke('sessao-empresa', body: {'empresa_id': empresaId});
    await _db.auth.refreshSession();
  }

  static Future<void> sair() => _db.auth.signOut();
}
