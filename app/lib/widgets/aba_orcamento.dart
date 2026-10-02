import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_orcamento.dart';
import '../core/formatos.dart';
import 'status_chip.dart';

/// Aba "Orçamento" do atendimento: os orçamentos da OS e o botão para
/// montar um no local (ou colher a assinatura do que o gestor enviou).
class AbaOrcamento extends StatelessWidget {
  const AbaOrcamento({super.key, required this.atd, required this.habilitado});

  final Map<String, dynamic> atd;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    final pode = AcoesOrcamento.podeOrcar(atd);
    final orcamentos = AcoesOrcamento.daOs(atd['os_id']);
    final aberto = AcoesOrcamento.abertoDaOs(atd['os_id']);
    final emMontagem = AcoesOrcamento.rascunho(atd['id']) != null;
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (habilitado && pode)
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: () => context.push('/orcamento/${atd['id']}'),
            icon: Icon(aberto?['status'] == 'enviado' ? Icons.draw_outlined : Icons.request_quote_outlined),
            label: Text(emMontagem
                ? 'Continuar o orçamento'
                : aberto?['status'] == 'enviado'
                    ? 'Colher assinatura do ${AcoesOrcamento.codigo(aberto!)}'
                    : 'Montar orçamento'),
          ),
        ),
      if (!pode)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(AcoesOrcamento.motivoSemPermissao(), style: const TextStyle(color: Cores.neutro)),
        ),
      const SizedBox(height: 8),
      if (orcamentos.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nenhum orçamento nesta OS.', style: TextStyle(color: Cores.neutro)),
        ),
      for (final o in orcamentos)
        Builder(builder: (_) {
          final aceite = AcoesOrcamento.aceiteDe('orcamento', o['id']);
          return Card(
            child: ListTile(
              title: Text(AcoesOrcamento.codigo(o)),
              subtitle: Text([
                dinheiro(o['total']),
                if (aceite != null)
                  '${aceite['decisao'] == 'aprovado' ? 'aprovado' : 'recusado'} por ${aceite['nome']}',
                if (o['origem'] == 'app') 'feito no local',
              ].join(' · ')),
              trailing: StatusChip(o['status'] as String?, statusOrcamento),
            ),
          );
        }),
    ]);
  }
}
