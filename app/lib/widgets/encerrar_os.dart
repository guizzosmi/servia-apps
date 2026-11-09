import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_atendimento.dart';
import '../core/acoes_encerrar.dart';
import '../core/consultas.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import '../core/regras_encerrar.dart';

/// Guia 111: "Encerrar a OS" no serviço concluído com a OS ainda aberta (só o
/// gestor). Mostra o que acontece e registra pela fila (funciona sem internet).
Future<void> encerrarOsDoServico(BuildContext context, Map<String, dynamic> item) async {
  final banco = EstadoApp.instancia.banco!;
  final os = banco.osDo(item);
  if (os == null) return;
  final visitas = AcoesEncerrar.outrasVisitas(os['id'], exceto: item['agendamento_id']);
  final bloqueio = bloqueioDoEncerramento(visitas.naAgenda);
  if (bloqueio != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(bloqueio)));
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Encerrar a ${codigoOs(os)}?'),
      content: Text(textoDoEncerramento(naFila: visitas.naFila)),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Encerrar a OS')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final atd = banco.um('atendimentos', AcoesAtendimento.idAtendimento(item['id']));
  try {
    await AcoesEncerrar.encerrar(os['id'], laudo: '${atd?['solucao'] ?? ''}');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${codigoOs(os)} encerrada: vai para o "A cobrar" do financeiro.')));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não deu para registrar: $e'), backgroundColor: Cores.erro));
    }
  }
}
