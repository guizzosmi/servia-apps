import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cadastros/campos.dart';
import '../cadastros/definicoes.dart';
import '../servicos/funcoes.dart';
import '../servicos/parametros.dart';
import '../servicos/status.dart';
import '../widgets/agenda_simples.dart';
import '../widgets/margem.dart';

/// Pedidos do WhatsApp (guia 65): o cliente manda mensagem (texto ou áudio) no
/// WhatsApp oficial da empresa, a IA monta o pedido (cliente pelo telefone,
/// local, aparelho, problema) e aqui o escritório confirma: vira OS na fila.
class WhatsappTela extends StatefulWidget {
  const WhatsappTela({super.key});

  @override
  State<WhatsappTela> createState() => _WhatsappTelaState();
}

const _statusPedido = {
  'recebendo': Rotulo('Recebendo', Cores.neutro),
  'processando': Rotulo('A IA está lendo', Cores.andamento),
  'a_confirmar': Rotulo('A confirmar', Cores.info),
  'aberto': Rotulo('Virou OS', Cores.sucesso),
  'descartado': Rotulo('Descartado', Cores.neutro),
  'erro': Rotulo('Erro', Cores.erro),
};

const _prioridadesOs = [('baixa', 'Baixa'), ('media', 'Média'), ('alta', 'Alta'), ('urgente', 'Urgente')];
const _tiposOs = [('corretiva', 'Corretiva'), ('preventiva', 'Preventiva'), ('instalacao', 'Instalação'), ('outro', 'Outro')];

class _WhatsappTelaState extends State<WhatsappTela> {
  List<Map<String, dynamic>> _pedidos = [];
  bool _configurado = false;
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
        'aberto' => ['aberto'],
        'descartado' => ['descartado'],
        _ => ['recebendo', 'processando', 'a_confirmar', 'erro'],
      };

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('whatsapp_pedidos_lista', params: {
        'p': {'status': _status}
      }) as Map);
      if (mounted) {
        setState(() {
          _pedidos = List<Map<String, dynamic>>.from((r['pedidos'] as List?) ?? const []);
          _configurado = r['configurado'] == true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _avisar(String t, {bool erro = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Cores.erro : null));

  Future<void> _processar(String pedidoId) async {
    try {
      await chamarFuncao('whatsapp', {'acao': 'processar', 'pedido_id': pedidoId});
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
    await _carregar();
  }

  Future<void> _simular() async {
    final tel = TextEditingController();
    final txt = TextEditingController(text: 'Bom dia! O ar-condicionado da recepção está pingando e fazendo barulho. Podem vir hoje?');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Simular mensagem do cliente'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Como se o cliente tivesse mandado no WhatsApp da empresa. Use o telefone de um contato cadastrado '
                'para ver o cliente reconhecido. Nada é enviado.', style: TextStyle(color: Cores.neutro)),
            const SizedBox(height: 12),
            TextField(controller: tel, decoration: const InputDecoration(labelText: 'Telefone do cliente', hintText: '(45) 99999-0000')),
            TextField(controller: txt, maxLines: 4, decoration: const InputDecoration(labelText: 'Mensagem')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Simular')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('whatsapp_simular', params: {
        'p': {'telefone': tel.text.trim(), 'texto': txt.text.trim()}
      }) as Map);
      _avisar('Mensagem recebida: a IA está lendo...');
      await _carregar();
      if (r['pedido_id'] != null) await _processar('${r['pedido_id']}');
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _descartar(Map<String, dynamic> p) async {
    try {
      await _db.rpc('whatsapp_pedido_acao', params: {
        'p': {'acao': 'descartar', 'pedido_id': p['id']}
      });
      _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _abrirOs(Map<String, dynamic> p) async {
    final dados = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _DialogoAbrirOs(pedido: p));
    if (dados == null || !mounted) return;
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('whatsapp_pedido_acao', params: {
        'p': {'acao': 'abrir_os', 'pedido_id': p['id'], ...dados}
      }) as Map);
      if (!mounted) return;
      if (ParametrosEmpresa.instancia.modoSimples && r['agendamento_id'] != null) {
        await agendarSimples(context, agendamentoId: '${r['agendamento_id']}');
      } else {
        _avisar('OS ${r['codigo'] ?? ''} aberta: está na fila para programar.');
      }
      _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Row(children: [
          Expanded(
            child: Text('Pedidos do WhatsApp',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          IconButton(tooltip: 'Atualizar', onPressed: _carregando ? null : _carregar, icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _simular, icon: const Icon(Icons.science_outlined), label: const Text('Simular mensagem')),
        ]),
        const Text('O cliente manda texto ou áudio no WhatsApp da empresa; a IA reconhece o cliente pelo telefone e monta o '
            'pedido (local, aparelho, problema). Confira e toque em Abrir OS.', style: TextStyle(color: Cores.neutro)),
        const SizedBox(height: 12),
        if (!_configurado && !_carregando)
          Card(
            color: Cores.indigo100,
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('O WhatsApp oficial ainda não está conectado.'),
              subtitle: const Text('Conecte em Configurações > WhatsApp oficial (guia 65). Enquanto isso, teste com "Simular mensagem".'),
              trailing: TextButton(onPressed: () => context.go('/configuracoes'), child: const Text('Configurações')),
            ),
          ),
        Wrap(spacing: 8, children: [
          for (final f in const [('abertos', 'Em aberto'), ('aberto', 'Viraram OS'), ('descartado', 'Descartados')])
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
        if (!_carregando && _pedidos.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nenhum pedido aqui.', style: TextStyle(color: Cores.neutro)),
          ),
        for (final p in _pedidos) _cartao(p),
      ]),
    );
  }

  Widget _cartao(Map<String, dynamic> p) {
    final st = _statusPedido[p['status']];
    final prop = Map<String, dynamic>.from((p['proposta'] as Map?) ?? const {});
    final cliente = (prop['cliente'] as Map?)?['nome'] ?? p['cliente'];
    final local = (prop['local'] as Map?)?['nome'];
    final equip = (prop['equipamento'] as Map?)?['texto'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.chat, color: Cores.sucesso, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [
                  p['contato'] ?? p['nome'],
                  // Guia 72: pedido do portal sem telefone entra com um número "00...".
                  if ('${p['telefone'] ?? ''}'.startsWith('00')) 'sem telefone' else p['telefone'],
                  if (p['simulado'] == true) '(simulação)',
                ]
                    .where((x) => x != null && '$x'.isNotEmpty)
                    .join(' · '),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(dataHoraBr(p['ultima_em']), style: const TextStyle(color: Cores.neutro, fontSize: 12)),
            const SizedBox(width: 8),
            if (st != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: st.cor.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
                child: Text(st.texto, style: TextStyle(color: st.cor, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 8),
          for (final m in (p['mensagens'] as List? ?? const []))
            Align(
              alignment: (m as Map)['direcao'] == 'saida' ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                constraints: const BoxConstraints(maxWidth: 560),
                decoration: BoxDecoration(
                  color: m['direcao'] == 'saida' ? const Color(0xFFDCF8C6) : const Color(0xFFF1F3F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${m['tipo'] == 'audio' ? '🎤 ' : m['tipo'] == 'imagem' ? '📷 ' : ''}${m['texto'] ?? ''}'),
              ),
            ),
          if (prop.isNotEmpty) ...[
            const Divider(),
            Wrap(spacing: 16, runSpacing: 4, children: [
              Text('Cliente: ${cliente ?? 'escolher'}'),
              Text('Local: ${local ?? 'escolher'}'),
              if (equip != null) Text('Aparelho: $equip'),
              Text('Tipo: ${prop['tipo_servico'] ?? 'corretiva'}'),
            ]),
            if (prop['problema'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Problema: ${prop['problema']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
          ],
          if (p['erro'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${p['erro']}', style: const TextStyle(color: Cores.erro)),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (p['status'] == 'a_confirmar' || p['status'] == 'erro')
              FilledButton.icon(
                onPressed: () => _abrirOs(p),
                icon: const Icon(Icons.assignment_add, size: 18),
                label: const Text('Abrir OS'),
              ),
            if (p['status'] == 'erro' || p['status'] == 'recebendo')
              OutlinedButton.icon(
                onPressed: () => _processar('${p['id']}'),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(p['status'] == 'erro' ? 'Tentar a IA de novo' : 'Ler agora'),
              ),
            if (p['os_id'] != null)
              TextButton(onPressed: () => context.push('/os/${p['os_id']}'), child: Text('Abrir ${p['os_codigo'] ?? 'a OS'}')),
            if (['recebendo', 'a_confirmar', 'erro'].contains(p['status']))
              TextButton(onPressed: () => _descartar(p), child: const Text('Descartar')),
          ]),
        ]),
      ),
    );
  }
}

/// Confere o que a IA montou e abre a OS.
class _DialogoAbrirOs extends StatefulWidget {
  const _DialogoAbrirOs({required this.pedido});

  final Map<String, dynamic> pedido;

  @override
  State<_DialogoAbrirOs> createState() => _DialogoAbrirOsState();
}

class _DialogoAbrirOsState extends State<_DialogoAbrirOs> {
  static const _campoCliente = CampoDef('cliente_id', 'Cliente',
      tipo: TipoCampo.lookup, obrigatorio: true, lookup: Lookup(tabela: 'clientes'));
  static const _campoLocal = CampoDef('local_id', 'Local',
      tipo: TipoCampo.lookup,
      obrigatorio: true,
      lookup: Lookup(tabela: 'locais', colunaDetalhe: 'cidade', colunaFiltro: 'cliente_id', campoPai: 'cliente_id',
          escolherUnico: true));

  String? _cliente;
  String? _local;
  late final TextEditingController _problema;
  String _prioridade = 'media';
  String _tipo = 'corretiva';
  String? _erro;
  String? _equipSugerido;
  String? _localDaIa;

  @override
  void initState() {
    super.initState();
    final prop = Map<String, dynamic>.from((widget.pedido['proposta'] as Map?) ?? const {});
    final eq = prop['equipamento'] as Map?;
    if (eq != null && eq['tipo'] == 'sugerido') _equipSugerido = eq['equipamento_id'] as String?;
    _localDaIa = (prop['local'] as Map?)?['local_id'] as String?;
    final c = prop['cliente'] as Map?;
    final l = prop['local'] as Map?;
    _cliente = (c?['cliente_id'] ?? widget.pedido['cliente_id']) as String?;
    _local = l?['local_id'] as String?;
    _problema = TextEditingController(text: '${prop['problema'] ?? ''}');
    final t = '${prop['tipo_servico'] ?? 'corretiva'}';
    _tipo = _tiposOs.any((x) => x.$1 == t) ? t : 'corretiva';
  }

  @override
  void dispose() {
    _problema.dispose();
    super.dispose();
  }

  Widget _lista(String rotulo, String valor, List<(String, String)> opcoes, ValueChanged<String> mudou) => InputDecorator(
        decoration: InputDecoration(labelText: rotulo),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: valor,
            isDense: true,
            isExpanded: true,
            items: [for (final o in opcoes) DropdownMenuItem(value: o.$1, child: Text(o.$2))],
            onChanged: (v) => mudou(v ?? valor),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Abrir OS do pedido'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CampoLookup(
              campo: _campoCliente,
              valor: _cliente,
              valorPai: null,
              rotuloPai: null,
              habilitado: true,
              aoMudar: (v) => setState(() {
                _cliente = v;
                _local = null;
              }),
            ),
            const SizedBox(height: 12),
            CampoLookup(
              key: ValueKey('local-$_cliente'),
              campo: _campoLocal,
              valor: _local,
              valorPai: _cliente,
              rotuloPai: 'Cliente',
              habilitado: _cliente != null,
              aoMudar: (v) => setState(() => _local = v),
            ),
            const SizedBox(height: 12),
            TextField(controller: _problema, maxLines: 3, decoration: const InputDecoration(labelText: 'Problema')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _lista('Tipo', _tipo, _tiposOs, (v) => setState(() => _tipo = v))),
              const SizedBox(width: 12),
              Expanded(child: _lista('Prioridade', _prioridade, _prioridadesOs, (v) => setState(() => _prioridade = v))),
            ]),
            if (widget.pedido['contato'] == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('O telefone fica salvo como contato deste cliente: o próximo pedido já chega reconhecido.',
                    style: TextStyle(color: Cores.neutro, fontSize: 12)),
              ),
            if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (_cliente == null || _local == null) {
              setState(() => _erro = 'Escolha o cliente e o local.');
              return;
            }
            Navigator.pop(context, {
              'cliente_id': _cliente,
              'local_id': _local,
              'problema_relatado': _problema.text.trim(),
              'prioridade': _prioridade,
              'tipo': _tipo,
              // Aparelho que a IA achou (o único do ambiente falado), se o local não mudou.
              if (_equipSugerido != null && _local == _localDaIa) 'equipamentos': [_equipSugerido],
            });
          },
          child: const Text('Abrir OS'),
        ),
      ],
    );
  }
}
