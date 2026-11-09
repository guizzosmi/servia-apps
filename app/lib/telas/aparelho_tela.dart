import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_checklist.dart';
import '../core/acoes_etiqueta.dart';
import '../core/acoes_os.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import '../widgets/busca_aparelhos.dart';
import '../widgets/indicador_sync.dart';
import '../widgets/ler_etiqueta.dart';

/// Guia 108: a ficha rápida do aparelho da etiqueta lida fora da OS
/// (código, descrição, ambiente, local, cliente, último serviço e próxima
/// preventiva que o celular conhece) e as OS em aberto com ele: a do meu dia
/// abre no checklist do aparelho; a de outro dia, da fila ou de outra equipe
/// tem o "Atender agora". Sem OS: "Abrir OS para este aparelho".
class AparelhoTela extends StatefulWidget {
  const AparelhoTela({super.key, required this.equipamentoId, this.lido});

  final String equipamentoId;

  /// O texto da etiqueta lida (fica registrado na identificação do aparelho).
  final String? lido;

  @override
  State<AparelhoTela> createState() => _AparelhoTelaState();
}

class _AparelhoTelaState extends State<AparelhoTela> {
  /// Com internet: as OS do aparelho com outras equipes (null = ainda não veio ou sem internet).
  List<OsDoAparelho>? _remotas;
  bool _buscando = true;

  String get equipamentoId => widget.equipamentoId;
  String? get lido => widget.lido;

  @override
  void initState() {
    super.initState();
    _buscarOutrasEquipes();
  }

  Future<void> _buscarOutrasEquipes() async {
    final r = await AcoesEtiqueta.osDeOutrasEquipes(equipamentoId);
    if (!mounted) return;
    setState(() {
      _remotas = r;
      _buscando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final banco = EstadoApp.instancia.banco!;
    return ListenableBuilder(
      listenable: banco,
      builder: (context, _) {
        final e = banco.um('equipamentos', equipamentoId);
        if (e == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Aparelho')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Este aparelho não está no celular. Sincronize e tente de novo.',
                    textAlign: TextAlign.center, style: TextStyle(color: Cores.neutro)),
              ),
            ),
          );
        }
        final ambiente = nomeDoAmbiente(ambienteDoAparelho(e['ambiente_id']));
        final local = banco.um('locais', e['local_id']) ?? const {};
        final cliente = banco.um('clientes', e['cliente_id']) ?? const {};
        final oss = AcoesEtiqueta.juntar(AcoesEtiqueta.osAbertas(e['id']), _remotas);
        final semInternet = !_buscando && _remotas == null;
        final ultimo = AcoesEtiqueta.ultimoServico(e['id']);
        final proxima = AcoesEtiqueta.proximaPreventiva(e['id']);
        final detalhe = detalheAparelho(e, comAmbiente: false);

        return Scaffold(
          appBar: AppBar(title: Text('${e['codigo'] ?? 'Aparelho'}'), actions: const [IndicadorSync()]),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              _Secao(titulo: 'Aparelho', filhos: [
                Text(rotuloAparelho(e), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                if (detalhe.isNotEmpty) Text(detalhe),
                if ('${e['numero_serie'] ?? ''}'.trim().isNotEmpty) Text('Nº de série: ${e['numero_serie']}'),
                const SizedBox(height: 6),
                _Linha(
                  icone: Icons.meeting_room_outlined,
                  texto: ambiente.isEmpty ? 'Ambiente não informado' : ambiente,
                  cor: ambiente.isEmpty ? Cores.neutro : null,
                ),
                _Linha(
                  icone: Icons.place_outlined,
                  texto: [local['nome'], local['cidade']].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                ),
                _Linha(icone: Icons.business_outlined, texto: '${cliente['nome'] ?? ''}'),
                _Linha(
                  icone: Icons.history,
                  texto: ultimo == null
                      ? 'Último serviço: nenhum no celular'
                      : 'Último serviço: ${dataBr(ultimo.$1)} · ${ultimo.$2}',
                  cor: ultimo == null ? Cores.neutro : null,
                ),
                if (proxima != null)
                  _Linha(icone: Icons.event_repeat_outlined, texto: 'Próxima preventiva: até ${dataBr(proxima)}'),
              ]),
              _Secao(
                titulo: oss.length > 1 ? '${oss.length} OS em aberto: escolha' : 'OS em aberto com este aparelho',
                filhos: [
                  if (oss.isEmpty)
                    Text(semInternet
                        ? 'Nenhuma OS em aberto com este aparelho no celular.'
                        : 'Nenhuma OS em aberto com este aparelho.'),
                  for (final o in oss) _CartaoOs(os: o, aparelho: e, lido: lido),
                  // Guia 108: as OS com outras equipes só vêm com internet.
                  if (_buscando)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Row(children: [
                        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('Procurando OS com outras equipes...',
                              style: TextStyle(fontSize: 12, color: Cores.neutro)),
                        ),
                      ]),
                    )
                  else if (semInternet)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Sem internet: pode haver OS com outras equipes.',
                          style: TextStyle(fontSize: 12, color: Cores.neutro)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (AcoesOs.possoAbrir)
                SizedBox(
                  height: 52,
                  child: oss.isEmpty
                      ? FilledButton.icon(
                          onPressed: () => _abrirOs(context, e),
                          icon: const Icon(Icons.add),
                          label: const Text('Abrir OS para este aparelho'),
                        )
                      : OutlinedButton.icon(
                          onPressed: () => _abrirOs(context, e),
                          icon: const Icon(Icons.add),
                          label: const Text('Abrir outra OS para este aparelho'),
                        ),
                )
              else if (oss.isEmpty)
                const Text('Para abrir OS pelo app, peça a liberação ao escritório.',
                    textAlign: TextAlign.center, style: TextStyle(color: Cores.neutro)),
            ],
          ),
        );
      },
    );
  }

  /// A Nova OS já com o cliente, o local e este aparelho escolhidos.
  void _abrirOs(BuildContext context, Map<String, dynamic> e) => context.push(Uri(path: '/nova-os', queryParameters: {
        'cliente': '${e['cliente_id']}',
        'local': '${e['local_id']}',
        'equipamento': '${e['id']}',
      }).toString());
}

/// Uma OS em aberto com o aparelho: tipo, código, data, onde está e o botão.
class _CartaoOs extends StatelessWidget {
  const _CartaoOs({required this.os, required this.aparelho, this.lido});

  final OsDoAparelho os;
  final Map<String, dynamic> aparelho;
  final String? lido;

  @override
  Widget build(BuildContext context) {
    final o = os.os;
    final item = os.item;
    final impedimento = os.impedimento;
    final temChecklist = AcoesChecklist.porAparelho(o['id'])['${aparelho['id']}']?.isNotEmpty ?? false;
    final situacao = statusItem[item?['status']]?.texto ?? '${item?['status'] ?? ''}';
    final onde = switch (os.onde) {
      'meu_dia' => 'Hoje, na sua parte · $situacao',
      'outra_parte' => 'Na agenda de outra equipe ou de outro dia',
      // Guia 108: com outra equipe (consulta com internet): "Com a Equipe Sul, dia 09/11 (líder Ana)".
      _ when os.remota && item != null => [
          textoComOutraEquipe({...item, 'equipe': os.equipe, 'lider': os.lider}),
          if (item['status'] != 'programado') situacao,
        ].join(' · '),
      _ => os.comoOsAberta.ondeEsta,
    };
    final problema = '${o['problema_relatado'] ?? ''}'.trim();
    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: os.noMeuDia ? Cores.indigo100 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text([codigoOs(o), tiposOs[o['tipo']] ?? ''].where((x) => x.isNotEmpty).join(' · '),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            if (os.data.isNotEmpty) Text(dataBr(os.data), style: const TextStyle(color: Cores.neutro)),
          ]),
          if (problema.isNotEmpty) Text(problema, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(onde, style: TextStyle(color: os.noMeuDia ? Cores.andamento : Cores.neutro, fontWeight: FontWeight.w600)),
          if (temChecklist) const Text('Checklist do plano neste aparelho', style: TextStyle(fontSize: 12)),
          if (impedimento != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(impedimento, style: const TextStyle(color: Cores.erro, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: impedimento != null ? null : () => atenderOsDoAparelho(context, os, aparelho, lido: lido),
              icon: Icon(os.noMeuDia ? Icons.assignment_outlined : Icons.play_arrow),
              label: Text(os.noMeuDia
                  ? (temChecklist ? 'Abrir o checklist deste aparelho' : 'Abrir o atendimento')
                  : os.remota && item != null
                      ? 'Trazer para mim'
                      : 'Atender agora'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.icone, required this.texto, this.cor});

  final IconData icone;
  final String texto;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    if (texto.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icone, size: 18, color: Cores.neutro),
        const SizedBox(width: 8),
        Expanded(child: Text(texto, style: TextStyle(color: cor))),
      ]),
    );
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(titulo.toUpperCase(),
                style: const TextStyle(fontSize: 12, letterSpacing: .6, fontWeight: FontWeight.w700, color: Cores.neutro)),
            const SizedBox(height: 6),
            ...filhos,
          ]),
        ),
      );
}
