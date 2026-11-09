import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/status.dart' show dataHoraBr;
import '../widgets/margem.dart';
import 'servico.dart';

/// Administração › ERP (Protheus) › Fila (guia 105): cada mensagem com o
/// Protheus (importações, compras, pedidos, custo, cobrança), a situação, as
/// tentativas, o erro e o documento no ERP. Reprocessar (uma ou todas com
/// erro), cancelar e processar agora.
class ErpFilaTela extends StatefulWidget {
  const ErpFilaTela({super.key});

  @override
  State<ErpFilaTela> createState() => _ErpFilaTelaState();
}

const _filtros = {
  '': 'Todas',
  'pendente': 'Na fila',
  'erro': 'Com erro',
  'concluida': 'Concluídas',
  'cancelada': 'Canceladas',
};

class _ErpFilaTelaState extends State<ErpFilaTela> {
  final _busca = TextEditingController();
  List<Map<String, dynamic>> _itens = [];
  Map<String, dynamic> _resumo = {};
  String _situacao = '';
  bool _carregando = true;
  bool _ocupado = false;
  bool _temMais = false;
  String? _erro;

  static const _pagina = 50;

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

  void _avisar(String t, {bool erro = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Cores.erro : null));

  Future<void> _carregar({bool mais = false}) async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await erpRpc('erp_fila_lista', {
        'situacao': _situacao,
        'busca': _busca.text.trim(),
        'limite': _pagina,
        if (mais && _itens.isNotEmpty) 'antes_de': _itens.last['criado_em'],
      });
      final novos = (r['itens'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _itens = mais ? [..._itens, ...novos] : novos;
        _resumo = r['resumo'] is Map ? Map<String, dynamic>.from(r['resumo'] as Map) : {};
        _temMais = novos.length == _pagina;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _processar() async {
    setState(() => _ocupado = true);
    try {
      final r = await funcaoErp({'acao': 'processar'});
      if (!mounted) return;
      _avisar(resumoProcessamento(r));
      await _carregar();
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _reprocessar({String? id, bool forcar = false}) async {
    setState(() => _ocupado = true);
    try {
      final r = await erpRpc('erp_fila_acao', {
        'acao': 'reprocessar',
        if (id != null) 'fila_id': id else 'todos_com_erro': true,
        if (forcar) 'forcar': true,
      });
      final p = await funcaoErp({'acao': 'processar'});
      if (!mounted) return;
      _avisar('${r['reprocessadas'] ?? 0} de volta para a fila. ${resumoProcessamento(p)}');
      await _carregar();
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _cancelar(String id) async {
    final motivo = await showDialog<String>(context: context, builder: (_) => const _MotivoDialogo());
    if (motivo == null || motivo.trim().isEmpty || !mounted) return;
    try {
      await erpRpc('erp_fila_acao', {'acao': 'cancelar', 'fila_id': id, 'motivo': motivo.trim()});
      if (!mounted) return;
      _avisar('Mensagem cancelada.');
      await _carregar();
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _detalhes(String id) async {
    try {
      final r = await erpRpc('erp_fila_ver', {'fila_id': id});
      if (!mounted) return;
      final it = Map<String, dynamic>.from((r['item'] as Map?) ?? const {});
      const json = JsonEncoder.withIndent('  ');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(rotuloTipoErp[it['tipo']] ?? '${it['tipo']}'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('Chave: ${it['chave']}', style: const TextStyle(color: Cores.neutro)),
                if ((it['documento_erp'] ?? '') != '') Text('No Protheus: ${it['documento_erp']}'),
                if ((it['erro'] ?? '') != '') ...[
                  const SizedBox(height: 8),
                  Text('${it['erro']}', style: const TextStyle(color: Cores.erro)),
                ],
                const SizedBox(height: 12),
                const Text('O que foi enviado', style: TextStyle(fontWeight: FontWeight.w600)),
                SelectableText(json.convert(it['carga']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                if (it['resposta'] != null) ...[
                  const SizedBox(height: 12),
                  const Text('Resposta', style: TextStyle(fontWeight: FontWeight.w600)),
                  SelectableText(json.convert(it['resposta']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ],
              ]),
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
        ),
      );
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    }
  }

  Widget _item(Map<String, dynamic> it) {
    final sit = '${it['situacao']}';
    final saida = it['direcao'] == 'saida';
    final linhas = <String>[
      [
        rotuloTipoErp[it['tipo']] ?? '${it['tipo']}',
        dataHoraBr(it['criado_em']),
        if ((it['tentativas'] ?? 0) != 0) '${it['tentativas']} tentativa(s)',
        if (sit == 'pendente' && it['proxima_tentativa_em'] != null) 'próxima ${dataHoraBr(it['proxima_tentativa_em'])}',
      ].join(' · '),
      if ((it['documento_erp'] ?? '') != '') 'No Protheus: ${it['documento_erp']}',
    ];
    return Card(
      child: ListTile(
        leading: Icon(saida ? Icons.north_east : Icons.south_west, color: saida ? Cores.indigo500 : Cores.andamento),
        title: Text('${it['descricao'] ?? rotuloTipoErp[it['tipo']] ?? it['tipo']}'),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(linhas.join('\n')),
          if ((it['erro'] ?? '') != '' && sit != 'concluida')
            Text('${it['erro']}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Cores.erro)),
        ]),
        isThreeLine: true,
        onTap: () => _detalhes('${it['id']}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          SeloErp(sit),
          PopupMenuButton<String>(
            enabled: !_ocupado,
            onSelected: (v) {
              if (v == 'ver') _detalhes('${it['id']}');
              if (v == 'reprocessar') _reprocessar(id: '${it['id']}', forcar: sit == 'concluida');
              if (v == 'cancelar') _cancelar('${it['id']}');
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'ver', child: Text('Ver o que foi e o que voltou')),
              if (sit == 'erro' || sit == 'pendente' || sit == 'concluida')
                PopupMenuItem(value: 'reprocessar', child: Text(sit == 'concluida' ? 'Mandar de novo' : 'Reprocessar agora')),
              if (sit == 'erro' || sit == 'pendente') const PopupMenuItem(value: 'cancelar', child: Text('Cancelar')),
            ],
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: margemDaTela(context),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text('Fila do ERP',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                  onPressed: () => context.go('/erp'), icon: const Icon(Icons.settings_outlined), label: const Text('Configuração')),
            ]),
            Text(
                '${_resumo['pendente'] ?? 0} na fila · ${_resumo['erro'] ?? 0} com erro · '
                '${_resumo['concluida_7d'] ?? 0} concluídas em 7 dias. A rotina processa a cada 5 minutos; '
                'com o Protheus fora do ar, a mensagem espera sem gastar tentativa.',
                style: const TextStyle(color: Cores.neutro)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final f in _filtros.entries)
                ChoiceChip(
                  label: Text(f.value),
                  selected: _situacao == f.key,
                  onSelected: (_) {
                    setState(() => _situacao = f.key);
                    _carregar();
                  },
                ),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _busca,
                  decoration: const InputDecoration(
                      isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Documento, descrição ou erro'),
                  onSubmitted: (_) => _carregar(),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilledButton.icon(
                  onPressed: _ocupado ? null : _processar, icon: const Icon(Icons.play_arrow), label: const Text('Processar agora')),
              OutlinedButton.icon(
                  onPressed: _ocupado || (_resumo['erro'] ?? 0) == 0 ? null : () => _reprocessar(),
                  icon: const Icon(Icons.replay),
                  label: const Text('Reprocessar todas com erro')),
              IconButton(onPressed: _carregando ? null : _carregar, tooltip: 'Atualizar', icon: const Icon(Icons.refresh)),
              if (_ocupado || _carregando) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            const SizedBox(height: 12),
            if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
            if (!_carregando && _erro == null && _itens.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhuma mensagem aqui.', style: TextStyle(color: Cores.neutro)),
              ),
            for (final it in _itens) _item(it),
            if (_temMais)
              Align(
                child: TextButton(onPressed: _carregando ? null : () => _carregar(mais: true), child: const Text('Carregar mais')),
              ),
          ]),
        ),
      ),
    );
  }
}

class _MotivoDialogo extends StatefulWidget {
  const _MotivoDialogo();

  @override
  State<_MotivoDialogo> createState() => _MotivoDialogoState();
}

class _MotivoDialogoState extends State<_MotivoDialogo> {
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancelar a mensagem'),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: _motivo,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Motivo', hintText: 'Ex.: pedido feito à mão no Protheus'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
        FilledButton(onPressed: () => Navigator.pop(context, _motivo.text), child: const Text('Cancelar a mensagem')),
      ],
    );
  }
}
