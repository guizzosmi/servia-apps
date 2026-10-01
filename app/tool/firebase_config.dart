// Gera lib/core/firebase_opcoes.dart a partir do google-services.json.
//
// Uso (na pasta servia-apps\app):
//   dart run tool/firebase_config.dart
//   dart run tool/firebase_config.dart C:\caminho\google-services.json
//
// Os valores deste arquivo NÃO são segredo (vão dentro do app instalado).
// O segredo do Firebase é a conta de serviço, que fica só na plataforma.
import 'dart:convert';
import 'dart:io';

const pacote = 'app.servia.servia_app';
const destino = 'lib/core/firebase_opcoes.dart';

Never falhar(String mensagem) {
  stderr.writeln(mensagem);
  exit(1);
}

void main(List<String> args) {
  final caminho = args.isNotEmpty ? args.first : 'android/app/google-services.json';
  final arquivo = File(caminho);
  if (!arquivo.existsSync()) {
    falhar('Não achei $caminho. Baixe o google-services.json no Firebase e salve em android\\app\\.');
  }
  final Map<String, dynamic> j;
  try {
    j = jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {
    falhar('$caminho não é um JSON válido. Baixe de novo no Firebase.');
  }
  final projeto = j['project_info'] as Map<String, dynamic>? ?? const {};
  final clientes = (j['client'] as List? ?? const []).cast<Map<String, dynamic>>();
  final cliente = clientes.where((c) {
    final info = (c['client_info'] as Map?)?['android_client_info'] as Map?;
    return info?['package_name'] == pacote;
  }).firstOrNull;
  if (cliente == null) {
    falhar('O google-services.json não tem o app $pacote. No Firebase, adicione um app Android com esse nome de pacote.');
  }
  final appId = (cliente['client_info'] as Map)['mobilesdk_app_id'];
  final chaves = (cliente['api_key'] as List? ?? const []);
  final apiKey = chaves.isEmpty ? null : (chaves.first as Map)['current_key'];
  final remetente = projeto['project_number'];
  final projetoId = projeto['project_id'];
  if (appId == null || apiKey == null || remetente == null || projetoId == null) {
    falhar('Faltam dados no google-services.json (app, chave ou projeto). Baixe de novo no Firebase.');
  }
  final bucket = projeto['storage_bucket'];

  File(destino).writeAsStringSync('''
// Configuração do Firebase (notificações no celular).
//
// GERADO por tool/firebase_config.dart a partir do google-services.json
// (projeto $projetoId). Para trocar, rode o comando de novo; não edite à mão.
// O tipo continua "FirebaseOptions?" porque, sem configuração, o valor é null.
// ignore_for_file: unnecessary_nullable_for_final_variable_declarations
import 'package:firebase_core/firebase_core.dart';

const FirebaseOptions? opcoesFirebase = FirebaseOptions(
  apiKey: '$apiKey',
  appId: '$appId',
  messagingSenderId: '$remetente',
  projectId: '$projetoId',${bucket == null ? '' : "\n  storageBucket: '$bucket',"}
);
''');
  stdout.writeln('Pronto: $destino gerado (projeto $projetoId).');
}
