import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Chama uma Edge Function da plataforma e devolve a resposta (JSON).
/// Erros (4xx/5xx) viram FunctionException, que mensagemDeErro() traduz.
Future<Map<String, dynamic>> chamarFuncao(
    String nome, Map<String, dynamic> corpo) async {
  final r = await Supabase.instance.client.functions.invoke(nome, body: corpo);
  final d = r.data;
  return d is Map<String, dynamic> ? d : <String, dynamic>{};
}

/// Nome de cada papel para exibir na tela.
const rotulosPapeis = {
  'admin': 'Admin',
  'gestor': 'Gestor',
  'financeiro': 'Financeiro',
  'tecnico': 'Técnico',
};

/// Login por matrícula + PIN usa um e-mail técnico que termina assim.
bool ehLoginPorPin(String? email) =>
    (email ?? '').endsWith('.${Config.dominioEmailApp}');

/// Matrícula tirada do e-mail técnico (parte antes do @).
String matriculaDoEmail(String email) => email.split('@').first;
