import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_atendimento.dart';
import '../core/acoes_orcamento.dart';
import '../core/conteudos.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import '../widgets/indicador_sync.dart';
import '../widgets/status_chip.dart';
import 'assinatura_tela.dart';

/// Orçamento no local: monta com os itens do catálogo (desconto até o
/// limite da empresa) e mostra ao cliente para assinar, ou deixa para o
/// gestor. Se o gestor já enviou um orçamento, colhe a assinatura dele.
/// Tudo funciona sem internet.
class OrcamentoTela extends StatefulWidget {
  const OrcamentoTela({super.key, required this.atendimentoId});

  final String atendimentoId;

  @override
  State<OrcamentoTela> createState() => _OrcamentoTelaState();
}

class _OrcamentoTelaState extends State<OrcamentoTela> {
  final _diagnostico = TextEditingController();
  final _desconto = TextEditingController();
  String _orcamentoId = AcoesAtendimento.novoId();
  String? _contatoId;
  List<ItemOrcamento> _itens = [];
  bool _montarOutro = false;
  bool _gravando = false;

  Map<String, dynamic>? get _atd => EstadoApp.instancia.banco?.um('atendimentos', widget.atendimentoId);

  @override
  void initState() {
    super.initState();
    final atd = _atd;
    if (atd == null) return;
    final banco = EstadoApp.instancia.banco!;
    final os = banco.um('ordens_servico', atd['os_id']) ?? const {};
    final r = AcoesOrcamento.rascunho(atd['id']);
    if (r != null) {
      // Continua o que estava sendo montado (os preços são os do catálogo de agora).
      _orcamentoId = '${r['orcamento_id']}';
      _contatoId = r['contato_id'] as String?;
      _diagnostico.text = '${r['diagnostico'] ?? ''}';
      _desconto.text = numeroBr(r['desconto_pct'] ?? 0);
      _itens = [
        for (final i in ((r['itens'] as List?) ?? const []).cast<Map>())
          if (banco.um('produtos', i['produto_id']) case final Map<String, dynamic> prod)
            ItemOrcamento(id: '${i['id']}', produto: prod, quantidade: num.tryParse('${i['quantidade']}') ?? 1),
      ];
      _montarOutro = r['montar_outro'] == true;
    } else {
      _desconto.text = '0';
      // Diagnóstico: o que o técnico já escreveu no relato; senão o problema da OS.
      final relato = [
        if ('${atd['problema_identificado'] ?? ''}'.isNotEmpty) 'Problema: ${atd['problema_identificado']}',
        if ('${atd['causa'] ?? ''}'.isNotEmpty) 'Causa: ${atd['causa']}',
      ].join('\n');
      _diagnostico.text = relato.isNotEmpty ? relato : '${os['problema_relatado'] ?? ''}';
      // Contato: um aprovador do cliente (do local primeiro); senão quem pediu.
      final contatos = _contatos(os);
      final aprovador = contatos.where((c) => ((c['funcoes'] as List?) ?? const []).contains('aprovador')).toList()
        ..sort((a, b) => (b['local_id'] == os['local_id'] ? 1 : 0).compareTo(a['local_id'] == os['local_id'] ? 1 : 0));
      _contatoId = (aprovador.firstOrNull ?? banco.um('contatos', os['solicitante_contato_id']))?['id'] as String?;
    }
  }

  @override
  void dispose() {
    _diagnostico.dispose();
    _desconto.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _contatos(Map os) => EstadoApp.instancia.banco!
      .todos('contatos')
      .where((c) => c['cliente_id'] == os['cliente_id'] && c['ativo'] != false)
      .toList()
    ..sort((a, b) => '${a['nome']}'.compareTo('${b['nome']}'));

  num get _descontoPct => num.tryParse(_desconto.text.trim().replaceAll(',', '.')) ?? 0;

  void _aviso(String texto, {bool erro = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));

  /// Guarda o que está sendo montado (se sair da tela, continua depois).
  Future<void> _guardar() => AcoesOrcamento.guardarRascunho(widget.atendimentoId, {
        'orcamento_id': _orcamentoId,
        'contato_id': _contatoId,
        'diagnostico': _diagnostico.text,
        'desconto_pct': _descontoPct,
        'montar_outro': _montarOutro,
        'itens': [for (final i in _itens) i.paraRascunho()],
      });

  void _mudou() {
    setState(() {});
    _guardar();
  }

  // ---------------------------------------------------------------- itens

  Future<void> _adicionar() async {
    final produtos = EstadoApp.instancia.banco!.todos('produtos').where((p) => p['ativo'] != false).toList()
      ..sort((a, b) => '${a['descricao']}'.compareTo('${b['descricao']}'));
    final escolhido = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EscolherProduto(produtos: produtos),
    );
    if (!mounted) return;
    if (escolhido == null) return;
    final qtd = await _pedirQuantidade('${escolhido['descricao']}', '${escolhido['unidade'] ?? 'un'}', 1);
    if (qtd == null || !mounted) return;
    _itens.add(ItemOrcamento(id: AcoesAtendimento.novoId(), produto: escolhido, quantidade: qtd));
    _mudou();
  }

  Future<void> _alterarQuantidade(ItemOrcamento i) async {
    final qtd = await _pedirQuantidade('${i.produto['descricao']}', '${i.produto['unidade'] ?? 'un'}', i.quantidade);
    if (qtd == null || !mounted) return;
    i.quantidade = qtd;
    _mudou();
  }

  Future<num?> _pedirQuantidade(String nome, String unidade, num atual) async {
    final c = TextEditingController(text: numeroBr(atual));
    final r = await showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(nome),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Quantidade', suffixText: unidade),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = num.tryParse(c.text.trim().replaceAll(',', '.'));
              if (v != null && v > 0) Navigator.of(ctx).pop(v);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    // Sem dispose: o diálogo ainda anima a saída usando o campo.
    return r;
  }

  Future<void> _escolherContato(Map os) async {
    final contatos = _contatos(os);
    final escolhido = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Quem aprova', style: TextStyle(fontWeight: FontWeight.w800))),
          if (contatos.isEmpty)
            const ListTile(title: Text('Nenhum contato cadastrado para este cliente.')),
          for (final c in contatos)
            ListTile(
              title: Text('${c['nome']}'),
              subtitle: Text([c['cargo'], c['telefone']].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
              trailing: c['id'] == _contatoId ? const Icon(Icons.check, color: Cores.sucesso) : null,
              onTap: () => Navigator.of(ctx).pop('${c['id']}'),
            ),
        ]),
      ),
    );
    if (escolhido == null || !mounted) return;
    _contatoId = escolhido;
    _mudou();
  }

  // ---------------------------------------------------------------- ações

  String? _problema() {
    final max = AcoesOrcamento.config.descontoMaxPct;
    if (_itens.isEmpty) return 'Inclua ao menos um item do catálogo.';
    final pct = num.tryParse(_desconto.text.trim().replaceAll(',', '.'));
    if (pct == null || pct < 0) return 'Desconto inválido.';
    if (pct > max) return 'O desconto vai até ${numeroBr(max)}% (configuração da empresa).';
    return null;
  }

  Future<void> _paraOGestor(Map<String, dynamic> atd) async {
    final problema = _problema();
    if (problema != null) {
      _aviso(problema, erro: true);
      return;
    }
    setState(() => _gravando = true);
    try {
      await AcoesOrcamento.registrarMontado(
        atd: atd,
        orcamentoId: _orcamentoId,
        contatoId: _contatoId,
        diagnostico: _diagnostico.text.trim(),
        itens: _itens,
        descontoPct: _descontoPct,
        destino: 'gestor',
      );
      if (!mounted) return;
      _aviso('Orçamento deixado para o gestor. Ele aparece no painel depois da sincronização.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _aviso('Não foi possível registrar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  Future<void> _mostrarAoCliente(Map<String, dynamic> atd, Map<String, dynamic>? aberto) async {
    final problema = _problema();
    if (problema != null) {
      _aviso(problema, erro: true);
      return;
    }
    if (aberto != null) {
      final segue = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Já há um orçamento em aberto'),
          content: Text('Se o cliente decidir agora, o ${AcoesOrcamento.codigo(aberto)} '
              '(${statusOrcamento[aberto['status']]?.texto.toLowerCase() ?? aberto['status']}) será cancelado '
              'e fica valendo este, feito no local.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Continuar')),
          ],
        ),
      );
      if (!mounted) return;
      if (segue != true) return;
    }
    final conteudo = Conteudos.orcamentoNovo(
      atd: atd,
      diagnostico: _diagnostico.text.trim(),
      contatoId: _contatoId,
      itens: _itens,
      descontoPct: _descontoPct,
    );
    final contato = EstadoApp.instancia.banco!.um('contatos', _contatoId);
    final decisao = await AssinaturaTela.abrir(
      context,
      AssinaturaTela(
        conteudo: conteudo,
        nomeInicial: contato?['nome'] as String?,
        pedirConcordo: true,
        permitirRecusa: true,
      ),
    );
    if (!mounted) return;
    if (decisao == null) return;
    setState(() => _gravando = true);
    try {
      await AcoesOrcamento.registrarMontado(
        atd: atd,
        orcamentoId: _orcamentoId,
        contatoId: _contatoId,
        diagnostico: _diagnostico.text.trim(),
        itens: _itens,
        descontoPct: _descontoPct,
        destino: decisao.decisao,
        conteudo: conteudo,
        decisao: decisao,
      );
      if (!mounted) return;
      _aviso(decisao.decisao == 'aprovado'
          ? 'Orçamento aprovado e assinado. Os itens vão para a OS na sincronização.'
          : 'Recusa registrada.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _aviso('Não foi possível registrar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  Future<void> _assinarEnviado(Map<String, dynamic> atd, Map<String, dynamic> orc) async {
    final conteudo = Conteudos.orcamentoEnviado(orc, atd);
    final contato = EstadoApp.instancia.banco!.um('contatos', orc['contato_id']);
    final decisao = await AssinaturaTela.abrir(
      context,
      AssinaturaTela(
        conteudo: conteudo,
        nomeInicial: contato?['nome'] as String?,
        pedirConcordo: true,
        permitirRecusa: true,
      ),
    );
    if (!mounted) return;
    if (decisao == null) return;
    setState(() => _gravando = true);
    try {
      await AcoesOrcamento.registrarAssinatura(atd: atd, orcamento: orc, conteudo: conteudo, decisao: decisao);
      if (!mounted) return;
      _aviso(decisao.decisao == 'aprovado' ? 'Orçamento aprovado e assinado.' : 'Recusa registrada.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _aviso('Não foi possível registrar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  // ---------------------------------------------------------------- tela

  @override
  Widget build(BuildContext context) {
    final banco = EstadoApp.instancia.banco!;
    return ListenableBuilder(
      listenable: banco,
      builder: (context, _) {
        final atd = _atd;
        if (atd == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Orçamento')),
            body: const Center(child: Text('Atendimento não encontrado neste aparelho.')),
          );
        }
        final os = banco.um('ordens_servico', atd['os_id']) ?? const {};
        final pode = AcoesOrcamento.podeOrcar(atd);
        final aberto = AcoesOrcamento.abertoDaOs(atd['os_id']);
        final outros = AcoesOrcamento.daOs(atd['os_id']).where((o) => o['id'] != aberto?['id']).toList();
        final montando = aberto == null || _montarOutro;

        return Scaffold(
          appBar: AppBar(
            title: Text('Orçamento · ${os['codigo'] ?? ''}'),
            actions: const [IndicadorSync()],
          ),
          body: !pode
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(AcoesOrcamento.motivoSemPermissao(),
                        textAlign: TextAlign.center, style: const TextStyle(color: Cores.neutro)),
                  ),
                )
              : ListView(padding: const EdgeInsets.all(12), children: [
                  if (aberto != null) _cartaoAberto(atd, aberto),
                  if (montando) ..._montagem(os),
                  if (outros.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 16, bottom: 4),
                      child: Text('ANTERIORES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Cores.neutro)),
                    ),
                    for (final o in outros) _linhaOrcamento(o),
                  ],
                ]),
          bottomNavigationBar: pode && montando
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(children: [
                      if (aberto == null) ...[
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: OutlinedButton(
                              onPressed: _gravando ? null : () => _paraOGestor(atd),
                              child: const Text('Deixar para o gestor', textAlign: TextAlign.center),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: _gravando ? null : () => _mostrarAoCliente(atd, aberto),
                            icon: const Icon(Icons.draw_outlined),
                            label: const Text('Mostrar ao cliente'),
                          ),
                        ),
                      ),
                    ]),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _linhaOrcamento(Map<String, dynamic> o) {
    final aceite = AcoesOrcamento.aceiteDe('orcamento', o['id']);
    return Card(
      child: ListTile(
        title: Text(AcoesOrcamento.codigo(o)),
        subtitle: Text([
          dinheiro(o['total']),
          if (aceite != null) '${aceite['decisao'] == 'aprovado' ? 'aprovado' : 'recusado'} por ${aceite['nome']}',
          if (o['origem'] == 'app') 'feito no local',
        ].join(' · ')),
        trailing: StatusChip(o['status'] as String?, statusOrcamento),
      ),
    );
  }

  /// O orçamento em aberto da OS: enviado (colher assinatura) ou com o gestor.
  Widget _cartaoAberto(Map<String, dynamic> atd, Map<String, dynamic> orc) {
    final itens = AcoesOrcamento.itensDe(orc['id']);
    final enviado = orc['status'] == 'enviado';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(AcoesOrcamento.codigo(orc), style: const TextStyle(fontWeight: FontWeight.w800))),
            StatusChip(orc['status'] as String?, statusOrcamento),
          ]),
          const SizedBox(height: 6),
          for (final i in itens)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(child: Text('${i['descricao']} · ${numeroBr(i['quantidade'])} ${i['unidade'] ?? ''}')),
                Text(dinheiro(i['total'])),
              ]),
            ),
          const Divider(),
          Text('Total ${dinheiro(orc['total'])}',
              textAlign: TextAlign.right, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          if (orc['validade_ate'] != null)
            Text('Válido até ${dataBr(orc['validade_ate'])}', textAlign: TextAlign.right,
                style: const TextStyle(color: Cores.neutro)),
          const SizedBox(height: 8),
          if (enviado && !_montarOutro)
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _gravando ? null : () => _assinarEnviado(atd, orc),
                icon: const Icon(Icons.draw_outlined),
                label: const Text('Mostrar ao cliente e colher assinatura'),
              ),
            ),
          if (!enviado)
            const Text('Este orçamento está com o gestor (rascunho): ele revisa e envia ao cliente.',
                style: TextStyle(color: Cores.neutro)),
          if (!_montarOutro)
            TextButton(
              onPressed: () {
                _montarOutro = true;
                _mudou();
              },
              child: const Text('Montar outro orçamento aqui no local'),
            ),
        ]),
      ),
    );
  }

  List<Widget> _montagem(Map os) {
    final cfg = AcoesOrcamento.config;
    final pct = _descontoPct;
    final bruto = _itens.fold<num>(0, (s, i) => s + i.bruto);
    final desconto = _itens.fold<num>(0, (s, i) => s + i.desconto(pct));
    final total = _itens.fold<num>(0, (s, i) => s + i.total(pct));
    final contato = EstadoApp.instancia.banco!.um('contatos', _contatoId);
    return [
      if (_montarOutro)
        const Padding(
          padding: EdgeInsets.only(top: 12, bottom: 4),
          child: Text('NOVO ORÇAMENTO NO LOCAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Cores.neutro)),
        ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(contato == null ? 'Escolher quem aprova' : '${contato['nome']}'),
          subtitle: const Text('Quem aprova pelo cliente'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _escolherContato(os),
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _diagnostico,
        minLines: 2,
        maxLines: 6,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Diagnóstico (o cliente vê)', alignLabelWithHint: true),
        onChanged: (_) => _guardar(),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: _adicionar,
          icon: const Icon(Icons.add),
          label: const Text('Adicionar item do catálogo'),
        ),
      ),
      if (_itens.isEmpty)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('No app, o orçamento usa só itens do catálogo (peças e serviços cadastrados no painel).',
              style: TextStyle(color: Cores.neutro)),
        ),
      for (final i in _itens)
        Card(
          child: ListTile(
            title: Text('${i.produto['descricao']}'),
            subtitle: Text('${numeroBr(i.quantidade)} ${i.produto['unidade'] ?? 'un'} × ${dinheiro(i.preco)}'
                '${pct > 0 ? ' − ${dinheiro(i.desconto(pct))}' : ''}'),
            onTap: () => _alterarQuantidade(i),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(dinheiro(i.total(pct)), style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                tooltip: 'Tirar',
                onPressed: () {
                  _itens.remove(i);
                  _mudou();
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ]),
          ),
        ),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 150,
          child: TextField(
            controller: _desconto,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Desconto',
              suffixText: '%',
              helperText: 'até ${numeroBr(cfg.descontoMaxPct)}%',
              errorText: pct > cfg.descontoMaxPct ? 'Máximo ${numeroBr(cfg.descontoMaxPct)}%' : null,
            ),
            onChanged: (_) => _mudou(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (desconto > 0) Text('Subtotal ${dinheiro(bruto)}', style: const TextStyle(color: Cores.neutro)),
            if (desconto > 0) Text('Descontos - ${dinheiro(desconto)}', style: const TextStyle(color: Cores.neutro)),
            Text('Total ${dinheiro(total)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text('Validade: ${cfg.validadeDias} dias', style: const TextStyle(color: Cores.neutro, fontSize: 12)),
          ]),
        ),
      ]),
    ];
  }
}

/// Busca no catálogo (peças e serviços ativos).
class _EscolherProduto extends StatefulWidget {
  const _EscolherProduto({required this.produtos});

  final List<Map<String, dynamic>> produtos;

  @override
  State<_EscolherProduto> createState() => _EscolherProdutoState();
}

class _EscolherProdutoState extends State<_EscolherProduto> {
  final _busca = TextEditingController();

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  String _texto(Map p) =>
      [p['codigo'], p['descricao'], ...((p['sinonimos'] as List?) ?? const [])].where((x) => x != null).join(' ');

  @override
  Widget build(BuildContext context) {
    final b = _busca.text.trim().toLowerCase();
    final achados = widget.produtos.where((p) => b.isEmpty || _texto(p).toLowerCase().contains(b)).take(60).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: Column(children: [
          const ListTile(title: Text('Item do catálogo', style: TextStyle(fontWeight: FontWeight.w800))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _busca,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Buscar', prefixIcon: Icon(Icons.search)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: achados.isEmpty
                ? const Center(child: Text('Nada encontrado no catálogo.', style: TextStyle(color: Cores.neutro)))
                : ListView(children: [
                    for (final p in achados)
                      ListTile(
                        title: Text('${p['descricao']}'),
                        subtitle: Text([p['codigo'], p['tipo'] == 'servico' ? 'serviço' : 'peça']
                            .where((x) => x != null)
                            .join(' · ')),
                        trailing: Text(dinheiro(p['preco_venda']), style: const TextStyle(fontWeight: FontWeight.w700)),
                        onTap: () => Navigator.of(context).pop(p),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}
