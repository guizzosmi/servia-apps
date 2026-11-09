import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../api.dart';
import '../widgets/comuns.dart';

/// Guia 103: planos próprios da Gestão de Equipamentos (decisão 9 do dono): valor, usuários e equipamentos
/// incluídos e o valor por equipamento acima do limite (vazio = não passa do limite). E o plano da aplicação de
/// cada conta que usa também a Refrigeração (segundo plano, cobrado na mesma mensalidade).
class EqpPlanosTela extends StatefulWidget {
  const EqpPlanosTela({super.key});

  @override
  State<EqpPlanosTela> createState() => _EqpPlanosTelaState();
}

class _EqpPlanosTelaState extends State<EqpPlanosTela> {
  late Future<Map<String, dynamic>> _dados = rpcMapa('admin_eqp_planos');

  void _recarregar() => setState(() => _dados = rpcMapa('admin_eqp_planos'));

  String _txt(dynamic v) => v == null ? '' : '$v'.replaceAll('.', ',');

  Future<void> _editar([Map<String, dynamic>? p]) async {
    final codigo = TextEditingController(text: '${p?['codigo'] ?? 'eqp_'}');
    final nome = TextEditingController(text: '${p?['nome'] ?? ''}');
    final desc = TextEditingController(text: '${p?['descricao'] ?? ''}');
    final valor = TextEditingController(text: _txt(p?['valor_mensal']));
    final usuarios = TextEditingController(text: '${p?['usuarios_incluidos'] ?? 3}');
    final usuarioExtra = TextEditingController(text: _txt(p?['valor_usuario_extra'] ?? 49));
    final equipamentos = TextEditingController(text: '${p?['equipamentos_incluidos'] ?? ''}');
    final equipamentoExtra = TextEditingController(text: _txt(p?['valor_equipamento_extra']));
    final minutos = TextEditingController(text: '${p?['minutos_ia_incluidos'] ?? 300}');
    final mensagens = TextEditingController(text: '${p?['mensagens_incluidas'] ?? 250}');
    final ok = await dialogoForm(context, titulo: p == null ? 'Novo plano da Gestão de Equipamentos' : 'Plano ${p['nome']}', campos: [
      if (p == null) campoTexto(codigo, 'Código', ajuda: 'Minúsculas e _ (ex.: eqp_basico). Não muda depois.'),
      campoTexto(nome, 'Nome'),
      campoTexto(desc, 'Descrição'),
      campoTexto(valor, 'Mensal (R\$)', teclado: const TextInputType.numberWithOptions(decimal: true)),
      campoTexto(usuarios, 'Usuários incluídos', teclado: TextInputType.number),
      campoTexto(usuarioExtra, 'Por usuário extra (R\$)', teclado: const TextInputType.numberWithOptions(decimal: true)),
      campoTexto(equipamentos, 'Equipamentos incluídos', ajuda: 'Vazio = sem limite', teclado: TextInputType.number),
      campoTexto(equipamentoExtra, 'Por equipamento extra (R\$)',
          ajuda: 'Vazio = não passa do limite (o cadastro para)', teclado: const TextInputType.numberWithOptions(decimal: true)),
      campoTexto(minutos, 'Minutos de IA incluídos', teclado: TextInputType.number),
      campoTexto(mensagens, 'Mensagens incluídas', teclado: TextInputType.number),
    ]);
    num? n(TextEditingController c) => num.tryParse(c.text.trim().replaceAll('.', '').replaceAll(',', '.'));
    if (!ok) return;
    try {
      await rpcMapa('admin_eqp_plano_salvar', {
        'p': {
          if (p != null) 'id': p['id'] else 'codigo': codigo.text.trim(),
          'nome': nome.text.trim(),
          'descricao': desc.text.trim(),
          if (n(valor) != null) 'valor_mensal': n(valor),
          if (n(usuarios) != null) 'usuarios_incluidos': n(usuarios)!.toInt(),
          if (n(usuarioExtra) != null) 'valor_usuario_extra': n(usuarioExtra),
          'equipamentos_incluidos': n(equipamentos)?.toInt(),
          'valor_equipamento_extra': n(equipamentoExtra),
          if (n(minutos) != null) 'minutos_ia_incluidos': n(minutos)!.toInt(),
          if (n(mensagens) != null) 'mensagens_incluidas': n(mensagens)!.toInt(),
        },
      });
      if (mounted) avisar(context, 'Plano salvo.');
      _recarregar();
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  Future<void> _ativo(Map<String, dynamic> p, bool ativo) async {
    try {
      await rpcMapa('admin_eqp_plano_salvar', {'p': {'id': p['id'], 'ativo': ativo}});
      _recarregar();
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  Future<void> _planoDaConta(Map<String, dynamic> c, String? planoId) async {
    try {
      await rpcMapa('admin_conta_plano_equipamentos', {'p': {'conta_id': c['conta_id'], 'plano_id': planoId}});
      if (mounted) avisar(context, planoId == null ? 'Segundo plano retirado.' : 'Plano da aplicação definido.');
      _recarregar();
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Carregar<Map<String, dynamic>>(
        futuro: _dados,
        recarregar: _recarregar,
        construir: (d) {
          final planos = lista(d['planos']);
          final ativos = planos.where((p) => p['ativo'] == true).toList();
          return ListView(padding: const EdgeInsets.all(24), children: [
            Row(children: [
              Expanded(child: Text('Planos da Gestão de Equipamentos', style: Theme.of(context).textTheme.headlineSmall)),
              FilledButton.icon(onPressed: () => _editar(), icon: const Icon(Icons.add), label: const Text('Novo plano')),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Plano próprio da aplicação, cobrando por equipamento. Ficam fora do site (os valores são hipóteses a fechar). '
              'Conta só com a Gestão de Equipamentos: assine o plano dela como o principal. Conta que já tem a Refrigeração: '
              'escolha abaixo o segundo plano, que entra na mesma mensalidade.',
              style: TextStyle(color: Cores.neutro),
            ),
            const SizedBox(height: 16),
            for (final p in planos)
              Secao(
                titulo: '${p['nome']}${p['ativo'] == true ? '' : ' (inativo)'}',
                acoes: [
                  Switch(value: p['ativo'] == true, onChanged: (v) => _ativo(p, v)),
                  IconButton(tooltip: 'Editar', onPressed: () => _editar(p), icon: const Icon(Icons.edit_outlined)),
                ],
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Campo('Código', '${p['codigo']}'),
                  Campo('Mensal', moeda(p['valor_mensal'])),
                  Campo('Usuários', '${p['usuarios_incluidos']} incluídos · ${moeda(p['valor_usuario_extra'])} por extra'),
                  Campo(
                      'Equipamentos',
                      p['equipamentos_incluidos'] == null
                          ? 'Sem limite'
                          : '${p['equipamentos_incluidos']} incluídos · '
                              '${p['valor_equipamento_extra'] == null ? 'não passa do limite' : '${moeda(p['valor_equipamento_extra'])} por extra'}'),
                  Campo('IA', '${p['minutos_ia_incluidos']} minutos e ${p['mensagens_incluidas']} mensagens'),
                  Campo('Contas', '${p['contas']}'),
                  if ('${p['descricao'] ?? ''}'.isNotEmpty) Campo('Descrição', '${p['descricao']}'),
                ]),
              ),
            Secao(
              titulo: 'Contas com a Gestão de Equipamentos',
              child: lista(d['contas']).isEmpty
                  ? const Text('Nenhuma conta com a aplicação ligada.', style: TextStyle(color: Cores.neutro))
                  : Column(children: [
                      for (final c in lista(d['contas']))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${c['nome']} (${c['codigo']})'),
                          subtitle: Text([
                            'principal: ${c['plano_principal'] ?? '—'}',
                            '${c['equipamentos_ativos']} equipamento(s)'
                                '${c['equipamentos_incluidos'] != null ? ' de ${c['equipamentos_incluidos']}' : ''}',
                            if (c['ligada_desde'] != null) 'ligada desde ${dataBr(c['ligada_desde'])}',
                          ].join(' · ')),
                          trailing: c['plano_principal_aplicacao'] == 'equipamentos'
                              ? const Text('Plano principal é da aplicação')
                              : SizedBox(
                                  width: 260,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: ativos.any((p) => p['id'] == c['plano_equipamentos_id'])
                                        ? '${c['plano_equipamentos_id']}'
                                        : '',
                                    isExpanded: true,
                                    decoration: const InputDecoration(labelText: 'Plano da aplicação', isDense: true),
                                    items: [
                                      const DropdownMenuItem(value: '', child: Text('Sem plano (em teste)')),
                                      for (final p in ativos) DropdownMenuItem(value: '${p['id']}', child: Text('${p['nome']}')),
                                    ],
                                    onChanged: (v) => _planoDaConta(c, v == null || v.isEmpty ? null : v),
                                  ),
                                ),
                        ),
                    ]),
            ),
          ]);
        },
      );
}
