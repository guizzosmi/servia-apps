import 'package:flutter/material.dart';

/// Cores da identidade visual do ServIA (ver "Identidade visual" na especificação).
class Cores {
  static const indigo700 = Color(0xFF1E2A5A); // primária
  static const indigo500 = Color(0xFF3A4FA8); // links, foco, seleção
  static const indigo100 = Color(0xFFE6E9F6); // fundos de destaque
  static const coral500 = Color(0xFFF0643A); // voz, IA, gravar
  static const neutro = Color(0xFF5B6474); // pendente, texto secundário
  static const info = Color(0xFF2F6DB5); // agendado
  static const andamento = Color(0xFF0F7C8C); // em execução
  static const alerta = Color(0xFFB96A00); // aguardando
  static const sucesso = Color(0xFF1E8E5A); // concluído
  static const erro = Color(0xFFC8372D); // não realizado
  static const tinta = Color(0xFF121A2B); // texto
  static const linha = Color(0xFFDCE1EA); // bordas
  static const fundo = Color(0xFFF5F6FA); // fundo de tela
}

ThemeData temaServia() {
  final esquema = ColorScheme.fromSeed(
    seedColor: Cores.indigo700,
    primary: Cores.indigo700,
    secondary: Cores.coral500,
    error: Cores.erro,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: Cores.fundo,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Cores.tinta,
      elevation: 0,
      surfaceTintColor: Colors.white,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Cores.linha),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
