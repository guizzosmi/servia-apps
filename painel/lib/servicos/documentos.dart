import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// PDF gerado na plataforma (função "relatorios").
/// tipo: 'orcamento', 'os' ou 'pmoc' (plano). valores (só OS): com ou sem os preços; null = padrão da empresa.
/// mes (só plano, "aaaa-mm"): o relatório de execução daquele mês, em vez do documento do plano.
Future<Uint8List> pdfDoServidor(String tipo, String id, {bool? valores, String? mes}) async {
  final r = await Supabase.instance.client.functions.invoke('relatorios',
      body: {'tipo': tipo, 'id': id, if (valores != null) 'valores': valores, if (mes != null) 'mes': mes});
  final d = r.data;
  if (d is Uint8List) return d;
  if (d is List<int>) return Uint8List.fromList(d);
  throw StateError('O servidor não devolveu o PDF.');
}

/// Botão "PDF" com as opções Ver e imprimir / Baixar.
class BotaoPdf extends StatefulWidget {
  const BotaoPdf({super.key, required this.tipo, required this.id, required this.nomeArquivo, this.rotulo = 'PDF'});

  final String tipo;
  final String id;
  final String nomeArquivo; // sem ".pdf"
  final String rotulo;

  @override
  State<BotaoPdf> createState() => _BotaoPdfState();
}

class _BotaoPdfState extends State<BotaoPdf> {
  bool _gerando = false;

  /// Plano (guia 56): escolhe o mês do relatório de execução (os 12 últimos).
  Future<String?> _escolherMes() {
    const nomes = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro',
      'novembro', 'dezembro'];
    final hoje = DateTime.now();
    final meses = [for (var i = 0; i < 12; i++) DateTime(hoje.year, hoje.month - i)];
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Relatório de execução de qual mês?'),
        children: [
          for (final m in meses)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop('${m.year}-${m.month.toString().padLeft(2, '0')}'),
              child: Text('${nomes[m.month - 1]} de ${m.year}'),
            ),
        ],
      ),
    );
  }

  /// opcao: 'ver' | 'baixar', com '-sem' quando é a OS sem os valores; 'mes' = relatório do mês (plano).
  Future<void> _abrir(String opcao) async {
    String? mes;
    if (opcao == 'mes') {
      mes = await _escolherMes();
      if (mes == null || !mounted) return;
    }
    final baixar = opcao.startsWith('baixar');
    final semValores = opcao.endsWith('-sem');
    setState(() => _gerando = true);
    try {
      final bytes =
          await pdfDoServidor(widget.tipo, widget.id, valores: widget.tipo == 'os' ? !semValores : null, mes: mes);
      final nome = '${widget.nomeArquivo}${semValores ? '-sem-valores' : ''}${mes != null ? '-execucao-$mes' : ''}';
      if (baixar) {
        await Printing.sharePdf(bytes: bytes, filename: '$nome.pdf');
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: nome);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(mensagemDeErro(e)), backgroundColor: Cores.erro));
      }
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final os = widget.tipo == 'os';
    return PopupMenuButton<String>(
      tooltip: widget.rotulo,
      enabled: !_gerando,
      onSelected: _abrir,
      itemBuilder: (_) => [
        PopupMenuItem(
            value: 'ver',
            child: ListTile(leading: const Icon(Icons.print_outlined), title: Text(os ? 'Ver e imprimir (com valores)' : 'Ver e imprimir'))),
        if (os)
          const PopupMenuItem(
              value: 'ver-sem', child: ListTile(leading: Icon(Icons.print_outlined), title: Text('Ver e imprimir (sem valores)'))),
        PopupMenuItem(
            value: 'baixar',
            child: ListTile(leading: const Icon(Icons.download_outlined), title: Text(os ? 'Baixar (com valores)' : 'Baixar'))),
        if (os)
          const PopupMenuItem(
              value: 'baixar-sem', child: ListTile(leading: Icon(Icons.download_outlined), title: Text('Baixar (sem valores)'))),
        if (widget.tipo == 'pmoc')
          const PopupMenuItem(
              value: 'mes',
              child: ListTile(leading: Icon(Icons.fact_check_outlined), title: Text('Relatório de execução do mês'))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: Cores.linha), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _gerando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.picture_as_pdf_outlined, size: 18, color: Cores.indigo500),
          const SizedBox(width: 8),
          Text(_gerando ? 'Gerando…' : widget.rotulo, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
