import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/acoes_atendimento.dart';
import '../core/consultas.dart';
import '../core/estado.dart';

/// "Estou neste serviço": confere se a pessoa está em outro serviço (e
/// pergunta se sai de lá), deixa o líder escolher quem entra junto e abre
/// o atendimento (com [abrir]).
Future<void> entrarNoServico(BuildContext context, Map<String, dynamic> item, {bool abrir = true}) async {
  final banco = EstadoApp.instancia.banco!;
  final atdId = AcoesAtendimento.idAtendimento(item['id']);
  final parte = banco.um('partes_diarias', item['parte_id']) ?? const {};

  // Já está em outro serviço? Sai de lá no mesmo instante.
  final atual = AcoesAtendimento.meuCheckin();
  if (atual != null && atual['atendimento_id'] != atdId) {
    final outro = banco.um('atendimentos', atual['atendimento_id']);
    final osOutro = outro == null ? null : banco.um('ordens_servico', outro['os_id']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Você está em outro serviço'),
        content: Text('Ao entrar aqui, você sai de ${osOutro?['codigo'] ?? 'outro serviço'} agora.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Entrar aqui')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
  }

  // O líder leva junto quem está livre (pode desmarcar alguém).
  var acompanhantes = <String>[];
  if (parte['lider_colaborador_id'] == AcoesAtendimento.eu) {
    final livres = AcoesAtendimento.membrosLivres('${parte['id']}');
    if (livres.isNotEmpty) {
      final escolha = await showModalBottomSheet<List<String>>(
        context: context,
        builder: (ctx) => _QuemEntra(livres: livres, nome: banco.nomeColaborador),
      );
      if (escolha == null || !context.mounted) return;
      acompanhantes = escolha;
    }
  }

  final id = await AcoesAtendimento.checkin(item, acompanhantes: acompanhantes);
  if (abrir && context.mounted) await context.push('/atendimento/$id');
}

class _QuemEntra extends StatefulWidget {
  const _QuemEntra({required this.livres, required this.nome});

  final List<String> livres;
  final String Function(Object?) nome;

  @override
  State<_QuemEntra> createState() => _QuemEntraState();
}

class _QuemEntraState extends State<_QuemEntra> {
  late final Set<String> _sel = {...widget.livres};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // Rola se a equipe for grande (a folha tem altura máxima).
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ListTile(
            title: Text('Quem entra com você?', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Membros da equipe que não estão em outro serviço.'),
          ),
          for (final c in widget.livres)
            CheckboxListTile(
              value: _sel.contains(c),
              title: Text(widget.nome(c)),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _sel.add(c);
                } else {
                  _sel.remove(c);
                }
              }),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_sel.toList()),
                child: Text(_sel.isEmpty ? 'Entrar só eu' : 'Entrar com ${_sel.length}'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
