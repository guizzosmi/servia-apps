import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/cofre.dart';
import 'core/estado.dart';
import 'core/notificacoes.dart';
import 'rotas.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // O app do técnico é só para celular/tablet (banco local, câmera, cofre).
    runApp(const _SoNoCelular());
    return;
  }
  await Supabase.initialize(
    url: Config.supabaseUrl,
    publishableKey: Config.supabaseChavePublica,
    // A sessão fica no cofre do aparelho, não nas preferências comuns.
    authOptions: const FlutterAuthClientOptions(localStorage: ArmazenamentoSessao()),
  );
  // Notificações: com o aviso chegando, o app sincroniza para trazer a mudança.
  await Notificacoes.iniciar(aoChegar: () => EstadoApp.instancia.sync?.pedir());
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
      scaffoldMessengerKey: Notificacoes.mensageiro,
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

class _SoNoCelular extends StatelessWidget {
  const _SoNoCelular();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: temaServia(),
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Este é o app do técnico: ele roda no celular ou tablet.\n'
                'No navegador, use o painel (pasta servia-apps\\painel).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
        ),
      );
}
