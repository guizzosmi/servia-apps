import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Integração com o Protheus (guia 105): o que as telas do ERP usam em comum.
/// As regras ficam no banco (erp_config, erp_fila_*, erp_importar...) e a
/// conversa com o Protheus na função "erp-protheus" (credenciais, testar e
/// processar a fila agora).

const rotuloTipoErp = {
  'importar_equipamentos': 'Importar equipamentos',
  'importar_clientes': 'Importar clientes',
  'importar_produtos': 'Importar produtos',
  'custo_realizado': 'Custo realizado',
  'cobranca_baixas': 'Baixas da cobrança',
  'enviar_equipamento': 'Enviar equipamento',
  'solicitacao_compra': 'Solicitação de compra',
  'pedido_locacao': 'Pedido de venda da locação',
  'pedido_avaria': 'Pedido de venda da avaria',
  'cobranca_titulo': 'Cobrança pelo ERP',
};

const rotuloSituacaoErp = {
  'pendente': 'Na fila',
  'processando': 'Enviando',
  'concluida': 'Concluída',
  'erro': 'Com erro',
  'cancelada': 'Cancelada',
};

const corSituacaoErp = {
  'pendente': Cores.alerta,
  'processando': Cores.info,
  'concluida': Cores.sucesso,
  'erro': Cores.erro,
  'cancelada': Cores.neutro,
};

/// O que dá para ligar e desligar, com o texto da tela (a ordem é a da tela).
const operacoesErp = {
  'importar_clientes': ('Importar clientes', 'SA1: cria ou atualiza pelo código e loja (ou pelo CNPJ/CPF), com o de-para.'),
  'importar_produtos': ('Importar produtos', 'SB1: código, descrição, unidade, NCM, preço e custo.'),
  'importar_equipamentos': ('Importar equipamentos', 'Ativo Fixo (SN1/SN3) ou Manutenção de Ativos (ST9).'),
  'enviar_equipamentos': ('Enviar equipamentos ao ERP', 'Quando o ServPilot é o dono do cadastro: cada inclusão ou alteração vai ao Protheus.'),
  'solicitacao_compra': ('Solicitação de compra', 'Peça ou serviço da OS vira SC no Compras, com o equipamento e o centro de custo.'),
  'custo_realizado': ('Custo realizado', 'Notas de entrada e requisições do equipamento entram nos custos dele, sem duplicar.'),
  'pedido_locacao': ('Pedido de venda da locação', 'O contrato ou a medição vira pedido de venda no Faturamento.'),
  'pedido_avaria': ('Pedido de venda da avaria', 'A avaria apontada na devolução vira pedido de venda.'),
  'cobranca': ('Cobrança pelo ERP', 'Modo de cobrança "Pelo ERP": o título vira pedido ou título no Protheus e a baixa volta sozinha.'),
};

/// Chama uma função erp_* do banco (com o objeto "p", quando houver).
Future<Map<String, dynamic>> erpRpc(String funcao, [Map<String, dynamic>? p]) async {
  final db = Supabase.instance.client;
  final r = p == null ? await db.rpc(funcao) : await db.rpc(funcao, params: {'p': p});
  return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
}

/// Chama a função "erp-protheus". Erros viram FunctionException, que mensagemDeErro() traduz.
Future<Map<String, dynamic>> funcaoErp(Map<String, dynamic> corpo) async {
  final r = await Supabase.instance.client.functions.invoke('erp-protheus', body: corpo);
  final d = r.data;
  return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
}

/// "3 concluídas, 1 na fila, 1 com erro" do resumo do processamento.
String resumoProcessamento(Map<String, dynamic> r) {
  final partes = <String>[
    if ((r['concluidas'] ?? 0) != 0) '${r['concluidas']} concluída(s)',
    if ((r['adiadas'] ?? 0) != 0) '${r['adiadas']} esperando o ERP',
    if ((r['com_erro'] ?? 0) != 0) '${r['com_erro']} com erro',
  ];
  return partes.isEmpty ? 'Nada vencido na fila agora.' : partes.join(', ');
}

/// Etiqueta colorida da situação da mensagem.
class SeloErp extends StatelessWidget {
  const SeloErp(this.situacao, {super.key});
  final String situacao;

  @override
  Widget build(BuildContext context) {
    final cor = corSituacaoErp[situacao] ?? Cores.neutro;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(rotuloSituacaoErp[situacao] ?? situacao,
          style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}
