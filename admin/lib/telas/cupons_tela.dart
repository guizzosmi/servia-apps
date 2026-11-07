import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../api.dart';
import '../widgets/comuns.dart';

/// Cupons de desconto: % ou R$, validade, plano, quantos meses, limite de usos.
class CuponsTela extends StatefulWidget {
  const CuponsTela({super.key});

  @override
  State<CuponsTela> createState() => _CuponsTelaState();
}

class _CuponsTelaState extends State<CuponsTela> {
  late Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _dados = _carregar();

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _carregar() async {
    final r = await Future.wait([rpcLista('admin_cupons'), rpcMapa('admin_precos')]);
    return (r[0] as List<Map<String, dynamic>>, lista((r[1] as Map<String, dynamic>)['planos']));
  }

  void _recarregar() => setState(() => _dados = _carregar());

  Future<void> _editar(List<Map<String, dynamic>> planos, [Map<String, dynamic>? c]) async {
    final salvou = await showDialog<bool>(context: context, builder: (_) => _DialogoCupom(cupom: c, planos: planos));
    if (salvou == true) _recarregar();
  }

  @override
  Widget build(BuildContext context) => Carregar<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)>(
        futuro: _dados,
        recarregar: _recarregar,
        construir: (r) {
          final (cupons, planos) = r;
          return ListView(padding: const EdgeInsets.all(24), children: [
            Row(children: [
              Expanded(child: Text('Cupons de desconto', style: Theme.of(context).textTheme.headlineSmall)),
              FilledButton.icon(onPressed: () => _editar(planos), icon: const Icon(Icons.add), label: const Text('Novo cupom')),
            ]),
            const SizedBox(height: 4),
            const Text('O cliente digita o cupom ao assinar pelo site (ou no painel, em Plano e consumo); você também aplica na tela do cliente. '
                'Para alguém usar de graça sem prazo, prefira a cortesia na assinatura do cliente.',
                style: TextStyle(color: Cores.neutro)),
            const SizedBox(height: 16),
            if (cupons.isEmpty) const Text('Nenhum cupom ainda.'),
            for (final c in cupons)
              Card(
                child: ListTile(
                  onTap: () => _editar(planos, c),
                  title: Text('${c['codigo']}${c['descricao'] != null ? ' · ${c['descricao']}' : ''}',
                      style: TextStyle(color: c['ativo'] == true ? Cores.tinta : Cores.neutro)),
                  subtitle: Text([
                    '${c['resumo']}',
                    c['plano'] != null ? 'plano ${c['plano']}' : 'qualquer plano',
                    if (c['valido_ate'] != null) 'usar até ${dataBr(c['valido_ate'])}',
                    'usado ${c['usos']}${c['usos_max'] != null ? ' de ${c['usos_max']}' : ''} vez(es)',
                    if (c['so_novos'] == true) 'só no cadastro pelo site',
                  ].join(' · ')),
                  trailing: c['ativo'] == true ? const ChipSituacao('ativa') : const ChipSituacao('cancelada'),
                ),
              ),
          ]);
        },
      );
}

class _DialogoCupom extends StatefulWidget {
  const _DialogoCupom({required this.cupom, required this.planos});

  final Map<String, dynamic>? cupom;
  final List<Map<String, dynamic>> planos;

  @override
  State<_DialogoCupom> createState() => _DialogoCupomState();
}

class _DialogoCupomState extends State<_DialogoCupom> {
  late final c = widget.cupom ?? const <String, dynamic>{};
  late final _codigo = TextEditingController(text: '${c['codigo'] ?? ''}');
  late final _descricao = TextEditingController(text: '${c['descricao'] ?? ''}');
  late final _valor = TextEditingController(text: c['valor'] == null ? '' : '${c['valor']}'.replaceAll('.', ','));
  late final _meses = TextEditingController(text: '${c['meses'] ?? ''}');
  late final _mesesGratis = TextEditingController(text: '${c['meses_gratis'] ?? 0}');
  late final _validade = TextEditingController(text: dataBr(c['valido_ate']));
  late final _usosMax = TextEditingController(text: '${c['usos_max'] ?? ''}');
  late String _tipo = '${c['tipo'] ?? 'percentual'}';
  late String _aplica = '${c['aplica_em'] ?? 'mensalidade'}';
  late String? _plano = c['plano_id'] as String?;
  late bool _soNovos = c['so_novos'] == true;
  late bool _ativo = c['ativo'] != false;
  bool _salvando = false;

  Widget _escolha<T>(String rotulo, T valor, Map<T, String> opcoes, ValueChanged<T?> mudar) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InputDecorator(
          decoration: InputDecoration(labelText: rotulo),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: valor,
              isExpanded: true,
              isDense: true,
              items: [for (final e in opcoes.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value))],
              onChanged: mudar,
            ),
          ),
        ),
      );

  Future<void> _salvar() async {
    final validade = _validade.text.trim().isEmpty ? null : dataIso(_validade.text);
    if (_validade.text.trim().isNotEmpty && validade == null) {
      avisar(context, 'Confira a validade (dd/mm/aaaa).', erro: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      await rpcLista('admin_cupom_salvar', {
        'p': {
          'id': c['id'],
          'codigo': _codigo.text.trim().toUpperCase(),
          'descricao': _descricao.text.trim(),
          'tipo': _tipo,
          'valor': numero(_valor.text),
          'aplica_em': _aplica,
          'plano_id': _plano,
          'meses': _meses.text.trim().isEmpty ? null : int.tryParse(_meses.text.trim()),
          'meses_gratis': int.tryParse(_mesesGratis.text.trim()) ?? 0,
          'valido_ate': validade,
          'usos_max': _usosMax.text.trim().isEmpty ? null : int.tryParse(_usosMax.text.trim()),
          'so_novos': _soNovos,
          'ativo': _ativo,
        }
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) avisarErro(context, e);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.cupom == null ? 'Novo cupom' : 'Cupom ${c['codigo']}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.cupom == null)
                campoTexto(_codigo, 'Código', ajuda: 'Letras e números, sem espaço (ex.: AMIGO20, PARCEIRO).'),
              campoTexto(_descricao, 'Descrição (aparece na fatura)'),
              _escolha<String>('Tipo', _tipo, const {'percentual': 'Percentual (%)', 'valor': 'Valor (R\$)'},
                  (v) => setState(() => _tipo = v ?? 'percentual')),
              campoTexto(_valor, _tipo == 'percentual' ? 'Desconto (%) · 100 = grátis' : 'Desconto (R\$) por fatura',
                  teclado: TextInputType.number),
              _escolha<String>('Vale para', _aplica,
                  const {'mensalidade': 'Mensalidade', 'pacote': 'Pacotes extras', 'tudo': 'Mensalidade e pacotes'},
                  (v) => setState(() => _aplica = v ?? 'mensalidade')),
              _escolha<String?>('Plano', _plano, {
                null: 'Qualquer plano',
                for (final p in widget.planos) p['id'] as String: '${p['nome']}',
              }, (v) => setState(() => _plano = v)),
              campoTexto(_mesesGratis, 'Meses grátis antes do desconto',
                  ajuda: 'Ex.: 3 = três meses de graça e depois o desconto acima (cliente fundador). 0 = nenhum.',
                  teclado: TextInputType.number),
              campoTexto(_meses, 'Em quantos meses com o desconto', ajuda: 'Vazio = todos, enquanto o cupom estiver na conta. '
                  'O pagamento anual conta 12 meses.',
                  teclado: TextInputType.number),
              campoTexto(_validade, 'Usar até (dd/mm/aaaa)', ajuda: 'Até quando dá para digitar o cupom. Vazio = sem prazo.'),
              campoTexto(_usosMax, 'Limite de contas', ajuda: 'Vazio = sem limite.', teclado: TextInputType.number),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _soNovos,
                onChanged: (v) => setState(() => _soNovos = v),
                title: const Text('Só para quem assina pelo site'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _ativo,
                onChanged: (v) => setState(() => _ativo = v),
                title: const Text('Ativo'),
                subtitle: const Text('Desligado: ninguém mais usa; quem já tem continua com o desconto.'),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: _salvando ? null : _salvar, child: const Text('Salvar')),
        ],
      );
}
