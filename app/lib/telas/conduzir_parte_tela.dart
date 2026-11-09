import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_lider.dart';
import '../core/acoes_reabrir.dart';
import '../core/banco_local.dart';
import '../core/consultas.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import '../widgets/indicador_sync.dart';
import '../widgets/reabrir_os.dart';
import '../widgets/status_chip.dart';

/// O líder conduz a parte (guia 28): a equipe do dia (tirar, incluir,
/// emprestar), a ordem dos serviços (arrastar), quem faz cada um e o
/// pedido de replanejamento ao escritório.
class ConduzirParteTela extends StatefulWidget {
  const ConduzirParteTela({super.key, required this.parteId});

  final String parteId;

  @override
  State<ConduzirParteTela> createState() => _ConduzirParteTelaState();
}

class _ConduzirParteTelaState extends State<ConduzirParteTela> {
  /// Ordem que o líder acabou de arrastar, até o banco do celular gravar
  /// (assim o cartão não volta para o lugar antigo por um instante).
  List<String>? _ordem;

  List<Map<String, dynamic>> _naOrdem(List<Map<String, dynamic>> itens) {
    final ordem = _ordem;
    if (ordem == null) return itens;
    final ids = [for (final i in itens) '${i['id']}'];
    if (ids.length != ordem.length || !ids.every(ordem.contains)) return itens;
    return [...itens]..sort((a, b) => ordem.indexOf('${a['id']}').compareTo(ordem.indexOf('${b['id']}')));
  }

  Future<void> _reordenar(Map<String, dynamic> parte, List<Map<String, dynamic>> itens, int de, int para) async {
    final ids = [for (final i in itens) '${i['id']}'];
    final movido = ids.removeAt(de);
    ids.insert(para, movido);   // onReorderItem já desconta o item tirado
    setState(() => _ordem = ids);
    try {
      await AcoesLider.reordenar(parte, ids);
    } finally {
      if (mounted) setState(() => _ordem = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final banco = EstadoApp.instancia.banco!;
    return ListenableBuilder(
      listenable: banco,
      builder: (context, _) {
        final parte = banco.um('partes_diarias', widget.parteId);
        final titulo = AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Conduzir a equipe', style: TextStyle(fontWeight: FontWeight.w800)),
            if (parte != null)
              Text('${banco.nomeEquipe(parte['equipe_id'])} · ${dataComDia('${parte['data']}')}',
                  style: const TextStyle(fontSize: 13, color: Cores.neutro)),
          ]),
          actions: const [IndicadorSync()],
        );
        if (parte == null || !AcoesLider.podeConduzir(parte)) {
          final texto = parte == null
              ? 'Esta parte não está mais no aparelho.'
              : parte['status'] == 'encerrada'
                  ? 'O dia desta equipe já foi encerrado.'
                  : 'Só o líder da equipe conduz a parte.';
          return Scaffold(
            appBar: titulo,
            body: Center(child: Text(texto, style: const TextStyle(color: Cores.neutro))),
          );
        }
        final itens = _naOrdem(banco.itensDaParte(widget.parteId));
        return Scaffold(
          appBar: titulo,
          // Uma rolagem só: arrastando um serviço para baixo, a tela rola junto.
          body: CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              sliver: SliverToBoxAdapter(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _EquipeDoDia(banco: banco, parte: parte),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 16, 4, 0),
                    child: Text('Serviços', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text('Arraste pela alça (à direita) para mudar a ordem. Toque para escolher quem faz ou '
                        'pedir replanejamento ao escritório.', style: TextStyle(color: Cores.neutro)),
                  ),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverReorderableList(
                itemCount: itens.length,
                onReorderItem: (de, para) => _reordenar(parte, itens, de, para),
                itemBuilder: (context, i) => _CartaoItem(
                  key: ValueKey('item-${itens[i]['id']}'),
                  banco: banco,
                  parte: parte,
                  item: itens[i],
                  posicao: i,
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ----------------------------------------------------------------------
// Equipe do dia
// ----------------------------------------------------------------------

class _EquipeDoDia extends StatelessWidget {
  const _EquipeDoDia({required this.banco, required this.parte});

  final BancoLocal banco;
  final Map<String, dynamic> parte;

  Future<void> _incluir(BuildContext context) async {
    final livres = AcoesLider.livresParaIncluir(parte);
    final escolhido = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Quem entra na equipe hoje?', style: TextStyle(fontWeight: FontWeight.w800))),
          if (livres.isEmpty)
            const ListTile(
              title: Text('Ninguém sem equipe neste dia. Para trazer alguém de outra equipe, peça ao escritório '
                  '(ou ao líder dela, que empresta).'),
            ),
          for (final c in livres)
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: Text('${c['nome']}'),
              subtitle: c['funcao'] == null ? null : Text('${c['funcao']}'),
              onTap: () => Navigator.of(ctx).pop('${c['id']}'),
            ),
        ]),
      ),
    );
    if (escolhido != null) await AcoesLider.incluir(parte, escolhido);
  }

  Future<void> _mexer(BuildContext context, String colaboradorId) async {
    final nome = banco.nomeColaborador(colaboradorId);
    final destinos = AcoesLider.destinosParaEmprestar(parte);
    final acao = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(nome, style: const TextStyle(fontWeight: FontWeight.w800))),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Tirar do dia'),
            subtitle: const Text('Foi embora, faltou... Sai do serviço em que estiver.'),
            onTap: () => Navigator.of(ctx).pop('sair'),
          ),
          for (final d in destinos)
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text('Emprestar para a ${banco.nomeEquipe(d['equipe_id'])}'),
              onTap: () => Navigator.of(ctx).pop('emprestar:${d['id']}'),
            ),
          if (destinos.isEmpty)
            const ListTile(
              enabled: false,
              leading: Icon(Icons.swap_horiz),
              title: Text('Nenhuma outra equipe com parte neste dia para emprestar'),
            ),
        ]),
      ),
    );
    if (acao == null || !context.mounted) return;
    final destino = acao.startsWith('emprestar:') ? acao.substring('emprestar:'.length) : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(destino == null ? 'Tirar $nome do dia?' : 'Emprestar $nome?'),
        content: Text(destino == null
            ? '$nome sai da equipe agora (e do serviço em que estiver).'
            : '$nome sai daqui agora e entra na '
                '${banco.nomeEquipe(banco.um('equipes_do_dia', destino)?['equipe_id'])}.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok == true) await AcoesLider.tirar(parte, colaboradorId, destinoParteId: destino);
  }

  @override
  Widget build(BuildContext context) {
    final presentes = banco.presentes('${parte['id']}');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Equipe do dia', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final c in presentes)
              c['colaborador_id'] == parte['lider_colaborador_id']
                  ? Chip(
                      avatar: const Icon(Icons.star, size: 16, color: Cores.indigo500),
                      label: Text(banco.nomeColaborador(c['colaborador_id'])),
                    )
                  : ActionChip(
                      avatar: const Icon(Icons.more_horiz, size: 16),
                      label: Text(banco.nomeColaborador(c['colaborador_id'])),
                      onPressed: () => _mexer(context, '${c['colaborador_id']}'),
                    ),
            ActionChip(
              avatar: const Icon(Icons.person_add_alt, size: 16),
              label: const Text('Incluir pessoa'),
              onPressed: () => _incluir(context),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Um serviço: ordem, quem faz, pedido ao escritório
// ----------------------------------------------------------------------

class _CartaoItem extends StatelessWidget {
  const _CartaoItem({
    super.key,
    required this.banco,
    required this.parte,
    required this.item,
    required this.posicao,
  });

  final BancoLocal banco;
  final Map<String, dynamic> parte;
  final Map<String, dynamic> item;
  final int posicao;

  bool get _encerrado => item['status'] == 'concluido' || item['status'] == 'nao_realizado';

  Future<void> _designar(BuildContext context) async {
    final presentes = [for (final c in banco.presentes('${parte['id']}')) '${c['colaborador_id']}'];
    final marcados = {...((item['designados'] as List?) ?? const []).cast<String>()}..retainAll(presentes);
    final r = await showModalBottomSheet<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            const ListTile(
              title: Text('Quem faz este serviço?', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('Ninguém marcado = a equipe toda.'),
            ),
            for (final c in presentes)
              CheckboxListTile(
                value: marcados.contains(c),
                title: Text(banco.nomeColaborador(c)),
                onChanged: (v) => setState(() => v == true ? marcados.add(c) : marcados.remove(c)),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: () => Navigator.of(ctx).pop(marcados), child: const Text('Salvar')),
              ),
            ),
          ]),
        ),
      ),
    );
    if (r != null) await AcoesLider.designar(item, r.toList());
  }

  Future<void> _pedir(BuildContext context) async {
    final r = await showModalBottomSheet<_Pedido>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _FolhaPedido(dataDoServico: '${parte['data']}'),
    );
    if (r == null) return;
    await AcoesLider.pedirReplanejamento(item, motivo: r.motivo, dataSugerida: r.data, observacao: r.observacao);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Pedido enviado ao escritório. O serviço continua na parte até a resposta.')));
  }

  Future<void> _opcoes(BuildContext context) async {
    final acao = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('Quem faz'),
            onTap: () => Navigator.of(ctx).pop('designar'),
          ),
          if (AcoesLider.podePedir(item))
            ListTile(
              leading: const Icon(Icons.event_repeat_outlined),
              title: const Text('Pedir replanejamento'),
              subtitle: const Text('Outro dia ou outra equipe: o escritório decide.'),
              onTap: () => Navigator.of(ctx).pop('pedir'),
            ),
        ]),
      ),
    );
    if (acao == null || !context.mounted) return;
    switch (acao) {
      case 'designar':
        await _designar(context);
      case 'pedir':
        await _pedir(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final os = banco.osDo(item) ?? const {};
    final cliente = banco.um('clientes', os['cliente_id']);
    final designados = ((item['designados'] as List?) ?? const []).cast<String>();
    final pedido = AcoesLider.pedidoDo(item['id']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: _encerrado ? Cores.fundo : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // Guia 109: no serviço concluído, o líder (ou o gestor) pode reabrir a OS.
        onTap: _encerrado
            ? (AcoesReabrir.podeReabrir(item) ? () => reabrirOsDoServico(context, item) : null)
            : () => _opcoes(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: Cores.indigo100,
              child: Text('${posicao + 1}', style: const TextStyle(fontWeight: FontWeight.w800, color: Cores.indigo700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text('${codigoOs(os)} · ${cliente?['nome'] ?? ''}',
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 6),
                  StatusChip(item['status'] as String?, statusItem),
                ]),
                Text(
                  designados.isEmpty ? 'Quem faz: a equipe' : 'Quem faz: ${designados.map(banco.nomeColaborador).join(', ')}',
                  style: const TextStyle(color: Cores.neutro),
                ),
                if (pedido != null) _TextoPedido(pedido: pedido),
              ]),
            ),
            ReorderableDragStartListener(
              index: posicao,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle, color: Cores.neutro),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TextoPedido extends StatelessWidget {
  const _TextoPedido({required this.pedido});

  final Map<String, dynamic> pedido;

  @override
  Widget build(BuildContext context) {
    final motivo = motivosReplanejamento[pedido['motivo']] ?? '${pedido['motivo']}';
    final resposta = '${pedido['resposta'] ?? ''}'.trim();
    final (texto, cor) = switch (pedido['status']) {
      'aceito' => ('Replanejamento aceito pelo escritório', Cores.sucesso),
      'recusado' => ('Replanejamento recusado${resposta.isEmpty ? '' : ': $resposta'}', Cores.erro),
      _ => ('Pedido ao escritório: $motivo (aguardando)', Cores.alerta),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(texto, style: TextStyle(color: cor, fontWeight: FontWeight.w600)),
    );
  }
}

// ----------------------------------------------------------------------
// Folha do pedido de replanejamento
// ----------------------------------------------------------------------

class _Pedido {
  const _Pedido(this.motivo, this.data, this.observacao);

  final String motivo;
  final String? data;
  final String observacao;
}

class _FolhaPedido extends StatefulWidget {
  const _FolhaPedido({required this.dataDoServico});

  final String dataDoServico;

  @override
  State<_FolhaPedido> createState() => _FolhaPedidoState();
}

class _FolhaPedidoState extends State<_FolhaPedido> {
  String? _motivo;
  String? _data;
  final _obs = TextEditingController();

  @override
  void dispose() {
    _obs.dispose();
    super.dispose();
  }

  Future<void> _escolherData() async {
    final base = DateTime.tryParse(widget.dataDoServico) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: base.add(const Duration(days: 1)),
      firstDate: base,
      lastDate: base.add(const Duration(days: 120)),
    );
    if (d != null) setState(() => _data = dataIso(d));
  }

  @override
  Widget build(BuildContext context) {
    final precisaTexto = _motivo == 'outro' && _obs.text.trim().isEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Pedir replanejamento', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const Text('O escritório decide: se aceitar, o serviço sai da parte e volta para a fila.',
                style: TextStyle(color: Cores.neutro)),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final m in motivosReplanejamento.entries)
                ChoiceChip(
                  label: Text(m.value),
                  selected: _motivo == m.key,
                  onSelected: (_) => setState(() => _motivo = m.key),
                ),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _escolherData,
              icon: const Icon(Icons.event_outlined),
              label: Text(_data == null ? 'Sugerir uma data (opcional)' : 'Data sugerida: ${dataBr(_data)}'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _obs,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _motivo == 'outro' ? 'O que aconteceu?' : 'Observação (opcional)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _motivo == null || precisaTexto
                    ? null
                    : () => Navigator.of(context).pop(_Pedido(_motivo!, _data, _obs.text)),
                child: const Text('Enviar ao escritório'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
