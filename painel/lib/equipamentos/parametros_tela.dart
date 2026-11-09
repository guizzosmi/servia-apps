import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../widgets/margem.dart';
import 'servico.dart';
import 'widgets.dart';

/// Parâmetros da Gestão de Equipamentos (guia 102, decisões 3, 7 e 8 do dono): preparação obrigatória para liberar,
/// retrofit como custo ou investimento, dono do cadastro com ERP e fotos obrigatórias na OS do equipamento.
/// Só o gestor muda; os outros veem.
class EqpParametrosTela extends StatefulWidget {
  const EqpParametrosTela({super.key});

  @override
  State<EqpParametrosTela> createState() => _EqpParametrosTelaState();
}

class _EqpParametrosTelaState extends State<EqpParametrosTela> {
  Map<String, dynamic> _p = {};
  bool _pode = false;
  bool _carregando = true;
  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await eqp('eqp_parametros', {});
      if (mounted) {
        setState(() {
          _p = Map<String, dynamic>.from((r['parametros'] as Map?) ?? const {});
          _pode = r['pode_alterar'] == true;
          _erro = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar(String chave, Object valor) async {
    setState(() => _salvando = true);
    try {
      final r = await eqp('eqp_parametros', {
        'acao': 'salvar',
        'valores': {chave: valor},
      });
      if (!mounted) return;
      setState(() => _p = Map<String, dynamic>.from((r['parametros'] as Map?) ?? const {}));
      avisarEqp(context, 'Parâmetro salvo');
    } catch (e) {
      if (mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _escolha(String chave, String titulo, String explicacao, Map<String, String> opcoes) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(explicacao, style: const TextStyle(color: Cores.neutro)),
          const SizedBox(height: 4),
          Wrap(spacing: 8, children: [
            for (final o in opcoes.entries)
              ChoiceChip(
                label: Text(o.value),
                selected: '${_p[chave]}' == o.key,
                onSelected: !_pode || _salvando ? null : (_) => _salvar(chave, o.key),
              ),
          ]),
          const SizedBox(height: 12),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    if (_carregando) return const Center(child: CircularProgressIndicator());
    return ListView(padding: margemDaTela(context), children: [
      Text('Parâmetros da Gestão de Equipamentos',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      if (!_pode) const Text('Só o gestor muda os parâmetros.', style: TextStyle(color: Cores.neutro)),
      if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
      if (_salvando) const LinearProgressIndicator(minHeight: 2),
      const SizedBox(height: 12),
      SecaoEqp(
        titulo: 'Operação',
        child: Column(children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _p['preparacao_obrigatoria'] == true,
            title: const Text('Preparação obrigatória para liberar'),
            subtitle: const Text('Ligado: o equipamento que voltou só fica disponível com o checklist e a OS de preparação '
                'concluídos.'),
            onChanged: !_pode || _salvando ? null : (v) => _salvar('preparacao_obrigatoria', v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _p['fotos_obrigatorias_os'] == true,
            title: const Text('Fotos obrigatórias na OS do equipamento'),
            subtitle: const Text('Ligado: o app pede fotos no início e na conclusão da OS de manutenção do equipamento.'),
            onChanged: !_pode || _salvando ? null : (v) => _salvar('fotos_obrigatorias_os', v),
          ),
        ]),
      ),
      SecaoEqp(
        titulo: 'Custos e ERP',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _escolha('retrofit_como', 'Retrofit', 'Custo do mês, ou investimento (soma ao valor do bem, fora do custo mensal, '
              'sempre visível no histórico).', const {'custo': 'Custo do mês', 'investimento': 'Investimento'}),
          _escolha('erp_dono_cadastro', 'Dono do cadastro do equipamento (com Protheus)', 'ServPilot: o cadastro é feito aqui e '
              'vai para o ERP. ERP: o ServPilot importa e não deixa editar os campos que vêm do ERP.',
              const {'servpilot': 'ServPilot', 'erp': 'ERP'}),
        ]),
      ),
    ]);
  }
}
