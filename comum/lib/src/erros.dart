import 'package:supabase_flutter/supabase_flutter.dart';

/// Nome do índice único no banco -> frase para o usuário.
const _duplicados = {
  'clientes_documento_uk': 'Já existe um cliente com este CPF/CNPJ.',
  'clientes_interno_uk': 'Esta empresa já tem o cliente interno.',
  'equipamentos_codigo_uk': 'Este cliente já tem um equipamento ativo com este código.',
  'produtos_codigo_uk': 'Já existe um produto ou serviço com este código.',
  'modelos_medicao_codigo_uk': 'Este tipo de equipamento já tem uma medição com este código.',
  'colaboradores_usuario_uk': 'Este usuário já está ligado a outro colaborador.',
  'equipe_membros_lider_uk': 'Esta equipe já tem um líder. Troque o atual para membro antes.',
  'equipe_membros_uk': 'Este colaborador já está nesta equipe.',
};

/// Transforma qualquer erro em uma frase que o usuário entenda.
String mensagemDeErro(Object e) {
  if (_semConexao(e)) {
    return 'Sem conexão com a internet. Confira o Wi-Fi ou os dados móveis e tente de novo.';
  }
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'E-mail ou senha incorretos.';
    if (m.contains('banned')) {
      return 'Usuário desativado. Fale com o administrador da sua empresa.';
    }
    if (m.contains('email not confirmed')) {
      return 'E-mail ainda não confirmado.';
    }
    return 'Falha no login: ${e.message}';
  }
  if (e is PostgrestException) {
    switch (e.code) {
      case '23505':
        for (final regra in _duplicados.entries) {
          if (e.message.contains(regra.key)) return regra.value;
        }
        return 'Já existe um registro com esses dados (duplicado).';
      case '23503':
        return 'Este registro está ligado a outro que não existe ou que ainda o usa.';
      case '23502':
        return 'Falta preencher um campo obrigatório.';
      case '23514':
        return 'Algum valor está fora do permitido.';
      case '42501':
        return 'Sem permissão para esta ação.';
      case 'PGRST116':
        return 'Registro não encontrado.';
    }
    return e.message;
  }
  if (e is FunctionException) {
    // As funções respondem { code, message, detail } (ver _shared/http.ts).
    final d = e.details;
    if (d is Map && d['message'] != null) return d['message'].toString();
    return 'Erro no servidor (${e.status}).';
  }
  return e.toString();
}

/// Falha de rede (sem internet, DNS, servidor inalcançável).
bool _semConexao(Object e) {
  if (e is AuthRetryableFetchException) return true;
  final t = e.toString();
  return t.contains('SocketException') ||
      t.contains('Failed host lookup') ||
      t.contains('ClientException') ||
      t.contains('Connection refused') ||
      t.contains('Network is unreachable');
}
