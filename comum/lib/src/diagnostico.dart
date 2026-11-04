import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'erros.dart';
import 'tema.dart';

/// Diagnóstico assistido (guia 74): o técnico (no app) ou o escritório (na OS)
/// escreve o sintoma ou o código de erro; a IA devolve as causas prováveis,
/// como confirmar cada uma, as peças (casadas com o catálogo) e os cuidados,
/// levando junto o histórico do aparelho.
Future<void> abrirDiagnostico(BuildContext context, {String? osId, String? equipamentoId, String? sintoma}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _Diagnostico(osId: osId, equipamentoId: equipamentoId, sintoma: sintoma),
    );

class _Diagnostico extends StatefulWidget {
  const _Diagnostico({this.osId, this.equipamentoId, this.sintoma});

  final String? osId;
  final String? equipamentoId;
  final String? sintoma;

  @override
  State<_Diagnostico> createState() => _DiagnosticoState();
}

class _DiagnosticoState extends State<_Diagnostico> {
  late final _sintoma = TextEditingController(text: widget.sintoma ?? '');
  bool _pensando = false;
  Map<String, dynamic>? _r;
  String? _erro;

  @override
  void dispose() {
    _sintoma.dispose();
    super.dispose();
  }

  Future<void> _perguntar() async {
    if (_sintoma.text.trim().length < 3) {
      setState(() => _erro = 'Conte o sintoma ou o código de erro.');
      return;
    }
    setState(() {
      _pensando = true;
      _erro = null;
    });
    try {
      final r = await Supabase.instance.client.functions.invoke('diagnostico', body: {
        'sintoma': _sintoma.text.trim(),
        if (widget.osId != null) 'os_id': widget.osId,
        if (widget.equipamentoId != null) 'equipamento_id': widget.equipamentoId,
      });
      if (mounted) setState(() => _r = Map<String, dynamic>.from(r.data as Map));
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _pensando = false);
    }
  }

  String _texto(Map<String, dynamic> r) {
    final b = StringBuffer('Diagnóstico (IA): ${r['resumo'] ?? ''}\n');
    for (final c in ((r['causas'] as List?) ?? const []).cast<Map>()) {
      b.writeln('- ${c['causa']} (${c['chance']}): ${c['como_confirmar'] ?? ''}');
    }
    final pecas = ((r['pecas'] as List?) ?? const []).cast<Map>();
    if (pecas.isNotEmpty) b.writeln('Peças: ${pecas.map((p) => p['descricao'] ?? p['nome']).join(', ')}');
    return b.toString();
  }

  Widget _chance(String c) {
    final (rotulo, cor) = switch (c) {
      'alta' => ('mais provável', Cores.erro),
      'baixa' => ('menos provável', Cores.neutro),
      _ => ('provável', Cores.alerta),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: cor.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
      child: Text(rotulo, style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final cod = r?['codigo_erro'] as Map?;
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.psychology_alt_outlined, color: Cores.coral500),
        SizedBox(width: 8),
        Text('Diagnóstico (IA)'),
      ]),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _sintoma,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Sintoma ou código de erro',
                hintText: 'Ex.: liga, a ventilação funciona, mas o compressor não parte; display com E5',
              ),
            ),
            if (widget.osId != null || widget.equipamentoId != null)
              const Text('Vai junto: os dados do aparelho e o que já foi feito nele.',
                  style: TextStyle(color: Cores.neutro, fontSize: 12)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _pensando ? null : _perguntar,
              icon: _pensando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: Text(_pensando ? 'Pensando...' : (r == null ? 'Diagnosticar' : 'Diagnosticar de novo')),
            ),
            if (_erro != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(_erro!, style: const TextStyle(color: Cores.erro))),
            if (r != null) ...[
              const Divider(height: 24),
              if ('${r['resumo'] ?? ''}'.isNotEmpty)
                Text('${r['resumo']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              if (cod != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Código ${cod['codigo']}: ${cod['significado'] ?? ''}'),
                ),
              const SizedBox(height: 10),
              const Text('Causas prováveis', style: TextStyle(fontWeight: FontWeight.w700, color: Cores.indigo700)),
              for (final c in ((r['causas'] as List?) ?? const []).cast<Map>())
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('${c['causa']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      _chance('${c['chance']}'),
                    ]),
                    if ('${c['como_confirmar'] ?? ''}'.isNotEmpty)
                      Text('Como confirmar: ${c['como_confirmar']}', style: const TextStyle(color: Cores.neutro)),
                  ]),
                ),
              if (((r['pecas'] as List?) ?? const []).isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Peças que costumam resolver', style: TextStyle(fontWeight: FontWeight.w700, color: Cores.indigo700)),
                for (final p in ((r['pecas'] as List?) ?? const []).cast<Map>())
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text([
                      '${p['quantidade'] ?? 1} × ${p['descricao'] ?? p['nome']}',
                      if (p['produto_id'] == null) '(sem cadastro)',
                      if (p['preco'] != null) 'R\$ ${(num.tryParse('${p['preco']}') ?? 0).toStringAsFixed(2).replaceAll('.', ',')}',
                      if ('${p['motivo'] ?? ''}'.isNotEmpty) '· ${p['motivo']}',
                    ].join(' ')),
                  ),
              ],
              if (((r['cuidados'] as List?) ?? const []).isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Cuidados', style: TextStyle(fontWeight: FontWeight.w700, color: Cores.indigo700)),
                for (final c in (r['cuidados'] as List)) Text('• $c'),
              ],
              const SizedBox(height: 12),
              const Text('Sugestão da IA para orientar: confirme com os testes antes de trocar peças.',
                  style: TextStyle(color: Cores.neutro, fontSize: 12)),
            ],
          ]),
        ),
      ),
      actions: [
        if (r != null)
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _texto(r)));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Diagnóstico copiado.')));
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
      ],
    );
  }
}
