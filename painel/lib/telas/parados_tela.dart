import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/status.dart';
import '../servicos/whatsapp.dart';
import '../widgets/itens_os.dart' show dinheiro;
import '../widgets/margem.dart';

/// Clientes parados (guia 68): quem não chama há N meses, com a mensagem
/// pronta para o WhatsApp ("faz tempo da última limpeza..."). Marketing de graça.
class ParadosTela extends StatefulWidget {
  const ParadosTela({super.key});

  @override
  State<ParadosTela> createState() => _ParadosTelaState();
}

class _ParadosTelaState extends State<ParadosTela> {
  int _meses = 8;
  List<Map<String, dynamic>> _lista = [];
  bool _carregando = true;
  String? _erro;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('clientes_parados', params: {
        'p': {'meses': _meses}
      }) as Map);
      if (mounted) setState(() => _lista = List<Map<String, dynamic>>.from((r['clientes'] as List?) ?? const []));
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _mandar(Map<String, dynamic> c) async {
    final envio = await mandarWhatsAppSemOs(
      context,
      modelo: 'reativar_cliente',
      titulo: 'Chamar o cliente de volta',
      clienteId: '${c['cliente_id']}',
      valores: {
        'cliente': '${c['cliente'] ?? ''}',
        'local': '${c['local'] ?? ''}',
        'ultimo': dataBr(c['ultimo_em']),
      },
    );
    if (envio == null) return;
    try {
      await _db.rpc('cliente_reativacao', params: {
        'p': {'cliente_id': c['cliente_id']}
      });
    } catch (_) {}
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          Expanded(
            child: Text('Clientes parados',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          IconButton(tooltip: 'Atualizar', onPressed: _carregando ? null : _carregar, icon: const Icon(Icons.refresh)),
        ]),
        const Text('Clientes sem serviço há algum tempo (e sem OS em aberto). Mande uma mensagem chamando para uma '
            'revisão ou limpeza: depois de mandar, o cliente sai da lista por 60 dias. Quem não quer lembretes fica de fora.',
            style: TextStyle(color: Cores.neutro)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          for (final m in const [6, 8, 12, 18])
            ChoiceChip(
              label: Text('$m meses'),
              selected: _meses == m,
              onSelected: (_) {
                setState(() => _meses = m);
                _carregar();
              },
            ),
        ]),
        const SizedBox(height: 12),
        if (_carregando) const LinearProgressIndicator(minHeight: 2),
        if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
        if (!_carregando && _lista.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nenhum cliente parado nesse prazo.', style: TextStyle(color: Cores.neutro)),
          ),
        if (_lista.isNotEmpty) Text('${_lista.length} cliente(s)', style: const TextStyle(color: Cores.neutro)),
        for (final c in _lista)
          Card(
            child: ListTile(
              title: Text('${c['cliente']}${c['cidade'] != null ? ' · ${c['cidade']}' : ''}'),
              subtitle: Text([
                'último serviço ${dataBr(c['ultimo_em'])} (${c['ultima_os'] ?? ''})',
                if ('${c['ultimo_problema'] ?? ''}'.isNotEmpty) '${c['ultimo_problema']}',
                '${c['os_total']} OS · ${dinheiro(c['valor_total'])} no total',
              ].join('\n')),
              isThreeLine: true,
              trailing: Wrap(spacing: 4, children: [
                IconButton(
                  tooltip: 'Abrir o cadastro',
                  onPressed: () => context.push('/c/clientes/${c['cliente_id']}'),
                  icon: const Icon(Icons.person_outline),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _mandar(c),
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: const Text('WhatsApp'),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
