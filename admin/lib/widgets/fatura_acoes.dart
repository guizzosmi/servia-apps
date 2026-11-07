import 'package:flutter/material.dart';

import '../api.dart';
import 'comuns.dart';

/// Menu de ações de uma fatura (lista de faturas e tela do cliente).
class MenuFatura extends StatelessWidget {
  const MenuFatura({super.key, required this.fatura, required this.aoMudar});

  final Map<String, dynamic> fatura;
  final VoidCallback aoMudar;

  @override
  Widget build(BuildContext context) {
    final aberta = fatura['situacao'] == 'aberta';
    final paga = fatura['situacao'] == 'paga';
    final pagaNoMp = paga && fatura['mp_pagamento_id'] != null && numero(fatura['valor_pago']) > 0;
    return PopupMenuButton<String>(
      tooltip: 'Ações',
      onSelected: (acao) async {
        final mudou = await _executar(context, acao);
        if (mudou) aoMudar();
      },
      itemBuilder: (_) => [
        if (aberta) const PopupMenuItem(value: 'link', child: Text('Copiar link de pagamento')),
        if (aberta) const PopupMenuItem(value: 'baixa', child: Text('Dar baixa (pago fora do Mercado Pago)')),
        if (paga) const PopupMenuItem(value: 'nf', child: Text('Registrar a nota fiscal')),
        if (aberta) const PopupMenuItem(value: 'cancelar', child: Text('Cancelar fatura')),
        if (pagaNoMp) const PopupMenuItem(value: 'estornar', child: Text('Devolver no Mercado Pago (estorno)')),
      ],
    );
  }

  Future<bool> _executar(BuildContext context, String acao) async {
    final id = fatura['id'] as String;
    try {
      switch (acao) {
        case 'link':
          await copiarLinkPagamento(id);
          if (context.mounted) avisar(context, 'Link copiado: cole no WhatsApp ou no e-mail do cliente (vale 3 dias).');
          return true;
        case 'baixa':
          final forma = TextEditingController(text: 'pix');
          final valor = TextEditingController(text: numero(fatura['valor_total']).toStringAsFixed(2).replaceAll('.', ','));
          final obs = TextEditingController();
          final ok = await dialogoForm(context, titulo: 'Dar baixa na fatura ${fatura['numero']}', confirmar: 'Dar baixa', campos: [
            campoTexto(forma, 'Forma', ajuda: 'pix, boleto, cartao, transferencia, dinheiro'),
            campoTexto(valor, 'Valor recebido (R\$)', teclado: TextInputType.number),
            campoTexto(obs, 'Observação'),
          ]);
          if (!ok) return false;
          await rpcMapa('admin_fatura_acao', {
            'p': {'acao': 'baixa', 'fatura_id': id, 'forma': forma.text.trim(), 'valor': numero(valor.text), 'obs': obs.text.trim()}
          });
          if (context.mounted) avisar(context, 'Baixa feita.');
          return true;
        case 'nf':
          final nf = TextEditingController(text: '${fatura['nf_numero'] ?? ''}');
          final data = TextEditingController(text: dataBr(fatura['nf_emitida_em'] ?? DateTime.now().toIso8601String()));
          final obs = TextEditingController();
          final ok = await dialogoForm(context, titulo: 'Nota fiscal da fatura ${fatura['numero']}', campos: [
            campoTexto(nf, 'Número da nota'),
            campoTexto(data, 'Emitida em (dd/mm/aaaa)'),
            campoTexto(obs, 'Observação'),
          ]);
          if (!ok) return false;
          await rpcMapa('admin_fatura_acao', {
            'p': {'acao': 'nf', 'fatura_id': id, 'nf_numero': nf.text.trim(), 'nf_emitida_em': dataIso(data.text), 'nf_obs': obs.text.trim()}
          });
          if (context.mounted) avisar(context, 'Nota registrada.');
          return true;
        case 'cancelar':
          final motivo = TextEditingController();
          final ok = await dialogoForm(context, titulo: 'Cancelar a fatura ${fatura['numero']}?', confirmar: 'Cancelar fatura', campos: [
            campoTexto(motivo, 'Motivo'),
          ]);
          if (!ok) return false;
          await rpcMapa('admin_fatura_acao', {'p': {'acao': 'cancelar', 'fatura_id': id, 'motivo': motivo.text.trim()}});
          if (context.mounted) avisar(context, 'Fatura cancelada.');
          return true;
        case 'estornar':
          // Guia 89: devolve o pagamento inteiro no Mercado Pago e desfaz créditos, cupom e comissão da fatura.
          final ok = await dialogoForm(context, titulo: 'Devolver ${moeda(fatura['valor_pago'])} da fatura ${fatura['numero']}?',
              confirmar: 'Devolver', campos: [
            Text(fatura['tipo'] == 'anual'
                ? 'O cliente volta ao pagamento mensal. Se o período já começou, a mensalidade do ciclo atual é gerada.'
                : 'A fatura fica como devolvida. Comissão já paga ao parceiro é descontada do próximo pagamento.'),
          ]);
          if (!ok) return false;
          await db.functions.invoke('cobranca', body: {'acao': 'estornar', 'fatura_id': id});
          if (context.mounted) avisar(context, 'Valor devolvido no Mercado Pago.');
          return true;
      }
    } catch (e) {
      if (context.mounted) avisarErro(context, e);
    }
    return false;
  }
}
