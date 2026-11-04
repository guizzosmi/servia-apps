import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/parametros.dart';
import '../servicos/status.dart';
import '../servicos/whatsapp.dart';
import '../widgets/agenda_simples.dart';
import '../widgets/margem.dart';

/// Lembretes de limpeza (guia 64): o cliente que limpou o ar-condicionado há
/// "N meses" recebe o lembrete pelo WhatsApp; respondeu que quer, vira OS.
class LembretesTela extends StatefulWidget {
  const LembretesTela({super.key});

  @override
  State<LembretesTela> createState() => _LembretesTelaState();
}

const _statusLembrete = {
  'pendente': Rotulo('Para enviar', Cores.info),
  'enviado': Rotulo('Enviado', Cores.andamento),
  'adiado': Rotulo('Adiado', Cores.neutro),
  'agendado': Rotulo('Virou OS', Cores.sucesso),
  'dispensado': Rotulo('Dispensado', Cores.neutro),
};

class _LembretesTelaState extends State<LembretesTela> {
  List<Map<String, dynamic>> _lista = [];
  Map<String, dynamic> _param = const {};
  String _filtro = 'abertos';
  bool _carregando = true;
  String? _erro;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  List<String> get _status => switch (_filtro) {
        'pendente' => ['pendente'],
        'enviado' => ['enviado'],
        'fechados' => ['agendado', 'dispensado'],
        _ => ['pendente', 'enviado', 'adiado'],
      };

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('lembretes_lista', params: {
        'p': {'status': _status}
      }) as Map);
      if (mounted) {
        setState(() {
          _lista = List<Map<String, dynamic>>.from((r['lembretes'] as List?) ?? const []);
          _param = Map<String, dynamic>.from((r['parametros'] as Map?) ?? const {});
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<Map<String, dynamic>> _acao(Map<String, dynamic> p) async =>
      Map<String, dynamic>.from(await _db.rpc('lembrete_acao', params: {'p': p}) as Map);

  void _avisar(String t, {bool erro = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Cores.erro : null));

  String _aparelhos(Map<String, dynamic> l) => [
        for (final a in (l['aparelhos'] as List? ?? const []))
          [(a as Map)['codigo'], a['descricao']].where((x) => x != null && '$x'.isNotEmpty).join(' '),
      ].join(', ');

  Future<void> _enviar(Map<String, dynamic> l) async {
    final envio = await mandarWhatsAppSemOs(
      context,
      modelo: 'lembrete_limpeza',
      titulo: 'Lembrete de limpeza',
      clienteId: '${l['cliente_id']}',
      valores: {
        'cliente': '${l['cliente'] ?? ''}',
        'local': '${l['local'] ?? ''}',
        'aparelhos': _aparelhos(l),
        'meses': '${_param['meses'] ?? 6}',
      },
    );
    if (envio == null) return;
    try {
      await _acao({'acao': 'enviado', 'lembrete_id': l['id'], ...envio.paraRegistro()});
      _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _agendar(Map<String, dynamic> l) async {
    try {
      final r = await _acao({'acao': 'agendar', 'lembrete_id': l['id']});
      if (!mounted) return;
      // Modo simples: já pergunta o dia; senão a OS fica na fila.
      if (ParametrosEmpresa.instancia.modoSimples && r['agendamento_id'] != null) {
        await agendarSimples(context, agendamentoId: '${r['agendamento_id']}', titulo: 'Agendar a limpeza');
      } else {
        _avisar('OS ${r['codigo'] ?? ''} aberta: a limpeza está na fila para programar.');
      }
      _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _outra(Map<String, dynamic> l, String op) async {
    try {
      await _acao({
        'acao': op,
        'lembrete_id': l['id'],
        if (op == 'adiar') 'dias': 30,
      });
      _avisar(switch (op) {
        'adiar' => 'Adiado por 30 dias.',
        'nao_lembrar' => 'Esse cliente não recebe mais lembretes (dá para religar no cadastro dele).',
        _ => 'Dispensado.',
      });
      _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usa = _param['usa'] == true;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          Expanded(
            child: Text('Lembretes de limpeza',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          IconButton(tooltip: 'Atualizar', onPressed: _carregando ? null : _carregar, icon: const Icon(Icons.refresh)),
        ]),
        Text(
          'Aparelho com a última limpeza há ${_param['meses'] ?? 6} meses vira um lembrete (um por local). Mande pelo '
          'WhatsApp; o cliente quer, toque em Agendar e a OS de limpeza nasce com os aparelhos. Aparelho em plano de '
          'preventiva, com OS em aberto ou de cliente que não quer lembrete fica de fora.',
          style: const TextStyle(color: Cores.neutro),
        ),
        const SizedBox(height: 12),
        if (!usa && !_carregando)
          Card(
            color: Cores.indigo100,
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Os lembretes estão desligados.'),
              subtitle: const Text('Ligue em Configurações > Lembrete de limpeza (e escolha de quantos em quantos meses).'),
              trailing: TextButton(onPressed: () => context.go('/configuracoes'), child: const Text('Configurações')),
            ),
          ),
        Wrap(spacing: 8, children: [
          for (final f in const [('abertos', 'Em aberto'), ('pendente', 'Para enviar'), ('enviado', 'Enviados'), ('fechados', 'Fechados')])
            ChoiceChip(
              label: Text(f.$2),
              selected: _filtro == f.$1,
              onSelected: (_) {
                setState(() => _filtro = f.$1);
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
            child: Text('Nenhum lembrete aqui.', style: TextStyle(color: Cores.neutro)),
          ),
        for (final l in _lista) _cartao(l),
      ]),
    );
  }

  Widget _cartao(Map<String, dynamic> l) {
    final st = _statusLembrete[l['status']];
    final aberto = ['pendente', 'enviado', 'adiado'].contains(l['status']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${l['cliente']} · ${l['local']}${l['cidade'] != null ? ' (${l['cidade']})' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (st != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: st.cor.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
                child: Text(st.texto, style: TextStyle(color: st.cor, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 4),
          Text(_aparelhos(l)),
          Text(
            [
              'Limpeza vence ${dataBr(l['vencimento'])}',
              if (l['ultima_em'] != null) 'última ${dataBr(l['ultima_em'])}',
              if (l['enviado_em'] != null) 'enviado ${dataHoraBr(l['enviado_em'])}',
              if (l['adiado_ate'] != null) 'adiado até ${dataBr(l['adiado_ate'])}',
            ].join(' · '),
            style: const TextStyle(color: Cores.neutro, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (aberto)
              FilledButton.tonalIcon(
                onPressed: () => _enviar(l),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: Text(l['status'] == 'enviado' ? 'Mandar de novo' : 'Mandar pelo WhatsApp'),
              ),
            if (aberto)
              FilledButton.icon(
                onPressed: () => _agendar(l),
                icon: const Icon(Icons.event_available, size: 18),
                label: const Text('Agendar a limpeza'),
              ),
            if (l['os_id'] != null)
              TextButton(onPressed: () => context.push('/os/${l['os_id']}'), child: Text('Abrir ${l['os_codigo'] ?? 'a OS'}')),
            if (aberto)
              PopupMenuButton<String>(
                tooltip: 'Mais',
                onSelected: (op) => _outra(l, op),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'adiar', child: Text('Adiar 30 dias')),
                  PopupMenuItem(value: 'dispensar', child: Text('Dispensar')),
                  PopupMenuItem(value: 'nao_lembrar', child: Text('Cliente não quer lembretes')),
                ],
              ),
          ]),
        ]),
      ),
    );
  }
}
