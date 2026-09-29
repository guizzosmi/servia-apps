import 'package:flutter/material.dart';

import '../cadastros/definicoes.dart';
import '../cadastros/lista.dart';

/// Página de um cadastro (ex.: /c/clientes). Toda a lógica está em ListaCadastro.
class CadastroListaTela extends StatelessWidget {
  const CadastroListaTela({super.key, required this.def});

  final CadastroDef def;

  @override
  Widget build(BuildContext context) => ListaCadastro(def: def);
}
