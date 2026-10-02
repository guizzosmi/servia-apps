import 'package:flutter/material.dart';

/// Composições da marca ServPilot (arte em imagens/ServPilot-vetores).
enum MarcaLayout {
  /// Símbolo + "ServPilot" + "Gestão inteligente de serviços".
  horizontal,

  /// Símbolo + "ServPilot", sem a frase (barras e cabeçalhos).
  compacta,

  /// Símbolo em cima, nome e frase embaixo (telas de entrada no celular).
  vertical,

  /// Só o símbolo.
  simbolo,
}

/// Logo do ServPilot. [altura] é a altura do desenho; a largura segue a proporção.
/// Use [fundoEscuro] sobre fundos escuros (chave e "Serv" em branco).
class Marca extends StatelessWidget {
  const Marca({
    super.key,
    this.altura = 28,
    this.layout = MarcaLayout.compacta,
    this.fundoEscuro = false,
  });

  final double altura;
  final MarcaLayout layout;
  final bool fundoEscuro;

  @override
  Widget build(BuildContext context) {
    final nome = '${layout.name}${fundoEscuro ? '_escuro' : ''}';
    return Semantics(
      label: 'ServPilot',
      image: true,
      child: Image.asset(
        'assets/marca/$nome.png',
        package: 'servia_comum',
        height: altura,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }
}
