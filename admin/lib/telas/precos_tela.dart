import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../api.dart';
import '../widgets/comuns.dart';

/// Plano, pacotes extras e regras de cobrança. O site mostra o que estiver aqui.
class PrecosTela extends StatefulWidget {
  const PrecosTela({super.key});

  @override
  State<PrecosTela> createState() => _PrecosTelaState();
}

class _PrecosTelaState extends State<PrecosTela> {
  late Future<Map<String, dynamic>> _dados = rpcMapa('admin_precos');

  void _recarregar() => setState(() => _dados = rpcMapa('admin_precos'));

  Future<void> _salvar(Map<String, dynamic> p) async {
    try {
      await rpcMapa('admin_precos_salvar', {'p': p});
      if (mounted) avisar(context, 'Salvo. O site e as próximas faturas já usam os valores novos.');
      if (mounted) _recarregar();
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Carregar<Map<String, dynamic>>(
        futuro: _dados,
        recarregar: _recarregar,
        construir: (d) => ListView(padding: const EdgeInsets.all(24), children: [
          Text('Preços e regras', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text('Mudou o preço? Vale para as próximas faturas de todos (menos quem tem valor combinado). '
              'A página de preços do site lê daqui.', style: TextStyle(color: Cores.neutro)),
          const SizedBox(height: 16),
          for (final p in lista(d['planos'])) _FormPlano(plano: p, aoSalvar: (x) => _salvar({'plano': x})),
          _Pacotes(pacotes: lista(d['pacotes']), aoSalvar: (x) => _salvar({'pacote': x})),
          _FormRegras(regras: mapa(d['regras']), aoSalvar: (x) => _salvar({'regras': x})),
        ]),
      );
}

class _FormPlano extends StatefulWidget {
  const _FormPlano({required this.plano, required this.aoSalvar});

  final Map<String, dynamic> plano;
  final void Function(Map<String, dynamic>) aoSalvar;

  @override
  State<_FormPlano> createState() => _FormPlanoState();
}

class _FormPlanoState extends State<_FormPlano> {
  static const _campos = [
    ('nome', 'Nome', false),
    ('valor_mensal', 'Mensalidade (R\$)', true),
    ('usuarios_incluidos', 'Usuários incluídos', true),
    ('minutos_ia_incluidos', 'Minutos de IA incluídos', true),
    ('mensagens_incluidas', 'Mensagens incluídas', true),
    ('valor_usuario_extra', 'Usuário extra (R\$/mês)', true),
    ('minutos_por_usuario_extra', '+ minutos por usuário extra', true),
    ('mensagens_por_usuario_extra', '+ mensagens por usuário extra', true),
    ('dias_teste', 'Dias de teste grátis', true),
  ];
  late final Map<String, TextEditingController> _c = {
    for (final (k, _, _) in _campos) k: TextEditingController(text: '${widget.plano[k] ?? ''}'.replaceAll('.', ',')),
  };
  late final _descricao = TextEditingController(text: '${widget.plano['descricao'] ?? ''}');
  // Guia 90: o módulo Comercial vem incluído neste plano?
  late bool _comercial = widget.plano['comercial_incluido'] != false;

  @override
  void dispose() {
    for (final c in [..._c.values, _descricao]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Secao(
        titulo: 'Plano ${widget.plano['nome']} (${widget.plano['codigo'] ?? ''})',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 12, children: [
            for (final (k, rotulo, ehNum) in _campos)
              SizedBox(width: 230, child: campoTexto(_c[k]!, rotulo, teclado: ehNum ? TextInputType.number : null)),
          ]),
          campoTexto(_descricao, 'Descrição (site)'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _comercial,
            onChanged: (v) => setState(() => _comercial = v),
            title: const Text('Módulo Comercial incluído'),
            subtitle: const Text('Desligado: quem ligar o Comercial paga o valor das regras abaixo, na mensalidade.'),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => widget.aoSalvar({
                'id': widget.plano['id'],
                'descricao': _descricao.text.trim(),
                'comercial_incluido': _comercial,
                for (final (k, _, ehNum) in _campos) k: ehNum ? numero(_c[k]!.text) : _c[k]!.text.trim(),
              }),
              child: const Text('Salvar plano'),
            ),
          ),
        ]),
      );
}

class _Pacotes extends StatelessWidget {
  const _Pacotes({required this.pacotes, required this.aoSalvar});

  final List<Map<String, dynamic>> pacotes;
  final void Function(Map<String, dynamic>) aoSalvar;

  Future<void> _editar(BuildContext context, [Map<String, dynamic>? k]) async {
    final codigo = TextEditingController(text: '${k?['codigo'] ?? ''}');
    final nome = TextEditingController(text: '${k?['nome'] ?? ''}');
    final tipo = TextEditingController(text: '${k?['tipo'] ?? 'minutos'}');
    final qtd = TextEditingController(text: '${k?['quantidade'] ?? ''}');
    final valor = TextEditingController(text: '${k?['valor'] ?? ''}'.replaceAll('.', ','));
    final ordem = TextEditingController(text: '${k?['ordem'] ?? 0}');
    final ativo = TextEditingController(text: k?['ativo'] == false ? 'não' : 'sim');
    final ok = await dialogoForm(context, titulo: k == null ? 'Novo pacote' : 'Pacote ${k['codigo']}', campos: [
      if (k == null) campoTexto(codigo, 'Código', ajuda: 'ex.: minutos-1000'),
      campoTexto(nome, 'Nome (aparece no site e na fatura)'),
      campoTexto(tipo, 'Tipo', ajuda: 'minutos ou mensagens'),
      campoTexto(qtd, 'Quantidade', teclado: TextInputType.number),
      campoTexto(valor, 'Valor (R\$)', teclado: TextInputType.number),
      campoTexto(ordem, 'Ordem no site', teclado: TextInputType.number),
      campoTexto(ativo, 'À venda?', ajuda: 'sim ou não'),
    ]);
    if (!ok) return;
    aoSalvar({
      'codigo': k?['codigo'] ?? codigo.text.trim().toLowerCase(),
      'nome': nome.text.trim(),
      'tipo': tipo.text.trim().toLowerCase(),
      'quantidade': numero(qtd.text).toInt(),
      'valor': numero(valor.text),
      'ordem': numero(ordem.text).toInt(),
      'ativo': !ativo.text.trim().toLowerCase().startsWith('n'),
    });
  }

  @override
  Widget build(BuildContext context) => Secao(
        titulo: 'Pacotes extras',
        acoes: [TextButton.icon(onPressed: () => _editar(context), icon: const Icon(Icons.add), label: const Text('Novo'))],
        child: Column(children: [
          for (final k in pacotes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => _editar(context, k),
              title: Text('${k['nome']}'),
              subtitle: Text('${k['codigo']} · ${k['quantidade']} ${k['tipo']}${k['ativo'] == true ? '' : ' · fora de venda'}'),
              trailing: Text(moeda(k['valor']), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
        ]),
      );
}

class _FormRegras extends StatefulWidget {
  const _FormRegras({required this.regras, required this.aoSalvar});

  final Map<String, dynamic> regras;
  final void Function(Map<String, dynamic>) aoSalvar;

  @override
  State<_FormRegras> createState() => _FormRegrasState();
}

class _FormRegrasState extends State<_FormRegras> {
  late final _dias = TextEditingController(text: '${widget.regras['dias_minimos'] ?? 15}');
  late final _pagar = TextEditingController(text: '${widget.regras['dias_para_pagar'] ?? 5}');
  late final _bloquear = TextEditingController(text: '${widget.regras['bloquear_apos_dias'] ?? ''}');
  late bool _atendeu = widget.regras['conta_quem_atendeu'] != false;
  // Guias 81 e 86: módulo de notas fiscais por faixa (notas por mês e valor) e a nota a mais.
  late final _faixaNotas = [
    TextEditingController(text: '${widget.regras['notas_faixa1_notas'] ?? widget.regras['notas_incluidas'] ?? 50}'),
    TextEditingController(text: '${widget.regras['notas_faixa2_notas'] ?? 200}'),
    TextEditingController(text: '${widget.regras['notas_faixa3_notas'] ?? 1000}'),
  ];
  late final _faixaValor = [
    TextEditingController(text: '${widget.regras['notas_faixa1_valor'] ?? widget.regras['notas_valor_modulo'] ?? 49}'),
    TextEditingController(text: '${widget.regras['notas_faixa2_valor'] ?? 99}'),
    TextEditingController(text: '${widget.regras['notas_faixa3_valor'] ?? 249}'),
  ];
  late final _notasExtra = TextEditingController(text: '${widget.regras['notas_valor_extra'] ?? 0.49}');
  // Guia 89: plano anual, arrependimento e comissão padrão dos parceiros.
  late final _anualPagos = TextEditingController(text: '${widget.regras['anual_meses_pagos'] ?? 10}');
  late final _anualRenovar = TextEditingController(text: '${widget.regras['anual_renovar_dias'] ?? 7}');
  late final _arrependimento = TextEditingController(text: '${widget.regras['arrependimento_dias'] ?? 7}');
  late final _parceiroPct = TextEditingController(text: '${widget.regras['parceiro_comissao_pct'] ?? 10}');
  late final _parceiroMeses = TextEditingController(text: '${widget.regras['parceiro_comissao_meses'] ?? 12}');
  // Guia 90: módulo Comercial nos planos que não o incluem.
  late final _comercialValor = TextEditingController(text: '${widget.regras['comercial_valor'] ?? 29}');

  @override
  void dispose() {
    _dias.dispose();
    _pagar.dispose();
    _bloquear.dispose();
    for (final c in [..._faixaNotas, ..._faixaValor]) {
      c.dispose();
    }
    _notasExtra.dispose();
    for (final c in [_anualPagos, _anualRenovar, _arrependimento, _parceiroPct, _parceiroMeses, _comercialValor]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Secao(
        titulo: 'Regras de cobrança',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          campoTexto(_dias, 'Usuário é cobrado com login ativo em quantos dias do ciclo', teclado: TextInputType.number),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _atendeu,
            onChanged: (v) => setState(() => _atendeu = v),
            title: const Text('Quem participou de atendimento no ciclo também é cobrado'),
            subtitle: const Text('Evita o rodízio: ligar um técnico só por alguns dias para não pagar.'),
          ),
          campoTexto(_pagar, 'Dias para pagar a mensalidade depois da virada do ciclo', teclado: TextInputType.number),
          campoTexto(_bloquear, 'Bloquear sozinho depois de quantos dias de atraso',
              ajuda: 'Vazio = nunca bloqueia sozinho (você decide na tela do cliente). Cortesia nunca é bloqueada.',
              teclado: TextInputType.number),
          const Subtitulo('Notas fiscais (módulo por empresa, em 3 faixas)'),
          for (var i = 0; i < 3; i++)
            Row(children: [
              Expanded(child: campoTexto(_faixaNotas[i], 'Faixa ${i + 1}: até quantas notas por mês', teclado: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: campoTexto(_faixaValor[i], 'Faixa ${i + 1}: mensalidade (R\$)', teclado: TextInputType.number)),
            ]),
          campoTexto(_notasExtra, 'Nota além da faixa (R\$ por nota)', teclado: TextInputType.number),
          const Subtitulo('Plano anual e parceiros'),
          Row(children: [
            Expanded(child: campoTexto(_anualPagos, 'Anual: paga quantos meses (usa 12)', teclado: TextInputType.number)),
            const SizedBox(width: 12),
            Expanded(child: campoTexto(_anualRenovar, 'Fatura da renovação: dias antes do fim', teclado: TextInputType.number)),
            const SizedBox(width: 12),
            Expanded(child: campoTexto(_arrependimento, 'Desistir com devolução: até quantos dias', teclado: TextInputType.number)),
          ]),
          Row(children: [
            Expanded(child: campoTexto(_parceiroPct, 'Comissão padrão do parceiro (%)', teclado: TextInputType.number)),
            const SizedBox(width: 12),
            Expanded(child: campoTexto(_parceiroMeses, 'Durante quantos meses', teclado: TextInputType.number)),
          ]),
          campoTexto(_comercialValor, 'Módulo Comercial nos planos que não incluem (R\$/mês)', teclado: TextInputType.number),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => widget.aoSalvar({
                'dias_minimos': numero(_dias.text).toInt(),
                'conta_quem_atendeu': _atendeu,
                'dias_para_pagar': numero(_pagar.text).toInt(),
                'bloquear_apos_dias': _bloquear.text.trim().isEmpty ? null : numero(_bloquear.text).toInt(),
                for (var i = 0; i < 3; i++) ...{
                  'notas_faixa${i + 1}_notas': numero(_faixaNotas[i].text).toInt(),
                  'notas_faixa${i + 1}_valor': numero(_faixaValor[i].text),
                },
                'notas_valor_extra': numero(_notasExtra.text),
                'anual_meses_pagos': numero(_anualPagos.text).toInt().clamp(1, 12),
                'anual_renovar_dias': numero(_anualRenovar.text).toInt(),
                'arrependimento_dias': numero(_arrependimento.text).toInt(),
                'parceiro_comissao_pct': numero(_parceiroPct.text),
                'parceiro_comissao_meses': numero(_parceiroMeses.text).toInt(),
                'comercial_valor': numero(_comercialValor.text),
              }),
              child: const Text('Salvar regras'),
            ),
          ),
        ]),
      );
}
