import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_orcamento.dart';
import '../core/acoes_reabrir.dart';
import '../core/consultas.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import '../core/regras_reabrir.dart';

/// Guia 109: "Reabrir OS" (o gestor ou o líder da equipe que fez o serviço).
/// Pede o motivo (obrigatório; dá para ditar pelo microfone do teclado),
/// mostra o que acontece e registra pela fila (funciona sem internet).
Future<void> reabrirOsDoServico(BuildContext context, Map<String, dynamic> item) async {
  final banco = EstadoApp.instancia.banco!;
  final os = banco.osDo(item);
  if (os == null) return;
  final parte = AcoesReabrir.parteParaRefazer(item);
  final simples = AcoesOrcamento.config.modoSimples;
  final explicacao = textoDaReabertura(
    osConcluida: os['status'] == 'concluida',
    equipeHoje: parte == null ? null : banco.nomeEquipe(parte['equipe_id']),
    modoSimples: simples,
  );
  final campo = TextEditingController();
  final motivo = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text('Reabrir a ${codigoOs(os)}?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(explicacao),
            const SizedBox(height: 12),
            TextField(
              controller: campo,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Motivo da reabertura *',
                hintText: 'Ex.: o cliente ligou, o vazamento voltou. Dá para ditar pelo microfone do teclado.',
              ),
              onChanged: (_) => setD(() {}),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: campo.text.trim().isEmpty ? null : () => Navigator.of(ctx).pop(campo.text.trim()),
            child: const Text('Reabrir'),
          ),
        ],
      ),
    ),
  );
  // Sem dispose: o diálogo ainda anima a saída usando o campo.
  if (motivo == null || motivo.isEmpty || !context.mounted) return;
  try {
    final novo = await AcoesReabrir.reabrir(item, motivo);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(novo != null
          ? '${codigoOs(os)} reaberta: o serviço voltou para o fim da sua parte de hoje.'
          : simples
              ? '${codigoOs(os)} reaberta: a visita nova vai para "Para agendar" (Agenda).'
              : '${codigoOs(os)} reaberta: a visita nova vai para a fila do escritório.'),
    ));
    if (novo != null) await context.push('/servico/$novo');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não deu para registrar: $e'), backgroundColor: Cores.erro));
    }
  }
}
