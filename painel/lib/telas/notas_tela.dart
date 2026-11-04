import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/arquivo_web.dart' show abrirEmNovaAba;
import '../servicos/notas.dart';
import '../servicos/status.dart' show dataBr, dataIso;
import '../widgets/itens_os.dart' show dinheiro;
import '../widgets/margem.dart';

/// Notas fiscais (guia 81): a lista das notas (emitir, ver o PDF, cancelar)
/// e "Gerar notas": escolher as OS por período e cliente(s), juntar por
/// cliente ou uma por OS, conferir e emitir. Gestor e financeiro.
class NotasTela extends StatefulWidget {
  const NotasTela({super.key});

  @override
  State<NotasTela> createState() => _NotasTelaState();
}

const _meses = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

class _NotasTelaState extends State<NotasTela> {
  late DateTime _mes;
  String? _status;
  List<Map<String, dynamic>> _notas = [];
  Map<String, dynamic>? _fiscal;
  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;
  final Set<String> _marcadas = {};

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    final h = DateTime.now();
    _mes = DateTime(h.year, h.month);
    _carregar();
  }

  void _avisar(String t, {bool erro = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Cores.erro : null));

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final fim = DateTime(_mes.year, _mes.month + 1, 0);
      final f = await _db.rpc('fiscal_config');
      final r = await _db.rpc('notas_lista', params: {
        'p': {'de': dataIso(_mes), 'ate': dataIso(fim), if (_status != null) 'status': _status}
      });
      if (mounted) {
        setState(() {
          _fiscal = Map<String, dynamic>.from(f as Map);
          _notas = ((r as Map)['notas'] as List? ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
          _marcadas.removeWhere((id) => !_notas.any((n) => n['id'] == id));
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  bool get _pronta => _fiscal?['pronta'] == true;
  bool get _producao => (_fiscal?['config'] as Map?)?['ambiente'] == 'producao';

  Future<void> _emitir(List<String> ids) async {
    if (ids.isEmpty) return;
    if (!_pronta) {
      _avisar('Termine a configuração fiscal antes de emitir.', erro: true);
      return;
    }
    setState(() => _ocupado = true);
    try {
      final (ok, falhas) = await emitirNotas(ids);
      if (!mounted) return;
      if (falhas.isEmpty) {
        _avisar(ok == 1 ? 'Nota enviada. Em instantes ela fica autorizada.' : '$ok notas enviadas. Em instantes ficam autorizadas.');
      } else {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('$ok enviadas, ${falhas.length} com problema'),
            content: SingleChildScrollView(child: Text(falhas.map((f) => '• $f').join('\n'))),
            actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendi'))],
          ),
        );
      }
      _marcadas.clear();
      await _carregar();
      // A Focus costuma responder em segundos: confere de novo.
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted) _atualizarEmitindo();
      });
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _atualizarEmitindo() async {
    final emitindo = _notas.where((n) => n['status'] == 'processando' || n['status'] == 'cancelando').toList();
    for (final n in emitindo.take(20)) {
      try {
        await funcaoNotas({'acao': 'consultar', 'nota_id': n['id']});
      } catch (_) {}
    }
    if (mounted && emitindo.isNotEmpty) _carregar();
  }

  Future<void> _consultar(Map<String, dynamic> n) async {
    try {
      final r = await funcaoNotas({'acao': 'consultar', 'nota_id': n['id']});
      if (r['ok'] != true) _avisar('${r['mensagem'] ?? 'A Focus não respondeu.'}', erro: true);
      _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _cancelar(Map<String, dynamic> n) async {
    final motivo = await showDialog<String>(context: context, builder: (_) => _Cancelar(nota: n));
    if (motivo == null) return;
    try {
      final r = await funcaoNotas({'acao': 'cancelar', 'nota_id': n['id'], 'motivo': motivo});
      _avisar(r['ok'] == true ? 'Cancelamento pedido.' : '${r['mensagem']}', erro: r['ok'] != true);
      _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _acao(Map<String, dynamic> p, String ok) async {
    try {
      await _db.rpc('nota_acao', params: {'p': p});
      _avisar(ok);
      _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _editar(Map<String, dynamic> n) async {
    final p = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _EditarNota(nota: n));
    if (p != null) await _acao({'acao': 'editar', 'nota_id': n['id'], ...p}, 'Nota ajustada.');
  }

  Future<void> _gerar() async {
    final ids = await showDialog<List<String>>(context: context, builder: (_) => const _GerarNotas());
    await _carregar();
    if (ids != null && ids.isNotEmpty) await _emitir(ids);
  }

  Future<void> _avulsa() async {
    final id = await showDialog<String>(context: context, builder: (_) => const _NotaAvulsa());
    await _carregar();
    if (id != null) await _emitir([id]);
  }

  Widget _aviso() {
    final contratado = _fiscal?['contratado'] == true;
    if (contratado && _pronta && _producao) return const SizedBox.shrink();
    final texto = !contratado
        ? 'A emissão de notas não está contratada.'
        : !_pronta
            ? 'Falta configurar a parte fiscal (dados da empresa e certificado digital).'
            : 'Emissão em TESTE (homologação): as notas não valem. Passe para produção na Configuração fiscal.';
    return Card(
      color: Cores.indigo100,
      child: ListTile(
        leading: Icon(contratado && _pronta ? Icons.science_outlined : Icons.info_outline, color: Cores.indigo700),
        title: Text(texto),
        trailing: TextButton(
            onPressed: () => context.go('/notas/configuracao'),
            child: Text(contratado ? 'Configuração fiscal' : 'Contratar')),
      ),
    );
  }

  Widget _linhaNota(Map<String, dynamic> n) {
    final st = '${n['status']}';
    final os = ((n['os'] as List?) ?? const []).map((o) => '${(o as Map)['codigo']}').join(', ');
    final pode = st == 'rascunho' || st == 'erro';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(
            value: _marcadas.contains(n['id']),
            onChanged: pode ? (v) => setState(() => v == true ? _marcadas.add('${n['id']}') : _marcadas.remove(n['id'])) : null,
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(rotuloTipoNota[n['tipo']] ?? '${n['tipo']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if ((n['numero'] ?? '') != '') Text('nº ${n['numero']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                SeloNota(st),
                if (n['ambiente'] == 'homologacao')
                  const Text('teste', style: TextStyle(color: Cores.alerta, fontSize: 12, fontWeight: FontWeight.w600)),
                if (n['iss_retido'] == true) const Text('ISS retido', style: TextStyle(color: Cores.neutro, fontSize: 12)),
              ]),
              const SizedBox(height: 2),
              Text('${n['cliente'] ?? ''}${(n['documento'] ?? '') != '' ? ' · ${n['documento']}' : ''}'),
              Text(
                  [
                    if (os.isNotEmpty) os,
                    'competência ${dataBr(n['competencia'])}',
                    if (n['autorizada_em'] != null) 'autorizada ${dataBr(n['autorizada_em'])}',
                  ].join(' · '),
                  style: const TextStyle(color: Cores.neutro, fontSize: 13)),
              if ((n['mensagem'] ?? '') != '')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${n['mensagem']}', style: const TextStyle(color: Cores.erro, fontSize: 13)),
                ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(dinheiro(n['valor_total']), style: const TextStyle(fontWeight: FontWeight.w700)),
            Wrap(children: [
              if (pode)
                IconButton(
                    tooltip: 'Emitir',
                    icon: const Icon(Icons.send_outlined),
                    onPressed: _ocupado ? null : () => _emitir(['${n['id']}'])),
              if (pode) IconButton(tooltip: 'Ajustar', icon: const Icon(Icons.edit_outlined), onPressed: () => _editar(n)),
              if (pode)
                IconButton(
                    tooltip: 'Descartar',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _acao({'acao': 'descartar', 'nota_id': n['id']}, 'Nota descartada.')),
              if (st == 'processando' || st == 'cancelando')
                IconButton(tooltip: 'Consultar agora', icon: const Icon(Icons.refresh), onPressed: () => _consultar(n)),
              if ((n['url_pdf'] ?? '') != '')
                IconButton(
                    tooltip: 'Ver a nota (PDF)',
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    onPressed: () => abrirEmNovaAba('${n['url_pdf']}')),
              if ((n['url_xml'] ?? '') != '')
                IconButton(
                    tooltip: 'XML', icon: const Icon(Icons.code), onPressed: () => abrirEmNovaAba('${n['url_xml']}')),
              if ((n['url_consulta'] ?? '') != '' && (n['url_pdf'] ?? '') == '')
                IconButton(
                    tooltip: 'Consultar no portal',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => abrirEmNovaAba('${n['url_consulta']}')),
              if (st == 'autorizada')
                IconButton(
                    tooltip: 'Cancelar a nota', icon: const Icon(Icons.block, color: Cores.erro), onPressed: () => _cancelar(n)),
            ]),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _notas
        .where((n) => n['status'] == 'autorizada')
        .fold<num>(0, (a, n) => a + (num.tryParse('${n['valor_total']}') ?? 0));
    return Padding(
      padding: margemDaTela(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Notas fiscais', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          IconButton(
              tooltip: 'Mês anterior',
              onPressed: () {
                setState(() => _mes = DateTime(_mes.year, _mes.month - 1));
                _carregar();
              },
              icon: const Icon(Icons.chevron_left)),
          Text('${_meses[_mes.month - 1]} de ${_mes.year}', style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
              tooltip: 'Próximo mês',
              onPressed: () {
                setState(() => _mes = DateTime(_mes.year, _mes.month + 1));
                _carregar();
              },
              icon: const Icon(Icons.chevron_right)),
          const SizedBox(width: 12),
          FilledButton.icon(
              onPressed: _fiscal?['contratado'] == true ? _gerar : null,
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('Gerar notas das OS')),
          OutlinedButton.icon(
              onPressed: _fiscal?['contratado'] == true ? _avulsa : null,
              icon: const Icon(Icons.add),
              label: const Text('Nota avulsa')),
          IconButton(
              tooltip: 'Configuração fiscal',
              onPressed: () => context.go('/notas/configuracao'),
              icon: const Icon(Icons.settings_outlined)),
        ]),
        const SizedBox(height: 8),
        if (_fiscal != null) _aviso(),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ChoiceChip(
              label: const Text('Todas'),
              selected: _status == null,
              onSelected: (_) {
                setState(() => _status = null);
                _carregar();
              }),
          for (final e in rotuloStatusNota.entries)
            ChoiceChip(
                label: Text(e.value),
                selected: _status == e.key,
                onSelected: (_) {
                  setState(() => _status = e.key);
                  _carregar();
                }),
          const SizedBox(width: 12),
          Text('Autorizadas no mês: ${dinheiro(total)}', style: const TextStyle(color: Cores.neutro)),
          if (_marcadas.isNotEmpty)
            FilledButton.icon(
                onPressed: _ocupado ? null : () => _emitir(_marcadas.toList()),
                icon: const Icon(Icons.send),
                label: Text('Emitir ${_marcadas.length} marcadas')),
          if (_ocupado) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: _carregando && _notas.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _erro != null
                  ? Center(child: Text(_erro!, style: const TextStyle(color: Cores.erro)))
                  : _notas.isEmpty
                      ? const Center(
                          child: Text('Nenhuma nota neste mês. Use "Gerar notas das OS" ou o botão Nota na OS.',
                              style: TextStyle(color: Cores.neutro)))
                      : RefreshIndicator(
                          onRefresh: _carregar,
                          child: ListView(children: [for (final n in _notas) _linhaNota(n)]),
                        ),
        ),
      ]),
    );
  }
}

// ---------- Gerar notas: escolher as OS ----------
class _GerarNotas extends StatefulWidget {
  const _GerarNotas();

  @override
  State<_GerarNotas> createState() => _GerarNotasState();
}

class _GerarNotasState extends State<_GerarNotas> {
  late DateTime _de;
  late DateTime _ate;
  final List<Map<String, dynamic>> _clientes = [];
  bool _soSemNota = true;
  bool _todasSituacoes = false;
  String _agrupar = 'cliente';
  List<Map<String, dynamic>> _os = [];
  final Set<String> _escolhidas = {};
  bool _carregando = false;
  bool _preparando = false;
  Map<String, dynamic>? _preparado;
  String? _erro;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    final h = DateTime.now();
    // Começo do mês passado até hoje (o caso comum: fechar o mês).
    _de = DateTime(h.year, h.month - (h.day <= 10 ? 1 : 0), 1);
    _ate = DateTime(h.year, h.month, h.day);
    _buscar();
  }

  Future<void> _buscar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await _db.rpc('notas_candidatas', params: {
        'p': {
          'de': dataIso(_de),
          'ate': dataIso(_ate),
          'cliente_ids': [for (final c in _clientes) c['id']],
          'so_sem_nota': _soSemNota,
          'situacao': _todasSituacoes ? 'todas' : 'concluidas',
        }
      });
      if (mounted) {
        setState(() {
          _os = ((r as Map)['os'] as List? ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
          _escolhidas
            ..clear()
            ..addAll(_os.where((o) => (o['notas'] as List? ?? const []).isEmpty).map((o) => '${o['os_id']}'));
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _escolherData(bool inicio) async {
    final d = await showDatePicker(
      context: context,
      initialDate: inicio ? _de : _ate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null) return;
    setState(() {
      if (inicio) {
        _de = d;
      } else {
        _ate = d;
      }
    });
    _buscar();
  }

  Future<void> _escolherClientes() async {
    final r = await showDialog<List<Map<String, dynamic>>>(
        context: context, builder: (_) => _EscolherClientes(escolhidos: List.of(_clientes)));
    if (r == null) return;
    setState(() => _clientes
      ..clear()
      ..addAll(r));
    _buscar();
  }

  Future<void> _preparar() async {
    setState(() {
      _preparando = true;
      _erro = null;
    });
    try {
      final r = await _db.rpc('notas_preparar', params: {
        'p': {'os_ids': _escolhidas.toList(), 'agrupar': _agrupar}
      });
      if (mounted) setState(() => _preparado = Map<String, dynamic>.from(r as Map));
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _preparando = false);
    }
  }

  Widget _conferir() {
    final notas = ((_preparado?['notas'] as List?) ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final avisos = ((_preparado?['avisos'] as List?) ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final total = notas.fold<num>(0, (a, n) => a + (num.tryParse('${n['valor']}') ?? 0));
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${notas.length} notas prontas para emitir · ${dinheiro(total)}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (avisos.isNotEmpty)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Cores.alerta.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Text(avisos.map((a) => '• ${a['cliente']}: ${a['aviso']}').join('\n'),
              style: const TextStyle(color: Cores.alerta)),
        ),
      const SizedBox(height: 8),
      Flexible(
        child: ListView(shrinkWrap: true, children: [
          for (final n in notas)
            ListTile(
              dense: true,
              leading: Text(rotuloTipoNota[n['tipo']] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
              title: Text('${n['cliente']}'),
              subtitle: Text('${n['os']}'),
              trailing: Text(dinheiro(n['valor'])),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      const Text('Ficaram como rascunho na lista. Emita agora ou ajuste antes (descrição, ISS retido).',
          style: TextStyle(color: Cores.neutro, fontSize: 12)),
    ]);
  }

  Widget _escolher() {
    final valor = _os
        .where((o) => _escolhidas.contains(o['os_id']))
        .fold<num>(0, (a, o) => a + (num.tryParse('${o['valor_total']}') ?? 0));
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(
            onPressed: () => _escolherData(true), icon: const Icon(Icons.event), label: Text('De ${dataBr(dataIso(_de))}')),
        OutlinedButton.icon(
            onPressed: () => _escolherData(false), icon: const Icon(Icons.event), label: Text('Até ${dataBr(dataIso(_ate))}')),
        OutlinedButton.icon(
            onPressed: _escolherClientes,
            icon: const Icon(Icons.people_alt_outlined),
            label: Text(_clientes.isEmpty
                ? 'Todos os clientes'
                : _clientes.length == 1
                    ? '${_clientes.first['nome']}'
                    : '${_clientes.length} clientes')),
        FilterChip(
            label: const Text('Só OS sem nota'),
            selected: _soSemNota,
            onSelected: (v) {
              setState(() => _soSemNota = v);
              _buscar();
            }),
        FilterChip(
            label: const Text('Incluir OS não concluídas'),
            selected: _todasSituacoes,
            onSelected: (v) {
              setState(() => _todasSituacoes = v);
              _buscar();
            }),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Checkbox(
          value: _os.isNotEmpty && _escolhidas.length == _os.length,
          tristate: true,
          onChanged: (_) => setState(() {
            if (_escolhidas.length == _os.length) {
              _escolhidas.clear();
            } else {
              _escolhidas.addAll(_os.map((o) => '${o['os_id']}'));
            }
          }),
        ),
        Expanded(child: Text('${_escolhidas.length} de ${_os.length} OS · ${dinheiro(valor)}')),
        if (_carregando) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      Flexible(
        child: _os.isEmpty && !_carregando
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhuma OS no período.', textAlign: TextAlign.center, style: TextStyle(color: Cores.neutro)))
            : ListView(shrinkWrap: true, children: [
                for (final o in _os)
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _escolhidas.contains(o['os_id']),
                    onChanged: (v) => setState(() => v == true ? _escolhidas.add('${o['os_id']}') : _escolhidas.remove(o['os_id'])),
                    title: Text('${o['codigo']} · ${o['cliente']}${(o['local'] ?? '') != '' ? ' · ${o['local']}' : ''}'),
                    subtitle: Text([
                      if (o['concluida_em'] != null) 'concluída ${dataBr(o['concluida_em'])}',
                      if ((num.tryParse('${o['produtos']}') ?? 0) > 0) 'peças ${dinheiro(o['produtos'])}',
                      if ((o['documento'] ?? '') == '') 'SEM CPF/CNPJ',
                      if ((o['notas'] as List? ?? const []).isNotEmpty) 'já tem nota',
                    ].join(' · ')),
                    secondary: Text(dinheiro(o['valor_total'])),
                  ),
              ]),
      ),
      const Divider(),
      Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Juntar:', style: TextStyle(fontWeight: FontWeight.w600)),
        ChoiceChip(
            label: const Text('Uma nota por cliente'),
            selected: _agrupar == 'cliente',
            onSelected: (_) => setState(() => _agrupar = 'cliente')),
        ChoiceChip(
            label: const Text('Uma nota por OS'), selected: _agrupar == 'os', onSelected: (_) => setState(() => _agrupar = 'os')),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final notas = ((_preparado?['notas'] as List?) ?? const []).map((x) => '${(x as Map)['nota_id']}').toList();
    return AlertDialog(
      title: Text(_preparado == null ? 'Gerar notas das OS' : 'Conferir as notas'),
      content: SizedBox(
        width: 760,
        height: 520,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _preparado == null ? _escolher() : _conferir()),
          if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
        ]),
      ),
      actions: _preparado == null
          ? [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
              FilledButton(
                  onPressed: _escolhidas.isEmpty || _preparando ? null : _preparar,
                  child: Text(_preparando ? 'Preparando...' : 'Preparar as notas')),
            ]
          : [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Deixar como rascunho')),
              FilledButton.icon(
                  onPressed: notas.isEmpty ? null : () => Navigator.pop(context, notas),
                  icon: const Icon(Icons.send),
                  label: Text('Emitir ${notas.length} agora')),
            ],
    );
  }
}

// ---------- Escolher clientes ----------
class _EscolherClientes extends StatefulWidget {
  const _EscolherClientes({required this.escolhidos});
  final List<Map<String, dynamic>> escolhidos;

  @override
  State<_EscolherClientes> createState() => _EscolherClientesState();
}

class _EscolherClientesState extends State<_EscolherClientes> {
  List<Map<String, dynamic>> _todos = [];
  late final Map<String, Map<String, dynamic>> _marcados = {for (final c in widget.escolhidos) '${c['id']}': c};
  String _busca = '';

  @override
  void initState() {
    super.initState();
    Supabase.instance.client
        .from('clientes')
        .select('id, nome, nome_fantasia, documento')
        .isFilter('excluido_em', null)
        .order('nome')
        .limit(2000)
        .then((r) {
      if (mounted) setState(() => _todos = r.map((x) => Map<String, dynamic>.from(x)).toList());
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = _busca.toLowerCase();
    final lista = _todos
        .where((c) => b.isEmpty || '${c['nome']} ${c['nome_fantasia'] ?? ''} ${c['documento'] ?? ''}'.toLowerCase().contains(b))
        .take(200)
        .toList();
    return AlertDialog(
      title: const Text('Clientes'),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nome ou CNPJ'),
            onChanged: (v) => setState(() => _busca = v),
          ),
          Expanded(
            child: ListView(children: [
              for (final c in lista)
                CheckboxListTile(
                  dense: true,
                  value: _marcados.containsKey(c['id']),
                  onChanged: (v) => setState(() => v == true ? _marcados['${c['id']}'] = c : _marcados.remove(c['id'])),
                  title: Text('${c['nome']}'),
                  subtitle: (c['nome_fantasia'] ?? '') != '' ? Text('${c['nome_fantasia']}') : null,
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, <Map<String, dynamic>>[]), child: const Text('Todos os clientes')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _marcados.values.toList()),
            child: Text('Usar ${_marcados.length} escolhidos')),
      ],
    );
  }
}

// ---------- Nota avulsa ----------
class _NotaAvulsa extends StatefulWidget {
  const _NotaAvulsa();

  @override
  State<_NotaAvulsa> createState() => _NotaAvulsaState();
}

class _NotaAvulsaState extends State<_NotaAvulsa> {
  Map<String, dynamic>? _cliente;
  final _descricao = TextEditingController();
  final _valor = TextEditingController();
  bool _issRetido = false;
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _descricao.dispose();
    _valor.dispose();
    super.dispose();
  }

  Future<void> _criar(bool emitir) async {
    if (_cliente == null) {
      setState(() => _erro = 'Escolha o cliente.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final r = await Supabase.instance.client.rpc('nota_avulsa', params: {
        'p': {
          'cliente_id': _cliente!['id'],
          'descricao': _descricao.text.trim(),
          'valor': _valor.text.trim(),
          'iss_retido': _issRetido,
        }
      });
      if (mounted) Navigator.pop(context, emitir ? '${(r as Map)['nota_id']}' : null);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nota avulsa (NFS-e)'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Para serviço sem OS, como a mensalidade de um contrato.', style: TextStyle(color: Cores.neutro)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final r = await showDialog<List<Map<String, dynamic>>>(
                  context: context,
                  builder: (_) => _EscolherClientes(escolhidos: [if (_cliente != null) _cliente!]));
              if (r != null && r.isNotEmpty) setState(() => _cliente = r.last);
            },
            icon: const Icon(Icons.person_outline),
            label: Text(_cliente == null ? 'Escolher o cliente' : '${_cliente!['nome']}'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descricao,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Descrição do serviço'),
          ),
          TextField(
            controller: _valor,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor (R\$)', hintText: '1.200,00'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('ISS retido pelo cliente'),
            value: _issRetido,
            onChanged: (v) => setState(() => _issRetido = v),
          ),
          if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(onPressed: _salvando ? null : () => _criar(false), child: const Text('Salvar rascunho')),
        FilledButton(onPressed: _salvando ? null : () => _criar(true), child: const Text('Criar e emitir')),
      ],
    );
  }
}

// ---------- Ajustar rascunho ----------
class _EditarNota extends StatefulWidget {
  const _EditarNota({required this.nota});
  final Map<String, dynamic> nota;

  @override
  State<_EditarNota> createState() => _EditarNotaState();
}

class _EditarNotaState extends State<_EditarNota> {
  late final _descricao = TextEditingController(text: '${widget.nota['descricao'] ?? ''}');
  late bool _issRetido = widget.nota['iss_retido'] == true;
  late DateTime _competencia = DateTime.tryParse('${widget.nota['competencia']}') ?? DateTime.now();

  @override
  void dispose() {
    _descricao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itens = ((widget.nota['itens'] as List?) ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    return AlertDialog(
      title: Text('Ajustar ${rotuloTipoNota[widget.nota['tipo']] ?? 'nota'}'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${widget.nota['cliente']} · ${dinheiro(widget.nota['valor_total'])}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          for (final i in itens.take(8))
            Text('• ${i['descricao']} (${dinheiro(i['valor_total'])})${i['tipo'] == 'produto' && i['ncm'] == null ? ' · SEM NCM' : ''}',
                style: const TextStyle(color: Cores.neutro, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(controller: _descricao, maxLines: 4, decoration: const InputDecoration(labelText: 'Descrição')),
          if (widget.nota['tipo'] == 'nfse')
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ISS retido pelo cliente'),
              value: _issRetido,
              onChanged: (v) => setState(() => _issRetido = v),
            ),
          OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                  context: context, initialDate: _competencia, firstDate: DateTime(2024), lastDate: DateTime(2100));
              if (d != null) setState(() => _competencia = d);
            },
            icon: const Icon(Icons.event),
            label: Text('Competência ${dataBr(dataIso(_competencia))}'),
          ),
          const SizedBox(height: 8),
          const Text('O cadastro do cliente (CPF/CNPJ, endereço, e-mail) é lido de novo ao salvar.',
              style: TextStyle(color: Cores.neutro, fontSize: 12)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'descricao': _descricao.text.trim(),
            'iss_retido': _issRetido,
            'competencia': dataIso(_competencia),
          }),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

// ---------- Cancelar ----------
class _Cancelar extends StatefulWidget {
  const _Cancelar({required this.nota});
  final Map<String, dynamic> nota;

  @override
  State<_Cancelar> createState() => _CancelarState();
}

class _CancelarState extends State<_Cancelar> {
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = _motivo.text.trim().length;
    return AlertDialog(
      title: Text('Cancelar a ${rotuloTipoNota[widget.nota['tipo']] ?? 'nota'} nº ${widget.nota['numero'] ?? ''}'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${widget.nota['cliente']} · ${dinheiro(widget.nota['valor_total'])}'),
          const SizedBox(height: 8),
          const Text('O cancelamento tem prazo (a prefeitura e a SEFAZ definem). Depois dele, só com nota de substituição.',
              style: TextStyle(color: Cores.neutro, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _motivo,
            maxLines: 3,
            maxLength: 255,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Justificativa (mínimo 15 letras)'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Cores.erro),
          onPressed: n < 15 ? null : () => Navigator.pop(context, _motivo.text.trim()),
          child: const Text('Cancelar a nota'),
        ),
      ],
    );
  }
}
