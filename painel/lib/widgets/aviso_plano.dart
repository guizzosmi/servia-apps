import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Faixa no topo do painel: teste acabando, fatura vencida, minutos ou
/// mensagens no fim (guia 44). Consulta no máximo a cada 5 minutos.
class AvisoPlano extends StatefulWidget {
  const AvisoPlano({super.key});

  /// Força consultar de novo (depois de pagar ou comprar pacote).
  static void esquecer() => _AvisoPlanoState._cache = null;

  @override
  State<AvisoPlano> createState() => _AvisoPlanoState();
}

class _AvisoPlanoState extends State<AvisoPlano> {
  static ({String conta, DateTime quando, Map<String, dynamic>? aviso})? _cache;
  Map<String, dynamic>? _aviso;
  bool _fechado = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final conta = Sessao.atual?.contaId;
    if (conta == null) return;
    final c = _cache;
    if (c != null && c.conta == conta && DateTime.now().difference(c.quando).inMinutes < 5) {
      setState(() => _aviso = c.aviso);
      return;
    }
    try {
      final r = await Supabase.instance.client.rpc('consumo_atual');
      final aviso = r is Map && r['aviso'] is Map ? Map<String, dynamic>.from(r['aviso'] as Map) : null;
      _cache = (conta: conta, quando: DateTime.now(), aviso: aviso);
      if (mounted) setState(() => _aviso = aviso);
    } catch (_) {
      // Sem internet ou sem permissão: sem faixa.
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _aviso;
    if (a == null || _fechado) return const SizedBox.shrink();
    final cor = switch (a['nivel']) { 'erro' => Cores.erro, 'alerta' => Cores.alerta, _ => Cores.info };
    return Material(
      color: cor.withValues(alpha: .08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(children: [
          Icon(a['tipo'] == 'fatura' ? Icons.receipt_long_outlined : Icons.data_usage, color: cor, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('${a['texto']}', style: TextStyle(color: cor))),
          TextButton(onPressed: () => context.go('/assinatura'), child: const Text('Ver plano')),
          IconButton(
            tooltip: 'Fechar',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _fechado = true),
          ),
        ]),
      ),
    );
  }
}
