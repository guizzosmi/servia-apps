import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cadastros/catalogo.dart';
import '../servicos/parametros.dart';
import '../widgets/sla.dart';
import '../widgets/avisos_contratos.dart';
import '../widgets/dias_sem_fechar.dart';
import '../widgets/margem.dart';
import '../widgets/prazos_preventivas.dart';
import '../widgets/resumo_semana.dart';

/// Tela inicial: números da operação, prazos das preventivas (quando a
/// empresa usa) e contadores dos cadastros.
class InicioTela extends StatefulWidget {
  const InicioTela({super.key});

  @override
  State<InicioTela> createState() => _InicioTelaState();
}

class _InicioTelaState extends State<InicioTela> {
  // Contagens feitas uma vez ao abrir (e não a cada redesenho da tela).
  late final Map<String, Future<int>> _contagens = {
    for (final def in cadastrosDoMenu) def.tabela: _contar(def.tabela),
  };

  // Números da operação: o que está na fila e as OS em aberto.
  late final Future<int> _naFila = Supabase.instance.client
      .from('agendamentos')
      .select('id')
      .eq('status', 'pendente')
      .isFilter('excluido_em', null)
      .limit(1)
      .count(CountOption.exact)
      .then((r) => r.count);
  late final Future<int> _osAbertas = Supabase.instance.client
      .from('ordens_servico')
      .select('id')
      .not('status', 'in', '(concluida,cancelada)')
      .isFilter('excluido_em', null)
      .limit(1)
      .count(CountOption.exact)
      .then((r) => r.count);

  // Primeiro nome de quem entrou, para o "Olá, Fulano!".
  late final Future<String?> _primeiroNome = () async {
    final id = Sessao.atual?.usuarioId;
    if (id == null) return null;
    final r = await Supabase.instance.client.from('usuarios').select('nome').eq('id', id).maybeSingle();
    final nome = (r?['nome'] as String?)?.trim() ?? '';
    return nome.isEmpty ? null : nome.split(RegExp(r'\s+')).first;
  }();

  late final Future<int> _orcamentosEmAberto = Supabase.instance.client
      .from('orcamentos')
      .select('id')
      .inFilter('status', ['rascunho', 'enviado'])
      .isFilter('excluido_em', null)
      .limit(1)
      .count(CountOption.exact)
      .then((r) => r.count);

  // OS concluídas ainda sem cobrança (guia 31): só para quem cobra.
  final bool _veCobranca =
      (Sessao.atual?.tem(Papel.gestor) ?? false) || (Sessao.atual?.tem(Papel.financeiro) ?? false);
  late final Future<int> _aCobrar = Supabase.instance.client
      .from('ordens_servico')
      .select('id')
      .eq('status', 'concluida')
      .inFilter('cobranca_status', ['pendente', 'calculada', 'revisada'])
      .isFilter('excluido_em', null)
      .limit(1)
      .count(CountOption.exact)
      .then((r) => r.count);

  Widget _cartaoOperacao(IconData icone, String titulo, Future<int> valor, String destino) {
    return SizedBox(
      width: 220,
      child: Card(
        margin: EdgeInsets.zero,
        color: Cores.indigo700,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go(destino),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(icone, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FutureBuilder<int>(
                    future: valor,
                    builder: (_, s) => Text(
                      s.hasData ? '${s.data}' : (s.hasError ? '–' : '…'),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  Text(titulo, style: const TextStyle(color: Colors.white70)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<int> _contar(String tabela) async {
    final r = await Supabase.instance.client
        .from(tabela)
        .select('id')
        .isFilter('excluido_em', null)
        .limit(1)
        .count(CountOption.exact);
    return r.count;
  }

  @override
  Widget build(BuildContext context) {
    final sessao = Sessao.atual;
    return SingleChildScrollView(
      padding: margemDaTela(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<String?>(
            future: _primeiroNome,
            builder: (context, snap) => Text(snap.data == null ? 'Olá!' : 'Olá, ${snap.data}!',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text('${sessao?.email ?? ''} · ${sessao?.papeis.join(', ') ?? ''}',
              style: const TextStyle(color: Cores.neutro)),
          // Dias anteriores sem fechar (só o gestor vê; nunca hoje nem futuro).
          const DiasSemFechar(),
          // Guia 68: os 7 dias em números e alertas.
          const ResumoSemana(),
          // Guia 70: SLA vencido ou vencendo.
          const AlertasSla(),
          const SizedBox(height: 24),
          Wrap(spacing: 16, runSpacing: 16, children: [
            _cartaoOperacao(Icons.inbox_outlined, ParametrosEmpresa.instancia.modoSimples ? 'para agendar' : 'na fila',
                _naFila, ParametrosEmpresa.instancia.modoSimples ? '/agenda' : '/fila'),
            _cartaoOperacao(Icons.assignment_outlined, 'OS em aberto', _osAbertas, '/os'),
            _cartaoOperacao(Icons.request_quote_outlined, 'Orçamentos em Aberto', _orcamentosEmAberto, '/orcamentos'),
            if (_veCobranca) _cartaoOperacao(Icons.receipt_long_outlined, 'OS a cobrar', _aCobrar, '/cobrar'),
          ]),
          // Abrir a Início também gera as OS de preventiva que já podem nascer.
          ListenableBuilder(
            listenable: ParametrosEmpresa.instancia,
            builder: (context, _) {
              final p = ParametrosEmpresa.instancia;
              if (!p.carregado || !p.usaPreventivas) return const SizedBox.shrink();
              return const Padding(
                padding: EdgeInsets.only(top: 24),
                child: PrazosPreventivas(),
              );
            },
          ),
          // Reajuste perto, franquia passada, OS do aparelho sem preço.
          const AvisosContratos(),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final def in cadastrosDoMenu)
                SizedBox(
                  width: 220,
                  child: Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.go('/c/${def.chave}'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Cores.indigo100,
                              foregroundColor: Cores.indigo700,
                              child: Icon(def.icone),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FutureBuilder<int>(
                                    future: _contagens[def.tabela],
                                    builder: (_, s) => Text(
                                      s.hasData ? '${s.data}' : (s.hasError ? '–' : '…'),
                                      style: const TextStyle(
                                          fontSize: 22, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  Text(def.titulo,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Cores.neutro)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
