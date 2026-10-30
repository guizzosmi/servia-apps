import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../api.dart';
import '../widgets/comuns.dart';

class ResumoTela extends StatefulWidget {
  const ResumoTela({super.key});

  @override
  State<ResumoTela> createState() => _ResumoTelaState();
}

class _ResumoTelaState extends State<ResumoTela> {
  late Future<Map<String, dynamic>> _dados = rpcMapa('admin_resumo');
  bool _rodando = false;

  void _recarregar() => setState(() => _dados = rpcMapa('admin_resumo'));

  Future<void> _rodarRotina() async {
    setState(() => _rodando = true);
    try {
      final r = await rpcMapa('admin_rodar_rotina');
      if (mounted) avisar(context, 'Rotina rodada: ${r['usuarios_registrados']} registro(s) de uso, ${r['ciclos_virados']} ciclo(s) virado(s).');
      if (mounted) _recarregar();
    } catch (e) {
      if (mounted) avisarErro(context, e);
    } finally {
      if (mounted) setState(() => _rodando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Carregar<Map<String, dynamic>>(
        futuro: _dados,
        recarregar: _recarregar,
        construir: (d) {
          final c = mapa(d['contas']);
          final venc = mapa(d['vencidas']);
          final terminando = lista(d['teste_terminando']);
          return ListView(padding: const EdgeInsets.all(24), children: [
            Row(children: [
              Expanded(child: Text('Resumo', style: Theme.of(context).textTheme.headlineSmall)),
              IconButton(onPressed: _recarregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
              OutlinedButton.icon(
                onPressed: _rodando ? null : _rodarRotina,
                icon: const Icon(Icons.play_arrow_outlined),
                label: const Text('Rodar a rotina agora'),
              ),
            ]),
            const SizedBox(height: 4),
            const Text('A rotina roda sozinha: uso dos usuários às 23h50 e faturas às 06h15.',
                style: TextStyle(color: Cores.neutro)),
            const SizedBox(height: 16),
            Text('Clientes', style: Theme.of(context).textTheme.titleMedium),
            Wrap(children: [
              Indicador(rotulo: 'Em teste grátis', valor: '${c['teste'] ?? 0}', cor: Cores.info,
                  aoTocar: () => context.go('/contas?situacao=teste')),
              Indicador(rotulo: 'Pagantes em dia', valor: '${c['ativa'] ?? 0}', cor: Cores.sucesso,
                  aoTocar: () => context.go('/contas?situacao=ativa')),
              Indicador(rotulo: 'Atrasados', valor: '${c['atrasada'] ?? 0}', cor: Cores.erro,
                  aoTocar: () => context.go('/contas?situacao=atrasada')),
              Indicador(rotulo: 'Cortesia', valor: '${c['cortesia'] ?? 0}', cor: Cores.andamento,
                  aoTocar: () => context.go('/contas?situacao=cortesia')),
              Indicador(rotulo: 'Bloqueados', valor: '${c['bloqueada'] ?? 0}',
                  aoTocar: () => context.go('/contas?situacao=bloqueada')),
              Indicador(rotulo: 'Novos neste mês', valor: '${d['novas_mes'] ?? 0}'),
            ]),
            const SizedBox(height: 16),
            Text('Dinheiro', style: Theme.of(context).textTheme.titleMedium),
            Wrap(children: [
              Indicador(rotulo: 'Mensalidades previstas (base)', valor: moeda(d['mensalidades_previstas'])),
              Indicador(rotulo: 'Recebido neste mês', valor: moeda(d['recebido_mes']), cor: Cores.sucesso),
              Indicador(rotulo: 'A receber (em aberto)', valor: moeda(d['a_receber']),
                  aoTocar: () => context.go('/faturas?situacao=aberta')),
              Indicador(rotulo: 'Vencidas (${venc['quantidade'] ?? 0})', valor: moeda(venc['valor']), cor: Cores.erro,
                  aoTocar: () => context.go('/faturas?situacao=vencida')),
              Indicador(rotulo: 'Notas fiscais a emitir', valor: '${d['notas_pendentes'] ?? 0}', cor: Cores.alerta,
                  aoTocar: () => context.go('/faturas?situacao=sem_nota')),
            ]),
            const SizedBox(height: 16),
            Text('Uso neste mês (todas as empresas)', style: Theme.of(context).textTheme.titleMedium),
            Wrap(children: [
              Indicador(rotulo: 'Minutos de áudio na IA', valor: '${d['minutos_mes'] ?? 0}'),
              Indicador(rotulo: 'Custo estimado da IA', valor: 'US\$ ${numero(d['custo_ia_mes_usd']).toStringAsFixed(2)}'),
              Indicador(rotulo: 'Mensagens automáticas', valor: '${d['mensagens_mes'] ?? 0}'),
            ]),
            if (terminando.isNotEmpty) ...[
              const SizedBox(height: 16),
              Secao(
                titulo: 'Teste grátis terminando (3 dias)',
                child: Column(children: [
                  for (final t in terminando)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${t['nome']}'),
                      subtitle: Text('termina em ${dataBr(t['teste_ate'])}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/contas/${t['conta_id']}'),
                    ),
                ]),
              ),
            ],
          ]);
        },
      );
}
