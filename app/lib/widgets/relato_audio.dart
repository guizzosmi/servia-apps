import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_relato.dart';
import '../core/arquivos.dart';
import '../core/consultas.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import '../telas/revisao_relato_tela.dart';
import 'status_chip.dart';

const _statusRelato = {
  'aguardando_envio': Rotulo('Aguardando envio', Cores.neutro),
  'recusado': Rotulo('Recusado', Cores.erro),
  'enviado': Rotulo('Na fila da IA', Cores.info),
  'processando': Rotulo('A IA está organizando', Cores.andamento),
  'pronto': Rotulo('Pronto para revisar', Cores.sucesso),
  'erro': Rotulo('Erro', Cores.erro),
  'revisado': Rotulo('Revisado', Cores.indigo700),
};

/// '83 s' -> '1:23'
String duracaoCurta(num? segundos) {
  if (segundos == null) return '';
  final s = segundos.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Relatos por áudio do atendimento (no alto da aba Relato): gravar e ver
/// a situação de cada um. A IA organiza depois que o áudio sobe.
class RelatosDoAtendimento extends StatelessWidget {
  const RelatosDoAtendimento({super.key, required this.atd, required this.habilitado, this.antesDeRevisar});

  final Map<String, dynamic> atd;
  final bool habilitado;

  /// Grava o que foi digitado no relato antes de abrir a revisão (o texto da
  /// IA entra embaixo do que já está escrito).
  final Future<void> Function()? antesDeRevisar;

  Future<void> _gravar(BuildContext context) async {
    final gravado = await Navigator.of(context).push<(String, Duration)>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const GravadorRelatoTela()),
    );
    if (gravado == null) return;
    // (registra mesmo se a tela mudou enquanto gravava: nada se perde)
    final (arquivo, duracao) = gravado;
    await AcoesRelato.registrar(atd,
        audioId: p.basenameWithoutExtension(arquivo), arquivoLocal: arquivo, duracao: duracao);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Relato guardado. Ele sobe com a sincronização e a IA organiza em seguida.')));
  }

  @override
  Widget build(BuildContext context) {
    final relatos = AcoesRelato.doAtendimento(atd);
    final ligado = AcoesRelato.ligado;
    if (!ligado && relatos.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Icon(Icons.mic_none, color: Cores.coral500),
            SizedBox(width: 8),
            Text('Relato por áudio', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          if (ligado && habilitado) ...[
            const SizedBox(height: 4),
            const Text('Fale o que encontrou e o que fez. A IA escreve o relato, separa as peças e acha o equipamento.',
                style: TextStyle(color: Cores.neutro, fontSize: 13)),
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Cores.coral500),
                onPressed: () => _gravar(context),
                icon: const Icon(Icons.mic),
                label: const Text('Gravar relato'),
              ),
            ),
          ],
          for (final r in relatos) _ItemRelato(r, atd: atd, habilitado: habilitado, antesDeRevisar: antesDeRevisar),
        ]),
      ),
    );
  }
}

class _ItemRelato extends StatelessWidget {
  const _ItemRelato(this.r, {required this.atd, required this.habilitado, this.antesDeRevisar});
  final RelatoAudio r;
  final Map<String, dynamic> atd;
  final bool habilitado;
  final Future<void> Function()? antesDeRevisar;

  Future<void> _revisar(BuildContext context) async {
    await antesDeRevisar?.call();
    if (!context.mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RevisaoRelatoTela(atd: atd, relato: r)),
    );
  }

  Future<void> _descartar(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar este relato?'),
        content: const Text('Ele sai da lista. O áudio continua registrado na plataforma.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Descartar', style: TextStyle(color: Cores.erro)),
          ),
        ],
      ),
    );
    if (ok == true) await AcoesRelato.descartar(r.id);
  }

  @override
  Widget build(BuildContext context) {
    final campos = r.resultado?['campos'] is Map ? (r.resultado!['campos'] as Map) : const {};
    final itens = r.resultado?['itens'] is List ? (r.resultado!['itens'] as List).whereType<Map>().toList() : const <Map>[];
    final eq = r.resultado?['equipamento'] is Map ? (r.resultado!['equipamento'] as Map) : const {};
    final esperandoIa = AcoesRelato.aguardandoIa(r.id);
    final podeTentar = !esperandoIa && (r.status == 'erro' || r.status == 'enviado' || r.status == 'processando');
    final banco = EstadoApp.instancia.banco!;

    String? linha(String rotulo, Object? v) {
      final t = '${v ?? ''}'.trim();
      return t.isEmpty ? null : '$rotulo: $t';
    }

    final resumo = [
      linha('Problema', campos['problema_identificado']),
      linha('Solução', campos['solucao']),
      if (itens.isNotEmpty) 'Peças: ${itens.map((i) => '${i['falado'] ?? i['nome'] ?? ''}').join(', ')}',
      linha('Equipamento', eq['texto']),
    ].whereType<String>().toList();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Divider(height: 1),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(dataHoraBr(r.gravadoEm), style: const TextStyle(fontWeight: FontWeight.w700)),
          if (r.duracaoS != null) Text(duracaoCurta(r.duracaoS), style: const TextStyle(color: Cores.neutro)),
          StatusChip(r.status, _statusRelato),
        ]),
        if (r.gravadoPor != null && r.gravadoPor != EstadoApp.instancia.conta?.colaboradorId)
          Text('Gravado por ${banco.nomeColaborador(r.gravadoPor)}',
              style: const TextStyle(color: Cores.neutro, fontSize: 12)),
        const SizedBox(height: 4),
        switch (r.status) {
          'aguardando_envio' => const Text('Fica no celular e sobe quando houver internet.',
              style: TextStyle(color: Cores.neutro, fontSize: 13)),
          'recusado' => Text(r.erro ?? 'A plataforma recusou este relato.',
              style: const TextStyle(color: Cores.erro, fontSize: 13)),
          'enviado' || 'processando' => Text(
              esperandoIa ? 'Transcrevendo e organizando (uns segundos com internet)...' : 'Aguardando a IA.',
              style: const TextStyle(color: Cores.neutro, fontSize: 13)),
          'erro' => Text(r.erro ?? 'A IA não conseguiu organizar este relato.',
              style: const TextStyle(color: Cores.erro, fontSize: 13)),
          _ => resumo.isEmpty
              ? const Text('A IA não encontrou nada para o relato.', style: TextStyle(color: Cores.neutro, fontSize: 13))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final l in resumo) Text(l, style: const TextStyle(fontSize: 13))],
                ),
        },
        if (podeTentar || (r.status == 'erro' && habilitado))
          Wrap(spacing: 8, children: [
            if (podeTentar)
              TextButton.icon(
                onPressed: () => AcoesRelato.processarDeNovo(r.id),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Tentar de novo'),
              ),
            if (r.status == 'erro' && habilitado)
              TextButton(
                onPressed: () => _descartar(context),
                child: const Text('Descartar', style: TextStyle(color: Cores.erro)),
              ),
          ]),
        if (r.status == 'pronto' && habilitado)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: () => _revisar(context),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Revisar e levar para o atendimento'),
              ),
            ),
          ),
        if (r.status == 'pronto' && !habilitado)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Atendimento encerrado: a revisão não está mais disponível no app.',
                style: TextStyle(color: Cores.neutro, fontSize: 12)),
          ),
      ]),
    );
  }
}

enum _Fase { preparando, semPermissao, gravando, pausado, terminado }

/// Tela de gravação: até 10 minutos, com pausa. "Terminar e enviar" já
/// devolve (arquivo, duração); gravação curta demais fica na tela para
/// gravar de novo ou descartar.
class GravadorRelatoTela extends StatefulWidget {
  const GravadorRelatoTela({super.key, this.abertura = false});

  /// Gravando para abrir uma OS (o título e a dica mudam).
  final bool abertura;

  @override
  State<GravadorRelatoTela> createState() => _GravadorRelatoTelaState();
}

class _GravadorRelatoTelaState extends State<GravadorRelatoTela> {
  final _gravador = AudioRecorder();
  final _relogio = Stopwatch();
  Timer? _tique;
  StreamSubscription<Amplitude>? _nivelSub;
  StreamSubscription<RecordState>? _estadoSub;
  double _nivel = 0;
  _Fase _fase = _Fase.preparando;
  String? _arquivo;
  String? _erro;
  bool _enviado = false;

  /// "Terminar e enviar" já foi tocado (ou o limite de 10 minutos chegou).
  bool _parando = false;

  @override
  void initState() {
    super.initState();
    _comecar();
  }

  @override
  void dispose() {
    _tique?.cancel();
    _nivelSub?.cancel();
    _estadoSub?.cancel();
    Arquivos.audioEmUso = null;
    // Saiu sem enviar: a gravação não fica no celular.
    if (_enviado) {
      unawaited(_gravador.dispose());
    } else {
      unawaited(_jogarFora().whenComplete(_gravador.dispose));
    }
    super.dispose();
  }

  Future<void> _jogarFora() async {
    try {
      if (_fase == _Fase.gravando || _fase == _Fase.pausado) await _gravador.cancel();
    } catch (_) {}
    final a = _arquivo;
    if (a != null) {
      try {
        await File(a).delete();
      } catch (_) {}
    }
  }

  Future<void> _comecar() async {
    setState(() {
      _fase = _Fase.preparando;
      _erro = null;
    });
    try {
      if (!await _gravador.hasPermission()) {
        if (mounted) setState(() => _fase = _Fase.semPermissao);
        return;
      }
      final pasta = await Arquivos.pastaAudios();
      await pasta.create(recursive: true);
      final arquivo = p.join(pasta.path, '${AcoesRelato.novoId()}.m4a');
      // AAC (m4a), mono: uns 480 KB por minuto, bom para a transcrição.
      Arquivos.audioEmUso = arquivo;
      _arquivo = arquivo;
      await _gravador.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1),
        path: arquivo,
      );
      if (!mounted) {
        // Saiu da tela enquanto o microfone abria.
        try {
          await _gravador.cancel();
        } catch (_) {}
        return;
      }
      // Ligação ou outro app pegou o microfone: a gravação pausa sozinha.
      await _estadoSub?.cancel();
      _estadoSub = _gravador.onStateChanged().listen((estado) {
        if (!mounted) return;
        if (estado == RecordState.pause && _fase == _Fase.gravando) {
          _relogio.stop();
          setState(() => _fase = _Fase.pausado);
        } else if (estado == RecordState.record && _fase == _Fase.pausado) {
          _relogio.start();
          setState(() => _fase = _Fase.gravando);
        }
      });
      _relogio
        ..reset()
        ..start();
      _nivelSub = _gravador.onAmplitudeChanged(const Duration(milliseconds: 200)).listen((a) {
        // dBFS: -60 (silêncio) a 0 (máximo)
        final v = ((a.current + 60) / 60).clamp(0.0, 1.0);
        if (mounted) setState(() => _nivel = v);
      });
      _tique = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        if (_relogio.elapsed >= AcoesRelato.duracaoMaxima && _fase == _Fase.gravando) {
          _parar(limite: true);
        } else {
          setState(() {});
        }
      });
      if (mounted) setState(() => _fase = _Fase.gravando);
    } catch (e) {
      if (mounted) {
        setState(() {
          _fase = _Fase.semPermissao;
          _erro = 'Não deu para gravar: $e';
        });
      }
    }
  }

  Future<void> _pausar() async {
    _relogio.stop();
    await _gravador.pause();
    if (!mounted) return;
    setState(() => _fase = _Fase.pausado);
  }

  Future<void> _continuar() async {
    await _gravador.resume();
    _relogio.start();
    if (!mounted) return;
    setState(() => _fase = _Fase.gravando);
  }

  Future<void> _parar({bool limite = false}) async {
    if (_parando) return;
    _parando = true;
    _relogio.stop();
    _tique?.cancel();
    await _nivelSub?.cancel();
    _nivelSub = null;
    await _estadoSub?.cancel();
    _estadoSub = null;
    final caminho = await _gravador.stop();
    if (caminho != null) _arquivo = caminho;
    if (!mounted) return;
    // Terminou: já vai para a IA (um toque a menos). Curta demais: fica aqui
    // para gravar de novo ou descartar.
    if (_relogio.elapsed >= AcoesRelato.duracaoMinima) {
      if (limite) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Chegou a 10 minutos: a gravação foi enviada.')));
      }
      _enviar();
      return;
    }
    setState(() {
      _fase = _Fase.terminado;
      _nivel = 0;
      _parando = false;
    });
  }

  Future<void> _deNovo() async {
    await _jogarFora();
    _arquivo = null;
    await _comecar();
  }

  void _enviar() {
    final a = _arquivo;
    if (a == null || _enviado) return;
    _enviado = true;
    Navigator.of(context).pop((a, _relogio.elapsed));
  }

  Future<bool> _confirmarSaida() async {
    if (_fase == _Fase.preparando || _fase == _Fase.semPermissao) return true;
    final sair = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar a gravação?'),
        content: const Text('O que foi gravado será apagado.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Descartar', style: TextStyle(color: Cores.erro)),
          ),
        ],
      ),
    );
    return sair == true;
  }

  @override
  Widget build(BuildContext context) {
    final tempo = _relogio.elapsed;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmarSaida() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.abertura ? 'Falar a OS' : 'Relato por áudio')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Cores.indigo100, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  widget.abertura
                      ? 'Comece dizendo onde está e o que vai fazer:\n'
                          '"Estou na Friella da Cacic, trocando a torneira do bebedouro do refeitório."\n\n'
                          'Se o serviço já foi feito, conte também o que encontrou e o que fez: '
                          'o mesmo áudio vira o relato.'
                      : 'Fale com calma:\n'
                          '• onde: o local, a sala e o equipamento;\n'
                          '• o que encontrou e a causa;\n'
                          '• o que fez, as peças trocadas e as medições;\n'
                          '• se cobra ou não, e quanto tempo levou.',
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ),
              const Spacer(),
              Center(
                child: Icon(
                  _fase == _Fase.gravando ? Icons.mic : Icons.mic_none,
                  size: 96,
                  color: _fase == _Fase.gravando ? Cores.coral500 : Cores.neutro,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  duracaoCurta(tempo.inMilliseconds / 1000),
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
              Center(
                child: Text(
                  switch (_fase) {
                    _Fase.preparando => 'Preparando o microfone...',
                    _Fase.semPermissao => _erro ?? 'Sem permissão para usar o microfone.',
                    _Fase.gravando => 'Gravando · até 10:00',
                    _Fase.pausado => 'Pausado',
                    _Fase.terminado => 'Gravação curta demais. Grave de novo.',
                  },
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _fase == _Fase.semPermissao ? Cores.erro : Cores.neutro),
                ),
              ),
              const SizedBox(height: 16),
              if (_fase == _Fase.gravando || _fase == _Fase.pausado)
                LinearProgressIndicator(
                  value: _fase == _Fase.gravando ? _nivel : 0,
                  minHeight: 8,
                  color: Cores.coral500,
                  backgroundColor: Cores.linha,
                ),
              const Spacer(),
              ..._botoes(),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _botoes() {
    Widget grande(Widget b) => Padding(padding: const EdgeInsets.only(top: 8), child: SizedBox(height: 56, child: b));
    switch (_fase) {
      case _Fase.preparando:
        return const [];
      case _Fase.semPermissao:
        return [
          const Text('Permita o uso do microfone para o ServPilot nas configurações do celular e tente de novo.',
              textAlign: TextAlign.center),
          grande(FilledButton(onPressed: _comecar, child: const Text('Tentar de novo'))),
          grande(OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar'))),
        ];
      case _Fase.gravando:
      case _Fase.pausado:
        return [
          Row(children: [
            Expanded(
              child: grande(OutlinedButton.icon(
                onPressed: _fase == _Fase.gravando ? _pausar : _continuar,
                icon: Icon(_fase == _Fase.gravando ? Icons.pause : Icons.play_arrow),
                label: Text(_fase == _Fase.gravando ? 'Pausar' : 'Continuar'),
              )),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: grande(FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Cores.coral500),
                onPressed: _parando ? null : _parar,
                icon: const Icon(Icons.send),
                label: const Text('Terminar e enviar'),
              )),
            ),
          ]),
        ];
      case _Fase.terminado:
        return [
          Row(children: [
            Expanded(
              child: grande(OutlinedButton.icon(
                onPressed: _deNovo,
                icon: const Icon(Icons.replay),
                label: const Text('Gravar de novo'),
              )),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: grande(OutlinedButton(
                onPressed: () async {
                  await _jogarFora();
                  _arquivo = null;
                  if (mounted) Navigator.of(context).pop();
                },
                child: const Text('Descartar', style: TextStyle(color: Cores.erro)),
              )),
            ),
          ]),
        ];
    }
  }
}
