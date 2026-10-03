import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/planos.dart';
import '../servicos/status.dart';
import 'escolha_equipamentos.dart' show rotuloEquipamento;
import 'status_chip.dart';

bool _pronto(Map x) => x['status'] == 'feito' || x['status'] == 'nao_conforme' || x['status'] == 'nao_se_aplica';

/// Checklist do lote (preventiva do plano): por aparelho, com o que a equipe
/// marcou no app e a OS do ciclo de cada aparelho que fechou. O gestor
/// também marca (ex.: feito no papel). Com [ciclo], mostra só os itens da OS
/// do aparelho (somente leitura: para refazer, desmarca-se no lote).
class ChecklistDaOs extends StatefulWidget {
  const ChecklistDaOs(
      {super.key, required this.osId, required this.editavel, required this.versao, this.aoMudar, this.ciclo = false});

  final String osId;
  final bool editavel;
  final bool ciclo;

  /// Muda a cada recarga da OS (recarrega o checklist junto).
  final int versao;
  final VoidCallback? aoMudar;

  @override
  State<ChecklistDaOs> createState() => _ChecklistDaOsState();
}

class _ChecklistDaOsState extends State<ChecklistDaOs> {
  List<Map<String, dynamic>> _itens = [];
  Map<String, String> _pessoas = {};
  Map<String, String> _ciclos = {}; // id da OS do ciclo -> código
  bool _carregando = true;
  bool _ocupado = false;
  bool _soFaltando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(covariant ChecklistDaOs old) {
    super.didUpdateWidget(old);
    if (old.versao != widget.versao) _carregar();
  }

  Future<void> _carregar() async {
    final db = Supabase.instance.client;
    try {
      final itens = await db
          .from('plano_execucoes')
          .select('id, os_id, unidade_id, ciclo_os_id, foto_id, equipamento_id, plano_atividade_id, descricao, '
              'periodicidade, exige_foto, ordem, status, observacao, executado_por, executado_em, prazo, '
              'equipamentos(codigo, descricao, ambientes(nome))')
          .eq(widget.ciclo ? 'ciclo_os_id' : 'os_id', widget.osId)
          .isFilter('excluido_em', null)
          .neq('status', 'cancelada')
          .order('ordem', ascending: true);
      final ids = {for (final i in itens) if (i['executado_por'] != null) '${i['executado_por']}'};
      final pessoas = ids.isEmpty
          ? <Map<String, dynamic>>[]
          : await db.from('colaboradores').select('id, nome').inFilter('id', ids.toList());
      final idsCiclo = {for (final i in itens) if (i['ciclo_os_id'] != null) '${i['ciclo_os_id']}'};
      final ciclos = idsCiclo.isEmpty || widget.ciclo
          ? <Map<String, dynamic>>[]
          : await db.from('ordens_servico').select('id, codigo').inFilter('id', idsCiclo.toList());
      if (!mounted) return;
      setState(() {
        _itens = itens;
        _pessoas = {for (final p in pessoas) '${p['id']}': '${p['nome']}'};
        _ciclos = {for (final c in ciclos) '${c['id']}': '${c['codigo']}'};
        _erro = null;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _marcar(List<Map<String, dynamic>> itens) async {
    setState(() => _ocupado = true);
    try {
      await marcarPreventiva(widget.osId, itens);
      // Quem tem aoMudar recarrega a OS inteira (e este checklist junto).
      if (widget.aoMudar != null) {
        widget.aoMudar!();
      } else {
        await _carregar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(mensagemDeErro(e)), backgroundColor: Cores.erro));
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _escolher(Map<String, dynamic> x, String? resultado) async {
    String? obs;
    if (resultado == 'nao_conforme') {
      final c = TextEditingController(text: '${x['observacao'] ?? ''}');
      obs = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${x['descricao']}'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: c,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'O que não está conforme?'),
            ),
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
      if (obs == null || !mounted) return;
    }
    await _marcar([
      {'execucao_id': x['id'], 'resultado': resultado, if (obs != null) 'observacao': obs},
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const LinearProgressIndicator(minHeight: 2);
    if (_erro != null) return Text(_erro!, style: const TextStyle(color: Cores.erro));
    if (_itens.isEmpty) return const Text('Sem itens no checklist.', style: TextStyle(color: Cores.neutro));

    // Unidades: cada aparelho, ou cada atividade geral do plano. Um aparelho
    // com duas voltas no mesmo lote (ex.: quinzenal num lote mensal) aparece
    // uma vez por volta: a fechada (com a OS do ciclo) e a aberta.
    String unidade(Map<String, dynamic> x) => '${x['unidade_id'] ?? x['equipamento_id'] ?? 'g:${x['plano_atividade_id']}'}';
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final x in _itens) {
      grupos.putIfAbsent('${unidade(x)}|${x['ciclo_os_id'] ?? ''}', () => []).add(x);
    }
    // O andamento conta cada unidade uma vez: pronta quando nada falta nela.
    final porUnidade = <String, bool>{};
    for (final x in _itens) {
      porUnidade[unidade(x)] = (porUnidade[unidade(x)] ?? true) && _pronto(x);
    }
    final prontas = porUnidade.values.where((p) => p).length;
    final chaves = grupos.keys.toList()
      ..sort((a, b) {
        String rot(String k) {
          final e = grupos[k]!.first['equipamentos'] as Map?;
          return e == null ? ' ${grupos[k]!.first['descricao']}' : '${e['codigo']}';
        }

        final o = rot(a).compareTo(rot(b));
        return o != 0 ? o : b.endsWith('|') ? -1 : a.endsWith('|') ? 1 : 0; // a volta fechada antes da aberta
      });
    final visiveis = chaves.where((k) => !_soFaltando || !grupos[k]!.every(_pronto)).toList();

    final editavel = widget.editavel && !widget.ciclo;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!widget.ciclo) ...[
        Text('$prontas de ${porUnidade.length} pronto(s) (ciclo fechado = OS do aparelho)',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        LinearProgressIndicator(
            value: porUnidade.isEmpty ? 0 : prontas / porUnidade.length, minHeight: 8, borderRadius: BorderRadius.circular(4)),
        const SizedBox(height: 8),
      ] else ...[
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Itens deste ciclo, marcados no lote', style: TextStyle(color: Cores.neutro)),
          TextButton(
            onPressed: () => context.push('/os/${_itens.first['os_id']}'),
            child: const Text('Abrir o lote'),
          ),
        ]),
      ],
      if (!widget.ciclo)
      Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ChoiceChip(
            label: const Text('Todos'), selected: !_soFaltando, onSelected: (_) => setState(() => _soFaltando = false)),
        ChoiceChip(
            label: const Text('Faltando'), selected: _soFaltando, onSelected: (_) => setState(() => _soFaltando = true)),
        if (_ocupado) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      const SizedBox(height: 4),
      for (final k in visiveis)
        Builder(builder: (context) {
          final lista = grupos[k]!;
          final e = lista.first['equipamentos'] as Map?;
          final feitos = lista.where(_pronto).length;
          final problema = lista.any((x) => x['status'] == 'nao_conforme');
          final faltam = lista.where((x) => x['status'] == 'pendente').toList();
          final ciclo = lista.map((x) => x['ciclo_os_id']).firstWhere((c) => c != null, orElse: () => null);
          final venc = ([for (final x in lista) '${x['prazo']}']..sort()).first;
          return ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: widget.ciclo,
            leading: Icon(
              feitos == lista.length ? (problema ? Icons.report_problem_outlined : Icons.check_circle) : Icons.radio_button_unchecked,
              color: feitos == lista.length ? (problema ? Cores.alerta : Cores.sucesso) : Cores.neutro,
            ),
            title: Text(e == null ? 'Geral do plano: ${lista.first['descricao']}' : rotuloEquipamento(e)),
            subtitle: Text([
              if (e != null) '${(e['ambientes'] as Map?)?['nome'] ?? 'Sem ambiente'}',
              '$feitos de ${lista.length}',
              if (feitos < lista.length) 'vence ${dataBr(venc)}',
              if (problema) 'não conforme',
            ].join(' · ')),
            trailing: ciclo != null && !widget.ciclo
                ? TextButton(
                    onPressed: () => context.push('/os/$ciclo'),
                    child: Text(_ciclos['$ciclo'] ?? 'OS do ciclo'),
                  )
                : null,
            children: [
              for (final x in lista)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 40),
                  title: Text('${x['descricao']}'),
                  subtitle: Text([
                    periodicidades[x['periodicidade']] ?? '${x['periodicidade']}',
                    if (x['exige_foto'] == true) x['foto_id'] != null ? 'com foto' : 'pede foto',
                    if (x['observacao'] != null) '${x['observacao']}',
                    if (x['executado_em'] != null)
                      '${_pessoas['${x['executado_por']}'] ?? 'escritório'} em ${dataHoraBr(x['executado_em'])}',
                  ].join(' · ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    StatusChip(x['status'] as String?, statusExecucao, compacto: true),
                    if (editavel && x['status'] != 'nao_feito')
                      PopupMenuButton<String>(
                        tooltip: 'Marcar',
                        enabled: !_ocupado,
                        onSelected: (r) => _escolher(x, r == 'desmarcar' ? null : r),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'feito', child: Text('Feito')),
                          const PopupMenuItem(value: 'nao_se_aplica', child: Text('Não se aplica')),
                          const PopupMenuItem(value: 'nao_conforme', child: Text('Não conforme...')),
                          if (x['status'] != 'pendente') const PopupMenuItem(value: 'desmarcar', child: Text('Desmarcar')),
                        ],
                      ),
                  ]),
                ),
              if (editavel && faltam.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _ocupado
                        ? null
                        : () => _marcar([
                              for (final x in faltam) {'execucao_id': x['id'], 'resultado': 'feito'},
                            ]),
                    icon: const Icon(Icons.done_all, size: 18),
                    label: Text('Marcar o que falta como feito (${faltam.length})'),
                  ),
                ),
            ],
          );
        }),
      if (visiveis.isEmpty)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Nada faltando.', style: TextStyle(color: Cores.sucesso)),
        ),
    ]);
  }
}
