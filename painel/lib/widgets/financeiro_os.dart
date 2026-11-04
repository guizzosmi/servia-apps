import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/cobranca.dart';
import '../servicos/status.dart' show dataBr;
import 'itens_os.dart' show dinheiro;

/// Guia 84: a cobrança da OS, mostrada na própria OS, com o botão
/// "Reabrir o financeiro" (desfaz a cobrança e destrava os itens).
class FinanceiroDaOs extends StatefulWidget {
  const FinanceiroDaOs({super.key, required this.osId, required this.aoMudar});

  final String osId;
  final VoidCallback aoMudar;

  @override
  State<FinanceiroDaOs> createState() => _FinanceiroDaOsState();
}

/// Lê a cobrança da OS (null se não der: técnico ou sem permissão).
Future<Map<String, dynamic>?> cobrancaDaOs(String osId) async {
  try {
    final r = await Supabase.instance.client.rpc('os_cobranca', params: {
      'p': {'os_id': osId}
    });
    return r is Map ? Map<String, dynamic>.from(r) : null;
  } catch (_) {
    return null;
  }
}

/// Confirma e desfaz a cobrança. true = reabriu.
Future<bool> reabrirFinanceiro(BuildContext context, Map<String, dynamic> cob, List notas) async {
  final outras = ((cob['outras_os'] as List?) ?? const []).map((x) => '$x').toList();
  final recebida = cob['recebido_em'] != null;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Reabrir o financeiro da OS?'),
      content: SizedBox(
        width: 480,
        child: Text([
          if (recebida)
            'Esta cobrança já foi recebida (${dataBr(cob['recebido_em'])}). Desfaça antes o recebimento no Caixa e depois reabra aqui.'
          else ...[
            'A cobrança é desfeita e a OS volta para "A cobrar". Os itens ficam livres para incluir, alterar ou excluir; depois é só cobrar de novo.',
            if (outras.isNotEmpty) 'A mesma cobrança tem também ${outras.join(', ')}: elas voltam para "A cobrar" junto.',
            if ((cob['nf_numero'] ?? '') != '')
              'A nota ${cob['nf_numero']} não é cancelada aqui: se precisar, cancele ou substitua no sistema de notas.',
            if (notas.isNotEmpty) 'Há nota fiscal emitida pelo ServPilot nesta OS: cancele em Notas fiscais se o valor mudar.',
          ],
        ].join('\n\n')),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(recebida ? 'Entendi' : 'Voltar')),
        if (!recebida)
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Reabrir o financeiro')),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await desfazerCobranca(cobrancaId: '${cob['id']}');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Financeiro reaberto: os itens já podem ser alterados.')));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensagemDeErro(e)), backgroundColor: Cores.erro));
    }
    return false;
  }
}

class _FinanceiroDaOsState extends State<FinanceiroDaOs> {
  Map<String, dynamic>? _r;

  @override
  void initState() {
    super.initState();
    cobrancaDaOs(widget.osId).then((r) {
      if (mounted) setState(() => _r = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final cob = r?['cobranca'] is Map ? Map<String, dynamic>.from(r!['cobranca'] as Map) : null;
    if (cob == null) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text('OS cobrada: os itens não mudam mais.', style: TextStyle(color: Cores.neutro)),
      );
    }
    final outras = ((cob['outras_os'] as List?) ?? const []).map((x) => '$x').toList();
    final notas = (r?['notas'] as List?) ?? const [];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Cores.indigo100, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.lock_outline, color: Cores.indigo700),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            [
              'OS cobrada em ${dataBr(cob['criado_em'])}',
              (cob['nf_numero'] ?? '') != '' ? 'nota ${cob['nf_numero']}' : 'sem nota',
              dinheiro(cob['valor']),
              if (outras.isNotEmpty) 'junto com ${outras.join(', ')}',
              if (cob['recebido_em'] != null) 'recebida em ${dataBr(cob['recebido_em'])}',
            ].join(' · '),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () async {
            if (await reabrirFinanceiro(context, cob, notas)) widget.aoMudar();
          },
          icon: const Icon(Icons.lock_open_outlined, size: 18),
          label: const Text('Reabrir o financeiro'),
        ),
      ]),
    );
  }
}
