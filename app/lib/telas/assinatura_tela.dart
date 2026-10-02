import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_orcamento.dart';
import '../core/formatos.dart';
import '../core/resumo.dart';

/// Tela cheia, com o aparelho deitado: o cliente vê o resumo, informa o
/// nome e assina com o dedo. Devolve a [Decisao] (ou null, se voltou).
///
/// [pedirConcordo]: o orçamento pede "Li e concordo" antes de aprovar.
/// [permitirRecusa]: o orçamento permite registrar a recusa (com motivo).
class AssinaturaTela extends StatefulWidget {
  const AssinaturaTela({
    super.key,
    required this.conteudo,
    this.nomeInicial,
    this.pedirConcordo = false,
    this.permitirRecusa = false,
    this.decisaoAoAssinar = 'aprovado',
    this.botaoAssinar = 'Aprovar e assinar',
  });

  final ConteudoResumo conteudo;
  final String? nomeInicial;
  final bool pedirConcordo;
  final bool permitirRecusa;
  final String decisaoAoAssinar; // aprovado | ciente
  final String botaoAssinar;

  /// Abre a tela e devolve o que o cliente decidiu.
  static Future<Decisao?> abrir(BuildContext context, AssinaturaTela tela) =>
      Navigator.of(context).push<Decisao>(MaterialPageRoute(builder: (_) => tela, fullscreenDialog: true));

  @override
  State<AssinaturaTela> createState() => _AssinaturaTelaState();
}

class _AssinaturaTelaState extends State<AssinaturaTela> {
  final _nome = TextEditingController();
  final _documento = TextEditingController();
  final _quadro = GlobalKey<_QuadroAssinaturaState>();
  bool _concordo = false;
  bool _gravando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _nome.text = widget.nomeInicial ?? '';
    // Deitado: mais espaço para assinar.
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    _nome.dispose();
    _documento.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    FocusScope.of(context).unfocus();
    if (_nome.text.trim().isEmpty) {
      setState(() => _erro = 'Informe o nome de quem assina.');
      return;
    }
    if (widget.pedirConcordo && !_concordo) {
      setState(() => _erro = 'Marque "Li e concordo" para aprovar.');
      return;
    }
    final quadro = _quadro.currentState!;
    if (!quadro.assinado) {
      setState(() => _erro = 'Assine no quadro, com o dedo.');
      return;
    }
    setState(() {
      _erro = null;
      _gravando = true;
    });
    try {
      final png = await quadro.png();
      if (!mounted) return;
      Navigator.of(context).pop(Decisao(
        nome: _nome.text.trim(),
        documento: _documento.text.trim().isEmpty ? null : _documento.text.trim(),
        png: png,
        decisao: widget.decisaoAoAssinar,
      ));
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não foi possível gravar a assinatura: $e');
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  Future<void> _recusar() async {
    FocusScope.of(context).unfocus();
    if (_nome.text.trim().isEmpty) {
      setState(() => _erro = 'Informe o nome de quem recusou.');
      return;
    }
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar a recusa?'),
        content: TextField(
          controller: motivo,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Cores.erro),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Registrar recusa'),
          ),
        ],
      ),
    );
    // Sem dispose: o diálogo ainda anima a saída usando o campo.
    if (!mounted) return;
    if (ok != true) return;
    Navigator.of(context).pop(Decisao(
      nome: _nome.text.trim(),
      documento: _documento.text.trim().isEmpty ? null : _documento.text.trim(),
      decisao: 'reprovado',
      motivo: motivo.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conteudo;
    return Scaffold(
      // O teclado não encolhe o quadro (senão a assinatura sai cortada).
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        toolbarHeight: 48,
        title: Text('${c.titulo} · ${c.subtitulo}', style: const TextStyle(fontSize: 16)),
      ),
      body: SafeArea(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Esquerda: o que o cliente está assinando.
          Expanded(flex: 5, child: ResumoNaTela(conteudo: c)),
          const VerticalDivider(width: 1),
          // Direita: nome, "li e concordo", quadro e botões.
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _nome,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nome de quem assina'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _documento,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'CPF (opcional)'),
                    ),
                  ),
                ]),
                if (widget.pedirConcordo)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _concordo,
                    onChanged: (v) => setState(() => _concordo = v ?? false),
                    title: const Text('Li e concordo com o orçamento e o termo de aceite'),
                  )
                else
                  const SizedBox(height: 8),
                Expanded(child: QuadroAssinatura(key: _quadro)),
                if (_erro != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_erro!, style: const TextStyle(color: Cores.erro, fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 6),
                Row(children: [
                  TextButton.icon(
                    onPressed: () => _quadro.currentState?.limpar(),
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('Limpar'),
                  ),
                  const Spacer(),
                  if (widget.permitirRecusa) ...[
                    OutlinedButton(
                      onPressed: _gravando ? null : _recusar,
                      child: const Text('Recusar', style: TextStyle(color: Cores.erro)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton.icon(
                    onPressed: _gravando ? null : _confirmar,
                    icon: _gravando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.draw_outlined),
                    label: Text(widget.botaoAssinar),
                  ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// O resumo como o cliente vê na tela (o mesmo conteúdo do PDF).
class ResumoNaTela extends StatelessWidget {
  const ResumoNaTela({super.key, required this.conteudo});

  final ConteudoResumo conteudo;

  @override
  Widget build(BuildContext context) {
    final c = conteudo;
    const rotulo = TextStyle(fontSize: 12, color: Cores.neutro);
    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(t.toUpperCase(),
              style: const TextStyle(fontSize: 11, letterSpacing: .6, fontWeight: FontWeight.w800, color: Cores.indigo700)),
        );
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text('${c.empresa['nome'] ?? ''}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Cores.indigo700)),
      for (final (r, v) in c.campos)
        if (v.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$r: ', style: rotulo),
              TextSpan(text: v, style: const TextStyle(fontSize: 13)),
            ])),
          ),
      for (final (t, txt) in c.blocos)
        if (txt.trim().isNotEmpty) ...[titulo(t), Text(txt, style: const TextStyle(fontSize: 13))],
      if (c.itens.isNotEmpty) ...[
        titulo(c.comValores ? 'Itens' : 'Peças e serviços'),
        for (final i in c.itens)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: i.descricao, style: const TextStyle(fontSize: 13)),
                  TextSpan(
                    text: '  ${i.quantidade}'
                        '${c.comValores ? ' × ${dinheiro(i.unitario)}' : ''}'
                        '${c.comValores && (i.desconto ?? 0) > 0 ? ' − ${dinheiro(i.desconto)}' : ''}',
                    style: rotulo,
                  ),
                ])),
              ),
              if (c.comValores)
                Text(dinheiro(i.total), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
          ),
      ],
      if (c.totais.isNotEmpty) ...[
        const Divider(),
        for (var k = 0; k < c.totais.length; k++)
          Row(children: [
            Expanded(
              child: Text(c.totais[k].$1,
                  textAlign: TextAlign.right,
                  style: k == c.totais.length - 1 ? const TextStyle(fontSize: 17, fontWeight: FontWeight.w800) : rotulo),
            ),
            const SizedBox(width: 12),
            Text(c.totais[k].$2,
                style: k == c.totais.length - 1
                    ? const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Cores.indigo700)
                    : const TextStyle(fontSize: 13)),
          ]),
      ],
      if (c.termo != null) ...[
        titulo(c.comValores ? 'Termo de aceite' : 'Declaração'),
        Text(c.termo!, style: const TextStyle(fontSize: 12, color: Cores.neutro)),
      ],
    ]);
  }
}

/// Quadro para assinar com o dedo. Gera um PNG (traço preto em fundo branco).
class QuadroAssinatura extends StatefulWidget {
  const QuadroAssinatura({super.key});

  @override
  State<QuadroAssinatura> createState() => _QuadroAssinaturaState();
}

class _QuadroAssinaturaState extends State<QuadroAssinatura> {
  final List<List<Offset>> _tracos = [];

  /// Algo de verdade foi desenhado (não só um toque).
  bool get assinado {
    var comprimento = 0.0;
    for (final t in _tracos) {
      for (var i = 1; i < t.length; i++) {
        comprimento += (t[i] - t[i - 1]).distance;
      }
    }
    return comprimento > 60;
  }

  void limpar() => setState(_tracos.clear);

  /// A assinatura como PNG, no dobro da resolução da tela (recortada nas bordas do desenho).
  Future<Uint8List> png() async {
    const escala = 2.0;
    var minX = double.infinity, minY = double.infinity, maxX = 0.0, maxY = 0.0;
    for (final t in _tracos) {
      for (final p in t) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
    }
    // Recorte pelas bordas do próprio desenho (com uma folga).
    const margem = 12.0;
    final origem = Offset(minX - margem < 0 ? 0 : minX - margem, minY - margem < 0 ? 0 : minY - margem);
    final w = (maxX + margem - origem.dx).clamp(1.0, 4000.0).toDouble();
    final h = (maxY + margem - origem.dy).clamp(1.0, 4000.0).toDouble();
    final gravador = ui.PictureRecorder();
    final canvas = Canvas(gravador)
      ..scale(escala)
      ..drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white)
      ..translate(-origem.dx, -origem.dy);
    _PintorAssinatura.desenhar(canvas, _tracos);
    final desenho = gravador.endRecording();
    final imagem = await desenho.toImage((w * escala).ceil(), (h * escala).ceil());
    try {
      final dados = await imagem.toByteData(format: ui.ImageByteFormat.png);
      return dados!.buffer.asUint8List();
    } finally {
      imagem.dispose();
      desenho.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Cores.indigo500, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GestureDetector(
            onPanStart: (d) => setState(() => _tracos.add([d.localPosition])),
            onPanUpdate: (d) => setState(() => _tracos.last.add(d.localPosition)),
            child: CustomPaint(
              painter: _PintorAssinatura(_tracos, _tracos.fold<int>(0, (s, t) => s + t.length)),
              child: _tracos.isEmpty
                  ? const Center(
                      child: Text('Assine aqui com o dedo', style: TextStyle(color: Cores.neutro, fontSize: 16)),
                    )
                  : const SizedBox.expand(),
            ),
          ),
        ),
      );
  }
}

class _PintorAssinatura extends CustomPainter {
  _PintorAssinatura(this.tracos, this.pontos);

  final List<List<Offset>> tracos;
  final int pontos; // muda a cada ponto novo: redesenha

  static void desenhar(Canvas canvas, List<List<Offset>> tracos) {
    final pincel = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final t in tracos) {
      if (t.length == 1) {
        canvas.drawCircle(t.first, 1.3, pincel..style = PaintingStyle.fill);
        pincel.style = PaintingStyle.stroke;
        continue;
      }
      final caminho = Path()..moveTo(t.first.dx, t.first.dy);
      for (var i = 1; i < t.length; i++) {
        // Curva suave entre os pontos (meio do caminho).
        final meio = Offset((t[i - 1].dx + t[i].dx) / 2, (t[i - 1].dy + t[i].dy) / 2);
        caminho.quadraticBezierTo(t[i - 1].dx, t[i - 1].dy, meio.dx, meio.dy);
      }
      caminho.lineTo(t.last.dx, t.last.dy);
      canvas.drawPath(caminho, pincel);
    }
  }

  @override
  void paint(Canvas canvas, Size size) => desenhar(canvas, tracos);

  @override
  bool shouldRepaint(_PintorAssinatura antigo) => antigo.pontos != pontos || antigo.tracos.length != tracos.length;
}
