import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_cadastro.dart';
import '../core/acoes_levantamento.dart';
import '../core/estado.dart';

const _unidades = {'btu_h': 'BTU/h', 'tr': 'TR', 'kw': 'kW'};

/// "12.000" -> 12000; "3,5" -> 3.5; "12000" -> 12000.
num? lerNumero(String texto) {
  var t = texto.trim().replaceAll(RegExp(r'[^0-9.,]'), '');
  if (t.isEmpty) return null;
  if (RegExp(r'^\d{1,3}([.,]\d{3})+$').hasMatch(t)) {
    t = t.replaceAll(RegExp(r'[.,]'), '');
  } else {
    t = t.replaceAll(',', '.');
  }
  return num.tryParse(t);
}

String _numeroTexto(Object? v) {
  final n = num.tryParse('${v ?? ''}');
  if (n == null) return '';
  return (n == n.roundToDouble() ? n.toInt().toString() : n.toString()).replaceAll('.', ',');
}

const _novo = '__novo__';

/// Folha para cadastrar um equipamento na hora. [localId] é o local da OS
/// (null quando o local também é novo: aí só dá para criar ambiente novo).
/// [codigosUsados]: códigos que já existem no cliente ({código minúsculo: rótulo}).
/// [pendentes]: equipamentos novos desta mesma OS, ainda não sincronizados
/// (os ambientes e tipos novos deles aparecem na lista).
Future<EquipamentoNovo?> cadastrarEquipamento(
  BuildContext context, {
  String? localId,
  Map<String, String> codigosUsados = const {},
  List<EquipamentoNovo> pendentes = const [],
  String sugestao = '',
  String? ambienteId,
}) =>
    showModalBottomSheet<EquipamentoNovo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormEquipamento(
        localId: localId,
        codigosUsados: codigosUsados,
        pendentes: pendentes,
        sugestao: sugestao,
        ambienteId: ambienteId,
      ),
    );

/// Folha para cadastrar o contato que pediu o serviço.
Future<ContatoNovo?> cadastrarContato(BuildContext context, {String sugestao = ''}) =>
    showModalBottomSheet<ContatoNovo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormContato(sugestao: sugestao),
    );

// ---------------------------------------------------------------------

class _FormEquipamento extends StatefulWidget {
  const _FormEquipamento({
    required this.localId,
    required this.codigosUsados,
    required this.pendentes,
    required this.sugestao,
    this.ambienteId,
  });

  final String? localId;

  /// Ambiente já escolhido (ex.: o que o técnico falou no relato).
  final String? ambienteId;
  final Map<String, String> codigosUsados;
  final List<EquipamentoNovo> pendentes;
  final String sugestao;

  @override
  State<_FormEquipamento> createState() => _FormEquipamentoState();
}

class _FormEquipamentoState extends State<_FormEquipamento> {
  final _form = GlobalKey<FormState>();
  late final _descricao = TextEditingController(text: widget.sugestao);
  final _codigo = TextEditingController();
  final _marca = TextEditingController();
  final _modelo = TextEditingController();
  final _serie = TextEditingController();
  final _fluido = TextEditingController();
  final _ambienteNovo = TextEditingController();
  final _tipoNovo = TextEditingController();
  // Guia 57: capacidade, leitura da plaqueta pela IA e a etiqueta QR em branco.
  final _capacidade = TextEditingController();
  String _unidade = 'btu_h';
  String? _qr;
  bool _lendo = false;
  String? _recado;
  bool _recadoErro = false;
  // (só se o ambiente estiver na lista: o menu não aceita valor de fora)
  late String? _ambiente =
      _ambientes.any((a) => '${a['id']}' == widget.ambienteId) ? widget.ambienteId : null;
  String? _tipo;

  @override
  void dispose() {
    for (final c in [_descricao, _codigo, _marca, _modelo, _serie, _fluido, _ambienteNovo, _tipoNovo, _capacidade]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Guia 59: como o cliente identifica os aparelhos (etiqueta, patrimonio, descricao).
  String get _modoCliente {
    final banco = EstadoApp.instancia.banco;
    final local = banco?.um('locais', widget.localId);
    return '${banco?.um('clientes', local?['cliente_id'])?['identificacao_equipamentos'] ?? 'etiqueta'}';
  }

  /// O tipo escolhido pede o número de série?
  bool get _serieObrigatoria =>
      _tipo != null && _tipo != _novo && EstadoApp.instancia.banco?.um('tipos_equipamento', _tipo)?['serie_obrigatoria'] == true;

  /// Ambientes do local mais os novos de outros equipamentos desta OS.
  List<Map<String, dynamic>> get _ambientes => [
        if (widget.localId != null) ...AcoesCadastro.ambientesDo(widget.localId),
        for (final p in widget.pendentes)
          if (p.ambienteNovo != null) {'id': p.ambienteNovoId, 'nome': p.ambienteNovo!.trim()},
      ];

  List<Map<String, dynamic>> get _tipos => [
        ...AcoesCadastro.tipos(),
        for (final p in widget.pendentes)
          if (p.tipoNovo != null) {'id': p.tipoNovoId, 'nome': p.tipoNovo!.trim()},
      ];

  /// Nome digitado que já existe na lista: usa o que existe (não duplica).
  static String? _existente(List<Map<String, dynamic>> lista, String nome) {
    final n = nome.trim().toLowerCase();
    for (final o in lista) {
      if ('${o['nome']}'.trim().toLowerCase() == n) return '${o['id']}';
    }
    return null;
  }

  void _avisar(String texto, {bool erro = false}) => setState(() {
        _recado = texto;
        _recadoErro = erro;
      });

  /// Foto da plaqueta: a IA preenche marca, modelo, série, capacidade e fluido.
  Future<void> _lerPlaqueta() async {
    final foto = await ImagePicker()
        .pickImage(source: ImageSource.camera, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
    if (foto == null || !mounted) return;
    setState(() {
      _lendo = true;
      _recado = null;
    });
    try {
      final r = await AcoesLevantamento.lerPlaqueta(await foto.readAsBytes());
      if (!mounted) return;
      if (r['legivel'] == false) {
        _avisar('Não deu para ler a plaqueta: tire outra foto, mais perto e sem reflexo.', erro: true);
        return;
      }
      void por(TextEditingController c, Object? v) {
        if (v != null && '$v'.trim().isNotEmpty) c.text = '$v'.trim();
      }

      setState(() {
        por(_marca, r['marca']);
        por(_modelo, r['modelo']);
        por(_serie, r['numero_serie']);
        por(_fluido, r['fluido']);
        if (r['capacidade_valor'] != null) {
          _capacidade.text = _numeroTexto(r['capacidade_valor']);
          if (_unidades.containsKey(r['capacidade_unidade'])) _unidade = '${r['capacidade_unidade']}';
        }
        if (_codigo.text.trim().isEmpty) por(_codigo, r['codigo']);
        final sugerido = '${r['tipo_sugerido'] ?? ''}'.trim().toLowerCase();
        if (_tipo == null && sugerido.isNotEmpty) {
          for (final t in _tipos) {
            if ('${t['nome']}'.trim().toLowerCase() == sugerido) _tipo = '${t['id']}';
          }
        }
        if (_descricao.text.trim().isEmpty) {
          _descricao.text = [r['tipo_sugerido'], r['marca']].where((x) => x != null && '$x' != 'outro').join(' ');
        }
      });
      _avisar('Plaqueta lida. Confira os campos antes de cadastrar.');
    } catch (_) {
      if (mounted) _avisar('Sem internet ou a leitura falhou: preencha à mão.', erro: true);
    } finally {
      if (mounted) setState(() => _lendo = false);
    }
  }

  /// Etiqueta QR em branco (impressa no painel): fica no aparelho ao cadastrar.
  Future<void> _lerEtiqueta() async {
    final lido = await context.push<String>('/ler-codigo');
    if (lido == null || !mounted) return;
    final t = lido.trim();
    if (!AcoesLevantamento.etiquetaValida(t)) {
      _avisar('Esta não é uma etiqueta em branco do ServPilot ($t).', erro: true);
      return;
    }
    final usada = AcoesLevantamento.etiquetaUsada(t);
    if (usada != null) {
      _avisar('Esta etiqueta já está no $usada. Use outra.', erro: true);
      return;
    }
    setState(() {
      _qr = t;
      _recado = null;
    });
  }

  void _salvar() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final ambienteExistente = _ambiente == _novo ? _existente(_ambientes, _ambienteNovo.text) : _ambiente;
    final tipoExistente = _tipo == _novo ? _existente(_tipos, _tipoNovo.text) : _tipo;
    Navigator.of(context).pop(EquipamentoNovo(
      descricao: _descricao.text,
      codigo: _codigo.text,
      marca: _marca.text,
      modelo: _modelo.text,
      numeroSerie: _serie.text,
      fluido: _fluido.text,
      capacidadeValor: lerNumero(_capacidade.text),
      capacidadeUnidade: _unidade,
      qrToken: _qr,
      ambienteId: ambienteExistente,
      ambienteNovo: _ambiente == _novo && ambienteExistente == null ? _ambienteNovo.text : null,
      tipoId: tipoExistente,
      tipoNovo: _tipo == _novo && tipoExistente == null ? _tipoNovo.text : null,
    ));
  }

  Widget _lista(String rotulo, String? valor, List<Map<String, dynamic>> opcoes, String rotuloNovo,
      ValueChanged<String?> aoMudar) {
    return InputDecorator(
      decoration: InputDecoration(labelText: rotulo),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: valor,
          isDense: true,
          isExpanded: true,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Não informar')),
            for (final o in opcoes)
              DropdownMenuItem<String?>(value: '${o['id']}', child: Text('${o['nome']}', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem<String?>(
              value: _novo,
              child: Text(rotuloNovo, style: const TextStyle(color: Cores.indigo500, fontWeight: FontWeight.w600)),
            ),
          ],
          onChanged: (v) => setState(() => aoMudar(v)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ambientes = _ambientes;
    final tipos = _tipos;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const Text('Cadastrar equipamento', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                key: const ValueKey('lerPlaqueta'),
                onPressed: _lendo ? null : _lerPlaqueta,
                icon: _lendo
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.document_scanner_outlined),
                label: Text(_lendo ? 'Lendo a plaqueta…' : 'Foto da plaqueta (IA preenche)'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('etiquetaQr'),
                onPressed: _lerEtiqueta,
                icon: Icon(_qr == null ? Icons.qr_code_2 : Icons.check_circle, color: _qr == null ? null : Cores.sucesso),
                label: Text(_qr == null ? 'Etiqueta QR' : 'Etiqueta $_qr'),
              ),
            ]),
            if (_recado != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_recado!, style: TextStyle(color: _recadoErro ? Cores.erro : Cores.sucesso)),
              ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descricao,
              autofocus: widget.sugestao.isEmpty,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Descrição *', hintText: 'Ex.: Bebedouro do refeitório, Split da sala 3'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Descreva o equipamento' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _codigo,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: switch (_modoCliente) {
                  'patrimonio' => 'Patrimônio do cliente *',
                  'descricao' => 'Código (se tiver)',
                  _ => 'Plaqueta ou patrimônio (se tiver)',
                },
                helperText: switch (_modoCliente) {
                  'patrimonio' => 'Este cliente identifica os aparelhos pelo patrimônio dele.',
                  'descricao' => 'Este cliente não usa plaqueta: vazio, o sistema gera o código (EQ-0001).',
                  _ => 'Sem plaqueta? Deixe vazio: o app cria um código provisório (PROV-...).',
                },
              ),
              validator: (v) {
                if (_modoCliente == 'patrimonio' && (v ?? '').trim().isEmpty) return 'Informe o patrimônio do cliente';
                final ja = widget.codigosUsados[(v ?? '').trim().toLowerCase()];
                return ja == null ? null : 'Já cadastrado neste cliente: $ja. Escolha na lista.';
              },
            ),
            const SizedBox(height: 8),
            _lista('Ambiente', _ambiente, ambientes, '+ Novo ambiente', (v) => _ambiente = v),
            if (_ambiente == _novo) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _ambienteNovo,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nome do ambiente *', hintText: 'Ex.: Refeitório, Sala 3'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o ambiente' : null,
              ),
            ],
            const SizedBox(height: 8),
            _lista('Tipo de equipamento', _tipo, tipos, '+ Novo tipo', (v) => _tipo = v),
            if (_tipo == _novo) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _tipoNovo,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nome do tipo *',
                  hintText: 'Ex.: Bebedouro',
                  helperText: 'O gestor completa as medições desse tipo no painel.',
                ),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o tipo' : null,
              ),
            ],
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextFormField(controller: _marca, decoration: const InputDecoration(labelText: 'Marca'))),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(controller: _modelo, decoration: const InputDecoration(labelText: 'Modelo'))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _serie,
                  decoration: InputDecoration(labelText: _serieObrigatoria ? 'Nº de série *' : 'Nº de série'),
                  validator: (v) => _serieObrigatoria && (v ?? '').trim().isEmpty ? 'Obrigatório neste tipo' : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _fluido,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Fluido', hintText: 'Ex.: R-410A'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _capacidade,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Capacidade', hintText: 'Ex.: 12.000'),
                  validator: (v) => (v ?? '').trim().isEmpty || lerNumero(v!) != null ? null : 'Só números',
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Unidade'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _unidade,
                      isDense: true,
                      isExpanded: true,
                      items: [for (final u in _unidades.entries) DropdownMenuItem(value: u.key, child: Text(u.value))],
                      onChanged: (v) => setState(() => _unidade = v ?? _unidade),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _salvar,
                icon: const Icon(Icons.check),
                label: const Text('Cadastrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------

class _FormContato extends StatefulWidget {
  const _FormContato({required this.sugestao});

  final String sugestao;

  @override
  State<_FormContato> createState() => _FormContatoState();
}

class _FormContatoState extends State<_FormContato> {
  final _form = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: widget.sugestao);
  final _telefone = TextEditingController();
  final _cargo = TextEditingController();
  bool _whatsapp = true;

  @override
  void dispose() {
    for (final c in [_nome, _telefone, _cargo]) {
      c.dispose();
    }
    super.dispose();
  }

  void _salvar() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(ContatoNovo(
      nome: _nome.text,
      telefone: _telefone.text,
      cargo: _cargo.text,
      aceitaWhatsapp: _whatsapp && _telefone.text.trim().isNotEmpty,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const Text('Cadastrar contato', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nome,
              autofocus: widget.sugestao.isEmpty,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o nome' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _telefone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Celular (com DDD)'),
              validator: (v) {
                final n = (v ?? '').replaceAll(RegExp(r'\D'), '');
                return n.isEmpty || n.length == 10 || n.length == 11 ? null : 'Use DDD + número';
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _cargo,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Cargo ou função', hintText: 'Ex.: Gerente, Recepção'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _whatsapp,
              onChanged: (v) => setState(() => _whatsapp = v),
              title: const Text('Aceita receber avisos pelo WhatsApp'),
              subtitle: const Text('Pergunte para a pessoa.'),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _salvar,
                icon: const Icon(Icons.check),
                label: const Text('Cadastrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
