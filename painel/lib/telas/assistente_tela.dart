import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/margem.dart';

/// Assistente do dono (guia 75): perguntas em português sobre a empresa
/// ("como foi o mês?", "quem me deve?"), respondidas pela IA com os números
/// do retrato da empresa. A conversa fica só na tela.
class AssistenteTela extends StatefulWidget {
  const AssistenteTela({super.key});

  @override
  State<AssistenteTela> createState() => _AssistenteTelaState();
}

class _AssistenteTelaState extends State<AssistenteTela> {
  static const _sugestoes = [
    'Como foi o mês até agora, comparado com o mês passado?',
    'Quem me deve e há quanto tempo?',
    'O que está atrasado ou parado?',
    'Como está a agenda de hoje e de amanhã?',
    'Quais orçamentos estão esperando o cliente?',
    'O que merece minha atenção hoje?',
  ];

  final _pergunta = TextEditingController();
  final _rolagem = ScrollController();
  final List<({String pergunta, String? resposta, List<Map> telas, String? erro})> _conversa = [];
  bool _pensando = false;

  @override
  void dispose() {
    _pergunta.dispose();
    _rolagem.dispose();
    super.dispose();
  }

  Future<void> _perguntar([String? texto]) async {
    final q = (texto ?? _pergunta.text).trim();
    if (q.length < 2 || _pensando) return;
    _pergunta.clear();
    setState(() {
      _pensando = true;
      _conversa.add((pergunta: q, resposta: null, telas: const [], erro: null));
    });
    final i = _conversa.length - 1;
    try {
      final r = await Supabase.instance.client.functions.invoke('assistente', body: {'pergunta': q});
      final m = Map<String, dynamic>.from(r.data as Map);
      if (mounted) {
        setState(() => _conversa[i] = (
              pergunta: q,
              resposta: '${m['resposta'] ?? ''}',
              telas: ((m['telas'] as List?) ?? const []).cast<Map>(),
              erro: null,
            ));
      }
    } catch (e) {
      if (mounted) setState(() => _conversa[i] = (pergunta: q, resposta: null, telas: const [], erro: mensagemDeErro(e)));
    } finally {
      if (mounted) setState(() => _pensando = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_rolagem.hasClients) {
          _rolagem.animateTo(_rolagem.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });
    }
  }

  Widget _bolha(({String pergunta, String? resposta, List<Map> telas, String? erro}) c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 12, left: 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: Cores.indigo100, borderRadius: BorderRadius.circular(14)),
          child: Text(c.pergunta),
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
                    Text('Olhando os números...', style: TextStyle(color: Cores.neutro)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SelectableText(c.resposta!, style: const TextStyle(height: 1.4)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final t in c.telas)
                        ActionChip(
                          avatar: const Icon(Icons.open_in_new, size: 16),
                          label: Text('${t['nome']}'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => context.go('${t['rota']}'),
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
              Text('Pergunte ao assistente', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            const Text(
                'Faturamento, cobranças, agenda, orçamentos, atrasos: pergunte como perguntaria ao seu gerente. '
                'A IA responde com os números da empresa (mês atual, mês passado e os últimos 7 dias).',
                style: TextStyle(color: Cores.neutro)),
            const SizedBox(height: 12),
            Expanded(
              child: _conversa.isEmpty
                  ? SingleChildScrollView(
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final s in _sugestoes)
                          ActionChip(label: Text(s), onPressed: () => _perguntar(s)),
                      ]),
                    )
                  : ListView(controller: _rolagem, children: [for (final c in _conversa) _bolha(c)]),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _pergunta,
                  maxLength: 500,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _perguntar(),
                  decoration: const InputDecoration(hintText: 'Ex.: quanto entrou no caixa este mês?', counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _pensando ? null : () => _perguntar(),
                icon: const Icon(Icons.send),
                label: const Text('Perguntar'),
              ),
            ]),
            const SizedBox(height: 4),
            const Text('A IA pode errar: confira os números nas telas antes de decidir.',
                style: TextStyle(color: Cores.neutro, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
