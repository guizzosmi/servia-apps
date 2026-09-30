import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/consultas.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import '../widgets/indicador_sync.dart';
import '../widgets/status_chip.dart';

/// Um serviço da parte: cliente, local, o que fazer, equipamentos e o
/// andamento (a caminho, não realizado). O atendimento em si (check-in,
/// relato, medições...) entra no guia 10.
class ServicoTela extends StatelessWidget {
  const ServicoTela({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    final estado = EstadoApp.instancia;
    final banco = estado.banco!;
    return ListenableBuilder(
      listenable: banco,
      builder: (context, _) {
        final item = banco.um('partes_itens', itemId);
        if (item == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Serviço')),
            body: const Center(child: Text('Este serviço não está mais na sua parte.')),
          );
        }
        final ag = banco.agendamentoDo(item) ?? const {};
        final os = banco.osDo(item) ?? const {};
        final parte = banco.um('partes_diarias', item['parte_id']) ?? const {};
        final cliente = banco.um('clientes', os['cliente_id']) ?? const {};
        final local = banco.um('locais', os['local_id']) ?? const {};
        final contato = banco.um('contatos', os['solicitante_contato_id']);
        final equipamentos = banco.equipamentosDaOs(os['id']);
        final endereco = [
          [local['logradouro'], local['numero']].where((x) => x != null && '$x'.isNotEmpty).join(', '),
          local['bairro'],
          [local['cidade'], local['uf']].where((x) => x != null && '$x'.isNotEmpty).join('/'),
        ].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
        final orientacoes = [ag['orientacoes'], item['orientacoes']].where((x) => x != null && '$x'.isNotEmpty);

        return Scaffold(
          appBar: AppBar(
            title: Text('${os['codigo'] ?? 'Serviço'}'),
            actions: const [IndicadorSync()],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              Row(children: [
                StatusChip(item['status'] as String?, statusItem),
                const SizedBox(width: 8),
                if (ag['prioridade'] != null) StatusChip(ag['prioridade'] as String?, prioridades),
                const Spacer(),
                Text(tiposAgendamento[ag['tipo']] ?? '', style: const TextStyle(color: Cores.neutro)),
              ]),
              if (os['garantia_status'] == 'confirmada')
                const _Faixa(
                  icone: Icons.verified_user_outlined,
                  texto: 'Retorno em garantia: sem cobrança.',
                  cor: Cores.alerta,
                ),
              if (item['status'] == 'nao_realizado')
                _Faixa(
                  icone: Icons.block,
                  texto: 'Não realizado: ${motivosNaoRealizado[item['resultado_motivo']] ?? item['resultado_motivo'] ?? ''}',
                  cor: Cores.erro,
                ),
              _Secao(titulo: 'Cliente e local', filhos: [
                Text('${cliente['nome'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text('${local['nome'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (endereco.isNotEmpty) Text(endereco),
                if ((local['instrucoes_acesso'] ?? '').toString().isNotEmpty)
                  Text('Acesso: ${local['instrucoes_acesso']}', style: const TextStyle(color: Cores.neutro)),
                if (contato != null)
                  Text('Contato: ${contato['nome']}${contato['telefone'] != null ? ' · ${contato['telefone']}' : ''}'),
              ]),
              _Secao(titulo: 'O que fazer', filhos: [
                if ((os['problema_relatado'] ?? '').toString().isNotEmpty) Text('${os['problema_relatado']}'),
                for (final o in orientacoes)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Orientação: $o', style: const TextStyle(fontStyle: FontStyle.italic)),
                  ),
                if (janela(ag['janela_inicio'], ag['janela_fim']).isNotEmpty)
                  Text('Janela: ${janela(ag['janela_inicio'], ag['janela_fim'])}',
                      style: const TextStyle(color: Cores.indigo500)),
                if (ag['duracao_estimada_min'] != null) Text('Duração estimada: ${ag['duracao_estimada_min']} min'),
              ]),
              _Secao(titulo: 'Equipamentos (${equipamentos.length})', filhos: [
                if (equipamentos.isEmpty)
                  const Text('Nenhum equipamento na OS.', style: TextStyle(color: Cores.neutro)),
                for (final e in equipamentos)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.ac_unit),
                    title: Text([e['codigo'], e['descricao']].where((x) => x != null).join(' · ')),
                    subtitle: Text([
                      banco.um('ambientes', e['ambiente_id'])?['nome'],
                      [e['marca'], e['modelo']].where((x) => x != null).join(' '),
                    ].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
                  ),
              ]),
              const SizedBox(height: 8),
              _Acoes(item: item, parte: parte),
            ],
          ),
        );
      },
    );
  }
}

/// Botões de andamento, conforme o status do serviço.
class _Acoes extends StatelessWidget {
  const _Acoes({required this.item, required this.parte});

  final Map<String, dynamic> item;
  final Map<String, dynamic> parte;

  Future<void> _mudar(String status, {String? motivo}) async {
    final estado = EstadoApp.instancia;
    final banco = estado.banco!;
    await estado.sync!.registrar(
      'item_status',
      {'parte_item_id': item['id'], 'status': status, if (motivo != null) 'motivo': motivo},
      aplicarLocal: () async {
        final agora = DateTime.now().toUtc().toIso8601String();
        await banco.alterar('partes_itens', item['id'], {
          'status': status,
          if (status == 'em_deslocamento' && item['iniciado_em'] == null) 'iniciado_em': agora,
          if (status == 'nao_realizado') ...{'resultado_motivo': motivo, 'concluido_em': agora},
        });
        if (status == 'em_deslocamento' && parte['status'] == 'publicada') {
          await banco.alterar('partes_diarias', parte['id'], {'status': 'em_andamento'});
        }
      },
    );
  }

  Future<void> _naoRealizado(BuildContext context) async {
    final motivo = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Por que não foi feito?', style: TextStyle(fontWeight: FontWeight.w800))),
          for (final m in motivosNaoRealizado.entries)
            ListTile(title: Text(m.value), onTap: () => Navigator.of(ctx).pop(m.key)),
        ]),
      ),
    );
    if (motivo != null) await _mudar('nao_realizado', motivo: motivo);
  }

  @override
  Widget build(BuildContext context) {
    final status = item['status'];
    final aberta = parte['status'] == 'publicada' || parte['status'] == 'em_andamento';
    if (!aberta) {
      return const Text('Parte encerrada: nada a fazer aqui.', style: TextStyle(color: Cores.neutro));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (status == 'programado')
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: () => _mudar('em_deslocamento'),
            icon: const Icon(Icons.directions_car_outlined),
            label: const Text('Estou a caminho'),
          ),
        ),
      if (status == 'em_deslocamento')
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            onPressed: () => _mudar('programado'),
            icon: const Icon(Icons.undo),
            label: const Text('Voltar para programado'),
          ),
        ),
      if (status == 'em_atendimento' || status == 'pausado')
        const Text('Atendimento em andamento. As telas do atendimento chegam no próximo passo.',
            style: TextStyle(color: Cores.neutro)),
      if (status == 'programado' || status == 'em_deslocamento') ...[
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: TextButton.icon(
            onPressed: () => _naoRealizado(context),
            icon: const Icon(Icons.block, color: Cores.erro),
            label: const Text('Não foi possível fazer', style: TextStyle(color: Cores.erro)),
          ),
        ),
      ],
    ]);
  }
}

class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.filhos});

  final String titulo;
  final List<Widget> filhos;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo.toUpperCase(),
                style: const TextStyle(fontSize: 12, letterSpacing: .6, fontWeight: FontWeight.w700, color: Cores.neutro)),
            const SizedBox(height: 6),
            ...filhos,
          ]),
        ),
      );
}

class _Faixa extends StatelessWidget {
  const _Faixa({required this.icone, required this.texto, required this.cor});

  final IconData icone;
  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cor.withValues(alpha: .4)),
        ),
        child: Row(children: [
          Icon(icone, color: cor),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: TextStyle(color: cor, fontWeight: FontWeight.w600))),
        ]),
      );
}
