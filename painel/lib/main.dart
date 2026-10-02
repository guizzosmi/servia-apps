import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'rotas.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Abrir uma tela com push (OS, orçamento...) também muda o endereço do
  // navegador: recarregar a página (F5) volta para a mesma tela.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  await Supabase.initialize(
    url: Config.supabaseUrl,
    publishableKey: Config.supabaseChavePublica,
  );
  runApp(const PainelApp());
}

class PainelApp extends StatelessWidget {
  const PainelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ServPilot · Painel',
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
