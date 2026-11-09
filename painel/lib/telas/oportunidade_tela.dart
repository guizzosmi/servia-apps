import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/arquivo_web.dart';
import '../servicos/comercial.dart';
import '../servicos/status.dart';
import '../widgets/campos_data_hora.dart';
import '../widgets/comercial_itens.dart';
import '../widgets/comercial_linha_do_tempo.dart';
import '../widgets/margem.dart';
import 'comercial_funil_tela.dart' show pedirMotivoPerda;

/// Oportunidade do Comercial (guia 90): dados do contato ou cliente, valores, etapa,
/// orçamento e contrato ligados e as atividades (tarefas e anotações).
/// Guia 97: itens da proposta (com itens, os valores são a soma), histórico do cliente (OS, orçamentos,
/// contratos, cobranças), o WhatsApp fica registrado e concluir a última tarefa pede o próximo passo.
class OportunidadeTela extends StatefulWidget {
  const OportunidadeTela({super.key, this.id});

  /// null = nova.
  final String? id;

  @override
  State<OportunidadeTela> createState() => _OportunidadeTelaState();
}

class _OportunidadeTelaState extends State<OportunidadeTela> {
  final _db = Supabase.instance.client;
  final _titulo = TextEditingController();
  final _contato = TextEditingController();
  final _empresa = TextEditingController();
  final _telefone = TextEditingController();
  final _email = TextEditingController();
  final _cidade = TextEditingController();
  final _uf = TextEditingController();
  final _valor = TextEditingController();
  final _mensal = TextEditingController();
  final _obs = TextEditingController();
  String _origem = 'indicacao';
  String? _responsavel;
  DateTime? _previsao;
  String? _orcamento;
  String? _contrato;

  Map<String, dynamic>? _op;
  List<Map<String, dynamic>> _etapas = [];
  List<Map<String, dynamic>> _responsaveis = [];
  List<Map<String, dynamic>> _atividades = [];
  List<Map<String, dynamic>> _orcamentos = [];
  List<Map<String, dynamic>> _contratos = [];
  int _itens = 0;
  bool _carregando = true;
  bool _salvando = false;
  String? _erro;

  String? get _id => widget.id ?? _op?['id'] as String?;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in [_titulo, _contato, _empresa, _telefone, _email, _cidade, _uf, _valor, _mensal, _obs]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> _lista(dynamic v) =>
      v is List ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];

  String _numero(Object? v) {
    final n = num.tryParse('${v ?? ''}') ?? 0;
    return n == 0 ? '' : n.toStringAsFixed(2).replaceAll('.', ',');
  }

  num _lerNumero(TextEditingController c) => num.tryParse(c.text.trim().replaceAll('.', '').replaceAll(',', '.')) ?? 0;

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final resp = await _db.rpc('comercial_responsaveis');
      _responsaveis = _lista(resp);
      final funil = await _db.rpc('comercial_funil', params: {'p': <String, dynamic>{}});
      _etapas = _lista((funil as Map)['etapas']);
      if (widget.id != null) {
        final o = await _db
            .from('oportunidades')
            .select('*, clientes(nome, telefone)')
            .eq('id', widget.id!)
            .single();
        _op = Map<String, dynamic>.from(o);
        _preencher();
        await _carregarRelacionados();
      } else {
        _responsavel = Sessao.atual?.usuarioId;
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _preencher() {
    final o = _op!;
    _titulo.text = '${o['titulo'] ?? ''}';
    _contato.text = '${o['contato_nome'] ?? ''}';
    _empresa.text = '${o['empresa_nome'] ?? ''}';
    _telefone.text = '${o['telefone'] ?? ''}';
    _email.text = '${o['email'] ?? ''}';
    _cidade.text = '${o['cidade'] ?? ''}';
    _uf.text = '${o['uf'] ?? ''}';
    _valor.text = _numero(o['valor']);
    _mensal.text = _numero(o['valor_mensal']);
    _obs.text = '${o['observacoes'] ?? ''}';
    _origem = '${o['origem'] ?? 'outro'}';
    _responsavel = o['responsavel_id'] as String?;
    _previsao = DateTime.tryParse('${o['previsao_fechamento'] ?? ''}');
    _orcamento = o['orcamento_id'] as String?;
    _contrato = o['contrato_id'] as String?;
  }

  Future<void> _carregarRelacionados() async {
    final id = _id;
    if (id == null) return;
    final ativ = await _db
        .from('com_atividades')
        .select('id, tipo, titulo, descricao, previsto_para, concluida_em, resultado, origem, criado_em, usuarios:responsavel_id(nome)')
        .eq('oportunidade_id', id)
        .isFilter('excluido_em', null)
        .order('criado_em', ascending: false);
    _atividades = _lista(ativ);
    final itens = await _db.from('com_itens').select('id').eq('oportunidade_id', id).isFilter('excluido_em', null);
    _itens = itens.length;
    final cli = _op?['cliente_id'] as String?;
    if (cli != null) {
      final orc = await _db
          .from('orcamentos')
          .select('id, codigo, status, total, ordens_servico!inner(cliente_id)')
          .eq('ordens_servico.cliente_id', cli)
          .isFilter('excluido_em', null)
          .order('numero', ascending: false)
          .limit(30);
      _orcamentos = _lista(orc);
      final ctr = await _db
          .from('contratos')
          .select('id, codigo, situacao, valor_mensal')
          .eq('cliente_id', cli)
          .isFilter('excluido_em', null)
          .order('numero', ascending: false);
      _contratos = _lista(ctr);
    }
  }

  void _avisar(String t, {bool erro = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Cores.erro : null));

  Future<void> _salvar() async {
    if (_titulo.text.trim().isEmpty) {
      _avisar('Dê um título (ex.: "PMOC do Mercado Bom").', erro: true);
      return;
    }
    if (_op?['cliente_id'] == null && _contato.text.trim().isEmpty && _empresa.text.trim().isEmpty) {
      _avisar('Informe o nome do contato ou da empresa.', erro: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      final dados = {
        'titulo': _titulo.text.trim(),
        'contato_nome': _contato.text.trim().isEmpty ? null : _contato.text.trim(),
        'empresa_nome': _empresa.text.trim().isEmpty ? null : _empresa.text.trim(),
        'telefone': _telefone.text.trim().isEmpty ? null : _telefone.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'cidade': _cidade.text.trim().isEmpty ? null : _cidade.text.trim(),
        'uf': _uf.text.trim().isEmpty ? null : _uf.text.trim(),
        'origem': _origem,
        'valor': _lerNumero(_valor),
        'valor_mensal': _lerNumero(_mensal),
        'previsao_fechamento': _previsao == null ? null : dataIso(_previsao!),
        'responsavel_id': _responsavel,
        'orcamento_id': _orcamento,
        'contrato_id': _contrato,
        'observacoes': _obs.text.trim().isEmpty ? null : _obs.text.trim(),
      };
      if (_id == null) {
        final o = await _db.from('oportunidades').insert(dados).select('id').single();
        if (!mounted) return;
        _avisar('Oportunidade criada.');
        context.go('/comercial/${o['id']}');
        return;
      }
      await _db.from('oportunidades').update(dados).eq('id', _id!);
      if (mounted) _avisar('Salvo.');
      await _carregar();
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _acao(Map<String, dynamic> p, String ok) async {
    setState(() => _salvando = true);
    try {
      await acaoComercial({...p, 'oportunidade_id': _id});
      if (mounted) _avisar(ok);
      await _carregar();
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _mudarEtapa(Map<String, dynamic> etapa) async {
    String? motivo;
    if (etapa['tipo'] == 'perdido') {
      motivo = await pedirMotivoPerda(context);
      if (motivo == null) return;
    }
    await _acao({'acao': 'mover', 'etapa_id': etapa['id'], 'motivo_perda': motivo}, 'Etapa: ${etapa['nome']}.');
  }

  Future<void> _virarCliente() async {
    final rua = TextEditingController(), numero = TextEditingController(), bairro = TextEditingController();
    final cidade = TextEditingController(text: _cidade.text), uf = TextEditingController(text: _uf.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cadastrar como cliente'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Cria o cliente com o nome, telefone e e-mail desta oportunidade, e o local "Principal".',
                style: TextStyle(color: Cores.neutro)),
            TextField(controller: rua, decoration: const InputDecoration(labelText: 'Rua')),
            Row(children: [
              Expanded(child: TextField(controller: numero, decoration: const InputDecoration(labelText: 'Número'))),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: TextField(controller: bairro, decoration: const InputDecoration(labelText: 'Bairro'))),
            ]),
            Row(children: [
              Expanded(flex: 3, child: TextField(controller: cidade, decoration: const InputDecoration(labelText: 'Cidade'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: uf, decoration: const InputDecoration(labelText: 'UF'))),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Cadastrar')),
        ],
      ),
    );
    final local = {'logradouro': rua.text.trim(), 'numero': numero.text.trim(), 'bairro': bairro.text.trim(),
      'cidade': cidade.text.trim(), 'uf': uf.text.trim()};
    for (final c in [rua, numero, bairro, cidade, uf]) {
      c.dispose();
    }
    if (ok != true) return;
    await _acao({'acao': 'virar_cliente', 'local': local}, 'Cliente cadastrado. Agora dá para abrir OS e orçamento para ele.');
  }

  Future<void> _novaAtividade() async {
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoAtividade(responsaveis: _responsaveis, responsavel: _responsavel ?? Sessao.atual?.usuarioId),
    );
    if (r == null) return;
    try {
      await _db.from('com_atividades').insert({...r, 'oportunidade_id': _id});
      if (mounted) _avisar(r['tipo'] == 'nota' ? 'Anotado.' : 'Tarefa marcada.');
      await _carregarRelacionados();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    }
  }

  /// Abre o WhatsApp e registra a conversa (tira o "parada"). Abre antes de gravar: o navegador só
  /// deixa abrir a aba no clique.
  void _whatsapp(String link) {
    abrirEmNovaAba(link);
    final id = _id;
    if (id == null) return;
    acaoComercial({'acao': 'whatsapp', 'oportunidade_id': id, 'resumo': 'WhatsApp aberto pelo painel'}).then((_) async {
      await _carregarRelacionados();
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  Future<void> _concluir(Map<String, dynamic> a) async {
    final resultado = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Concluir: ${a['titulo']}'),
        content: SizedBox(
          width: 420,
          child: TextField(controller: resultado, decoration: const InputDecoration(labelText: 'Como foi? (opcional)'), maxLines: 3),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Concluir')),
        ],
      ),
    );
    final texto = resultado.text.trim();
    resultado.dispose();
    if (ok != true) return;
    try {
      final r = await acaoComercial({'acao': 'concluir', 'atividade_id': a['id'], 'resultado': texto.isEmpty ? null : texto});
      await _carregarRelacionados();
      if (!mounted) return;
      setState(() {});
      // Guia 97: oportunidade aberta sem próxima tarefa esfria. Já pede o próximo passo.
      if (r['sem_proxima'] == true) {
        _avisar('Ficou sem próxima tarefa: marque o próximo passo.');
        await _novaAtividade();
      }
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando && _op == null && _etapas.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_erro != null && _etapas.isEmpty) return Center(child: Text(_erro!, style: const TextStyle(color: Cores.erro)));
    final o = _op;
    final etapaAtual = _etapas.where((e) => e['id'] == o?['etapa_id']).firstOrNull;
    final largo = MediaQuery.sizeOf(context).width >= 1100;
    final whatsapp = linkWhatsapp(_telefone.text.isNotEmpty ? _telefone.text : (o?['clientes'] as Map?)?['telefone']);

    final dados = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _titulo, decoration: const InputDecoration(labelText: 'Título', hintText: 'Ex.: PMOC do Mercado Bom')),
          const SizedBox(height: 8),
          if (o?['cliente_id'] != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.business_outlined),
              title: Text('Cliente: ${(o!['clientes'] as Map?)?['nome'] ?? ''}'),
              trailing: TextButton(onPressed: () => context.push('/c/clientes/${o['cliente_id']}'), child: const Text('Abrir')),
            ),
          Row(children: [
            Expanded(child: TextField(controller: _contato, decoration: const InputDecoration(labelText: 'Contato (pessoa)'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _empresa, decoration: const InputDecoration(labelText: 'Empresa'))),
          ]),
          Row(children: [
            Expanded(child: TextField(controller: _telefone, decoration: const InputDecoration(labelText: 'WhatsApp'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _email, decoration: const InputDecoration(labelText: 'E-mail'))),
          ]),
          Row(children: [
            Expanded(flex: 3, child: TextField(controller: _cidade, decoration: const InputDecoration(labelText: 'Cidade'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _uf, decoration: const InputDecoration(labelText: 'UF'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(controller: _valor, keyboardType: TextInputType.number, readOnly: _itens > 0,
                  decoration: InputDecoration(labelText: 'Valor (serviço ou instalação)', prefixText: 'R\$ ',
                      helperText: _itens > 0 ? 'Soma dos itens da proposta' : null)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(controller: _mensal, keyboardType: TextInputType.number, readOnly: _itens > 0,
                  decoration: InputDecoration(labelText: 'Valor mensal (contrato, PMOC)', prefixText: 'R\$ ',
                      helperText: _itens > 0 ? 'Soma dos itens mensais' : null)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('origem-$_origem'),
                initialValue: _origem,
                decoration: const InputDecoration(labelText: 'Origem'),
                items: [for (final e in origensComercial.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _origem = v ?? 'outro'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String?>(
                key: ValueKey('resp-$_responsavel-${_responsaveis.length}'),
                initialValue: _responsaveis.any((u) => u['id'] == _responsavel) ? _responsavel : null,
                decoration: const InputDecoration(labelText: 'Responsável'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Ninguém')),
                  for (final u in _responsaveis) DropdownMenuItem<String?>(value: u['id'] as String, child: Text('${u['nome']}')),
                ],
                onChanged: (v) => setState(() => _responsavel = v),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          CampoData(rotulo: 'Previsão de fechamento', valor: _previsao, aoMudar: (d) => setState(() => _previsao = d)),
          if (o?['cliente_id'] != null) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              key: ValueKey('orc-$_orcamento-${_orcamentos.length}'),
              initialValue: _orcamentos.any((x) => x['id'] == _orcamento) ? _orcamento : null,
              decoration: const InputDecoration(labelText: 'Orçamento ligado', helperText: 'Aprovado, a oportunidade é ganha sozinha.'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Nenhum')),
                for (final x in _orcamentos)
                  DropdownMenuItem<String?>(
                      value: x['id'] as String, child: Text('${x['codigo']} · ${x['status']} · ${reais(x['total'])}')),
              ],
              onChanged: (v) => setState(() => _orcamento = v),
            ),
            DropdownButtonFormField<String?>(
              key: ValueKey('ctr-$_contrato-${_contratos.length}'),
              initialValue: _contratos.any((x) => x['id'] == _contrato) ? _contrato : null,
              decoration: const InputDecoration(labelText: 'Contrato ligado', helperText: 'Ativado, a oportunidade é ganha sozinha.'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Nenhum')),
                for (final x in _contratos)
                  DropdownMenuItem<String?>(
                      value: x['id'] as String,
                      child: Text('${x['codigo']} · ${x['situacao']}${x['valor_mensal'] != null ? ' · ${reais(x['valor_mensal'])}/mês' : ''}')),
              ],
              onChanged: (v) => setState(() => _contrato = v),
            ),
          ],
          const SizedBox(height: 8),
          TextField(controller: _obs, maxLines: 3, decoration: const InputDecoration(labelText: 'Observações')),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _salvando ? null : _salvar,
              icon: const Icon(Icons.save_outlined),
              label: Text(_id == null ? 'Criar oportunidade' : 'Salvar'),
            ),
            if (whatsapp != null)
              OutlinedButton.icon(onPressed: () => _whatsapp(whatsapp), icon: const Icon(Icons.chat_outlined), label: const Text('WhatsApp')),
            if (o != null && o['cliente_id'] == null)
              OutlinedButton.icon(
                  onPressed: _salvando ? null : _virarCliente, icon: const Icon(Icons.person_add_alt), label: const Text('Cadastrar como cliente')),
            if (o != null && o['cliente_id'] != null)
              OutlinedButton.icon(onPressed: () => context.push('/os/nova'), icon: const Icon(Icons.add_task), label: const Text('Nova OS (orçamento)')),
          ]),
        ]),
      ),
    );

    final etapa = o == null
        ? const SizedBox.shrink()
        : Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text('${o['codigo']} · ${etapaAtual?['nome'] ?? ''}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: o['situacao'] == 'ganha' ? Cores.sucesso : (o['situacao'] == 'perdida' ? Cores.erro : Cores.indigo700))),
                  ),
                  if (o['situacao'] != 'aberta')
                    TextButton(onPressed: _salvando ? null : () => _acao({'acao': 'reabrir'}, 'Reaberta.'), child: const Text('Reabrir')),
                ]),
                if (o['situacao'] == 'perdida' && o['motivo_perda'] != null)
                  Text('Motivo: ${o['motivo_perda']}', style: const TextStyle(color: Cores.erro)),
                if (o['fechada_em'] != null) Text('Fechada em ${dataBr(o['fechada_em'])}', style: const TextStyle(color: Cores.neutro)),
                if (o['utm_source'] != null || o['utm_campaign'] != null)
                  Text('Campanha: ${[o['utm_source'], o['utm_medium'], o['utm_campaign']].where((x) => x != null).join(' / ')}',
                      style: const TextStyle(color: Cores.neutro)),
                const SizedBox(height: 8),
                if (o['situacao'] == 'aberta')
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final e in _etapas.where((e) => e['ativo'] == true))
                      ChoiceChip(
                        label: Text('${e['nome']}'),
                        selected: e['id'] == o['etapa_id'],
                        selectedColor: e['tipo'] == 'ganho' ? Cores.sucesso.withValues(alpha: .15) : null,
                        onSelected: _salvando ? null : (_) => _mudarEtapa(e),
                      ),
                  ]),
              ]),
            ),
          );

    final atividades = o == null
        ? const SizedBox.shrink()
        : Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Expanded(child: Text('Atividades', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                  FilledButton.tonalIcon(onPressed: _novaAtividade, icon: const Icon(Icons.add), label: const Text('Tarefa ou anotação')),
                ]),
                const SizedBox(height: 8),
                if (_atividades.isEmpty)
                  const Text('Nada ainda. Marque a próxima ação: quem não tem próxima tarefa esfria.', style: TextStyle(color: Cores.neutro)),
                for (final a in _atividades) _LinhaAtividade(a, aoConcluir: () => _concluir(a)),
              ]),
            ),
          );

    final itens = o == null
        ? const SizedBox.shrink()
        : ItensProposta(key: ValueKey('itens-${o['id']}'), oportunidadeId: '${o['id']}', aoSalvar: _carregar);
    final historico = o == null || o['cliente_id'] == null
        ? const SizedBox.shrink()
        : LinhaDoTempoCliente(key: ValueKey('historico-${o['cliente_id']}'), clienteId: '${o['cliente_id']}');

    return ListView(padding: margemDaTela(context), children: [
      Row(children: [
        IconButton(onPressed: () => context.canPop() ? context.pop() : context.go('/comercial'), icon: const Icon(Icons.arrow_back)),
        Expanded(
          child: Text(o == null ? 'Nova oportunidade' : '${o['titulo']}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
      ]),
      const SizedBox(height: 12),
      if (largo)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(children: [etapa, dados, itens])),
          const SizedBox(width: 16),
          Expanded(child: Column(children: [atividades, historico])),
        ])
      else ...[
        etapa,
        dados,
        itens,
        atividades,
        historico,
      ],
    ]);
  }
}

class _LinhaAtividade extends StatelessWidget {
  const _LinhaAtividade(this.a, {required this.aoConcluir});

  final Map<String, dynamic> a;
  final VoidCallback aoConcluir;

  IconData get _icone => switch (a['tipo']) {
        'ligacao' => Icons.call_outlined,
        'whatsapp' => Icons.chat_outlined,
        'visita' => Icons.place_outlined,
        'reuniao' => Icons.groups_outlined,
        'email' => Icons.mail_outline,
        'nota' => Icons.sticky_note_2_outlined,
        _ => Icons.check_box_outline_blank,
      };

  @override
  Widget build(BuildContext context) {
    final feita = a['concluida_em'] != null;
    final quando = DateTime.tryParse('${a['previsto_para'] ?? ''}')?.toLocal();
    final atrasada = !feita && quando != null && quando.isBefore(DateTime.now());
    final quem = (a['usuarios'] as Map?)?['nome'];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_icone, color: atrasada ? Cores.erro : (feita ? Cores.neutro : Cores.indigo700)),
      title: Text('${a['titulo']}',
          style: TextStyle(
              fontWeight: feita ? FontWeight.w400 : FontWeight.w600,
              decoration: feita && a['tipo'] != 'nota' ? TextDecoration.lineThrough : null)),
      subtitle: Text([
        if (a['tipo'] == 'nota') dataHoraBr(a['criado_em']) else if (quando != null) '${atrasada ? 'ATRASADA · ' : ''}${dataHoraBr(a['previsto_para'])}',
        if (quem != null) '$quem',
        if (a['origem'] == 'sistema') 'automático',
        if (a['origem'] == 'ia') 'pelo Claude',
        if (a['origem'] == 'site') 'site',
        if (a['descricao'] != null) '${a['descricao']}',
        if (a['resultado'] != null) 'Resultado: ${a['resultado']}',
      ].join(' · ')),
      trailing: !feita ? TextButton(onPressed: aoConcluir, child: const Text('Concluir')) : null,
    );
  }
}

/// Nova tarefa (com data) ou anotação (sem data, já registrada).
class _DialogoAtividade extends StatefulWidget {
  const _DialogoAtividade({required this.responsaveis, required this.responsavel});

  final List<Map<String, dynamic>> responsaveis;
  final String? responsavel;

  @override
  State<_DialogoAtividade> createState() => _DialogoAtividadeState();
}

class _DialogoAtividadeState extends State<_DialogoAtividade> {
  final _titulo = TextEditingController();
  final _descricao = TextEditingController();
  String _tipo = 'ligacao';
  DateTime? _dia = DateTime.now().add(const Duration(days: 1));
  TimeOfDay? _hora = const TimeOfDay(hour: 9, minute: 0);
  late String? _responsavel = widget.responsavel;

  @override
  void dispose() {
    _titulo.dispose();
    _descricao.dispose();
    super.dispose();
  }

  void _ok() {
    if (_titulo.text.trim().isEmpty) return;
    DateTime? quando;
    if (_tipo != 'nota' && _dia != null) {
      final h = _hora ?? const TimeOfDay(hour: 9, minute: 0);
      quando = DateTime(_dia!.year, _dia!.month, _dia!.day, h.hour, h.minute);
    }
    Navigator.of(context).pop({
      'tipo': _tipo,
      'titulo': _titulo.text.trim(),
      'descricao': _descricao.text.trim().isEmpty ? null : _descricao.text.trim(),
      'previsto_para': quando?.toUtc().toIso8601String(),
      'responsavel_id': _responsavel,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Tarefa ou anotação'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in tiposAtividade.entries)
                  ChoiceChip(label: Text(e.value), selected: _tipo == e.key, onSelected: (_) => setState(() => _tipo = e.key)),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: _titulo,
                autofocus: true,
                decoration: InputDecoration(labelText: _tipo == 'nota' ? 'O que aconteceu' : 'O que fazer'),
              ),
              TextField(controller: _descricao, maxLines: 3, decoration: const InputDecoration(labelText: 'Detalhes (opcional)')),
              if (_tipo != 'nota') ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: CampoData(rotulo: 'Dia', valor: _dia, aoMudar: (d) => setState(() => _dia = d))),
                  const SizedBox(width: 12),
                  Expanded(child: CampoHora(rotulo: 'Hora', valor: _hora, aoMudar: (h) => setState(() => _hora = h))),
                ]),
                DropdownButtonFormField<String?>(
                  initialValue: widget.responsaveis.any((u) => u['id'] == _responsavel) ? _responsavel : null,
                  decoration: const InputDecoration(labelText: 'Quem faz'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Qualquer um')),
                    for (final u in widget.responsaveis)
                      DropdownMenuItem<String?>(value: u['id'] as String, child: Text('${u['nome']}')),
                  ],
                  onChanged: (v) => setState(() => _responsavel = v),
                ),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
          FilledButton(onPressed: _ok, child: Text(_tipo == 'nota' ? 'Anotar' : 'Marcar')),
        ],
      );
}
