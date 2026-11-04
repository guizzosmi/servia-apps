import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../api.dart';
import '../widgets/aplicacoes_conta.dart';
import '../widgets/comuns.dart';
import '../widgets/fatura_acoes.dart';
import 'conta_formularios.dart';

/// Tudo de um cliente: assinatura, dados da nota, consumo, usuários, cupons e faturas.
class ContaTela extends StatefulWidget {
  const ContaTela({super.key, required this.id});

  final String id;

  @override
  State<ContaTela> createState() => _ContaTelaState();
}

class _ContaTelaState extends State<ContaTela> {
  late Future<(Map<String, dynamic>, Map<String, dynamic>)> _dados = _carregar();

  Future<(Map<String, dynamic>, Map<String, dynamic>)> _carregar() async {
    final r = await Future.wait([rpcMapa('admin_conta', {'p_conta': widget.id}), rpcMapa('admin_precos')]);
    return (r[0], r[1]);
  }

  void _recarregar() => setState(() => _dados = _carregar());

  Future<void> _salvar(Map<String, dynamic> campos, String ok) async {
    try {
      await rpcMapa('admin_conta_salvar', {'p': {'conta_id': widget.id, ...campos}});
      if (mounted) avisar(context, ok);
      if (mounted) _recarregar();
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  Future<void> _confirmar(String titulo, String texto, Map<String, dynamic> campos, String ok) async {
    final sim = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (sim == true) await _salvar(campos, ok);
  }

  Future<void> _aplicarCupom() async {
    final codigo = TextEditingController();
    final ok = await dialogoForm(context, titulo: 'Aplicar cupom', confirmar: 'Aplicar', campos: [
      campoTexto(codigo, 'Código do cupom', ajuda: 'Vale nas próximas faturas. Substitui o cupom atual.'),
    ]);
    if (!ok) return;
    try {
      final r = await rpcMapa('admin_cupom_aplicar', {'p': {'conta_id': widget.id, 'codigo': codigo.text.trim()}});
      if (mounted) avisar(context, 'Cupom ${r['codigo']}: ${r['resumo']}.');
      if (mounted) _recarregar();
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  Future<void> _avulsa() async {
    final desc = TextEditingController(text: 'Implantação e treinamento');
    final valor = TextEditingController();
    final venc = TextEditingController(text: dataBr(DateTime.now().add(const Duration(days: 5)).toIso8601String()));
    final ok = await dialogoForm(context, titulo: 'Nova cobrança avulsa', confirmar: 'Criar', campos: [
      campoTexto(desc, 'Descrição (vai na fatura e na nota)'),
      campoTexto(valor, 'Valor (R\$)', teclado: TextInputType.number),
      campoTexto(venc, 'Vencimento (dd/mm/aaaa)'),
    ]);
    if (!ok) return;
    try {
      await db.rpc('admin_fatura_avulsa', params: {
        'p': {'conta_id': widget.id, 'descricao': desc.text.trim(), 'valor': numero(valor.text), 'vencimento': dataIso(venc.text)}
      });
      if (mounted) avisar(context, 'Cobrança criada. Use "Copiar link de pagamento" para enviar.');
      if (mounted) _recarregar();
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Carregar<(Map<String, dynamic>, Map<String, dynamic>)>(
        futuro: _dados,
        recarregar: _recarregar,
        construir: (r) {
          final d = r.$1, precos = r.$2;
          final conta = mapa(d['conta']);
          final a = mapa(d['assinatura']);
          final c = mapa(d['consumo']);
          final bloqueada = conta['situacao'] == 'bloqueada';
          final cancelada = a['situacao'] == 'cancelada';
          return ListView(padding: const EdgeInsets.all(24), children: [
            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${conta['nome']}', style: Theme.of(context).textTheme.headlineSmall),
              Text('código ${conta['codigo']}', style: const TextStyle(color: Cores.neutro)),
              ChipSituacao(a['cobrar'] == false && !cancelada ? 'cortesia' : '${a['situacao']}'),
              if (bloqueada) const ChipSituacao('bloqueada'),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                icon: Icon(bloqueada ? Icons.lock_open : Icons.lock_outline),
                label: Text(bloqueada ? 'Desbloquear' : 'Bloquear acesso'),
                onPressed: () => _confirmar(
                  bloqueada ? 'Desbloquear?' : 'Bloquear o acesso?',
                  bloqueada
                      ? 'Todos os usuários voltam a entrar no painel e no app.'
                      : 'Ninguém da empresa entra no painel nem sincroniza o app até você desbloquear. Os dados ficam guardados.',
                  {'conta_situacao': bloqueada ? 'ativa' : 'bloqueada'},
                  bloqueada ? 'Desbloqueada.' : 'Bloqueada.'),
              ),
              OutlinedButton.icon(
                icon: Icon(cancelada ? Icons.restart_alt : Icons.cancel_outlined),
                label: Text(cancelada ? 'Reativar assinatura' : 'Cancelar assinatura'),
                onPressed: () => _confirmar(
                  cancelada ? 'Reativar a assinatura?' : 'Cancelar a assinatura?',
                  cancelada
                      ? 'Volta a gerar mensalidades na virada do ciclo (se a cobrança estiver ligada).'
                      : 'Para de gerar mensalidades e cancela as faturas em aberto que ainda não venceram. O acesso continua até você bloquear.',
                  cancelada ? {'reativar': true} : {'cancelar': true},
                  cancelada ? 'Reativada.' : 'Assinatura cancelada.'),
              ),
              OutlinedButton.icon(icon: const Icon(Icons.local_offer_outlined), label: const Text('Aplicar cupom'), onPressed: _aplicarCupom),
              OutlinedButton.icon(icon: const Icon(Icons.add), label: const Text('Cobrança avulsa'), onPressed: _avulsa),
            ]),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, box) {
              final duas = box.maxWidth >= 1100;
              final esquerda = [
                FormAssinatura(assinatura: a, planos: lista(precos['planos']), valorMensal: d['valor_mensal'],
                    aoSalvar: (campos) => _salvar(campos, 'Assinatura salva.')),
                FormNota(assinatura: a, aoSalvar: (campos) => _salvar(campos, 'Dados da nota salvos.')),
              ];
              final direita = [
                Secao(
                  titulo: 'Consumo do ciclo ${dataBr(c['ciclo_inicio'])} a ${dataBr(c['ciclo_fim'])}',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Medidor(rotulo: 'Usuários cobrados (regra dos dias)', usado: numero(c['usuarios_cobrados']), incluido: numero(c['usuarios_incluidos'])),
                    Medidor(rotulo: 'Minutos de IA', usado: numero(c['minutos_usados']), incluido: numero(c['minutos_incluidos'])),
                    Medidor(rotulo: 'Mensagens de WhatsApp', usado: numero(c['mensagens_usadas']), incluido: numero(c['mensagens_incluidas'])),
                    const SizedBox(height: 8),
                    Campo('Usuários com login hoje', '${c['usuarios_ativos'] ?? 0}'),
                    Campo('Custo estimado da IA', 'US\$ ${numero(c['custo_ia_usd']).toStringAsFixed(3)}'),
                  ]),
                ),
                _Usuarios(lista(d['usuarios'])),
                _Empresas(lista(d['empresas'])),
                AplicacoesDaConta(contaId: widget.id),
              ];
              return duas
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Column(children: esquerda)),
                      const SizedBox(width: 16),
                      Expanded(child: Column(children: direita)),
                    ])
                  : Column(children: [...esquerda, ...direita]);
            }),
            _Faturas(lista(d['faturas']), aoMudar: _recarregar),
            _Cupons(lista(d['cupons'])),
            _Eventos(lista(d['eventos'])),
          ]);
        },
      );
}

class _Usuarios extends StatelessWidget {
  const _Usuarios(this.usuarios);

  final List<Map<String, dynamic>> usuarios;

  @override
  Widget build(BuildContext context) => Secao(
        titulo: 'Usuários no ciclo',
        child: Column(children: [
          for (final u in usuarios)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${u['nome']}${u['ativo'] == true ? '' : ' (desligado)'}'),
              subtitle: Text('${u['email'] ?? ''} · ${(u['papeis'] as List?)?.join(', ') ?? ''}'
                  '${u['ultimo_acesso'] != null ? ' · último acesso ${dataBr(u['ultimo_acesso'], hora: true)}' : ''}'),
              trailing: Text('${u['dias']} dia(s)${u['trabalhou'] == true ? ' · atendeu' : ''}\n${u['cobrado'] == true ? 'cobrado' : 'não cobrado'}',
                  textAlign: TextAlign.right,
                  style: TextStyle(color: u['cobrado'] == true ? Cores.tinta : Cores.neutro)),
            ),
        ]),
      );
}

class _Empresas extends StatelessWidget {
  const _Empresas(this.empresas);

  final List<Map<String, dynamic>> empresas;

  @override
  Widget build(BuildContext context) => Secao(
        titulo: 'Empresas da conta',
        child: Column(children: [
          for (final e in empresas)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${e['razao_social']}'),
              subtitle: Text([e['documento'], '${e['cidade'] ?? ''}/${e['uf'] ?? ''}', e['telefone'], e['email']]
                  .where((x) => x != null && '$x'.isNotEmpty)
                  .join(' · ')),
            ),
        ]),
      );
}

class _Faturas extends StatelessWidget {
  const _Faturas(this.faturas, {required this.aoMudar});

  final List<Map<String, dynamic>> faturas;
  final VoidCallback aoMudar;

  @override
  Widget build(BuildContext context) => Secao(
        titulo: 'Faturas',
        child: faturas.isEmpty
            ? const Text('Nenhuma fatura ainda.', style: TextStyle(color: Cores.neutro))
            : Column(children: [
                for (final f in faturas)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Nº ${f['numero']} · ${rotulosTipoFatura[f['tipo']] ?? f['tipo']}'
                        '${f['periodo_inicio'] != null ? ' · ${dataBr(f['periodo_inicio'])} a ${dataBr(f['periodo_fim'])}' : ''}'),
                    subtitle: Text('vence ${dataBr(f['vencimento'])} · ${moeda(f['valor_total'])}'
                        '${f['pago_em'] != null ? ' · pago em ${dataBr(f['pago_em'])} (${f['forma_pagamento'] ?? ''})' : ''}'
                        '${f['nf_numero'] != null ? ' · NF ${f['nf_numero']}' : ''}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      ChipSituacao(f['situacao'] == 'aberta' && '${f['vencimento']}'.compareTo(DateTime.now().toIso8601String().substring(0, 10)) < 0
                          ? 'vencida'
                          : '${f['situacao']}'),
                      MenuFatura(fatura: f, aoMudar: aoMudar),
                    ]),
                    children: [
                      for (final i in lista(f['itens']))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            Expanded(child: Text('${i['descricao']}')),
                            Text('${numero(i['quantidade']) == 1 ? '' : '${numero(i['quantidade'])} x ${moeda(i['valor_unitario'])} = '}${moeda(i['total'])}'),
                          ]),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
              ]),
      );
}

class _Cupons extends StatelessWidget {
  const _Cupons(this.cupons);

  final List<Map<String, dynamic>> cupons;

  @override
  Widget build(BuildContext context) => cupons.isEmpty
      ? const SizedBox.shrink()
      : Secao(
          titulo: 'Cupons',
          child: Column(children: [
            for (final c in cupons)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${c['codigo']}${c['ativo'] == true ? '' : ' (substituído)'}'),
                subtitle: Text('${c['resumo']} · usado em ${c['faturas_usadas']} mensalidade(s) · pelo ${c['origem']} em ${dataBr(c['aplicado_em'])}'),
              ),
          ]),
        );
}

class _Eventos extends StatelessWidget {
  const _Eventos(this.eventos);

  final List<Map<String, dynamic>> eventos;

  @override
  Widget build(BuildContext context) => eventos.isEmpty
      ? const SizedBox.shrink()
      : Secao(
          titulo: 'Avisos de pagamento recebidos',
          child: Column(children: [
            for (final e in eventos)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${dataBr(e['recebido_em'], hora: true)} · ${e['origem']} · ${e['status'] ?? ''}'),
                subtitle: Text('${e['resultado'] ?? ''}${e['mp_pagamento_id'] != null ? ' · MP ${e['mp_pagamento_id']}' : ''}'),
                trailing: e['valor'] != null ? Text(moeda(e['valor'])) : null,
              ),
          ]),
        );
}
