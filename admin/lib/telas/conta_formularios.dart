import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../api.dart';
import '../widgets/comuns.dart';

/// Plano, cobrança (ou cortesia), desconto, valor combinado e fim do teste.
class FormAssinatura extends StatefulWidget {
  const FormAssinatura({super.key, required this.assinatura, required this.planos, required this.valorMensal, required this.aoSalvar});

  final Map<String, dynamic> assinatura;
  final List<Map<String, dynamic>> planos;
  final dynamic valorMensal;
  final Future<void> Function(Map<String, dynamic> campos) aoSalvar;

  @override
  State<FormAssinatura> createState() => _FormAssinaturaState();
}

class _FormAssinaturaState extends State<FormAssinatura> {
  late final a = widget.assinatura;
  late String? _plano = a['plano_id'] as String?;
  late bool _cobrar = a['cobrar'] != false;
  late final _desconto = TextEditingController(text: numero(a['desconto_pct']) == 0 ? '' : '${numero(a['desconto_pct'])}');
  late final _fixo = TextEditingController(text: a['valor_mensal_fixo'] == null ? '' : '${a['valor_mensal_fixo']}'.replaceAll('.', ','));
  late final _teste = TextEditingController(text: dataBr(a['teste_ate']));
  late final _obs = TextEditingController(text: '${a['observacao'] ?? ''}');

  @override
  void dispose() {
    for (final c in [_desconto, _fixo, _teste, _obs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    final campos = <String, dynamic>{
      'plano_id': _plano,
      'cobrar': _cobrar,
      'desconto_pct': numero(_desconto.text),
      'valor_mensal_fixo': _fixo.text.trim().isEmpty ? null : numero(_fixo.text),
      'observacao': _obs.text.trim(),
    };
    if (a['situacao'] == 'teste') {
      final iso = dataIso(_teste.text);
      if (iso == null) {
        avisar(context, 'Confira a data do fim do teste (dd/mm/aaaa).', erro: true);
        return;
      }
      campos['teste_ate'] = iso;
    }
    await widget.aoSalvar(campos);
  }

  @override
  Widget build(BuildContext context) => Secao(
        titulo: 'Assinatura',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Campo('Mensalidade hoje', moeda(widget.valorMensal)),
          Campo('Ciclo atual', '${dataBr(a['ciclo_inicio'])} a ${dataBr(a['ciclo_fim'])}'),
          if (a['teste_ate'] != null) Campo('Teste grátis até', dataBr(a['teste_ate'])),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Plano'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _plano,
                isExpanded: true,
                isDense: true,
                items: [
                  for (final p in widget.planos)
                    DropdownMenuItem(value: p['id'] as String, child: Text('${p['nome']} · ${moeda(p['valor_mensal'])}')),
                ],
                onChanged: (v) => setState(() => _plano = v),
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _cobrar,
            onChanged: (v) => setState(() => _cobrar = v),
            title: Text(_cobrar ? 'Cobrar mensalidade' : 'Cortesia (não gera fatura)'),
            subtitle: const Text('Cortesia: usa tudo, nunca recebe fatura e nunca fica atrasado. Bom para parceiros e família.'),
          ),
          if (_cobrar) ...[
            campoTexto(_desconto, 'Desconto fixo (%)', ajuda: 'Vale sempre, no plano e nos usuários extras. Para desconto por um tempo, use um cupom.',
                teclado: TextInputType.number),
            campoTexto(_fixo, 'Valor combinado do plano (R\$)', ajuda: 'Vazio = preço da tabela.', teclado: TextInputType.number),
          ],
          if (a['situacao'] == 'teste') campoTexto(_teste, 'Fim do teste grátis (dd/mm/aaaa)', ajuda: 'Para estender o teste.'),
          campoTexto(_obs, 'Observação (só você vê)'),
          Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _salvar, child: const Text('Salvar assinatura'))),
        ]),
      );
}

/// Tomador da nota fiscal (o que o contador precisa).
class FormNota extends StatefulWidget {
  const FormNota({super.key, required this.assinatura, required this.aoSalvar});

  final Map<String, dynamic> assinatura;
  final Future<void> Function(Map<String, dynamic> campos) aoSalvar;

  @override
  State<FormNota> createState() => _FormNotaState();
}

class _FormNotaState extends State<FormNota> {
  static const _campos = [
    ('fat_nome', 'Razão social ou nome'),
    ('fat_documento', 'CNPJ ou CPF'),
    ('fat_inscricao_municipal', 'Inscrição municipal'),
    ('fat_email', 'E-mail para a nota'),
    ('fat_telefone', 'Telefone'),
    ('fat_cep', 'CEP'),
    ('fat_logradouro', 'Endereço'),
    ('fat_numero', 'Número'),
    ('fat_complemento', 'Complemento'),
    ('fat_bairro', 'Bairro'),
    ('fat_cidade', 'Cidade'),
    ('fat_uf', 'UF'),
  ];
  late final Map<String, TextEditingController> _c = {
    for (final (chave, _) in _campos) chave: TextEditingController(text: '${widget.assinatura[chave] ?? ''}'.trim()),
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Secao(
        titulo: 'Dados para a nota fiscal',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Vêm do cadastro no site. O contador usa estes dados (vão na planilha de Faturas > Exportar).',
              style: TextStyle(color: Cores.neutro)),
          const SizedBox(height: 12),
          Wrap(spacing: 12, children: [
            for (final (chave, rotulo) in _campos)
              SizedBox(width: chave == 'fat_nome' || chave == 'fat_logradouro' ? 420 : 200, child: campoTexto(_c[chave]!, rotulo)),
          ]),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => widget.aoSalvar({for (final e in _c.entries) e.key: e.value.text.trim()}),
              child: const Text('Salvar dados da nota'),
            ),
          ),
        ]),
      );
}
