import 'package:flutter/material.dart';

import '../servicos/status.dart';

/// Etiqueta colorida de status (OS, agendamento, item, parte, prioridade).
class StatusChip extends StatelessWidget {
  const StatusChip(this.codigo, this.tabela, {super.key, this.compacto = false});

  final String? codigo;
  final Map<String, Rotulo> tabela;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final r = tabela[codigo] ?? Rotulo(codigo ?? '—', Colors.grey);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compacto ? 6 : 10, vertical: compacto ? 2 : 4),
      decoration: BoxDecoration(
        color: r.cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: r.cor.withValues(alpha: 0.5)),
      ),
      child: Text(
        r.texto,
        style: TextStyle(
          color: r.cor,
          fontSize: compacto ? 11 : 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
