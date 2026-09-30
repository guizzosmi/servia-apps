import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/status.dart';
import 'modelo.dart';

/// Motivo e observação de "não realizado". Devolve null se cancelou.
Future<({String motivo, String observacao})?> pedirNaoRealizado(BuildContext context, String titulo) {
  var motivo = 'cliente_ausente';
  final obs = TextEditingController();
  return showDialog<({String motivo, String observacao})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(titulo),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Opcoes(
              rotulo: 'Motivo',
              valor: motivo,
              opcoes: motivosNaoRealizado,
              aoMudar: (v) => setState(() => motivo = v),
            ),
            const SizedBox(height: 12),
            TextField(controller: obs, decoration: const InputDecoration(labelText: 'Observação (opcional)')),
            const SizedBox(height: 8),
            const Text('Falta de peça e aguardando orçamento deixam o serviço suspenso; '
                'os outros motivos devolvem para a fila.',
                style: TextStyle(fontSize: 12, color: Cores.neutro)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop((motivo: motivo, observacao: obs.text.trim())),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ),
  );
}

/// Escolhe quem da equipe faz o serviço. Lista vazia = a equipe toda.
Future<List<String>?> escolherDesignados(
  BuildContext context, {
  required List<Map<String, dynamic>> presentes,
  required List<String> atuais,
  required String Function(String?) nome,
}) {
  final sel = {...atuais};
  return showDialog<List<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Quem faz este serviço'),
        scrollable: true,
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Sem ninguém marcado, vale para a equipe toda.',
                style: TextStyle(fontSize: 12, color: Cores.neutro)),
            const SizedBox(height: 8),
            if (presentes.isEmpty) const Text('Ninguém na equipe agora.'),
            for (final c in presentes)
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: sel.contains(c['colaborador_id']),
                title: Text(nome(c['colaborador_id'] as String?)),
                subtitle: c['papel'] == 'lider' ? const Text('Líder') : null,
                onChanged: (v) => setState(() {
                  final id = c['colaborador_id'] as String;
                  if (v == true) {
                    sel.add(id);
                  } else {
                    sel.remove(id);
                  }
                }),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(sel.toList()), child: const Text('Salvar')),
        ],
      ),
    ),
  );
}

/// Pergunta simples com observação opcional (ex.: tirar da parte).
Future<String?> confirmarComObservacao(BuildContext context,
    {required String titulo, required String texto, required String botao}) {
  final obs = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(texto),
          const SizedBox(height: 12),
          TextField(controller: obs, decoration: const InputDecoration(labelText: 'Observação (opcional)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(obs.text.trim()), child: Text(botao)),
      ],
    ),
  );
}

/// Encerrar o dia: motivo de cada serviço não concluído + resumo.
/// Devolve {motivos: {item_id: motivo}, resumo_texto} ou null.
Future<Map<String, dynamic>?> pedirEncerramento(
  BuildContext context, {
  required ColunaQuadro coluna,
}) {
  final abertos = coluna.itens.where(itemAberto).toList();
  final motivos = {for (final i in abertos) i['id'] as String: 'tempo'};
  final resumo = TextEditingController();
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Encerrar o dia · ${coluna.nome}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (abertos.isEmpty)
                const Text('Todos os serviços foram concluídos ou já têm resultado.')
              else ...[
                Text('${abertos.length} serviço(s) não concluído(s) voltam para a fila '
                    '(ou ficam suspensos, se o motivo for peça ou orçamento):'),
                const SizedBox(height: 8),
                for (final i in abertos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          '${((i['agendamentos'] as Map?)?['ordens_servico'] as Map?)?['codigo'] ?? ''} · '
                          '${(((i['agendamentos'] as Map?)?['ordens_servico'] as Map?)?['clientes'] as Map?)?['nome'] ?? ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 210,
                        child: _Opcoes(
                          rotulo: 'Motivo',
                          valor: motivos[i['id']]!,
                          opcoes: motivosNaoRealizado,
                          aoMudar: (v) => setState(() => motivos[i['id'] as String] = v),
                        ),
                      ),
                    ]),
                  ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: resumo,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Resumo do dia (opcional)'),
              ),
              const SizedBox(height: 8),
              const Text('A composição é fechada no horário de agora.',
                  style: TextStyle(fontSize: 12, color: Cores.neutro)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop({'motivos': motivos, 'resumo_texto': resumo.text.trim()}),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    ),
  );
}

/// Escolhe uma equipe entre as colunas informadas.
Future<ColunaQuadro?> escolherEquipe(BuildContext context,
    {required String titulo, required List<ColunaQuadro> colunas}) {
  return showDialog<ColunaQuadro>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(titulo),
      children: [
        if (colunas.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nenhuma outra equipe disponível neste dia.'),
          ),
        for (final c in colunas)
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(c),
            child: Text(c.parte == null ? '${c.nome} (abre a parte)' : c.nome),
          ),
      ],
    ),
  );
}

/// Pessoa para incluir na equipe: quem está livre entra; quem está em
/// outra equipe sai de lá e entra aqui.
class EscolhaPessoa {
  const EscolhaPessoa({required this.colaboradorId, this.deParteId});
  final String colaboradorId;
  final String? deParteId;
}

Future<EscolhaPessoa?> escolherPessoa(
  BuildContext context, {
  required String equipe,
  required List<Map<String, dynamic>> colaboradores,
  required Map<String, ({String parteId, String equipe})> alocados,
}) {
  final busca = TextEditingController();
  return showDialog<EscolhaPessoa>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final b = busca.text.trim().toLowerCase();
      final lista = colaboradores
          .where((c) => b.isEmpty || '${c['nome']}'.toLowerCase().contains(b))
          .toList();
      return AlertDialog(
        title: Text('Incluir pessoa · $equipe'),
        content: SizedBox(
          width: 420,
          height: 420,
          child: Column(children: [
            TextField(
              controller: busca,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Nome', prefixIcon: Icon(Icons.search, size: 20)),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(children: [
                for (final c in lista)
                  Builder(builder: (_) {
                    final onde = alocados[c['id']];
                    return ListTile(
                      dense: true,
                      title: Text('${c['nome']}'),
                      subtitle: Text(onde == null ? 'Livre' : 'Hoje na ${onde.equipe} (sai de lá e vem para cá)',
                          style: TextStyle(color: onde == null ? Cores.sucesso : Cores.alerta)),
                      onTap: () => Navigator.of(ctx)
                          .pop(EscolhaPessoa(colaboradorId: c['id'] as String, deParteId: onde?.parteId)),
                    );
                  }),
              ]),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar'))],
      );
    }),
  );
}

/// Lista suspensa simples (valor sempre preenchido).
class _Opcoes extends StatelessWidget {
  const _Opcoes({required this.rotulo, required this.valor, required this.opcoes, required this.aoMudar});

  final String rotulo;
  final String valor;
  final Map<String, String> opcoes;
  final ValueChanged<String> aoMudar;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: rotulo, isDense: true),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: valor,
          isDense: true,
          isExpanded: true,
          items: [
            for (final e in opcoes.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            if (v != null) aoMudar(v);
          },
        ),
      ),
    );
  }
}
