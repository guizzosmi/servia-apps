import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/arquivo_web.dart';
import '../servicos/status.dart';
import 'servico.dart';

/// Etiqueta colorida do status do equipamento.
class ChipStatusEqp extends StatelessWidget {
  const ChipStatusEqp(this.status, {super.key});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final cor = corDoStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: .08),
        border: Border.all(color: cor.withValues(alpha: .5)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(statusEquipamento[status] ?? status ?? '',
          style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// Cartão com título (seções das telas da aplicação).
class SecaoEqp extends StatelessWidget {
  const SecaoEqp({super.key, required this.titulo, required this.child, this.acoes = const []});

  final String titulo;
  final Widget child;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              ...acoes,
            ]),
            const SizedBox(height: 8),
            child,
          ]),
        ),
      );
}

/// Botão que mostra uma data e abre o calendário.
class CampoDataEqp extends StatelessWidget {
  const CampoDataEqp({super.key, required this.rotulo, required this.data, required this.aoMudar});

  final String rotulo;
  final DateTime? data;
  final ValueChanged<DateTime> aoMudar;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: () async {
          final hoje = DateTime.now();
          final d = await showDatePicker(
            context: context,
            initialDate: data ?? hoje,
            firstDate: DateTime(hoje.year - 2),
            lastDate: DateTime(hoje.year + 3),
          );
          if (d != null) aoMudar(d);
        },
        icon: const Icon(Icons.event_outlined, size: 18),
        label: Text(data == null ? rotulo : '$rotulo: ${dataBr(iso(data!))}'),
      );
}

/// Pergunta sim/não.
Future<bool> confirmarEqp(BuildContext context, String titulo, String texto, {String sim = 'Confirmar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(sim)),
      ],
    ),
  );
  return r == true;
}

/// Pede um texto (motivo, observação). null = desistiu.
Future<String?> pedirTextoEqp(BuildContext context, String titulo, String rotulo, {bool obrigatorio = true}) async {
  final c = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: SizedBox(
        width: 420,
        child: TextField(controller: c, autofocus: true, maxLines: 3, decoration: InputDecoration(labelText: rotulo)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Voltar')),
        FilledButton(
          onPressed: () {
            if (obrigatorio && c.text.trim().isEmpty) return;
            Navigator.of(ctx).pop(c.text.trim());
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
  c.dispose();
  return r;
}

/// Mensagem rápida no rodapé.
void avisarEqp(BuildContext context, String texto, {bool erro = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null),
  );
}

/// Itens padrão do checklist de saída e de retorno (dá para desmarcar e incluir outros).
const itensChecklistPadrao = [
  'Equipamento completo (acessórios, mangueiras, cabos)',
  'Funcionando no teste',
  'Sem vazamento',
  'Limpo',
];

/// Check-out (retirada) ou check-in (devolução): condição, checklist, fotos, horímetro e quem recebeu.
/// Devolve o corpo para eqp_locacao_acao / eqp_movimentar, ou null se desistiu.
Future<Map<String, dynamic>?> dialogoConferencia(
  BuildContext context, {
  required String titulo,
  required bool devolucao,
  String? medidor,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _Conferencia(titulo: titulo, devolucao: devolucao, medidor: medidor),
  );
}

class _Conferencia extends StatefulWidget {
  const _Conferencia({required this.titulo, required this.devolucao, this.medidor});

  final String titulo;
  final bool devolucao;
  final String? medidor;

  @override
  State<_Conferencia> createState() => _ConferenciaState();
}

class _ConferenciaState extends State<_Conferencia> {
  String _condicao = 'ok';
  final _leitura = TextEditingController();
  final _recebido = TextEditingController();
  final _obs = TextEditingController();
  final _avaria = TextEditingController();
  final _valor = TextEditingController();
  final _novoItem = TextEditingController();
  final Map<String, bool> _itens = {for (final i in itensChecklistPadrao) i: true};
  final List<String> _fotos = [];
  bool _manutencao = false;
  bool _enviando = false;

  @override
  void dispose() {
    for (final c in [_leitura, _recebido, _obs, _avaria, _valor, _novoItem]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _foto() async {
    final arquivo = await escolherArquivo(aceitar: 'image/jpeg');
    if (arquivo == null) return;
    setState(() => _enviando = true);
    try {
      final caminho = await enviarFoto(arquivo);
      if (mounted) setState(() => _fotos.add(caminho));
    } catch (e) {
      if (mounted) avisarEqp(context, 'Foto não enviada: ${mensagemDeErro(e)}', erro: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _ok() {
    final leitura = num.tryParse(_leitura.text.trim().replaceAll(',', '.'));
    final valor = num.tryParse(_valor.text.trim().replaceAll(',', '.'));
    Navigator.of(context).pop(<String, dynamic>{
      'condicao': _condicao,
      if (leitura != null) 'leitura': leitura,
      if (_recebido.text.trim().isNotEmpty) 'recebido_por': _recebido.text.trim(),
      if (_obs.text.trim().isNotEmpty) 'observacao': _obs.text.trim(),
      'checklist': [for (final e in _itens.entries) {'item': e.key, 'ok': e.value}],
      'fotos': _fotos,
      if (widget.devolucao && _avaria.text.trim().isNotEmpty) 'avaria_descricao': _avaria.text.trim(),
      if (widget.devolucao && valor != null) 'avaria_valor': valor,
      if (widget.devolucao && _manutencao) 'abrir_manutencao': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    final medidor = widget.medidor;
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Condição', style: TextStyle(fontWeight: FontWeight.w600)),
            Wrap(spacing: 8, children: [
              for (final c in condicoes.entries)
                ChoiceChip(
                  label: Text(c.value),
                  selected: _condicao == c.key,
                  onSelected: (_) => setState(() => _condicao = c.key),
                ),
            ]),
            const SizedBox(height: 8),
            const Text('Checklist', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final e in _itens.entries)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: e.value,
                title: Text(e.key),
                onChanged: (v) => setState(() => _itens[e.key] = v ?? false),
              ),
            Row(children: [
              Expanded(child: TextField(controller: _novoItem, decoration: const InputDecoration(labelText: 'Outro item'))),
              IconButton(
                tooltip: 'Incluir item',
                onPressed: () {
                  final t = _novoItem.text.trim();
                  if (t.isEmpty) return;
                  setState(() {
                    _itens[t] = true;
                    _novoItem.clear();
                  });
                },
                icon: const Icon(Icons.add),
              ),
            ]),
            if (medidor != null && medidor != 'nenhum')
              TextField(
                controller: _leitura,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: switch (medidor) { 'km' => 'Km', 'ciclos' => 'Ciclos', _ => 'Horímetro (h)' }),
              ),
            TextField(
              controller: _recebido,
              decoration: InputDecoration(labelText: widget.devolucao ? 'Quem conferiu / devolveu' : 'Quem recebeu'),
            ),
            TextField(controller: _obs, maxLines: 2, decoration: const InputDecoration(labelText: 'Observação')),
            if (widget.devolucao) ...[
              const SizedBox(height: 8),
              TextField(controller: _avaria, maxLines: 2, decoration: const InputDecoration(labelText: 'Avaria ou falta (vai para cobrar)')),
              TextField(
                controller: _valor,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Valor sugerido da avaria (R\$)'),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _manutencao,
                title: const Text('Abrir OS de reparo agora'),
                onChanged: (v) => setState(() => _manutencao = v),
              ),
            ],
            const SizedBox(height: 8),
            Row(children: [
              OutlinedButton.icon(
                onPressed: _enviando ? null : _foto,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(_enviando ? 'Enviando…' : 'Adicionar foto (JPEG)'),
              ),
              const SizedBox(width: 12),
              Text('${_fotos.length} foto(s)', style: const TextStyle(color: Cores.neutro)),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
        FilledButton(onPressed: _enviando ? null : _ok, child: Text(widget.devolucao ? 'Registrar devolução' : 'Registrar retirada')),
      ],
    );
  }
}

/// Fotos de um movimento (abre cada uma numa aba nova).
class FotosEqp extends StatelessWidget {
  const FotosEqp(this.fotos, {super.key});

  final List<dynamic> fotos;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 4, children: [
        for (var i = 0; i < fotos.length; i++)
          ActionChip(
            avatar: const Icon(Icons.photo_outlined, size: 16),
            label: Text('Foto ${i + 1}'),
            onPressed: () async {
              try {
                abrirEmNovaAba(await linkDaFoto('${fotos[i]}'));
              } catch (e) {
                if (context.mounted) avisarEqp(context, mensagemDeErro(e), erro: true);
              }
            },
          ),
      ]);
}

/// Aviso para quem abre a área sem a aplicação liberada.
class SemAplicacaoEqp extends StatelessWidget {
  const SemAplicacaoEqp({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'A Gestão de Equipamentos não está liberada para você nesta empresa. Fale com o ServPilot para ligar a '
            'aplicação na sua conta (entre de novo depois de liberada).',
            textAlign: TextAlign.center,
            style: TextStyle(color: Cores.neutro),
          ),
        ),
      );
}
