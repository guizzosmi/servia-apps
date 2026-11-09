import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/gravador_web.dart';
import '../widgets/margem.dart';

/// Uma troca da conversa: o pedido (texto ou a transcrição do áudio) e a
/// resposta do assistente, com as ações feitas e a confirmação pendente.
class _Troca {
  _Troca({this.pedido, this.porVoz = false});

  String? pedido;
  final bool porVoz;
  String? resposta;
  String? erro;
  List<Map<String, dynamic>> acoes = const [];
  Map<String, dynamic>? confirmar;

  /// null (esperando o toque), 'confirmando', 'confirmado' ou 'cancelado'.
  String? situacaoConfirmar;
}

/// Assistente (guia 93): o Claude dentro do painel. Pede por texto ou voz e
/// ele consulta, grava e analisa com as mesmas ferramentas do conector
/// (guia 91), dentro do que a empresa liberou. Ações que desfazem ou
/// encerram pedem o toque em Confirmar. A conversa fica só na tela.
class AssistenteTela extends StatefulWidget {
  const AssistenteTela({super.key});

  @override
  State<AssistenteTela> createState() => _AssistenteTelaState();
}

class _AssistenteTelaState extends State<AssistenteTela> {
  static const _sugestoes = [
    'Como foi o mês até agora, comparado com o mês passado?',
    'Quem me deve e há quanto tempo?',
    'Quais OS estão na agenda de hoje e de amanhã?',
    'O que está atrasado ou parado?',
    'Quais orçamentos estão esperando o cliente?',
    'O que merece minha atenção hoje?',
  ];

  /// Comando de voz: até 1 minuto.
  static const _maxVoz = Duration(seconds: 60);
  static final _codigoOs = RegExp(r'OS-\d{4,}');

  final _texto = TextEditingController();
  final _rolagem = ScrollController();
  final _gravador = GravadorWeb();
  final List<_Troca> _conversa = [];
  Timer? _tique;
  bool _pensando = false;
  bool _parandoGravacao = false;

  @override
  void dispose() {
    _tique?.cancel();
    _gravador.cancelar();
    _texto.dispose();
    _rolagem.dispose();
    super.dispose();
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

  /// As últimas trocas (só texto) para o assistente lembrar do contexto.
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

  Future<Map<String, dynamic>> _chamar(Map<String, dynamic> corpo) async {
    final r = await Supabase.instance.client.functions.invoke('assistente-claude', body: {'origem': 'painel', ...corpo});
    return r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
  }

  Future<void> _enviar({String? texto, AudioGravado? audio}) async {
    final t = (texto ?? _texto.text).trim();
    if (_pensando || (audio == null && t.length < 2)) return;
    final historico = _historico();
    if (audio == null) _texto.clear();
    final troca = _Troca(pedido: audio == null ? t : null, porVoz: audio != null);
    setState(() {
      _pensando = true;
      _conversa.add(troca);
    });
    _rolar();
    try {
      final m = await _chamar({
        'mensagens': historico,
        if (audio == null) 'texto': t else ...{'audio': base64Encode(audio.bytes), 'audio_tipo': audio.tipo},
      });
      troca
        ..pedido = troca.pedido ?? '${m['transcricao'] ?? ''}'
        ..resposta = '${m['resposta'] ?? ''}'
        ..acoes = _lista(m['acoes'])
        ..confirmar = m['confirmar'] is Map ? Map<String, dynamic>.from(m['confirmar'] as Map) : null;
    } catch (e) {
      troca.erro = mensagemDeErro(e);
    } finally {
      if (mounted) setState(() => _pensando = false);
      _rolar();
    }
  }

  /// Toque no microfone: começa a gravar; outro toque para e envia.
  Future<void> _microfone() async {
    if (_pensando || _parandoGravacao) return;
    if (_gravador.gravando) {
      _parandoGravacao = true;
      _tique?.cancel();
      final audio = await _gravador.parar();
      _parandoGravacao = false;
      if (!mounted) return;
      setState(() {});
      if (audio == null || audio.duracao < const Duration(milliseconds: 700)) {
        _aviso('Gravação curta demais. Toque no microfone, fale o pedido e toque de novo para enviar.');
        return;
      }
      await _enviar(audio: audio);
      return;
    }
    try {
      await _gravador.comecar();
    } on ErroGravacao catch (e) {
      if (mounted) _aviso(e.mensagem);
      return;
    }
    if (!mounted) {
      _gravador.cancelar();
      return;
    }
    _tique = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (_gravador.duracao >= _maxVoz) {
        _microfone();
      } else {
        setState(() {});
      }
    });
    setState(() {});
  }

  void _cancelarGravacao() {
    _tique?.cancel();
    _gravador.cancelar();
    setState(() {});
  }

  Future<void> _confirmar(_Troca c) async {
    final pend = c.confirmar;
    if (pend == null || c.situacaoConfirmar != null) return;
    setState(() => c.situacaoConfirmar = 'confirmando');
    final nova = _Troca(pedido: 'Confirmo: ${pend['resumo'] ?? pend['ferramenta']}');
    try {
      final m = await _chamar({
        'confirmado': {'ferramenta': pend['ferramenta'], 'argumentos': pend['argumentos'] ?? const {}},
      });
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

  /// Abre a OS pelo código (OS-000021) citado na resposta.
  Future<void> _abrirOs(String codigo) async {
    try {
      final r = await Supabase.instance.client
          .from('ordens_servico')
          .select('id')
          .eq('codigo', codigo)
          .isFilter('excluido_em', null)
          .maybeSingle();
      if (!mounted) return;
      if (r == null) {
        _aviso('$codigo não encontrada.');
        return;
      }
      context.go('/os/${r['id']}');
    } catch (e) {
      if (mounted) _aviso(mensagemDeErro(e));
    }
  }

  Widget _chipAcao(Map<String, dynamic> a) {
    final ok = a['ok'] == true;
    return Chip(
      avatar: Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
          size: 18, color: ok ? Cores.sucesso : Cores.erro),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${pend['resumo'] ?? pend['ferramenta']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        switch (s) {
          'confirmado' => const Text('Confirmado.', style: TextStyle(color: Cores.sucesso)),
          'cancelado' => const Text('Cancelado: nada foi feito.', style: TextStyle(color: Cores.neutro)),
          _ => Wrap(spacing: 8, children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Cores.alerta),
                onPressed: s == null ? () => _confirmar(c) : null,
                icon: s == 'confirmando'
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check),
                label: const Text('Confirmar'),
              ),
              OutlinedButton(
                onPressed: s == null ? () => setState(() => c.situacaoConfirmar = 'cancelado') : null,
                child: const Text('Cancelar'),
              ),
            ]),
        },
      ]),
    );
  }

  Widget _bolha(_Troca c) {
    final escritas = c.acoes.where((a) => a['escreve'] == true || a['ok'] != true).toList();
    final consultas = c.acoes.where((a) => a['escreve'] != true && a['ok'] == true).toList();
    final codigos = <String>{
      for (final m in _codigoOs.allMatches([c.resposta ?? '', ...c.acoes.map((a) => '${a['resumo']}')].join(' ')))
        m.group(0)!,
    }.take(3);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 12, left: 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: Cores.indigo100, borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (c.porVoz) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.mic, size: 16)),
            Flexible(child: Text(c.pedido ?? (c.erro == null ? 'Ouvindo o áudio...' : 'Áudio'))),
          ]),
        ),
      ),
      Container(
        margin: const EdgeInsets.only(top: 8, right: 60),
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
                    SelectableText(c.resposta!, style: const TextStyle(height: 1.4)),
                    if (escritas.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 4, children: [for (final a in escritas) _chipAcao(a)]),
                    ],
                    if (consultas.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Consultou: ${consultas.map((a) => a['resumo'] ?? a['ferramenta']).toSet().join(', ')}',
                          style: const TextStyle(color: Cores.neutro, fontSize: 12)),
                    ],
                    if (c.confirmar != null) _confirmacao(c),
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      for (final codigo in codigos)
                        ActionChip(
                          avatar: const Icon(Icons.open_in_new, size: 16),
                          label: Text('Abrir $codigo'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _abrirOs(codigo),
                        ),
                      IconButton(
                        tooltip: 'Copiar',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => Clipboard.setData(ClipboardData(text: c.resposta!)),
                      ),
                    ]),
                  ]),
      ),
    ]);
  }

  Widget _barraDeEntrada() {
    final gravando = _gravador.gravando;
    if (gravando) {
      final s = _gravador.duracao.inSeconds;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Cores.coral500),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.fiber_manual_record, color: Cores.coral500, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Gravando... ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')} '
                '(toque em Enviar quando terminar)'),
          ),
          TextButton(onPressed: _cancelarGravacao, child: const Text('Cancelar')),
          const SizedBox(width: 4),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Cores.coral500),
            onPressed: _microfone,
            icon: const Icon(Icons.stop),
            label: const Text('Enviar'),
          ),
        ]),
      );
    }
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _texto,
          maxLength: 1000,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _enviar(),
          decoration: const InputDecoration(
              hintText: 'Ex.: agende a OS-000021 para amanhã às 9h com a Equipe 1', counterText: ''),
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filled(
        tooltip: 'Falar o pedido',
        style: IconButton.styleFrom(backgroundColor: Cores.coral500, foregroundColor: Colors.white),
        onPressed: _pensando ? null : _microfone,
        icon: const Icon(Icons.mic),
      ),
      const SizedBox(width: 8),
      FilledButton.icon(
        onPressed: _pensando ? null : () => _enviar(),
        icon: const Icon(Icons.send),
        label: const Text('Enviar'),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margemDaTela(context),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [
              Icon(Icons.auto_awesome_outlined, color: Cores.coral500),
              SizedBox(width: 8),
              Text('Assistente', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            const Text(
                'Peça por texto ou pelo microfone: consultar (agenda, OS, clientes, a receber), fazer (abrir e agendar '
                'OS, incluir peça, registrar recebimento) e analisar (como foi o mês, o que está atrasado). '
                'Ele só faz o que a empresa liberou em Configurações › Conector do Claude.',
                style: TextStyle(color: Cores.neutro)),
            const SizedBox(height: 12),
            Expanded(
              child: _conversa.isEmpty
                  ? SingleChildScrollView(
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final s in _sugestoes) ActionChip(label: Text(s), onPressed: () => _enviar(texto: s)),
                      ]),
                    )
                  : ListView(controller: _rolagem, children: [for (final c in _conversa) _bolha(c)]),
            ),
            const SizedBox(height: 8),
            _barraDeEntrada(),
            const SizedBox(height: 4),
            const Text('A IA pode errar: confira nas telas antes de decidir. O áudio não fica guardado.',
                style: TextStyle(color: Cores.neutro, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
