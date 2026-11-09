import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/eqp_dados.dart';
import '../core/estado.dart';
import '../widgets/indicador_sync.dart';
import '../widgets/status_chip.dart';

/// Gestão de Equipamentos no app (guia 104): ler a etiqueta e ver os
/// equipamentos da empresa (funciona sem internet, com o que baixou).
class EqpInicioTela extends StatefulWidget {
  const EqpInicioTela({super.key});

  @override
  State<EqpInicioTela> createState() => _EqpInicioTelaState();
}

class _EqpInicioTelaState extends State<EqpInicioTela> {
  final _busca = TextEditingController();
  String? _status;

  static const _filtros = {
    null: 'Todos',
    'reservado': 'Reservados',
    'em_transito': 'Em trânsito',
    'em_uso': 'Em uso',
    'retornado': 'Aguardando conferência',
    'disponivel': 'Disponíveis',
  };

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _lerEtiqueta() async {
    final lido = await context.push<String>('/ler-codigo');
    if (lido == null || !mounted) return;
    final achado = EstadoApp.instancia.banco!.eqpPorEtiqueta(lido);
    final ficha = achado.ficha;
    if (ficha == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Etiqueta não encontrada nos equipamentos: $lido. Sincronize e tente de novo.')));
      return;
    }
    if (achado.componente != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${achado.componente!['codigo']} é componente do conjunto ${ficha['codigo']}.')));
    }
    await context.push('/equipamentos/${ficha['id']}');
  }

  @override
  Widget build(BuildContext context) {
    final banco = EstadoApp.instancia.banco!;
    return ListenableBuilder(
      listenable: banco,
      builder: (context, _) {
        final texto = _busca.text.trim().toLowerCase();
        final todos = banco.eqpFichas;
        final lista = todos.where((f) {
          if (_status != null && f['status'] != _status) return false;
          if (texto.isEmpty) return true;
          return [f['codigo'], f['descricao'], f['patrimonio'], f['marca'], f['modelo'], f['tipo'], f['com']]
              .any((x) => '${x ?? ''}'.toLowerCase().contains(texto));
        }).toList();
        final hoje = DateTime.now();
        final saemHoje = banco
            .todos('eqp_reservas')
            .where((r) => r['situacao'] == 'reservada' && !DateTime.parse('${r['inicio']}').isAfter(hoje))
            .length;
        return Scaffold(
          appBar: AppBar(title: const Text('Equipamentos'), actions: const [IndicadorSync()]),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'eqp-ler',
            onPressed: _lerEtiqueta,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Ler etiqueta'),
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                controller: _busca,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Código, patrimônio, descrição ou cliente',
                ),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final e in _filtros.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: _status == e.key,
                        onSelected: (_) => setState(() => _status = e.key),
                      ),
                    ),
                ],
              ),
            ),
            if (saemHoje > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('$saemHoje reserva(s) para sair até hoje.',
                    style: const TextStyle(color: Cores.info, fontWeight: FontWeight.w600)),
              ),
            Expanded(
              child: todos.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nenhum equipamento no aparelho ainda. Com internet, toque em sincronizar (ícone da nuvem).',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Cores.neutro),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                      itemCount: lista.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final f = lista[i];
                        final pendentes = banco.eqpNaFila(f['id']).length;
                        return Card(
                          child: ListTile(
                            onTap: () => context.push('/equipamentos/${f['id']}'),
                            title: Text('${f['codigo']} · ${f['descricao'] ?? ''}',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text([
                              f['local_atual'],
                              f['com'],
                              if (f['patrimonio'] != null) 'Pat. ${f['patrimonio']}',
                            ].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                StatusChip('${f['status']}', statusEqp),
                                if (pendentes > 0) ...[
                                  const SizedBox(height: 4),
                                  const Selo('Aguardando envio', Cores.alerta),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ]),
        );
      },
    );
  }
}
