import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resumo da semana do dono (guia 68), na Início: os números e os alertas dos
/// últimos 7 dias, com o texto pronto para copiar ou mandar para si no WhatsApp.
class ResumoSemana extends StatefulWidget {
  const ResumoSemana({super.key});

  @override
  State<ResumoSemana> createState() => _ResumoSemanaState();
}

class _ResumoSemanaState extends State<ResumoSemana> {
  String? _texto;

  @override
  void initState() {
    super.initState();
    if (!(Sessao.atual?.tem(Papel.gestor) ?? false)) return;
    Supabase.instance.client.rpc('resumo_semana', params: {'p': {}}).then((r) {
      if (mounted) setState(() => _texto = '${(r as Map)['texto'] ?? ''}');
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final t = _texto;
    if (t == null || t.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.insights_outlined, color: Cores.indigo700),
              const SizedBox(width: 8),
              const Expanded(child: Text('Resumo da semana', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: t));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Resumo copiado.')));
                  }
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copiar'),
              ),
              TextButton.icon(
                onPressed: () => abrirLink('https://wa.me/?text=${Uri.encodeComponent(t)}'),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('WhatsApp'),
              ),
            ]),
            const SizedBox(height: 4),
            Text(t.split('\n').skip(1).join('\n'), style: const TextStyle(height: 1.5)),
          ]),
        ),
      ),
    );
  }
}
