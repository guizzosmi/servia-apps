import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../cadastros/definicoes.dart';
import '../servicos/status.dart';
import 'modelo.dart';

/// Tudo o que o log precisa para montar frases legíveis.
class ContextoLog {
  const ContextoLog({
    required this.equipePorParte,
    required this.partePorItem,
    required this.osPorItem,
    required this.equipes,
    required this.nomeColaborador,
  });

  /// parte_id -> equipe_id
  final Map<String, String> equipePorParte;

  /// parte_item_id -> parte_id (inclusive removidos)
  final Map<String, String> partePorItem;

  /// parte_item_id -> código da OS
  final Map<String, String> osPorItem;

  /// equipe_id -> equipe (nome, cor)
  final Map<String, Map<String, dynamic>> equipes;

  final String Function(String?) nomeColaborador;

  String? equipeDoEvento(Map e) {
    final id = e['entidade_id'] as String?;
    if (id == null) return null;
    if (e['entidade'] == 'parte') return equipePorParte[id];
    final parte = partePorItem[id];
    return parte == null ? null : equipePorParte[parte];
  }

  String _equipeDaParte(Object? parteId) =>
      (equipes[equipePorParte['${parteId ?? ''}']]?['nome'] ?? 'outra equipe') as String;

  /// Frase do evento: "Programou OS-000012", "Rafael entrou às 13:00"...
  String frase(Map e) {
    final d = e['dados'] as Map? ?? const {};
    final os = osPorItem[e['entidade_id']] ?? d['os'] ?? 'serviço';
    final pessoa = nomeColaborador(d['colaborador_id'] as String?);
    return switch (e['acao']) {
      'abrir_dia' => 'Parte aberta',
      'programar' => d['papel'] == 'apoio' ? 'Apoio em $os' : 'Programou $os',
      'encaixar' => d['papel'] == 'apoio' ? 'Apoio (encaixe) em $os' : 'Encaixou $os',
      'remover' => 'Tirou $os da parte',
      'reordenar' => 'Mudou a ordem dos serviços',
      'designar' => ((d['designados'] as List?) ?? const []).isEmpty
          ? '$os: equipe toda'
          : '$os: só ${((d['designados'] as List).cast<String>()).map(nomeColaborador).join(', ')}',
      'mover' => 'Moveu $os da ${_equipeDaParte(d['de_parte_id'])} para a ${_equipeDaParte(d['para_parte_id'])}',
      'publicar' => 'Publicou (${d['itens'] ?? 0} serviço(s))',
      'composicao_entrar' => d['de_parte_id'] != null
          ? '$pessoa veio da ${_equipeDaParte(d['de_parte_id'])} às ${horaDe(d['em'])}'
          : '$pessoa entrou na equipe${horaDe(d['em']) == '00:00' ? '' : ' às ${horaDe(d['em'])}'}',
      'composicao_sair' => '$pessoa saiu da equipe${horaDe(d['em']) == '00:00' ? '' : ' às ${horaDe(d['em'])}'}',
      'lider' => '$pessoa agora é o líder',
      'status' => '$os: ${statusItem[d['de']]?.texto ?? d['de']} → ${statusItem[d['para']]?.texto ?? d['para']}'
          '${d['motivo'] != null ? ' (${motivosNaoRealizado[d['motivo']] ?? d['motivo']})' : ''}',
      'encerrar' => 'Encerrou o dia',
      'reabrir' => 'Reabriu a parte',
      _ => '${e['acao']}',
    };
  }
}

/// Painel lateral com os eventos do dia, filtrável por equipe.
class LogDoDia extends StatefulWidget {
  const LogDoDia({super.key, required this.eventos, required this.contexto, required this.aoFechar});

  final List<Map<String, dynamic>> eventos;
  final ContextoLog contexto;
  final VoidCallback aoFechar;

  @override
  State<LogDoDia> createState() => _LogDoDiaState();
}

class _LogDoDiaState extends State<LogDoDia> {
  String? _equipe;

  @override
  Widget build(BuildContext context) {
    final equipes = widget.contexto.equipes.values.toList()
      ..sort((a, b) => '${a['nome']}'.compareTo('${b['nome']}'));
    final filtro = equipes.any((e) => e['id'] == _equipe) ? _equipe : null;
    final lista = widget.eventos
        .where((e) => filtro == null || widget.contexto.equipeDoEvento(e) == filtro)
        .toList();

    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Cores.linha)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
          child: Row(children: [
            const Expanded(child: Text('Log do dia', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            IconButton(tooltip: 'Fechar', onPressed: widget.aoFechar, icon: const Icon(Icons.close, size: 20)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Equipe', isDense: true),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: filtro,
                isDense: true,
                isExpanded: true,
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                  for (final e in equipes)
                    DropdownMenuItem<String?>(value: e['id'] as String, child: Text('${e['nome']}')),
                ],
                onChanged: (v) => setState(() => _equipe = v),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(
          child: lista.isEmpty
              ? const Center(child: Text('Nada registrado ainda.', style: TextStyle(color: Cores.neutro)))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: lista.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (_, i) {
                    final e = lista[i];
                    final equipe = widget.contexto.equipes[widget.contexto.equipeDoEvento(e)];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(
                          width: 42,
                          child: Text(horaDe(e['criado_em']),
                              style: const TextStyle(fontSize: 12, color: Cores.neutro, fontWeight: FontWeight.w600)),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4, right: 8),
                          child: CircleAvatar(radius: 4, backgroundColor: corDeTexto(equipe?['cor'])),
                        ),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(widget.contexto.frase(e), style: const TextStyle(fontSize: 13)),
                            Text(
                              [equipe?['nome'], e['ator_nome']].where((x) => x != null).join(' · '),
                              style: const TextStyle(fontSize: 11, color: Cores.neutro),
                            ),
                          ]),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
