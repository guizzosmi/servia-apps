import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/estado.dart';

/// O administrador desconectou este aparelho. Nenhum dado é mostrado;
/// ao tocar em OK, o app apaga tudo e volta para o login.
class RevogadoTela extends StatelessWidget {
  const RevogadoTela({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.phonelink_erase, size: 64, color: Cores.erro),
            const SizedBox(height: 16),
            const Text('Este aparelho foi desconectado pelo administrador.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Fale com o gestor da sua empresa.',
                textAlign: TextAlign.center, style: TextStyle(color: Cores.neutro)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => EstadoApp.instancia.sair(),
              child: const Text('OK'),
            ),
          ]),
        ),
      ),
    );
  }
}
