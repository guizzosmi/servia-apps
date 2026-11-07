import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:servia_comum/servia_comum.dart';

import '../api.dart';
import 'comuns.dart';

/// Tela do cliente (guia 89): forma de pagamento (mensal/anual), quem indicou,
/// quem ele indicou e os meses grátis (créditos).
class ContaComercial extends StatelessWidget {
  const ContaComercial({super.key, required this.contaId, required this.dados, required this.aoMudar});

  final String contaId;
  final Map<String, dynamic> dados;
  final VoidCallback aoMudar;

  Future<void> _rodar(BuildContext context, Future<void> Function() f, String ok) async {
    try {
      await f();
      if (context.mounted) avisar(context, ok);
      aoMudar();
    } catch (e) {
      if (context.mounted) avisarErro(context, e);
    }
  }

  Future<void> _periodicidade(BuildContext context, String para) async {
    final ok = await dialogoForm(context,
        titulo: para == 'anual' ? 'Mudar para o pagamento anual?' : 'Voltar para o mensal?',
        confirmar: 'Confirmar',
        campos: [
          Text(para == 'anual'
              ? 'Gera agora a fatura anual do próximo ciclo. Se não for paga até o início, a conta continua no mensal.'
              : 'Cancela a fatura anual em aberto. O que já está pago continua valendo até o fim do período.'),
        ]);
    if (!ok || !context.mounted) return;
    await _rodar(context, () => rpcMapa('admin_conta_periodicidade', {
          'p': {'conta_id': contaId, 'periodicidade': para}
        }), para == 'anual' ? 'Fatura anual gerada.' : 'Volta ao mensal.');
  }

  Future<void> _definirIndicacao(BuildContext context) async {
    final codigo = TextEditingController();
    final ok = await dialogoForm(context, titulo: 'Quem indicou este cliente?', confirmar: 'Salvar', campos: [
      campoTexto(codigo, 'Código de indicação (cliente ou parceiro)',
          ajuda: 'Só antes do 1º pagamento do cliente. Depois do pagamento, dê o mês grátis direto a quem indicou.'),
    ]);
    if (!ok || !context.mounted) return;
    await _rodar(context, () => rpcMapa('admin_indicacao_definir', {
          'p': {'conta_id': contaId, 'codigo': codigo.text.trim()}
        }), 'Indicação registrada.');
  }

  Future<void> _darCredito(BuildContext context) async {
    final desc = TextEditingController(text: '1 mês grátis (cortesia)');
    final ok = await dialogoForm(context, titulo: 'Dar 1 mês do plano grátis', confirmar: 'Dar', campos: [
      campoTexto(desc, 'Descrição (aparece na fatura)', ajuda: 'Entra sozinho na próxima fatura que tem o plano.'),
    ]);
    if (!ok || !context.mounted) return;
    await _rodar(context, () => rpcMapa('admin_credito_dar', {
          'p': {'conta_id': contaId, 'descricao': desc.text.trim()}
        }), 'Mês grátis dado.');
  }

  Future<void> _cancelarCredito(BuildContext context, Map<String, dynamic> c) async {
    final motivo = TextEditingController();
    final ok = await dialogoForm(context, titulo: 'Cancelar "${c['descricao']}"?', confirmar: 'Cancelar o crédito', campos: [
      campoTexto(motivo, 'Motivo'),
    ]);
    if (!ok || !context.mounted) return;
    await _rodar(context, () => rpcMapa('admin_credito_cancelar', {
          'p': {'credito_id': c['id'], 'motivo': motivo.text.trim()}
        }), 'Crédito cancelado.');
  }

  /// Guia 90: os contatos do formulário do site entram no funil desta empresa.
  Future<void> _empresaDoComercial(BuildContext context, Map<String, dynamic> e) async {
    final ok = await dialogoForm(context, titulo: 'Receber os contatos do site em ${e['nome_fantasia'] ?? e['razao_social']}?',
        confirmar: 'Usar esta empresa', campos: [
      const Text('O formulário "Quero uma demonstração" do site cria a oportunidade no funil desta empresa, com a tarefa '
          'de responder. O módulo Comercial é ligado nela.'),
    ]);
    if (!ok || !context.mounted) return;
    await _rodar(context, () => rpcMapa('admin_comercial_empresa', {
          'p': {'empresa_id': e['id']}
        }), 'Pronto: os contatos do site vão para esta empresa.');
  }

  String _situacaoIndicacao(Map<String, dynamic> i) => switch (i['situacao']) {
        'valida' => 'valeu (1º pagamento em ${dataBr(i['primeiro_pagamento_em'])})',
        'recusada' => 'não valeu: ${i['motivo'] ?? ''}',
        _ => 'aguardando o 1º pagamento',
      };

  @override
  Widget build(BuildContext context) {
    final anual = mapa(dados['anual']);
    final vigente = anual['vigente'] is Map ? mapa(anual['vigente']) : null;
    final aberta = anual['aberta'] is Map ? mapa(anual['aberta']) : null;
    final indicacao = dados['indicacao'] is Map ? mapa(dados['indicacao']) : null;
    final indicados = lista(dados['indicados']);
    final creditos = lista(dados['creditos']);
    final codigo = '${dados['codigo_indicacao'] ?? ''}';
    return Secao(
      titulo: 'Pagamento, indicação e meses grátis',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Mensal ou anual
        Campo('Pagamento', anual['periodicidade'] == 'anual' ? 'Anual (renova sozinho)' : 'Mensal'),
        if (vigente != null)
          Campo('Anual pago', '${dataBr(vigente['inicio'])} a ${dataBr(vigente['fim'])} · ${moeda(vigente['valor_pago'])}'),
        if (aberta != null)
          Campo('Anual em aberto', 'nº ${aberta['numero']} · ${moeda(aberta['valor_total'])} · vence ${dataBr(aberta['vencimento'])}'),
        if (anual['disponivel'] == true)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _periodicidade(context, anual['periodicidade'] == 'anual' ? 'mensal' : 'anual'),
              child: Text(anual['periodicidade'] == 'anual'
                  ? 'Voltar para o mensal'
                  : 'Mudar para o anual (${moeda(anual['valor_anual'])}, começa em ${dataBr(anual['comeca_em'])})'),
            ),
          ),
        const Divider(),
        // Indicação
        Row(children: [
          Expanded(child: Campo('Código para indicar', codigo)),
          IconButton(
            tooltip: 'Copiar o link',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () => Clipboard.setData(ClipboardData(text: 'https://servpilot.com.br/assinar?indicacao=$codigo')),
          ),
        ]),
        Row(children: [
          Expanded(
            child: Campo('Indicado por', indicacao == null
                ? 'ninguém'
                : '${indicacao['indicador']} (${indicacao['tipo']}, ${indicacao['codigo']}) · ${_situacaoIndicacao(indicacao)}'),
          ),
          if (indicacao == null || indicacao['situacao'] != 'valida')
            TextButton(onPressed: () => _definirIndicacao(context), child: Text(indicacao == null ? 'Definir' : 'Trocar')),
        ]),
        if (indicados.isNotEmpty)
          Campo('Indicou', indicados.map((i) => '${i['nome']} (${rotulosIndicacao[i['situacao']] ?? i['situacao']})').join(', ')),
        const Divider(),
        // Guia 90: empresa que recebe os contatos do site (a do ServPilot).
        for (final e in lista(dados['empresas']))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _empresaDoComercial(context, e),
              icon: const Icon(Icons.campaign_outlined, size: 18),
              label: Text('Receber os contatos do site em ${e['nome_fantasia'] ?? e['razao_social']}'),
            ),
          ),
        const Divider(),
        // Créditos
        Row(children: [
          Expanded(
            child: Text('Meses grátis: ${creditos.where((c) => c['usado_em'] == null && c['cancelado_em'] == null).length} para usar',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          TextButton.icon(onPressed: () => _darCredito(context), icon: const Icon(Icons.add), label: const Text('Dar 1 mês grátis')),
        ]),
        for (final c in creditos)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${c['descricao']}', style: TextStyle(color: c['cancelado_em'] != null ? Cores.neutro : Cores.tinta)),
            subtitle: Text(c['cancelado_em'] != null
                ? 'cancelado em ${dataBr(c['cancelado_em'])}${c['cancelado_motivo'] != null ? ': ${c['cancelado_motivo']}' : ''}'
                : c['usado_em'] != null
                    ? 'usado na fatura nº ${c['fatura_numero']} em ${dataBr(c['usado_em'])}'
                    : 'ganho em ${dataBr(c['criado_em'])} · entra na próxima fatura com o plano'),
            trailing: c['usado_em'] == null && c['cancelado_em'] == null
                ? IconButton(tooltip: 'Cancelar', icon: const Icon(Icons.close, size: 18), onPressed: () => _cancelarCredito(context, c))
                : null,
          ),
      ]),
    );
  }
}
