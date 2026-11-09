import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/arquivo_web.dart' show abrirEmNovaAba, escolherArquivo;
import '../servicos/cobranca.dart' show lerValor;
import '../servicos/comercial.dart' show reais;
import '../servicos/status.dart' show dataBr, dataIso;
import '../widgets/margem.dart';
import 'servico_cobranca.dart';
import 'widgets_cobranca.dart';

/// Títulos de cobrança (guia 100): boletos e Pix registrados no banco, CNAB, Pix da empresa ou manual.
/// Lista com filtros e totais; emitir, copiar a linha ou o Pix, 2ª via, dar baixa, cancelar, mudar o
/// vencimento; gerar a remessa CNAB e importar o retorno. Gestor e financeiro.
class TitulosTela extends StatefulWidget {
  const TitulosTela({super.key});

  @override
  State<TitulosTela> createState() => _TitulosTelaState();
}

/// Filtros rápidos: rótulo e as situações (null = todas).
const _filtros = <String, List<String>?>{
  'Em aberto': ['registrado', 'a_registrar', 'erro'],
  'Vencidos': null,
  'Pagos': ['pago'],
  'Encerrados': ['baixado', 'cancelado'],
  'Rascunhos': ['rascunho'],
  'Todos': null,
};

class _TitulosTelaState extends State<TitulosTela> {
  String _filtro = 'Em aberto';
  final _busca = TextEditingController();
  List<Map<String, dynamic>> _titulos = [];
  Map<String, dynamic> _totais = {};
  Map<String, dynamic>? _config;
  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  void _avisar(String t, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Cores.erro : null));
  }

  List<Map<String, dynamic>> get _contas =>
      ((_config?['contas'] as List?) ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).where((c) => c['ativa'] == true).toList();

  String get _modo => '${(_config?['config'] as Map?)?['modo'] ?? 'manual'}';

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final c = await configCobranca();
      final r = await listaTitulos({
        if (_filtros[_filtro] != null) 'situacao': _filtros[_filtro],
        if (_filtro == 'Vencidos') 'so_vencidos': true,
        if (_busca.text.trim().isNotEmpty) 'busca': _busca.text.trim(),
        'limite': 300,
      });
      if (!mounted) return;
      setState(() {
        _config = c;
        _titulos = ((r['titulos'] as List?) ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
        _totais = Map<String, dynamic>.from((r['totais'] as Map?) ?? const {});
      });
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Ações: título por API passa pela função (o banco é avisado na hora); os outros, direto nas regras.
  Future<void> _acao(Map<String, dynamic> t, Map<String, dynamic> p, String ok) async {
    setState(() => _ocupado = true);
    try {
      final r = t['via'] == 'api'
          ? await funcaoCobranca({...p, 'titulo_id': t['id']})
          : await acaoCobranca({...p, 'titulo_id': t['id']});
      final banco = r['banco'] as Map?;
      final falhas = ((banco?['resultados'] as List?) ?? const []).where((x) => (x as Map)['ok'] != true).toList();
      _avisar(falhas.isEmpty ? ok : '$ok O banco ainda não confirmou: tentamos de novo em instantes.');
      await _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _emitir() async {
    final emitido = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _EmitirTitulo());
    if (emitido == null) return;
    final t = Map<String, dynamic>.from((emitido['titulo'] as Map?) ?? const {});
    if (t['via'] == 'api' && t['situacao'] == 'a_registrar') {
      try {
        await funcaoCobranca({'acao': 'processar', 'titulo_id': emitido['titulo_id']});
      } catch (_) {
        // a rotina registra em alguns minutos
      }
    }
    _avisar('Título ${emitido['codigo']} emitido.');
    await _carregar();
  }

  Future<void> _baixar(Map<String, dynamic> t) async {
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => DialogoBaixarTitulo(titulo: t));
    if (p != null) await _acao(t, {'acao': 'baixar', ...p}, 'Baixa lançada no Caixa.');
  }

  Future<void> _cancelar(Map<String, dynamic> t) async {
    final motivo = await showDialog<String>(context: context, builder: (_) => _Motivo(titulo: t));
    if (motivo != null) await _acao(t, {'acao': 'cancelar', 'motivo': motivo}, 'Título cancelado.');
  }

  Future<void> _vencimento(Map<String, dynamic> t) async {
    final hoje = DateTime.now();
    final atual = DateTime.tryParse('${t['vencimento']}') ?? hoje;
    final d = await showDatePicker(
        context: context,
        initialDate: atual.isBefore(hoje) ? hoje : atual,
        firstDate: hoje,
        lastDate: hoje.add(const Duration(days: 365)));
    if (d != null) await _acao(t, {'acao': 'alterar_vencimento', 'vencimento': dataIso(d)}, 'Vencimento alterado.');
  }

  Future<void> _simples(Map<String, dynamic> t, String acao, String ok) async {
    setState(() => _ocupado = true);
    try {
      if (acao == 'processar' || acao == 'consultar') {
        final r = await funcaoCobranca({'acao': acao, 'titulo_id': t['id']});
        final res = ((r['resultados'] as List?) ?? const []).cast<Map>();
        final erro = res.where((x) => x['ok'] != true).map((x) => '${x['mensagem'] ?? ''}').join(' ');
        _avisar(res.isEmpty ? 'Nada pendente para este título.' : erro.isEmpty ? ok : erro, erro: erro.isNotEmpty);
      } else {
        await acaoCobranca({'acao': acao, 'titulo_id': t['id']});
        _avisar(ok);
      }
      await _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<Map<String, dynamic>?> _escolherConta(String titulo) async {
    final contas = _contas;
    if (contas.isEmpty) {
      _avisar('Cadastre a conta de cobrança em Configurações › Cobrança.', erro: true);
      return null;
    }
    if (contas.length == 1) return contas.first;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(title: Text(titulo), children: [
        for (final c in contas)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, c),
            child: Text('${c['nome']} · ${nomesBancos[c['banco']] ?? c['banco']} · CNAB ${c['cnab_layout']}'),
          ),
      ]),
    );
  }

  Future<void> _gerarRemessa() async {
    final conta = await _escolherConta('Remessa de qual conta?');
    if (conta == null) return;
    setState(() => _ocupado = true);
    try {
      final r = await funcaoCobranca({'acao': 'gerar_remessa', 'conta_bancaria_id': conta['id']});
      baixarArquivoTexto('${r['nome_arquivo']}', '${r['conteudo']}');
      _avisar('Remessa ${r['nome_arquivo']} com ${r['qtd']} título(s). Envie o arquivo pelo internet banking.');
      await _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _importarRetorno() async {
    final conta = await _escolherConta('Retorno de qual conta?');
    if (conta == null) return;
    final arq = await escolherArquivo(aceitar: '.ret,.RET,.txt,.TXT,.crt,.CRT,.retorno');
    if (arq == null) return;
    setState(() => _ocupado = true);
    try {
      final r = await funcaoCobranca({
        'acao': 'ler_retorno',
        'conta_bancaria_id': conta['id'],
        'nome_arquivo': arq.nome,
        'conteudo': latin1.decode(arq.bytes, allowInvalid: true),
      });
      if (!mounted) return;
      final itens = ((r['itens'] as List?) ?? const []).cast<Map>();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(r['repetido'] == true ? 'Este retorno já tinha sido lido' : 'Retorno lido'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Text([
                '${r['qtd'] ?? itens.length} ocorrência(s); ${r['pagos'] ?? 0} pagamento(s) somando ${reais(r['valor_pago'])}.',
                if ((r['nao_encontrados'] ?? 0) != 0) '${r['nao_encontrados']} sem título no ServPilot (confira no banco).',
                '',
                for (final i in itens.take(60)) '• ${i['nosso_numero'] ?? ''}: ${i['situacao'] ?? ''} (${i['ocorrencia'] ?? ''})',
              ].join('\n')),
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendi'))],
        ),
      );
      await _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _copiar(String texto, String oQue) async {
    await Clipboard.setData(ClipboardData(text: texto));
    _avisar('$oQue copiado.');
  }

  Widget _linhaTitulo(Map<String, dynamic> t) {
    final st = '${t['situacao']}';
    final aberto = const {'rascunho', 'a_registrar', 'registrado', 'erro'}.contains(st);
    final linha = '${t['linha_digitavel'] ?? ''}';
    final pix = '${t['pix_copia_cola'] ?? ''}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${t['codigo']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                SeloTitulo(st, vencido: t['vencido'] == true),
                Text(rotuloViaTitulo[t['via']] ?? '${t['via']}', style: const TextStyle(color: Cores.neutro, fontSize: 12)),
                if (t['cnab_instrucao'] != null)
                  const Text('vai na próxima remessa', style: TextStyle(color: Cores.alerta, fontSize: 12)),
              ]),
              const SizedBox(height: 2),
              Text('${t['cliente'] ?? ''}'),
              Text(
                  [
                    'vence ${dataBr(t['vencimento'])}',
                    rotuloOrigemTitulo[t['origem']] ?? '${t['origem']}',
                    if ((t['documento'] ?? '') != '') '${t['documento']}',
                    if ((t['nosso_numero'] ?? '') != '') 'nosso número ${t['nosso_numero']}',
                    if (st == 'pago') 'pago ${reais(t['valor_pago'])} em ${dataBr(t['pago_em'])}',
                  ].join(' · '),
                  style: const TextStyle(color: Cores.neutro, fontSize: 13)),
              if ((t['erro'] ?? '') != '')
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${t['erro']}', style: const TextStyle(color: Cores.erro, fontSize: 13))),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(reais(t['valor']), style: const TextStyle(fontWeight: FontWeight.w700)),
            Wrap(children: [
              if (linha.isNotEmpty)
                IconButton(
                    tooltip: 'Copiar a linha digitável',
                    icon: const Icon(Icons.copy),
                    onPressed: () => _copiar(linha.replaceAll(RegExp(r'\D'), ''), 'Linha digitável')),
              if (pix.isNotEmpty)
                IconButton(tooltip: 'Copiar o Pix', icon: const Icon(Icons.pix), onPressed: () => _copiar(pix, 'Pix')),
              if ((t['url'] ?? '') != '')
                IconButton(
                    tooltip: 'Abrir o boleto do banco',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => abrirEmNovaAba('${t['url']}')),
              IconButton(
                  tooltip: '2ª via e história',
                  icon: const Icon(Icons.receipt_long_outlined),
                  onPressed: () => mostrarSegundaVia(context, '${t['id']}')),
              if (st == 'rascunho')
                IconButton(
                    tooltip: 'Emitir o rascunho',
                    icon: const Icon(Icons.send_outlined),
                    onPressed: _ocupado ? null : () => _simples(t, 'enviar', 'Rascunho emitido.')),
              if (st == 'a_registrar' && t['via'] == 'api')
                IconButton(
                    tooltip: 'Registrar no banco agora',
                    icon: const Icon(Icons.cloud_upload_outlined),
                    onPressed: _ocupado ? null : () => _simples(t, 'processar', 'Registrado no banco.')),
              if (st == 'erro')
                IconButton(
                    tooltip: 'Tentar de novo',
                    icon: const Icon(Icons.replay),
                    onPressed: _ocupado ? null : () => _simples(t, 'reenviar', 'Enviado de novo ao banco.')),
              if (st == 'registrado' && t['via'] == 'api')
                IconButton(
                    tooltip: 'Consultar no banco',
                    icon: const Icon(Icons.refresh),
                    onPressed: _ocupado ? null : () => _simples(t, 'consultar', 'Consultado no banco.')),
              if (aberto)
                PopupMenuButton<String>(
                  tooltip: 'Mais',
                  onSelected: (op) {
                    if (op == 'baixar') _baixar(t);
                    if (op == 'vencimento') _vencimento(t);
                    if (op == 'cancelar') _cancelar(t);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'baixar', child: ListTile(leading: Icon(Icons.price_check), title: Text('Dar baixa (recebi)'))),
                    PopupMenuItem(value: 'vencimento', child: ListTile(leading: Icon(Icons.event), title: Text('Mudar vencimento'))),
                    PopupMenuItem(value: 'cancelar', child: ListTile(leading: Icon(Icons.block), title: Text('Cancelar'))),
                  ],
                ),
            ]),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final temContas = _contas.isNotEmpty;
    final pend = (_config?['pendencias'] as Map?) ?? const {};
    return Padding(
      padding: margemDaTela(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Títulos', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          FilledButton.icon(onPressed: _ocupado ? null : _emitir, icon: const Icon(Icons.add), label: const Text('Emitir título')),
          if (temContas) ...[
            OutlinedButton.icon(
                onPressed: _ocupado ? null : _gerarRemessa,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text('Gerar remessa${(pend['cnab_a_enviar'] ?? 0) != 0 ? ' (${pend['cnab_a_enviar']})' : ''}')),
            OutlinedButton.icon(
                onPressed: _ocupado ? null : _importarRetorno,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Importar retorno')),
          ],
          IconButton(
              tooltip: 'Configurações › Cobrança',
              onPressed: () => context.go('/titulos/configuracao'),
              icon: const Icon(Icons.settings_outlined)),
        ]),
        const SizedBox(height: 8),
        if (_config != null && _modo == 'manual')
          Card(
            color: Cores.indigo100,
            child: ListTile(
              leading: const Icon(Icons.info_outline, color: Cores.indigo700),
              title: const Text('A empresa está no modo manual: os títulos servem de controle e a baixa é à mão. '
                  'Para boleto/Pix registrado ou CNAB, escolha o modo em Configurações › Cobrança.'),
              trailing: TextButton(onPressed: () => context.go('/titulos/configuracao'), child: const Text('Configurar')),
            ),
          ),
        if ((pend['fila_erro'] ?? 0) != 0)
          Card(
            color: Cores.erro.withValues(alpha: 0.08),
            child: ListTile(
              leading: const Icon(Icons.error_outline, color: Cores.erro),
              title: Text('${pend['fila_erro']} pedido(s) ao banco com erro nos últimos 30 dias. Veja os títulos "Com erro".'),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final f in _filtros.keys)
            ChoiceChip(
                label: Text(f),
                selected: _filtro == f,
                onSelected: (_) {
                  setState(() => _filtro = f);
                  _carregar();
                }),
          SizedBox(
            width: 260,
            child: TextField(
              controller: _busca,
              decoration: const InputDecoration(
                  isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Cliente, TIT-…, nosso número, nota'),
              onSubmitted: (_) => _carregar(),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 16, children: [
          Text('Em aberto: ${reais(_totais['em_aberto'])} (${_totais['em_aberto_qtd'] ?? 0})',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Vencido: ${reais(_totais['vencido'])} (${_totais['vencido_qtd'] ?? 0})',
              style: const TextStyle(color: Cores.alerta, fontWeight: FontWeight.w600)),
          Text('Pago no mês: ${reais(_totais['pago_mes'])} (${_totais['pago_mes_qtd'] ?? 0})',
              style: const TextStyle(color: Cores.sucesso, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: _carregando
              ? const Center(child: CircularProgressIndicator())
              : _erro != null
                  ? Center(child: Text(_erro!, style: const TextStyle(color: Cores.erro)))
                  : _titulos.isEmpty
                      ? const Center(
                          child: Text('Nenhum título aqui. Emita pelo botão acima ou pelo A cobrar (botão Boleto).',
                              style: TextStyle(color: Cores.neutro)))
                      : RefreshIndicator(
                          onRefresh: _carregar,
                          child: ListView(children: [for (final t in _titulos) _linhaTitulo(t)]),
                        ),
        ),
      ]),
    );
  }
}

// ---------- Cancelar (motivo) ----------
class _Motivo extends StatefulWidget {
  const _Motivo({required this.titulo});

  final Map<String, dynamic> titulo;

  @override
  State<_Motivo> createState() => _MotivoState();
}

class _MotivoState extends State<_Motivo> {
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Cancelar ${widget.titulo['codigo']}?'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Se o título está no banco, a baixa é pedida lá (o boleto deixa de valer).'),
          const SizedBox(height: 8),
          TextField(
            controller: _motivo,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Motivo'),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Cores.erro),
          onPressed: _motivo.text.trim().isEmpty ? null : () => Navigator.pop(context, _motivo.text.trim()),
          child: const Text('Cancelar o título'),
        ),
      ],
    );
  }
}

// ---------- Emitir título avulso ----------
class _EmitirTitulo extends StatefulWidget {
  const _EmitirTitulo();

  @override
  State<_EmitirTitulo> createState() => _EmitirTituloState();
}

class _EmitirTituloState extends State<_EmitirTitulo> {
  List<Map<String, dynamic>> _clientes = [];
  Map<String, dynamic>? _cliente;
  String _busca = '';
  final _valor = TextEditingController();
  final _descricao = TextEditingController();
  final _documento = TextEditingController();
  DateTime? _vencimento;
  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    Supabase.instance.client
        .from('clientes')
        .select('id, nome, nome_fantasia, documento')
        .isFilter('excluido_em', null)
        .order('nome', ascending: true)
        .limit(2000)
        .then((r) {
      if (mounted) setState(() => _clientes = r.map((x) => Map<String, dynamic>.from(x)).toList());
    });
  }

  @override
  void dispose() {
    _valor.dispose();
    _descricao.dispose();
    _documento.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final r = await acaoCobranca({
        'acao': 'emitir',
        'cliente_id': _cliente!['id'],
        'valor': lerValor(_valor.text),
        if (_vencimento != null) 'vencimento': dataIso(_vencimento!),
        if (_descricao.text.trim().isNotEmpty) 'descricao': _descricao.text.trim(),
        if (_documento.text.trim().isNotEmpty) 'documento': _documento.text.trim(),
      });
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _busca.toLowerCase();
    final lista = _clientes
        .where((c) => b.isEmpty || '${c['nome']} ${c['nome_fantasia'] ?? ''} ${c['documento'] ?? ''}'.toLowerCase().contains(b))
        .take(50)
        .toList();
    final valor = lerValor(_valor.text);
    return AlertDialog(
      title: const Text('Emitir título'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_cliente == null) ...[
              TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cliente: nome ou CNPJ'),
                onChanged: (v) => setState(() => _busca = v),
              ),
              SizedBox(
                height: 220,
                child: ListView(children: [
                  for (final c in lista)
                    ListTile(
                      dense: true,
                      title: Text('${c['nome']}'),
                      subtitle: Text([c['nome_fantasia'], c['documento']].where((x) => (x ?? '') != '').join(' · ')),
                      onTap: () => setState(() => _cliente = c),
                    ),
                ]),
              ),
            ] else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text('${_cliente!['nome']}'),
                subtitle: Text('${_cliente!['documento'] ?? 'sem CPF/CNPJ'}'),
                trailing: TextButton(onPressed: () => setState(() => _cliente = null), child: const Text('Trocar')),
              ),
            TextField(
              controller: _valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor (R\$)'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(controller: _descricao, decoration: const InputDecoration(labelText: 'Descrição (opcional)')),
            TextField(controller: _documento, decoration: const InputDecoration(labelText: 'Nota, fatura ou recibo (opcional)')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_outlined),
              label: Text(_vencimento == null ? 'Vencimento padrão da empresa' : 'Vence em ${dataBr(dataIso(_vencimento!))}'),
              onPressed: () async {
                final hoje = DateTime.now();
                final d = await showDatePicker(
                    context: context,
                    initialDate: _vencimento ?? hoje.add(const Duration(days: 5)),
                    firstDate: hoje,
                    lastDate: hoje.add(const Duration(days: 365)));
                if (d != null && mounted) setState(() => _vencimento = d);
              },
            ),
            if (_erro != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8), child: Text(_erro!, style: const TextStyle(color: Cores.erro))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _salvando ? null : () => Navigator.pop(context), child: const Text('Voltar')),
        FilledButton(
          onPressed: _salvando || _cliente == null || valor == null || valor <= 0 ? null : _salvar,
          child: const Text('Emitir'),
        ),
      ],
    );
  }
}
