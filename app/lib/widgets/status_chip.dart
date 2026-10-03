import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/estado.dart';
import '../core/formatos.dart';

/// Etiqueta colorida de status: sempre cor e texto.
class StatusChip extends StatelessWidget {
  const StatusChip(this.codigo, this.tabela, {super.key});

  final String? codigo;
  final Map<String, Rotulo> tabela;

  @override
  Widget build(BuildContext context) {
    final r = tabela[codigo] ?? Rotulo(codigo ?? '—', Colors.grey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: r.cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: r.cor.withValues(alpha: 0.5)),
      ),
      child: Text(r.texto, style: TextStyle(color: r.cor, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// Selo pequeno (Novo, Alterado, Apoio...).
class Selo extends StatelessWidget {
  const Selo(this.texto, this.cor, {super.key});
  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: cor.withValues(alpha: .12), borderRadius: BorderRadius.circular(4)),
        child: Text(texto, style: TextStyle(fontSize: 11, color: cor, fontWeight: FontWeight.w700)),
      );
}

/// Situação de envio de um registro criado no aparelho (OS aberta, cadastro
/// rápido): "Aguardando envio", "Recusado" ou null (já subiu, ou veio da
/// plataforma).
String? textoEnvio(Object? id) {
  if (id == null) return null;
  return switch (EstadoApp.instancia.banco?.criadosNaFila['$id']) {
    'pendente' => 'Aguardando envio',
    'recusada' => 'Recusado (veja Sincronização)',
    _ => null,
  };
}

/// Selo de envio (nada, se o registro já subiu).
class SeloEnvio extends StatelessWidget {
  const SeloEnvio(this.id, {super.key});
  final Object? id;

  @override
  Widget build(BuildContext context) {
    final texto = textoEnvio(id);
    if (texto == null) return const SizedBox.shrink();
    return Selo(texto, texto.startsWith('Recusado') ? Cores.erro : Cores.alerta);
  }
}
