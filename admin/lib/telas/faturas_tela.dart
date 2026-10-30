import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../api.dart';
import '../baixar.dart';
import '../widgets/comuns.dart';
import '../widgets/fatura_acoes.dart';

/// Faturas de todos os clientes + planilha para o contador emitir as notas.
class FaturasTela extends StatefulWidget {
  const FaturasTela({super.key, this.situacao});

  final String? situacao;

  @override
  State<FaturasTela> createState() => _FaturasTelaState();
}

class _FaturasTelaState extends State<FaturasTela> {
  late String _situacao = widget.situacao ?? '';
  late Future<List<Map<String, dynamic>>> _dados = _carregar();

  Future<List<Map<String, dynamic>>> _carregar() => rpcLista('admin_faturas', {'p': {'situacao': _situacao}});

  void _recarregar() => setState(() => _dados = _carregar());

  @override
  void didUpdateWidget(covariant FaturasTela old) {
    super.didUpdateWidget(old);
    if (old.situacao != widget.situacao) {
      _situacao = widget.situacao ?? '';
      _dados = _carregar();
    }
  }

  Future<void> _exportar() async {
    final hoje = DateTime.now();
    final ini = DateTime(hoje.year, hoje.month - 1, 1);
    final fim = DateTime(hoje.year, hoje.month, 0);
    final de = TextEditingController(text: dataBr(ini.toIso8601String()));
    final ate = TextEditingController(text: dataBr(fim.toIso8601String()));
    final ok = await dialogoForm(context, titulo: 'Planilha para o contador', confirmar: 'Baixar', campos: [
      const Text('Tudo o que foi PAGO no período, com os dados do tomador e a discriminação de cada nota.'),
      const SizedBox(height: 12),
      campoTexto(de, 'Pago de (dd/mm/aaaa)'),
      campoTexto(ate, 'até (dd/mm/aaaa)'),
    ]);
    if (!ok) return;
    final isoDe = dataIso(de.text), isoAte = dataIso(ate.text);
    if (isoDe == null || isoAte == null) {
      if (mounted) avisar(context, 'Confira as datas (dd/mm/aaaa).', erro: true);
      return;
    }
    try {
      final linhas = await rpcLista('admin_exportar_nf', {'p': {'de': isoDe, 'ate': isoAte}});
      final conteudo = csv(
        ['Fatura', 'Pago em', 'Valor', 'Forma', 'Tipo', 'Discriminação', 'Tomador', 'CNPJ/CPF', 'Inscrição municipal',
         'E-mail', 'Telefone', 'Endereço', 'Cidade', 'UF', 'CEP', 'Pagamento MP', 'NF já emitida'],
        [
          for (final l in linhas)
            [l['fatura'], l['pago_em'], numero(l['valor']).toStringAsFixed(2).replaceAll('.', ','), l['forma'], l['tipo'],
             'ServPilot - ${l['discriminacao'] ?? ''}', l['tomador'], l['documento'], l['inscricao_municipal'], l['email'],
             l['telefone'], l['endereco'], l['cidade'], l['uf'], l['cep'], l['mp_pagamento'], l['nf_numero']],
        ],
      );
      baixarTexto('servpilot-notas-${isoDe}_a_$isoAte.csv', conteudo);
      if (mounted) avisar(context, '${linhas.length} pagamento(s) na planilha.');
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Faturas', style: Theme.of(context).textTheme.headlineSmall)),
            FilledButton.icon(onPressed: _exportar, icon: const Icon(Icons.download), label: const Text('Planilha para o contador')),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            DropdownButton<String>(
              value: _situacao,
              onChanged: (v) {
                _situacao = v ?? '';
                _recarregar();
              },
              items: const [
                DropdownMenuItem(value: '', child: Text('Todas (últimos meses)')),
                DropdownMenuItem(value: 'aberta', child: Text('Em aberto')),
                DropdownMenuItem(value: 'vencida', child: Text('Vencidas')),
                DropdownMenuItem(value: 'paga', child: Text('Pagas')),
                DropdownMenuItem(value: 'sem_nota', child: Text('Pagas sem nota fiscal')),
                DropdownMenuItem(value: 'cancelada', child: Text('Canceladas')),
              ],
            ),
            IconButton(onPressed: _recarregar, icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: Carregar<List<Map<String, dynamic>>>(
              futuro: _dados,
              recarregar: _recarregar,
              construir: (fs) => fs.isEmpty
                  ? const Center(child: Text('Nenhuma fatura.'))
                  : Card(
                      child: ListView.separated(
                        itemCount: fs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final f = fs[i];
                          return ListTile(
                            onTap: () => context.go('/contas/${f['conta_id']}'),
                            title: Text('Nº ${f['numero']} · ${f['conta']} · ${rotulosTipoFatura[f['tipo']] ?? f['tipo']}'),
                            subtitle: Text([
                              'vence ${dataBr(f['vencimento'])}',
                              if (f['periodo_inicio'] != null) '${dataBr(f['periodo_inicio'])} a ${dataBr(f['periodo_fim'])}',
                              if (f['pago_em'] != null) 'pago em ${dataBr(f['pago_em'])} (${f['forma_pagamento'] ?? ''})',
                              f['nf_numero'] != null ? 'NF ${f['nf_numero']}' : (f['situacao'] == 'paga' && numero(f['valor_pago']) > 0 ? 'sem nota' : ''),
                            ].where((x) => x.isNotEmpty).join(' · ')),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(moeda(f['valor_total']), style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              ChipSituacao(f['vencida'] == true ? 'vencida' : '${f['situacao']}'),
                              MenuFatura(fatura: f, aoMudar: _recarregar),
                            ]),
                          );
                        },
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Depois que o contador emitir, registre o número da nota em cada fatura (menu ⋮ > Registrar a nota fiscal).',
              style: TextStyle(color: Cores.neutro)),
        ]),
      );
}
