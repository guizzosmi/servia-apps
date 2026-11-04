import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../api.dart';
import 'comuns.dart';

/// Guia 52: aplicações do hub ligadas nesta conta (o cliente só vê as ligadas).
class AplicacoesDaConta extends StatefulWidget {
  const AplicacoesDaConta({super.key, required this.contaId});

  final String contaId;

  @override
  State<AplicacoesDaConta> createState() => _AplicacoesDaContaState();
}

class _AplicacoesDaContaState extends State<AplicacoesDaConta> {
  List<Map<String, dynamic>>? _itens;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await db.rpc('admin_conta_aplicacoes', params: {'p_conta': widget.contaId});
      if (mounted) setState(() => _itens = lista(r));
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  Future<void> _ligar(String app, bool ligada) async {
    setState(() => _ocupado = true);
    try {
      await rpcMapa('admin_conta_aplicacao', {'p': {'conta_id': widget.contaId, 'aplicacao': app, 'ligada': ligada}});
      if (mounted) avisar(context, ligada ? 'Aplicação ligada.' : 'Aplicação desligada.');
      await _carregar();
    } catch (e) {
      if (mounted) avisarErro(context, e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) => Secao(
        titulo: 'Aplicações do hub',
        child: _itens == null
            ? const LinearProgressIndicator(minHeight: 2)
            : Column(children: [
                for (final a in _itens!)
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${a['nome']}'),
                    subtitle: Text(a['situacao'] == 'em_breve'
                        ? 'Em breve (ligue só para quem for testar)'
                        : a['ligada'] == true && a['desde'] != null
                            ? 'Ligada desde ${dataBr(a['desde'])}'
                            : 'Desligada'),
                    value: a['ligada'] == true,
                    onChanged: _ocupado ? null : (v) => _ligar('${a['codigo']}', v),
                  ),
                const Text('Os usuários entram de novo (ou esperam o token renovar, até 1 hora) para ver a mudança.',
                    style: TextStyle(color: Cores.neutro, fontSize: 12)),
              ]),
      );
}
