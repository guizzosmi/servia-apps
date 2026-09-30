import 'package:flutter/material.dart';

import '../servicos/status.dart';

/// Campo de data (abre o calendário). Opcional: tem botão de limpar.
class CampoData extends StatelessWidget {
  const CampoData({
    super.key,
    required this.rotulo,
    required this.valor,
    required this.aoMudar,
    this.habilitado = true,
  });

  final String rotulo;
  final DateTime? valor;
  final ValueChanged<DateTime?> aoMudar;
  final bool habilitado;

  Future<void> _escolher(BuildContext context) async {
    final d = await showDatePicker(
      context: context,
      initialDate: valor ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) aoMudar(d);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: habilitado ? () => _escolher(context) : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: rotulo,
          enabled: habilitado,
          suffixIcon: valor != null && habilitado
              ? IconButton(
                  tooltip: 'Limpar',
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => aoMudar(null),
                )
              : const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(valor == null ? '' : dataBr(dataIso(valor!))),
      ),
    );
  }
}

/// Campo de hora (abre o relógio). Opcional: tem botão de limpar.
class CampoHora extends StatelessWidget {
  const CampoHora({
    super.key,
    required this.rotulo,
    required this.valor,
    required this.aoMudar,
    this.habilitado = true,
  });

  final String rotulo;
  final TimeOfDay? valor;
  final ValueChanged<TimeOfDay?> aoMudar;
  final bool habilitado;

  Future<void> _escolher(BuildContext context) async {
    final t = await showTimePicker(
      context: context,
      initialTime: valor ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (t != null) aoMudar(t);
  }

  @override
  Widget build(BuildContext context) {
    final texto = valor == null
        ? ''
        : '${valor!.hour.toString().padLeft(2, '0')}:${valor!.minute.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: habilitado ? () => _escolher(context) : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: rotulo,
          enabled: habilitado,
          suffixIcon: valor != null && habilitado
              ? IconButton(
                  tooltip: 'Limpar',
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => aoMudar(null),
                )
              : const Icon(Icons.schedule, size: 18),
        ),
        child: Text(texto),
      ),
    );
  }
}

/// '08:30:00' -> TimeOfDay(8, 30)
TimeOfDay? horaDoBanco(Object? v) {
  final s = '${v ?? ''}';
  if (s.length < 5) return null;
  final h = int.tryParse(s.substring(0, 2));
  final m = int.tryParse(s.substring(3, 5));
  return (h == null || m == null) ? null : TimeOfDay(hour: h, minute: m);
}

/// TimeOfDay -> '08:30' (ou null)
String? horaParaBanco(TimeOfDay? t) =>
    t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
