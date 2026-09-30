import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/cofre.dart';
import 'core/estado.dart';
import 'rotas.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: Config.supabaseUrl,
    publishableKey: Config.supabaseChavePublica,
    // A sessão fica no cofre do aparelho, não nas preferências comuns.
    authOptions: const FlutterAuthClientOptions(localStorage: ArmazenamentoSessao()),
  );
  try {
    await EstadoApp.instancia.iniciar();
  } catch (e) {
    // Cofre ilegível (ex.: backup restaurado em outro aparelho): começa pelo login.
    debugPrint('Falha ao abrir os dados locais: $e');
  }
  runApp(const ServiaApp());
}

class ServiaApp extends StatelessWidget {
  const ServiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ServIA',
      debugShowCheckedModeBanner: false,
      theme: temaServia(),
      routerConfig: rotas,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
