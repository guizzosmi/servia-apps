import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/banco_local.dart';
import '../core/consultas.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import '../core/sincronizacao.dart';
import '../widgets/indicador_sync.dart';
import '../widgets/status_chip.dart';

/// Tela principal: a parte do dia da equipe, com os serviços em ordem.
class HojeTela extends StatefulWidget {
  const HojeTela({super.key});

  @override
  State<HojeTela> createState() => _HojeTelaState();
}

class _HojeTelaState extends State<HojeTela> {
  /// Dias a partir de hoje: -1 (ontem) a 2 (depois de amanhã).
  int _deslocamento = 0;

  Future<void> _sair() async {
    final estado = EstadoApp.instancia;
    final pendentes = estado.pendentes;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair do app?'),
        content: Text(pendentes > 0
            ? 'Há $pendentes ação(ões) que ainda não subiram para a plataforma. Se sair agora, elas se perdem.'
            : 'Os dados deste aparelho serão apagados. Para voltar, é só entrar de novo.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: pendentes > 0 ? FilledButton.styleFrom(backgroundColor: Cores.erro) : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(pendentes > 0 ? 'Sair e perder' : 'Sair'),
          ),
        ],
      ),
    );
    if (ok == true) await estado.sair();
  }

  @override
  Widget build(BuildContext context) {
    final estado = EstadoApp.instancia;
    final banco = estado.banco;
    final sync = estado.sync;
    final conta = estado.conta;
    if (banco == null || sync == null || conta == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ListenableBuilder(
      listenable: Listenable.merge([banco, sync]),
      builder: (context, _) {
        final hoje = sync.hoje;
        final data = somarDias(hoje, _deslocamento);
        final partes = banco.partesDoDia(data);
        final eu = conta.colaboradorId;
        return Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Parte do dia', style: TextStyle(fontWeight: FontWeight.w800)),
              Text(banco.nomeColaborador(eu), style: const TextStyle(fontSize: 13, color: Cores.neutro)),
            ]),
            actions: [
              const IndicadorSync(),
              PopupMenuButton<String>(
                onSelected: (op) {
                  if (op == 'sync') sync.sincronizar();
                  if (op == 'sair') _sair();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'sync', child: Text('Sincronizar agora')),
                  PopupMenuItem(value: 'sair', child: Text('Sair')),
                ],
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: sync.sincronizar,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                _SeletorDeDia(
                  hoje: hoje,
                  deslocamento: _deslocamento,
                  aoMudar: (d) => setState(() => _deslocamento = d),
                ),
                if (sync.situacao == SituacaoSync.precisaEntrar)
                  _Aviso(
                    icone: Icons.lock_clock_outlined,
                    texto: 'Sua sessão venceu. Entre de novo para sincronizar (nada se perde).',
                    botao: 'Entrar',
                    aoTocar: () => context.push('/reentrar'),
                  ),
                if (partes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(children: [
                      const Icon(Icons.event_busy_outlined, size: 48, color: Cores.neutro),
                      const SizedBox(height: 8),
                      Text(
                        _deslocamento == 0
                            ? 'Nenhuma parte publicada para hoje.'
                            : 'Nenhuma parte publicada para ${dataComDia(data)}.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Cores.neutro),
                      ),
                      const SizedBox(height: 4),
                      Text('Última sincronização: ${haQuanto(sync.ultimaSync)}',
                          style: const TextStyle(color: Cores.neutro, fontSize: 12)),
                    ]),
                  ),
                for (final parte in partes) _BlocoParte(banco: banco, parte: parte, eu: eu),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SeletorDeDia extends StatelessWidget {
  const _SeletorDeDia({required this.hoje, required this.deslocamento, required this.aoMudar});

  final String hoje;
  final int deslocamento;
  final ValueChanged<int> aoMudar;

  @override
  Widget build(BuildContext context) {
    String rotulo(int d) => switch (d) {
          -1 => 'Ontem',
          0 => 'Hoje',
          1 => 'Amanhã',
          _ => dataComDia(somarDias(hoje, d)).split(',').first,
        };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Wrap(spacing: 6, children: [
            for (final d in const [-1, 0, 1, 2])
              ChoiceChip(
                label: Text(rotulo(d)),
                selected: deslocamento == d,
                onSelected: (_) => aoMudar(d),
              ),
          ]),
        ),
        Text(dataBr(somarDias(hoje, deslocamento)), style: const TextStyle(color: Cores.neutro)),
      ]),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icone, required this.texto, required this.botao, required this.aoTocar});

  final IconData icone;
  final String texto;
  final String botao;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) => Card(
        color: Cores.alerta.withValues(alpha: .08),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(children: [
            Icon(icone, color: Cores.alerta),
            const SizedBox(width: 8),
            Expanded(child: Text(texto)),
            TextButton(onPressed: aoTocar, child: Text(botao)),
          ]),
        ),
      );
}

/// Cabeçalho da parte (equipe, status, composição) e os serviços.
class _BlocoParte extends StatelessWidget {
  const _BlocoParte({required this.banco, required this.parte, required this.eu});

  final BancoLocal banco;
  final Map<String, dynamic> parte;
  final String eu;

  @override
  Widget build(BuildContext context) {
    final itens = banco.itensDaParte(parte['id'] as String);
    final feitos = itens.where((i) => i['status'] == 'concluido').length;
    final presentes = banco.presentes(parte['id'] as String);
    final equipe = banco.um('equipes', parte['equipe_id']);
    final estouNela = presentes.any((c) => c['colaborador_id'] == eu);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(height: 5, color: _cor(equipe?['cor'])),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text('${equipe?['nome'] ?? 'Equipe'}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  StatusChip(parte['status'] as String?, statusParte),
                ]),
                const SizedBox(height: 4),
                Text('$feitos de ${itens.length} concluído(s)', style: const TextStyle(color: Cores.neutro)),
                if (presentes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final c in presentes)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: c['papel'] == 'lider' ? const Icon(Icons.star, size: 16, color: Cores.indigo500) : null,
                        label: Text(banco.nomeColaborador(c['colaborador_id'])),
                      ),
                  ]),
                ],
                if (!estouNela)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Você saiu desta equipe neste dia.', style: TextStyle(color: Cores.alerta)),
                  ),
              ]),
            ),
          ]),
        ),
        if (itens.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Nenhum serviço nesta parte.', style: TextStyle(color: Cores.neutro)),
          ),
        for (var i = 0; i < itens.length; i++)
          _CartaoServico(banco: banco, item: itens[i], posicao: i + 1, eu: eu),
      ]),
    );
  }

  static Color _cor(Object? hex) {
    final s = '${hex ?? ''}'.replaceAll('#', '');
    final n = int.tryParse(s, radix: 16);
    return s.length == 6 && n != null ? Color(0xFF000000 | n) : Cores.indigo500;
  }
}

class _CartaoServico extends StatelessWidget {
  const _CartaoServico({required this.banco, required this.item, required this.posicao, required this.eu});

  final BancoLocal banco;
  final Map<String, dynamic> item;
  final int posicao;
  final String eu;

  @override
  Widget build(BuildContext context) {
    final ag = banco.agendamentoDo(item) ?? const {};
    final os = banco.osDo(item) ?? const {};
    final cliente = banco.um('clientes', os['cliente_id']);
    final local = banco.um('locais', os['local_id']);
    final designados = ((item['designados'] as List?) ?? const []).cast<String>();
    final paraOutros = designados.isNotEmpty && !designados.contains(eu);
    final finalizado = item['status'] == 'concluido' || item['status'] == 'nao_realizado';
    final atd = banco.atendimentoDoItem(item['id']);
    final noServico = atd == null ? const <Map<String, dynamic>>[] : banco.participantes(atd['id'], soAbertos: true);
    final estouAqui = noServico.any((p) => p['colaborador_id'] == eu);
    final quando = [
      tiposAgendamento[ag['tipo']] ?? '',
      janela(ag['janela_inicio'], ag['janela_fim']),
    ].where((x) => x.isNotEmpty).join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: finalizado ? Cores.fundo : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/servico/${item['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: Cores.indigo100,
              child: Text('$posicao', style: const TextStyle(fontWeight: FontWeight.w800, color: Cores.indigo700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('${os['codigo'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  StatusChip(item['status'] as String?, statusItem),
                ]),
                const SizedBox(height: 4),
                Text('${cliente?['nome'] ?? ''}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text([local?['nome'], local?['cidade']].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                    style: const TextStyle(color: Cores.neutro)),
                if (quando.isNotEmpty) Text(quando, style: const TextStyle(color: Cores.indigo500)),
                if (noServico.isNotEmpty)
                  Text(
                    '${estouAqui ? 'Você está aqui · ' : ''}No serviço: '
                    '${noServico.map((p) => banco.nomeColaborador(p['colaborador_id'])).join(', ')}',
                    style: const TextStyle(color: Cores.andamento, fontWeight: FontWeight.w600),
                  ),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (ag['prioridade'] == 'urgente' || ag['prioridade'] == 'alta')
                    StatusChip(ag['prioridade'] as String?, prioridades),
                  if (item['incluido_apos_publicacao'] == true) const Selo('Novo', Cores.coral500),
                  if (item['alterado_apos_publicacao'] == true) const Selo('Alterado', Cores.alerta),
                  if (item['papel_equipe'] == 'apoio') const Selo('Apoio', Cores.andamento),
                  if (paraOutros)
                    Selo('Com ${designados.map(banco.nomeColaborador).join(', ')}', Cores.neutro),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
