import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

/// Logotipo em texto: "Serv" em índigo + "IA" em coral.
class Marca extends StatelessWidget {
  const Marca({super.key, this.tamanho = 22, this.claro = false});

  final double tamanho;
  final bool claro;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: tamanho, fontWeight: FontWeight.w800),
        children: [
          TextSpan(
            text: 'Serv',
            style: TextStyle(color: claro ? Colors.white : Cores.indigo700),
          ),
          const TextSpan(text: 'IA', style: TextStyle(color: Cores.coral500)),
        ],
      ),
    );
  }
}
