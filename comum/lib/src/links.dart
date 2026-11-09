import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre um endereço fora do app (loja, página de privacidade...).
/// Devolve false se o aparelho não conseguiu abrir.
Future<bool> abrirLink(String endereco) async {
  try {
    return await launchUrl(Uri.parse(endereco), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Como pedir a exclusão da conta e dos dados (exigido pelas lojas; guias 41 e 96).
const linkExcluirConta = 'https://servpilot.com.br/excluir-conta';

/// Termos de uso e política de privacidade (servpilot.com.br), para as telas de login.
class LinksLegais extends StatelessWidget {
  const LinksLegais({super.key});

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        children: [
          TextButton(
            onPressed: () => abrirLink('https://servpilot.com.br/termos'),
            child: const Text('Termos de uso'),
          ),
          TextButton(
            onPressed: () => abrirLink('https://servpilot.com.br/privacidade'),
            child: const Text('Privacidade'),
          ),
        ],
      );
}
