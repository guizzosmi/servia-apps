import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_atendimento.dart';
import '../core/acoes_mensagens.dart';
import '../core/acoes_orcamento.dart';
import '../core/conteudos.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import '../widgets/indicador_sync.dart';
import '../widgets/status_chip.dart';
import 'assinatura_tela.dart';

/// Orçamento no local: monta com os itens do catálogo (e, se a empresa
/// liberar, itens fora do catálogo), desconto até o limite da empresa, e
/// mostra ao cliente para assinar, ou deixa para o gestor. Se o gestor já
/// enviou um orçamento, colhe a assinatura dele. Tudo funciona sem internet.
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
  String? _aprovadorNome; // sem contato cadastrado: o nome digitado
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
      _aprovadorNome = r['aprovador_nome'] as String?;
      _diagnostico.text = '${r['diagnostico'] ?? ''}';
      _desconto.text = numeroBr(r['desconto_pct'] ?? 0);
      _itens = [
        for (final i in ((r['itens'] as List?) ?? const []).cast<Map>())
          if (ItemOrcamento.doRascunho(i, (id) => banco.um('produtos', id)) case final ItemOrcamento item) item,
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
        'aprovador_nome': _aprovadorNome,
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

  bool get _avulsosLiberados => AcoesOrcamento.config.itensAvulsos != 'desligado';

  Future<void> _adicionar() async {
    final produtos = EstadoApp.instancia.banco!.todos('produtos').where((p) => p['ativo'] != false).toList()
      ..sort((a, b) => '${a['descricao']}'.compareTo('${b['descricao']}'));
    // Volta o produto escolhido, ou o texto buscado quando é item fora do catálogo.
    final escolhido = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EscolherProduto(produtos: produtos, permitirAvulso: _avulsosLiberados),
    );
    if (!mounted) return;
    if (escolhido is String) {
      await _itemAvulso(descricaoInicial: escolhido);
      return;
    }
    if (escolhido is! Map<String, dynamic>) return;
    final qtd = await _pedirQuantidade('${escolhido['descricao']}', '${escolhido['unidade'] ?? 'un'}', 1);
    if (qtd == null || !mounted) return;
    _itens.add(ItemOrcamento(id: AcoesAtendimento.novoId(), produto: escolhido, quantidade: qtd));
    _mudou();
  }

  /// Item fora do catálogo: o técnico digita descrição, tipo, unidade e preço.
  Future<void> _itemAvulso({ItemOrcamento? atual, String descricaoInicial = ''}) async {
    final item = await showDialog<ItemOrcamento>(
      context: context,
      builder: (_) => _ItemAvulsoDialog(atual: atual, descricaoInicial: descricaoInicial),
    );
    if (item == null || !mounted) return;
    final k = atual == null ? -1 : _itens.indexOf(atual);
    if (k >= 0) {
      _itens[k] = item;
    } else {
      _itens.add(item);
    }
    _mudou();
  }

  Future<void> _alterarQuantidade(ItemOrcamento i) async {
    if (i.avulso) return _itemAvulso(atual: i);
    final qtd = await _pedirQuantidade(i.descricao, i.unidade, i.quantidade);
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
    const outra = '__outra__';
    final escolhido = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .75),
          child: ListView(shrinkWrap: true, children: [
            const ListTile(title: Text('Quem aprova', style: TextStyle(fontWeight: FontWeight.w800))),
            if (contatos.isEmpty)
              const ListTile(
                title: Text('Nenhum contato cadastrado para este cliente.'),
                subtitle: Text('Digite o nome de quem aprova. O gestor pode cadastrar o contato depois.'),
              ),
            for (final c in contatos)
              ListTile(
                title: Text('${c['nome']}'),
                subtitle: Text([c['cargo'], c['telefone']].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
                trailing: c['id'] == _contatoId ? const Icon(Icons.check, color: Cores.sucesso) : null,
                onTap: () => Navigator.of(ctx).pop('${c['id']}'),
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Outra pessoa (digitar o nome)'),
              subtitle: _contatoId == null && (_aprovadorNome ?? '').isNotEmpty ? Text(_aprovadorNome!) : null,
              trailing: _contatoId == null && (_aprovadorNome ?? '').isNotEmpty
                  ? const Icon(Icons.check, color: Cores.sucesso)
                  : null,
              onTap: () => Navigator.of(ctx).pop(outra),
            ),
          ]),
        ),
      ),
    );
    if (escolhido == null || !mounted) return;
    if (escolhido == outra) {
      final nome = await _digitarNome();
      if (nome == null || !mounted) return;
      _contatoId = null;
      _aprovadorNome = nome;
    } else {
      _contatoId = escolhido;
      _aprovadorNome = null;
    }
    _mudou();
  }

  Future<String?> _digitarNome() async {
    final c = TextEditingController(text: _contatoId == null ? _aprovadorNome ?? '' : '');
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) {
        void ok() {
          final v = c.text.trim();
          if (v.isNotEmpty) Navigator.of(ctx).pop(v);
        }

        return AlertDialog(
          title: const Text('Quem aprova pelo cliente'),
          content: TextField(
            controller: c,
            autofocus: true,
            maxLength: 120,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Jorge (zelador)'),
            onSubmitted: (_) => ok(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
            FilledButton(onPressed: ok, child: const Text('OK')),
          ],
        );
      },
    );
    // Sem dispose: o diálogo ainda anima a saída usando o campo.
    return r;
  }

  // ---------------------------------------------------------------- ações

  String? _problema({bool paraCliente = false, bool temAberto = false}) {
    final cfg = AcoesOrcamento.config;
    final max = cfg.descontoMaxPct;
    if (_itens.isEmpty) return 'Inclua ao menos um item.';
    final avulsos = _itens.where((i) => i.avulso).length;
    if (avulsos > 0 && cfg.itensAvulsos == 'desligado') {
      return 'A empresa não usa mais itens fora do catálogo no app: tire os $avulsos item(ns) marcado(s).';
    }
    if (avulsos > 0 && paraCliente && cfg.itensAvulsos == 'gestor') {
      if (temAberto) {
        return 'Com item fora do catálogo, o orçamento precisa da revisão do gestor, e esta OS já tem um '
            'orçamento em aberto com ele. Tire o item fora do catálogo ou fale com o gestor.';
      }
      return 'Com item fora do catálogo, o orçamento vai para o gestor revisar antes (configuração da empresa). '
          'Use "Deixar para o gestor".';
    }
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
        aprovadorNome: _aprovadorNome,
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
    final problema = _problema(paraCliente: true, temAberto: aberto != null);
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
      aprovadorNome: _aprovadorNome,
      itens: _itens,
      descontoPct: _descontoPct,
    );
    final contato = EstadoApp.instancia.banco!.um('contatos', _contatoId);
    final decisao = await AssinaturaTela.abrir(
      context,
      AssinaturaTela(
        conteudo: conteudo,
        nomeInicial: (contato?['nome'] as String?) ?? _aprovadorNome,
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
        aprovadorNome: _aprovadorNome,
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

  /// Link de aprovação do orçamento enviado, pelo WhatsApp (o cliente
  /// aprova depois, pelo celular dele).
  Future<void> _mandarLink(Map<String, dynamic> atd, Map<String, dynamic> orc) async {
    final os = EstadoApp.instancia.banco!.um('ordens_servico', atd['os_id']);
    if (os == null) return;
    final mandou = await AcoesMensagens.mandar(
      context,
      modelo: 'orcamento_link',
      titulo: 'Mandar o link do ${AcoesOrcamento.codigo(orc)}',
      os: os,
      contatoInicialId: orc['contato_id'] as String?,
      valores: {
        'orcamento': '${orc['codigo'] ?? ''}',
        'total': dinheiro(orc['total']),
        'validade': dataBr(orc['validade_ate']),
      },
      link: LinkPreparado.novo(entidade: 'orcamento', osId: '${os['id']}', orcamentoId: '${orc['id']}'),
      entidade: 'orcamento',
      entidadeId: '${orc['id']}',
    );
    if (!mandou || !mounted) return;
    _aviso('Link registrado. Ele passa a abrir quando o aparelho sincronizar.');
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
          if (enviado && !_montarOutro) ...[
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _gravando ? null : () => _assinarEnviado(atd, orc),
                icon: const Icon(Icons.draw_outlined),
                label: const Text('Mostrar ao cliente e colher assinatura'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _gravando ? null : () => _mandarLink(atd, orc),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Mandar o link pelo WhatsApp'),
              ),
            ),
          ],
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
    final nomeLivre = contato == null && (_aprovadorNome ?? '').isNotEmpty ? _aprovadorNome : null;
    final temAvulso = _itens.any((i) => i.avulso);
    return [
      if (_montarOutro)
        const Padding(
          padding: EdgeInsets.only(top: 12, bottom: 4),
          child: Text('NOVO ORÇAMENTO NO LOCAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Cores.neutro)),
        ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(contato != null ? '${contato['nome']}' : nomeLivre ?? 'Escolher quem aprova'),
          subtitle: Text(nomeLivre != null ? 'Quem aprova pelo cliente (sem cadastro)' : 'Quem aprova pelo cliente'),
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
          label: Text(_avulsosLiberados ? 'Adicionar item' : 'Adicionar item do catálogo'),
        ),
      ),
      if (_itens.isEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
              switch (cfg.itensAvulsos) {
                'liberado' => 'Use os itens do catálogo; se faltar algum, inclua como item fora do catálogo.',
                'gestor' => 'Use os itens do catálogo. Item fora do catálogo também entra, mas aí o orçamento '
                    'vai para o gestor revisar antes do cliente.',
                _ => 'No app, o orçamento usa só itens do catálogo (peças e serviços cadastrados no painel).',
              },
              style: const TextStyle(color: Cores.neutro)),
        ),
      if (temAvulso && cfg.itensAvulsos == 'gestor')
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: Text('Tem item fora do catálogo: este orçamento vai para o gestor revisar antes do cliente.',
              style: TextStyle(color: Cores.alerta, fontWeight: FontWeight.w600)),
        ),
      for (final i in _itens)
        Card(
          child: ListTile(
            title: Text(i.descricao),
            subtitle: Text('${numeroBr(i.quantidade)} ${i.unidade} × ${dinheiro(i.preco)}'
                '${pct > 0 ? ' − ${dinheiro(i.desconto(pct))}' : ''}'
                '${i.avulso ? '\nfora do catálogo · ${i.tipo == 'produto' ? 'peça' : 'serviço'}' : ''}'),
            isThreeLine: i.avulso,
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

/// Busca no catálogo (peças e serviços ativos). Volta o produto, ou o texto
/// buscado quando o técnico escolhe incluir um item fora do catálogo.
class _EscolherProduto extends StatefulWidget {
  const _EscolherProduto({required this.produtos, this.permitirAvulso = false});

  final List<Map<String, dynamic>> produtos;
  final bool permitirAvulso;

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
          ListTile(
            title: Text(widget.permitirAvulso ? 'Adicionar item' : 'Item do catálogo',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
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
          if (widget.permitirAvulso)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(_busca.text.trim()),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Item fora do catálogo'),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Item fora do catálogo: descrição, peça ou serviço, quantidade, unidade e preço.
class _ItemAvulsoDialog extends StatefulWidget {
  const _ItemAvulsoDialog({this.atual, this.descricaoInicial = ''});

  final ItemOrcamento? atual;
  final String descricaoInicial;

  @override
  State<_ItemAvulsoDialog> createState() => _ItemAvulsoDialogState();
}

class _ItemAvulsoDialogState extends State<_ItemAvulsoDialog> {
  late final _descricao = TextEditingController(text: widget.atual?.descricao ?? widget.descricaoInicial);
  late final _quantidade = TextEditingController(text: numeroBr(widget.atual?.quantidade ?? 1));
  late final _unidade = TextEditingController(text: widget.atual?.unidade ?? 'un');
  late final _preco = TextEditingController(
      text: widget.atual == null ? '' : widget.atual!.preco.toStringAsFixed(2).replaceAll('.', ','));
  late String _tipo = widget.atual?.tipo ?? 'servico';
  String? _erro;

  // Sem dispose dos campos: o diálogo ainda anima a saída usando eles.

  /// Aceita "1.234,56", "1234,56" e "1234.56".
  static num? _numero(String t) {
    final s = t.trim().replaceAll(' ', '');
    if (s.isEmpty) return null;
    return num.tryParse(s.contains(',') ? s.replaceAll('.', '').replaceAll(',', '.') : s);
  }

  void _ok() {
    final descricao = _descricao.text.trim();
    final qtd = _numero(_quantidade.text);
    final preco = _numero(_preco.text);
    final erro = descricao.isEmpty
        ? 'Digite a descrição.'
        : qtd == null || qtd <= 0
            ? 'Quantidade inválida.'
            : preco == null || preco < 0
                ? 'Informe o preço unitário.'
                : null;
    if (erro != null) {
      setState(() => _erro = erro);
      return;
    }
    final unidade = _unidade.text.trim();
    Navigator.of(context).pop(ItemOrcamento(
      id: widget.atual?.id ?? AcoesAtendimento.novoId(),
      quantidade: qtd!,
      descricao: descricao,
      tipo: _tipo,
      unidade: unidade.isEmpty ? 'un' : unidade,
      preco: centavos(preco!),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Item fora do catálogo'),
      scrollable: true,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _descricao,
          autofocus: widget.atual == null && widget.descricaoInicial.isEmpty,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Descrição (o cliente vê)'),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'servico', label: Text('Serviço'), icon: Icon(Icons.handyman_outlined)),
            ButtonSegment(value: 'produto', label: Text('Peça'), icon: Icon(Icons.inventory_2_outlined)),
          ],
          selected: {_tipo},
          onSelectionChanged: (v) => setState(() => _tipo = v.first),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _quantidade,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantidade'),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _unidade,
              maxLength: 10,
              decoration: const InputDecoration(labelText: 'Unidade', counterText: ''),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _preco,
          autofocus: widget.atual == null && widget.descricaoInicial.isNotEmpty,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Preço unitário', prefixText: 'R\$ '),
          onSubmitted: (_) => _ok(),
        ),
        if (_erro != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_erro!, style: const TextStyle(color: Cores.erro)),
          ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _ok, child: const Text('OK')),
      ],
    );
  }
}
