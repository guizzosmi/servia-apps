import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/eqp_dados.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import '../widgets/indicador_sync.dart';
import '../widgets/status_chip.dart';

/// Ficha resumida do equipamento no app (guia 104): onde está, com quem, o
/// conjunto, as reservas e as ações que o status permite.
class EqpFichaTela extends StatelessWidget {
  const EqpFichaTela({super.key, required this.equipamentoId});

  final String equipamentoId;

  static const _icones = {
    'saida': Icons.local_shipping_outlined,
    'chegada': Icons.where_to_vote_outlined,
    'transferencia': Icons.swap_horiz,
    'recolher': Icons.assignment_return_outlined,
    'retorno': Icons.warehouse_outlined,
    'mover': Icons.move_down,
    'iniciar_manutencao': Icons.build_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final banco = EstadoApp.instancia.banco!;
    return ListenableBuilder(
      listenable: banco,
      builder: (context, _) {
        final f = banco.eqpFicha(equipamentoId);
        if (f == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Equipamento')),
            body: const Center(child: Text('Equipamento não encontrado no aparelho.')),
          );
        }
        final reservas = banco.eqpReservas(f['id']);
        final ativa = reservas.where((r) => r['situacao'] == 'ativa').firstOrNull;
        final reservadas = reservas.where((r) => r['situacao'] == 'reservada').toList();
        final eventos = eventosPermitidos(f, temReserva: reservadas.isNotEmpty, temAtiva: ativa != null);
        final conjunto = ((f['conjunto'] as List?) ?? const []).cast<Map>();
        final naFila = banco.eqpNaFila(f['id']);
        return Scaffold(
          appBar: AppBar(title: Text('${f['codigo']}'), actions: const [IndicadorSync()]),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${f['descricao'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    StatusChip('${f['status']}', statusEqp),
                    if (f['destino_atual'] != null) Selo(destinosEqp[f['destino_atual']] ?? '', Cores.andamento),
                  ]),
                  const SizedBox(height: 10),
                  _Linha('Onde está', '${f['local_atual'] ?? '—'}'),
                  if (f['com'] != null) _Linha('Com', '${f['com']}'),
                  if (f['patrimonio'] != null) _Linha('Patrimônio', '${f['patrimonio']}'),
                  if ([f['tipo'], f['marca'], f['modelo']].any((x) => x != null))
                    _Linha('Tipo / modelo',
                        [f['tipo'], f['marca'], f['modelo']].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
                  if (f['medidor'] != null && f['medidor'] != 'nenhum')
                    _Linha('Última leitura', leituraEqp(f['leitura_atual'], f['medidor'])),
                  _Linha('Desde', dataHoraBr(f['status_desde'])),
                ]),
              ),
            ),
            if (naFila.isNotEmpty)
              Card(
                color: Cores.indigo100,
                child: Column(children: [
                  for (final o in naFila)
                    ListTile(
                      dense: true,
                      leading: Icon(o.situacao == 'recusada' ? Icons.error_outline : Icons.cloud_upload_outlined,
                          color: o.situacao == 'recusada' ? Cores.erro : Cores.alerta),
                      title: Text('${o.dados['rotulo'] ?? eventosEqp[o.dados['evento']] ?? 'Registro'}'),
                      subtitle: Text(o.situacao == 'recusada'
                          ? 'Recusado: ${o.erro ?? ''} (veja Sincronização)'
                          : 'Aguardando envio · ${dataHoraBr(o.em)}'),
                      onTap: () => context.push('/sincronizacao'),
                    ),
                ]),
              ),
            const SizedBox(height: 4),
            if (eventos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Nada a registrar pelo app neste status (o escritório faz pelo painel).',
                    style: TextStyle(color: Cores.neutro)),
              ),
            for (final ev in eventos)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  height: 52,
                  child: ev == eventos.first
                      ? FilledButton.icon(
                          onPressed: () => context.push('/equipamentos/${f['id']}/registrar/$ev'),
                          icon: Icon(_icones[ev]),
                          label: Text(eventosEqp[ev] ?? ev),
                        )
                      : OutlinedButton.icon(
                          onPressed: () => context.push('/equipamentos/${f['id']}/registrar/$ev'),
                          icon: Icon(_icones[ev]),
                          label: Text(eventosEqp[ev] ?? ev),
                        ),
                ),
              ),
            if (ativa != null || reservadas.isNotEmpty) ...[
              const _Titulo('Reservas e uso'),
              for (final r in [if (ativa != null) ativa, ...reservadas])
                Card(
                  child: ListTile(
                    title: Text('${r['com'] ?? destinosEqp[r['destino']] ?? ''}'),
                    subtitle: Text([
                      r['situacao'] == 'ativa' ? 'Em andamento' : 'Reservada',
                      if (r['locacao'] != null) '${r['locacao']}',
                      '${dataBr(r['inicio'])}${r['fim_previsto'] != null ? ' a ${dataBr(r['fim_previsto'])}' : ''}',
                      [r['local'], r['endereco']].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                    ].where((x) => x.isNotEmpty).join('\n')),
                    isThreeLine: true,
                  ),
                ),
            ],
            if (conjunto.isNotEmpty) ...[
              const _Titulo('Conjunto'),
              Card(
                child: Column(children: [
                  for (final c in conjunto)
                    ListTile(
                      dense: true,
                      leading: Icon(c['tipo'] == 'serializado' ? Icons.qr_code_2 : Icons.inventory_2_outlined),
                      title: Text([c['codigo'], c['descricao']].where((x) => x != null).join(' · ')),
                      subtitle: Text([
                        'Quantidade ${numeroBr(c['quantidade'])}',
                        if (c['valor_reposicao'] != null) 'reposição ${dinheiro(c['valor_reposicao'])}',
                      ].join(' · ')),
                    ),
                ]),
              ),
            ],
          ]),
        );
      },
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(texto.toUpperCase(),
            style: const TextStyle(fontSize: 12, letterSpacing: .6, fontWeight: FontWeight.w800, color: Cores.indigo700)),
      );
}

class _Linha extends StatelessWidget {
  const _Linha(this.rotulo, this.valor);
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(rotulo, style: const TextStyle(color: Cores.neutro))),
          Expanded(child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}
