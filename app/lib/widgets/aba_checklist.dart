import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_atendimento.dart';
import '../core/acoes_checklist.dart';
import '../core/acoes_orcamento.dart';
import '../core/banco_local.dart';
import '../core/consultas.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import 'abas_atendimento.dart';

void _aviso(BuildContext context, String texto) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

String _rotulo(Map e) => [e['codigo'], e['descricao']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');

/// Foto de um item que pede foto. Com [passo] ("Foto 1 de 3"), avisa antes
/// qual item é. Devolve o id da foto; '' = marcar sem foto (quando a foto não
/// é obrigatória); null = não marcar.
Future<String?> fotoDoItem(BuildContext context, Map<String, dynamic> atd, Map<String, dynamic> item,
    {String? passo}) async {
  if (passo != null) {
    final seguir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(passo),
        content: Text('${item['descricao']}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Parar')),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Abrir a câmera'),
          ),
        ],
      ),
    );
    if (seguir != true || !context.mounted) return null;
  }
  String? id;
  try {
    id = await tirarFoto(atd, equipamentoId: item['equipamento_id'] as String?);
  } catch (e) {
    if (context.mounted) _aviso(context, 'Não foi possível tirar a foto: $e');
  }
  if (id != null || !context.mounted) return id;
  if (AcoesOrcamento.config.fotoPreventivaObrigatoria) {
    _aviso(context, 'Sem a foto, "${item['descricao']}" não é marcado.');
    return null;
  }
  final sem = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Marcar sem a foto?'),
      content: Text('${item['descricao']} pede foto.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Não marcar')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Marcar sem foto')),
      ],
    ),
  );
  return sem == true ? '' : null;
}

/// O item pede foto e ainda não tem.
bool _precisaFoto(Map<String, dynamic> x) => x['exige_foto'] == true && x['foto_id'] == null;

/// Aba "Checklist" do atendimento do lote de preventivas: o que o plano pede
/// em cada aparelho (e as atividades gerais). A equipe marca o que fez nesta
/// visita; aparelho com tudo marcado fecha o ciclo (vira a OS dele); o que
/// faltar volta para a fila numa nova visita.
class AbaChecklist extends StatefulWidget {
  const AbaChecklist({super.key, required this.atd, required this.habilitado});

  final Map<String, dynamic> atd;
  final bool habilitado;

  @override
  State<AbaChecklist> createState() => _AbaChecklistState();
}

class _AbaChecklistState extends State<AbaChecklist> {
  final _busca = TextEditingController();
  bool _soFaltando = true;

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  BancoLocal get _banco => EstadoApp.instancia.banco!;

  /// Lê a etiqueta e abre o checklist daquele aparelho.
  Future<void> _lerEtiqueta(Map<String, List<Map<String, dynamic>>> grupos) async {
    final lido = await context.push<String>('/ler-codigo');
    if (lido == null || !mounted) return;
    final valor = lido.trim().toLowerCase();
    final achado = grupos.keys.where((id) => id.isNotEmpty).map((id) => _banco.um('equipamentos', id)).firstWhere(
        (e) => e != null && ('${e['qr_token'] ?? ''}'.toLowerCase() == valor || '${e['codigo'] ?? ''}'.toLowerCase() == valor),
        orElse: () => null);
    if (achado == null) {
      _aviso(context, 'Este aparelho não está no checklist desta OS: $lido');
      return;
    }
    // A leitura da etiqueta fica registrada (prova de que o técnico esteve no aparelho).
    if (widget.habilitado && _banco.identificacao(widget.atd['id'], achado['id']) == null) {
      await AcoesAtendimento.identificarEquipamento(widget.atd, achado, leitura: 'qr', valorLido: lido);
    }
    if (!mounted) return;
    await _abrir(achado['id'] as String);
  }

  Future<void> _abrir(String aparelhoId) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _ChecklistDoAparelho(atd: widget.atd, aparelhoId: aparelhoId, habilitado: widget.habilitado),
      );

  @override
  Widget build(BuildContext context) {
    final osId = widget.atd['os_id'];
    final grupos = AcoesChecklist.porAparelho(osId);
    final and = AcoesChecklist.andamento(osId);
    final b = _busca.text.trim().toLowerCase();
    final gerais = [
      for (final x in grupos[''] ?? const <Map<String, dynamic>>[])
        if ((!_soFaltando || !AcoesChecklist.feito(x)) && (b.isEmpty || '${x['descricao']}'.toLowerCase().contains(b))) x,
    ];

    // Aparelhos por ambiente, na ordem do código.
    final porAmbiente = <String, List<Map<String, dynamic>>>{};
    for (final id in grupos.keys.where((k) => k.isNotEmpty)) {
      final e = _banco.um('equipamentos', id) ?? {'id': id, 'codigo': '(aparelho)'};
      final itens = grupos[id]!;
      if (_soFaltando && itens.every(AcoesChecklist.feito)) continue;
      final ambiente = '${_banco.um('ambientes', e['ambiente_id'])?['nome'] ?? 'Sem ambiente'}';
      if (b.isNotEmpty && !'${_rotulo(e)} $ambiente'.toLowerCase().contains(b)) continue;
      porAmbiente.putIfAbsent(ambiente, () => []).add(e);
    }
    final ambientes = porAmbiente.keys.toList()..sort();
    for (final l in porAmbiente.values) {
      l.sort((x, y) => '${x['codigo']}'.compareTo('${y['codigo']}'));
    }

    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${and.prontas} de ${and.total} pronto(s)',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: and.fracao, minHeight: 8, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 6),
            Text(
              [
                if (and.prazo != null) 'Lote até ${dataBr(and.prazo)}',
                if (and.naoConformes > 0) '${and.naoConformes} com não conformidade',
              ].join(' · '),
              style: const TextStyle(color: Cores.neutro),
            ),
            const SizedBox(height: 4),
            const Text('Não precisa fazer tudo hoje: o que faltar volta para a fila numa nova visita.',
                style: TextStyle(color: Cores.neutro, fontSize: 12)),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _busca,
            decoration: const InputDecoration(hintText: 'Buscar aparelho ou ambiente', prefixIcon: Icon(Icons.search)),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Ler a etiqueta',
          onPressed: () => _lerEtiqueta(grupos),
          icon: const Icon(Icons.qr_code_scanner),
        ),
      ]),
      const SizedBox(height: 4),
      Wrap(spacing: 8, children: [
        ChoiceChip(label: const Text('Faltando'), selected: _soFaltando, onSelected: (_) => setState(() => _soFaltando = true)),
        ChoiceChip(label: const Text('Todos'), selected: !_soFaltando, onSelected: (_) => setState(() => _soFaltando = false)),
      ]),
      if (gerais.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Text('Gerais do plano', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        for (final x in gerais) _ItemChecklist(atd: widget.atd, item: x, habilitado: widget.habilitado),
      ],
      for (final amb in ambientes) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Text(amb, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        for (final e in porAmbiente[amb]!)
          Builder(builder: (context) {
            final itens = grupos['${e['id']}']!;
            final feitos = itens.where(AcoesChecklist.feito).length;
            final pronto = feitos == itens.length;
            final problema = itens.any((x) => x['status'] == 'nao_conforme');
            final foto = itens.any(_precisaFoto);
            final venc = AcoesChecklist.vencimento(itens);
            final hoje = EstadoApp.instancia.sync?.hoje;
            final atrasado = !pronto && venc != null && hoje != null && venc.compareTo(hoje) < 0;
            return Card(
              child: ListTile(
                onTap: () => _abrir('${e['id']}'),
                leading: Icon(
                  pronto ? (problema ? Icons.report_problem_outlined : Icons.check_circle) : Icons.radio_button_unchecked,
                  color: pronto ? (problema ? Cores.alerta : Cores.sucesso) : Cores.neutro,
                ),
                title: Text(_rotulo(e)),
                subtitle: Text(
                  [
                    if (AcoesChecklist.cicloFechado(itens)) 'Ciclo fechado' else '$feitos de ${itens.length} item(ns)',
                    if (!pronto && venc != null) '${atrasado ? 'venceu' : 'vence'} ${dataBr(venc)}',
                    if (!pronto && foto) 'pede foto',
                  ].join(' · '),
                  style: TextStyle(color: atrasado ? Cores.erro : null),
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            );
          }),
      ],
      if (ambientes.isEmpty && grupos.keys.any((k) => k.isNotEmpty))
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_soFaltando && b.isEmpty ? 'Todos os aparelhos estão prontos.' : 'Nada encontrado.',
              style: const TextStyle(color: Cores.neutro)),
        ),
    ]);
  }
}

/// Um item do checklist: feito / não se aplica / não conforme (com observação).
class _ItemChecklist extends StatelessWidget {
  const _ItemChecklist({required this.atd, required this.item, required this.habilitado});

  final Map<String, dynamic> atd;
  final Map<String, dynamic> item;
  final bool habilitado;

  Future<void> _marcar(BuildContext context, String? resultado) async {
    String? obs;
    if (resultado == 'nao_conforme') {
      obs = await pedirObservacao(context, '${item['descricao']}', inicial: '${item['observacao'] ?? ''}');
      if (obs == null) return;
    }
    // Item que pede foto: a câmera abre ao marcar (feito ou não conforme).
    String? foto;
    if ((resultado == 'feito' || resultado == 'nao_conforme') && _precisaFoto(item)) {
      if (!context.mounted) return;
      foto = await fotoDoItem(context, atd, item);
      if (foto == null) return;
      if (foto.isEmpty) foto = null;
    }
    await AcoesChecklist.marcar(atd, {'${item['id']}': (resultado, obs, foto)});
  }

  @override
  Widget build(BuildContext context) {
    final status = '${item['status']}';
    final encerrado = status == 'nao_feito';
    final pode = habilitado && !encerrado;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${item['descricao']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (item['exige_foto'] == true)
            Text(item['foto_id'] != null ? 'Foto tirada' : 'Pede foto: a câmera abre ao marcar',
                style: TextStyle(color: item['foto_id'] != null ? Cores.sucesso : Cores.indigo500, fontSize: 12)),
          if (status == 'nao_conforme' && (item['observacao'] ?? '').toString().isNotEmpty)
            Text('${item['observacao']}', style: const TextStyle(color: Cores.alerta)),
          if (encerrado) const Text('Não feito (a OS foi encerrada)', style: TextStyle(color: Cores.neutro)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in resultadosChecklist.entries)
              ChoiceChip(
                label: Text(r.value),
                selected: status == r.key,
                selectedColor: (r.key == 'nao_conforme' ? Cores.alerta : (r.key == 'feito' ? Cores.sucesso : Cores.neutro))
                    .withValues(alpha: .2),
                onSelected: !pode
                    ? null
                    : (sim) => _marcar(context, sim || r.key == 'nao_conforme' ? r.key : null),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// Observação da não conformidade (obrigatória). null = desistiu.
Future<String?> pedirObservacao(BuildContext context, String titulo, {String inicial = ''}) async {
  final c = TextEditingController(text: inicial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: TextField(
        controller: c,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'O que não está conforme?'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (c.text.trim().isNotEmpty) Navigator.of(ctx).pop(c.text.trim());
          },
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
  // Sem dispose: o diálogo ainda anima a saída usando o campo.
  return r;
}

/// O checklist de um aparelho, numa folha de baixo: os itens, "Marcar o que
/// falta" (abrindo a câmera em sequência para os itens que pedem foto) e a
/// foto do aparelho.
class _ChecklistDoAparelho extends StatefulWidget {
  const _ChecklistDoAparelho({required this.atd, required this.aparelhoId, required this.habilitado});

  final Map<String, dynamic> atd;
  final String aparelhoId;
  final bool habilitado;

  @override
  State<_ChecklistDoAparelho> createState() => _ChecklistDoAparelhoState();
}

class _ChecklistDoAparelhoState extends State<_ChecklistDoAparelho> {
  bool _tirando = false;

  /// Marca o que falta como feito. Os itens que pedem foto abrem a câmera um a
  /// um ("Foto 1 de 3"); se parar, fica marcado o que já tem foto.
  Future<void> _marcarOQueFalta(List<Map<String, dynamic>> faltando) async {
    final precisam = faltando.where(_precisaFoto).toList();
    final marcas = <String, (String?, String?, String?)>{
      for (final x in faltando)
        if (!_precisaFoto(x)) '${x['id']}': ('feito', null, null),
    };
    var i = 0;
    for (final x in precisam) {
      i++;
      if (!mounted) return;
      final f = await fotoDoItem(context, widget.atd, x,
          passo: precisam.length == 1 ? 'Foto do item' : 'Foto $i de ${precisam.length}');
      if (f == null) break;
      marcas['${x['id']}'] = ('feito', null, f.isEmpty ? null : f);
    }
    await AcoesChecklist.marcar(widget.atd, marcas);
    if (!mounted) return;
    if (marcas.length == faltando.length) {
      Navigator.of(context).pop();
    } else {
      _aviso(context, '${marcas.length} de ${faltando.length} marcado(s). Os outros pedem foto.');
    }
  }

  Future<void> _foto() async {
    setState(() => _tirando = true);
    try {
      await tirarFoto(widget.atd, equipamentoId: widget.aparelhoId);
    } catch (e) {
      if (mounted) _aviso(context, 'Não foi possível tirar a foto: $e');
    } finally {
      if (mounted) setState(() => _tirando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final banco = EstadoApp.instancia.banco!;
    return ListenableBuilder(
      listenable: banco,
      builder: (context, _) {
        final e = banco.um('equipamentos', widget.aparelhoId) ?? const {};
        final itens = AcoesChecklist.porAparelho(widget.atd['os_id'])[widget.aparelhoId] ?? const [];
        final faltando = itens.where((x) => x['status'] == 'pendente').toList();
        final fotos = banco
            .doAtendimento('atendimento_fotos', widget.atd['id'])
            .where((f) => f['equipamento_id'] == widget.aparelhoId)
            .length;
        final pedeFoto = itens.any((x) => x['exige_foto'] == true);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .85,
            child: Column(children: [
              ListTile(
                title: Text(_rotulo(e), style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text([
                  banco.um('ambientes', e['ambiente_id'])?['nome'],
                  [e['marca'], e['modelo']].where((x) => x != null).join(' '),
                ].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
                trailing: IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  for (final x in itens) _ItemChecklist(atd: widget.atd, item: x, habilitado: widget.habilitado),
                  const SizedBox(height: 8),
                  if (widget.habilitado)
                    OutlinedButton.icon(
                      onPressed: _tirando ? null : _foto,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(fotos == 0
                          ? (pedeFoto ? 'Tirar foto deste aparelho (pedida)' : 'Tirar foto deste aparelho')
                          : 'Mais uma foto ($fotos tirada(s))'),
                    ),
                ]),
              ),
              if (widget.habilitado)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: faltando.isEmpty ? null : () => _marcarOQueFalta(faltando),
                        icon: const Icon(Icons.done_all),
                        label: Text(faltando.isEmpty ? 'Tudo marcado' : 'Marcar o que falta como feito (${faltando.length})'),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
}
