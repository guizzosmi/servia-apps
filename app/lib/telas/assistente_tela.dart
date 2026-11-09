import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_atendimento.dart';
import '../core/assistente.dart';
import '../core/consultas.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import '../widgets/entrar_no_servico.dart';

/// Uma troca da conversa: o pedido, a resposta e o que foi feito.
class _Troca {
  _Troca({this.pedido, this.porVoz = false});

  String? pedido;
  final bool porVoz;
  String? resposta;
  String? erro;
  List<Map<String, dynamic>> acoes = [];
  Map<String, dynamic>? confirmar;

  /// null (esperando o toque), 'confirmando', 'confirmado' ou 'cancelado'.
  String? situacaoConfirmar;
}

/// Assistente (guia 93): o técnico fala ou escreve e o Claude responde e faz
/// ("estou indo na OS 21", "cheguei", "adiciona um capacitor de 35 na OS",
/// "quais são minhas OS de amanhã"). Precisa de internet. As ações do próprio
/// app (a caminho, estou no serviço, peça no atendimento) rodam aqui, como o
/// botão, e sobem na sincronização.
class AssistenteTela extends StatefulWidget {
  const AssistenteTela({super.key, this.falarAoAbrir = false});

  /// Já abre gravando (o botão de microfone da tela Hoje).
  final bool falarAoAbrir;

  @override
  State<AssistenteTela> createState() => _AssistenteTelaState();
}

class _AssistenteTelaState extends State<AssistenteTela> {
  static const _sugestoes = [
    'Quais são minhas OS de amanhã?',
    'Estou indo para a próxima OS',
    'Cheguei no cliente',
    'Adiciona um capacitor de 35 na OS em que estou',
  ];

  /// Comando de voz: até 1 minuto.
  static const _maxVoz = Duration(seconds: 60);

  final _texto = TextEditingController();
  final _rolagem = ScrollController();
  final _gravador = AudioRecorder();
  final _relogio = Stopwatch();
  final List<_Troca> _conversa = [];
  Timer? _tique;
  String? _arquivo;
  bool _gravando = false;
  bool _parando = false;
  bool _pensando = false;

  @override
  void initState() {
    super.initState();
    if (widget.falarAoAbrir) WidgetsBinding.instance.addPostFrameCallback((_) => _microfone());
  }

  @override
  void dispose() {
    _tique?.cancel();
    if (_gravando) {
      unawaited(_gravador.cancel().catchError((_) {}).whenComplete(_gravador.dispose));
    } else {
      unawaited(_gravador.dispose());
    }
    _apagarArquivo();
    _texto.dispose();
    _rolagem.dispose();
    super.dispose();
  }

  void _apagarArquivo() {
    final a = _arquivo;
    _arquivo = null;
    if (a == null) return;
    try {
      File(a).deleteSync();
    } catch (_) {}
  }

  void _aviso(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  void _rolar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_rolagem.hasClients) {
        _rolagem.animateTo(_rolagem.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  static List<Map<String, dynamic>> _lista(Object? v) =>
      [for (final x in (v is List ? v : const [])) if (x is Map) Map<String, dynamic>.from(x)];

  List<Map<String, String>> _historico() {
    final h = <Map<String, String>>[];
    for (final c in _conversa) {
      if (c.erro != null || c.resposta == null) continue;
      if ((c.pedido ?? '').isNotEmpty) h.add({'papel': 'usuario', 'texto': c.pedido!});
      // O que ele consultou e fez naquela resposta vai junto: sem isso, ele acha que respondeu sem consultar.
      final feitas = c.acoes.where((a) => a['ok'] == true).map((a) => '${a['resumo'] ?? a['ferramenta']}').toSet();
      h.add({
        'papel': 'assistente',
        'texto': feitas.isEmpty ? c.resposta! : '${c.resposta!}\n[Ferramentas usadas: ${feitas.join(', ')}]',
      });
    }
    return h.length > 10 ? h.sublist(h.length - 10) : h;
  }

  // ------------------------------------------------------------------ pedido

  Future<void> _enviar({String? texto, String? audioBase64}) async {
    final t = (texto ?? _texto.text).trim();
    if (_pensando || (audioBase64 == null && t.length < 2)) return;
    final historico = _historico();
    if (audioBase64 == null) _texto.clear();
    FocusScope.of(context).unfocus();
    final troca = _Troca(pedido: audioBase64 == null ? t : null, porVoz: audioBase64 != null);
    setState(() {
      _pensando = true;
      _conversa.add(troca);
    });
    _rolar();
    Map<String, dynamic>? app;
    try {
      final m = await Assistente.pedir(
        texto: audioBase64 == null ? t : null,
        audioBase64: audioBase64,
        mensagens: historico,
      );
      troca
        ..pedido = troca.pedido ?? '${m['transcricao'] ?? ''}'
        ..resposta = '${m['resposta'] ?? ''}'
        ..acoes = _lista(m['acoes'])
        ..confirmar = m['confirmar'] is Map ? Map<String, dynamic>.from(m['confirmar'] as Map) : null;
      if (m['app'] is Map) app = Map<String, dynamic>.from(m['app'] as Map);
    } catch (e) {
      troca.erro = _semInternet(e)
          ? 'Sem internet: o assistente precisa de conexão. O resto do app continua funcionando offline.'
          : mensagemDeErro(e);
    }
    if (!mounted) return;
    setState(() => _pensando = false);
    _rolar();
    if (app != null) await _executarNoApp(troca, app);
  }

  static bool _semInternet(Object e) {
    final t = e.toString();
    return e is TimeoutException ||
        e is SocketException ||
        t.contains('SocketException') ||
        t.contains('ClientException') ||
        t.contains('Failed host lookup');
  }

  Future<void> _confirmar(_Troca c) async {
    final pend = c.confirmar;
    if (pend == null || c.situacaoConfirmar != null) return;
    setState(() => c.situacaoConfirmar = 'confirmando');
    final nova = _Troca(pedido: 'Confirmo: ${pend['resumo'] ?? pend['ferramenta']}');
    try {
      final m = await Assistente.confirmar(pend);
      nova
        ..resposta = '${m['resposta'] ?? ''}'
        ..acoes = _lista(m['acoes']);
      c.situacaoConfirmar = 'confirmado';
    } catch (e) {
      nova.erro = mensagemDeErro(e);
      c.situacaoConfirmar = null;
    }
    if (!mounted) return;
    setState(() => _conversa.add(nova));
    _rolar();
  }

  // ------------------------------------------------------------------ ações do app

  /// Faz no celular o que o assistente pediu, como se o técnico tocasse no botão.
  Future<void> _executarNoApp(_Troca troca, Map<String, dynamic> app) async {
    final banco = EstadoApp.instancia.banco;
    final args = app['argumentos'] is Map ? Map<String, dynamic>.from(app['argumentos'] as Map) : <String, dynamic>{};
    final item = banco?.um('partes_itens', args['item_id']);
    void registrar(bool ok, String resumo) {
      if (!mounted) return;
      setState(() => troca.acoes = [
            ...troca.acoes,
            {'ferramenta': 'app_${app['acao']}', 'ok': ok, 'escreve': true, 'resumo': resumo},
          ]);
    }

    if (banco == null || item == null) {
      registrar(false, 'Este serviço não está no seu celular. Sincronize e tente de novo.');
      return;
    }
    final os = codigoOs(banco.osDo(item));
    final parte = banco.um('partes_diarias', item['parte_id']) ?? const <String, dynamic>{};
    final aberta = parte['status'] == 'publicada' || parte['status'] == 'em_andamento';
    final status = '${item['status']}';
    final encerrado = status == 'concluido' || status == 'nao_realizado' || status == 'removido';
    final atd = banco.atendimentoDoItem(item['id']);
    final atdAberto = atd != null && (atd['status'] == 'em_andamento' || atd['status'] == 'pausado');

    switch (app['acao']) {
      case 'a_caminho':
        if (!aberta || status != 'programado') {
          registrar(false, '$os: "a caminho" só vale para serviço programado de parte publicada.');
          return;
        }
        await AcoesAtendimento.mudarStatus(item, 'em_deslocamento');
        registrar(true, 'A caminho · $os');
        if (!mounted) return;
        await avisarACaminho(context, item);
      case 'estou_no_servico':
        if (!aberta || encerrado) {
          registrar(false, '$os: este serviço não aceita check-in agora.');
          return;
        }
        final entrou = await entrarNoServico(context, item);
        registrar(entrou, entrou ? 'Estou no serviço · $os' : 'Check-in não feito · $os');
      case 'incluir_item':
        if (atd == null || !atdAberto) {
          registrar(false, '$os: entre no serviço antes ("Estou neste serviço") para incluir peças.');
          return;
        }
        final produto = args['produto_id'] == null ? null : banco.um('produtos', args['produto_id']);
        final descricao = '${args['descricao'] ?? ''}'.trim();
        final qtd = args['quantidade'] is num ? args['quantidade'] as num : num.tryParse('${args['quantidade']}') ?? 0;
        if (qtd <= 0 || (produto == null && descricao.isEmpty)) {
          registrar(false, 'Faltou a peça ou a quantidade.');
          return;
        }
        // Peça com número de série: inclui pela aba Peças, onde o app pede a série.
        if (produto != null && '${produto['controla_serie'] ?? 'nao'}' != 'nao') {
          registrar(false, '${produto['descricao']} pede número de série: inclua pela aba Peças do atendimento.');
          if (mounted) await context.push('/atendimento/${atd['id']}');
          return;
        }
        await AcoesAtendimento.salvarItem(atd, produto: produto, descricao: produto == null ? descricao : null, quantidade: qtd);
        registrar(true, 'Incluído · ${qtd.toString().replaceAll(RegExp(r'\.0$'), '')} ${produto?['descricao'] ?? descricao} · $os');
      case 'abrir':
        registrar(true, 'Abrindo · $os');
        if (!mounted) return;
        if (args['tela'] == 'atendimento' && atd != null) {
          await context.push('/atendimento/${atd['id']}');
        } else {
          await context.push('/servico/${item['id']}');
        }
      default:
        registrar(false, 'Ação do app desconhecida: atualize o app.');
    }
  }

  // ------------------------------------------------------------------ voz

  Future<void> _microfone() async {
    if (_pensando || _parando) return;
    if (_gravando) {
      await _pararEEnviar();
      return;
    }
    try {
      if (!await _gravador.hasPermission()) {
        if (mounted) _aviso('Permita o microfone para o ServPilot nas configurações do celular.');
        return;
      }
      final pasta = await getTemporaryDirectory();
      _apagarArquivo();
      final arquivo = p.join(pasta.path, 'assistente_${DateTime.now().millisecondsSinceEpoch}.m4a');
      _arquivo = arquivo;
      await _gravador.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1),
        path: arquivo,
      );
    } catch (e) {
      if (mounted) _aviso('Não deu para gravar: $e');
      return;
    }
    if (!mounted) {
      try {
        await _gravador.cancel();
      } catch (_) {}
      return;
    }
    _relogio
      ..reset()
      ..start();
    _tique = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (_relogio.elapsed >= _maxVoz) {
        _pararEEnviar();
      } else {
        setState(() {});
      }
    });
    setState(() => _gravando = true);
  }

  Future<void> _pararEEnviar() async {
    if (_parando || !_gravando) return;
    _parando = true;
    _tique?.cancel();
    _relogio.stop();
    String? caminho;
    try {
      caminho = await _gravador.stop();
    } catch (_) {}
    _gravando = false;
    _parando = false;
    final arquivo = caminho ?? _arquivo;
    if (!mounted) return;
    setState(() {});
    if (arquivo == null || _relogio.elapsed < const Duration(milliseconds: 700)) {
      _apagarArquivo();
      _aviso('Gravação curta demais. Toque no microfone, fale e toque de novo para enviar.');
      return;
    }
    List<int> bytes;
    try {
      bytes = await File(arquivo).readAsBytes();
    } catch (e) {
      if (mounted) _aviso('Não deu para ler a gravação: $e');
      return;
    } finally {
      _arquivo = arquivo;
      _apagarArquivo();
    }
    if (!mounted) return;
    await _enviar(audioBase64: base64Encode(bytes));
  }

  Future<void> _cancelarGravacao() async {
    _tique?.cancel();
    _relogio.stop();
    try {
      await _gravador.cancel();
    } catch (_) {}
    _apagarArquivo();
    if (mounted) setState(() => _gravando = false);
  }

  // ------------------------------------------------------------------ tela

  Widget _chipAcao(Map<String, dynamic> a) {
    final ok = a['ok'] == true;
    return Chip(
      avatar: Icon(ok ? Icons.check_circle_outline : Icons.error_outline, size: 18, color: ok ? Cores.sucesso : Cores.erro),
      label: Text('${a['resumo'] ?? a['ferramenta']}'),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: ok ? Cores.sucesso : Cores.erro),
    );
  }

  Widget _confirmacao(_Troca c) {
    final pend = c.confirmar!;
    final s = c.situacaoConfirmar;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        border: Border.all(color: Cores.alerta),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${pend['resumo'] ?? pend['ferramenta']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        switch (s) {
          'confirmado' => const Text('Confirmado.', style: TextStyle(color: Cores.sucesso)),
          'cancelado' => const Text('Cancelado: nada foi feito.', style: TextStyle(color: Cores.neutro)),
          _ => Row(children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Cores.alerta, minimumSize: const Size(0, 48)),
                  onPressed: s == null ? () => _confirmar(c) : null,
                  child: Text(s == 'confirmando' ? 'Confirmando...' : 'Confirmar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: s == null ? () => setState(() => c.situacaoConfirmar = 'cancelado') : null,
                  child: const Text('Cancelar'),
                ),
              ),
            ]),
        },
      ]),
    );
  }

  Widget _bolha(_Troca c) {
    final feitas = c.acoes.where((a) => a['escreve'] == true || a['ok'] != true).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 12, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: Cores.indigo100, borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (c.porVoz) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.mic, size: 16)),
            Flexible(child: Text(c.pedido ?? (c.erro == null ? 'Ouvindo o áudio...' : 'Áudio'))),
          ]),
        ),
      ),
      Container(
        margin: const EdgeInsets.only(top: 8, right: 40),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Cores.linha),
          borderRadius: BorderRadius.circular(14),
        ),
        child: c.erro != null
            ? Text(c.erro!, style: const TextStyle(color: Cores.erro))
            : c.resposta == null
                ? const Row(children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Trabalhando no pedido...', style: TextStyle(color: Cores.neutro)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.resposta!, style: const TextStyle(height: 1.4, fontSize: 15)),
                    if (feitas.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 4, children: [for (final a in feitas) _chipAcao(a)]),
                    ],
                    if (c.confirmar != null) _confirmacao(c),
                  ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = _relogio.elapsed.inSeconds;
    return Scaffold(
      appBar: AppBar(title: const Text('Assistente')),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: _conversa.isEmpty
                ? ListView(padding: const EdgeInsets.all(16), children: [
                    const Text('Fale ou escreva o que precisa. Ele consulta suas OS e faz por você o que o app faz.',
                        style: TextStyle(color: Cores.neutro)),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final x in _sugestoes) ActionChip(label: Text(x), onPressed: () => _enviar(texto: x)),
                    ]),
                    const SizedBox(height: 12),
                    const Text('Precisa de internet. O áudio não fica guardado.',
                        style: TextStyle(color: Cores.neutro, fontSize: 12)),
                  ])
                : ListView(
                    controller: _rolagem,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [for (final c in _conversa) _bolha(c)],
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _gravando
                ? Row(children: [
                    const Icon(Icons.fiber_manual_record, color: Cores.coral500),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Gravando ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}')),
                    TextButton(onPressed: _cancelarGravacao, child: const Text('Cancelar')),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Cores.coral500),
                        onPressed: _pararEEnviar,
                        icon: const Icon(Icons.send),
                        label: const Text('Enviar'),
                      ),
                    ),
                  ])
                : Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _texto,
                        minLines: 1,
                        maxLines: 3,
                        maxLength: 1000,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _enviar(),
                        decoration: const InputDecoration(hintText: 'Escreva o pedido', counterText: ''),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Enviar',
                      onPressed: _pensando ? null : () => _enviar(),
                      icon: const Icon(Icons.send),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 60,
                      height: 60,
                      child: FloatingActionButton(
                        heroTag: 'assistente-falar',
                        tooltip: 'Falar',
                        backgroundColor: Cores.coral500,
                        foregroundColor: Colors.white,
                        onPressed: _pensando ? null : _microfone,
                        child: _pensando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.mic, size: 30),
                      ),
                    ),
                  ]),
          ),
        ]),
      ),
    );
  }
}
