import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'rotas.dart';

/// Versão do admin (aparece nos erros enviados para a plataforma).
const versaoAdmin = '0.1.0';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoRouter.optionURLReflectsImperativeAPIs = true;
  await Supabase.initialize(
    url: Config.supabaseUrl,
    publishableKey: Config.supabaseChavePublica,
  );
  // Os erros entram como "painel", com a versão "admin-..." para separar.
  ErrosRemotos.ligar(origem: 'painel', versao: 'admin-$versaoAdmin', plataforma: 'web');
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ServPilot · Administração',
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
