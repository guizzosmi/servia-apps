import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_atendimento.dart';
import '../core/consultas.dart';
import '../core/estado.dart';

const _nomesLeitura = {
  'qr': 'QR',
  'barras': 'código de barras',
  'ocr': 'foto da plaqueta',
  'ia': 'IA',
  'lista': 'lista',
  'digitado': 'digitado',
};

String _rotuloEquipamento(Map e) => [e['codigo'], e['descricao']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');

/// Número digitado com vírgula ou ponto ("8,2" -> 8.2). Vazio = null.
num? _numero(String texto) => num.tryParse(texto.trim().replaceAll(',', '.'));

String _numeroTexto(Object? v) {
  if (v == null) return '';
  final n = num.tryParse('$v');
  if (n == null) return '$v';
  return (n == n.roundToDouble() ? n.toInt().toString() : n.toString()).replaceAll('.', ',');
}

void _aviso(BuildContext context, String texto) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

// =====================================================================
// Equipamentos
// =====================================================================

class AbaEquipamentos extends StatelessWidget {
  const AbaEquipamentos({super.key, required this.atd, required this.habilitado});

  final Map<String, dynamic> atd;
  final bool habilitado;

  /// Lê a etiqueta e identifica o equipamento. Com [esperado], confere se a
  /// etiqueta é mesmo daquele equipamento (evita confundir aparelhos vizinhos).
  Future<void> _lerQr(BuildContext context, {Map<String, dynamic>? esperado}) async {
    final banco = EstadoApp.instancia.banco!;
    final lido = await context.push<String>('/ler-codigo');
    if (lido == null || !context.mounted) return;
    final os = banco.um('ordens_servico', atd['os_id']) ?? const {};
    final valor = lido.trim().toLowerCase();
    final achados = banco.todos('equipamentos').where((e) =>
        '${e['qr_token'] ?? ''}'.toLowerCase() == valor || '${e['codigo'] ?? ''}'.toLowerCase() == valor);
    final doCliente = achados.where((e) => e['cliente_id'] == os['cliente_id']).toList();
    if (doCliente.isEmpty) {
      _aviso(context, achados.isEmpty ? 'Etiqueta não encontrada: $lido' : 'Esta etiqueta é de outro cliente.');
      return;
    }
    final lidoEquip = doCliente.first;
    if (esperado != null && lidoEquip['id'] != esperado['id']) {
      _aviso(context,
          'Esta etiqueta é do ${_rotuloEquipamento(lidoEquip)}, não do ${_rotuloEquipamento(esperado)}. '
          'Confira se está no aparelho certo.');
      return;
    }
    await AcoesAtendimento.identificarEquipamento(atd, lidoEquip, leitura: 'qr', valorLido: lido);
    if (context.mounted) _aviso(context, 'Identificado: ${_rotuloEquipamento(lidoEquip)}');
  }

  Future<void> _escolherDoLocal(BuildContext context, List<Map<String, dynamic>> jaNaLista) async {
    final banco = EstadoApp.instancia.banco!;
    final os = banco.um('ordens_servico', atd['os_id']) ?? const {};
    final ids = jaNaLista.map((e) => e['id']).toSet();
    final opcoes = banco
        .todos('equipamentos')
        .where((e) => e['local_id'] == os['local_id'] && e['situacao'] == 'ativo' && !ids.contains(e['id']))
        .toList()
      ..sort((a, b) => '${a['codigo']}'.compareTo('${b['codigo']}'));
    final escolhido = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _Busca(
        titulo: 'Equipamentos deste local',
        lerEtiqueta: true,
        itens: opcoes,
        texto: (e) => [_rotuloEquipamento(e), banco.um('ambientes', e['ambiente_id'])?['nome'], e['marca']]
            .where((x) => x != null && '$x'.isNotEmpty)
            .join(' · '),
      ),
    );
    if (escolhido == null || !context.mounted) return;
    if (escolhido['_qr'] == true) {
      await _lerQr(context);
    } else {
      await AcoesAtendimento.identificarEquipamento(atd, escolhido, leitura: 'lista');
    }
  }

  @override
  Widget build(BuildContext context) {
    final banco = EstadoApp.instancia.banco!;
    final lista = banco.equipamentosDoAtendimento(atd);
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (habilitado)
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: () => _lerQr(context),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Ler etiqueta'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () => _escolherDoLocal(context, lista),
                icon: const Icon(Icons.add),
                label: const Text('Outro do local'),
              ),
            ),
          ),
        ]),
      const SizedBox(height: 8),
      if (lista.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nenhum equipamento nesta OS. Leia a etiqueta ou escolha no local.',
              style: TextStyle(color: Cores.neutro)),
        ),
      for (final e in lista)
        Builder(builder: (context) {
          final id = banco.identificacao(atd['id'], e['id']);
          return Card(
            child: ListTile(
              leading: Icon(id != null ? Icons.verified : Icons.ac_unit, color: id != null ? Cores.sucesso : Cores.neutro),
              title: Text(_rotuloEquipamento(e)),
              subtitle: Text([
                banco.um('ambientes', e['ambiente_id'])?['nome'],
                [e['marca'], e['modelo']].where((x) => x != null).join(' '),
                if (id != null) 'Identificado (${_nomesLeitura[id['leitura']] ?? id['leitura']})',
              ].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
              trailing: id == null && habilitado
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Ler a etiqueta deste',
                        onPressed: () => _lerQr(context, esperado: e),
                        icon: const Icon(Icons.qr_code_scanner, color: Cores.indigo500),
                      ),
                      TextButton(
                        onPressed: () => AcoesAtendimento.identificarEquipamento(atd, e, leitura: 'lista'),
                        child: const Text('Sem etiqueta'),
                      ),
                    ])
                  : null,
            ),
          );
        }),
    ]);
  }
}

/// Lista com busca, numa folha de baixo.
class _Busca extends StatefulWidget {
  const _Busca({
    required this.titulo,
    required this.itens,
    required this.texto,
    this.livre = false,
    this.lerEtiqueta = false,
  });

  final String titulo;
  final List<Map<String, dynamic>> itens;
  final String Function(Map<String, dynamic>) texto;

  /// Oferece usar o texto digitado quando não achar (item sem cadastro).
  final bool livre;

  /// Mostra no topo "Ler a etiqueta" (devolve {'_qr': true}).
  final bool lerEtiqueta;

  @override
  State<_Busca> createState() => _BuscaState();
}

class _BuscaState extends State<_Busca> {
  final _busca = TextEditingController();

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = _busca.text.trim().toLowerCase();
    final achados = widget.itens.where((i) => b.isEmpty || widget.texto(i).toLowerCase().contains(b)).take(60).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: Column(children: [
          ListTile(title: Text(widget.titulo, style: const TextStyle(fontWeight: FontWeight.w800))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _busca,
              // Com a opção de ler a etiqueta, o teclado não abre sozinho.
              autofocus: !widget.lerEtiqueta,
              decoration: const InputDecoration(hintText: 'Buscar', prefixIcon: Icon(Icons.search)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              if (widget.lerEtiqueta) ...[
                ListTile(
                  leading: const Icon(Icons.qr_code_scanner, color: Cores.indigo500),
                  title: const Text('Ler a etiqueta', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Mais seguro quando há muitos aparelhos no local'),
                  onTap: () => Navigator.of(context).pop(<String, dynamic>{'_qr': true}),
                ),
                const Divider(height: 1),
              ],
              if (widget.livre && b.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: Text('Usar "${_busca.text.trim()}" (sem cadastro)'),
                  onTap: () => Navigator.of(context).pop(<String, dynamic>{'_livre': _busca.text.trim()}),
                ),
              if (achados.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nada encontrado.', style: TextStyle(color: Cores.neutro)),
                ),
              for (final i in achados)
                ListTile(title: Text(widget.texto(i)), onTap: () => Navigator.of(context).pop(i)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// =====================================================================
// Medições e fluido
// =====================================================================

class AbaMedicoes extends StatefulWidget {
  const AbaMedicoes({super.key, required this.atd, required this.habilitado});

  final Map<String, dynamic> atd;
  final bool habilitado;

  @override
  State<AbaMedicoes> createState() => _AbaMedicoesState();
}

class _AbaMedicoesState extends State<AbaMedicoes> {
  String? _equipId;
  final Map<String, TextEditingController> _campos = {};
  final _fluido = TextEditingController();
  final _adicionado = TextEditingController();
  final _recolhido = TextEditingController();
  bool _sujo = false;

  @override
  void dispose() {
    for (final c in _campos.values) {
      c.dispose();
    }
    _fluido.dispose();
    _adicionado.dispose();
    _recolhido.dispose();
    super.dispose();
  }

  /// Controle de um campo (um por equipamento e medição, criado na hora).
  TextEditingController _campo(Object? equipId, Object? modeloId) =>
      _campos.putIfAbsent('$equipId:$modeloId', TextEditingController.new);

  /// Carrega nos campos o que já foi medido neste equipamento.
  void _carregar(Map<String, dynamic> equip) {
    final banco = EstadoApp.instancia.banco!;
    for (final m in banco.modelosDoTipo(equip['tipo_equipamento_id'])) {
      final atual = banco.um('atendimento_medicoes', AcoesAtendimento.idMedicao(widget.atd['id'], equip['id'], m['id']));
      _campo(equip['id'], m['id']).text =
          atual == null ? '' : (m['tipo_valor'] == 'numero' ? _numeroTexto(atual['valor_numero']) : '${atual['valor_texto'] ?? ''}');
    }
    final fl = banco.um('atendimento_fluidos', AcoesAtendimento.idFluido(widget.atd['id'], equip['id']));
    _fluido.text = '${fl?['fluido'] ?? equip['fluido_refrigerante'] ?? ''}';
    _adicionado.text = _numeroTexto(fl?['adicionado_kg']);
    _recolhido.text = _numeroTexto(fl?['recolhido_kg']);
    _equipId = '${equip['id']}';
    _sujo = false;
  }

  Future<void> _salvar(Map<String, dynamic> equip) async {
    final banco = EstadoApp.instancia.banco!;
    var n = 0;
    for (final m in banco.modelosDoTipo(equip['tipo_equipamento_id'])) {
      final texto = _campo(equip['id'], m['id']).text.trim();
      final atual = banco.um('atendimento_medicoes', AcoesAtendimento.idMedicao(widget.atd['id'], equip['id'], m['id']));
      if (m['tipo_valor'] == 'numero') {
        final valor = _numero(texto);
        if (texto.isNotEmpty && valor == null) {
          if (mounted) _aviso(context, '${m['nome']}: número inválido.');
          return;
        }
        if (valor == (atual?['valor_numero'] == null ? null : num.tryParse('${atual!['valor_numero']}'))) continue;
        await AcoesAtendimento.salvarMedicao(widget.atd, equip, m, numero: valor);
      } else {
        if (texto == '${atual?['valor_texto'] ?? ''}') continue;
        await AcoesAtendimento.salvarMedicao(widget.atd, equip, m, texto: texto);
      }
      n++;
    }
    final fluido = _fluido.text.trim();
    final adicionado = _numero(_adicionado.text) ?? 0, recolhido = _numero(_recolhido.text) ?? 0;
    final fl = banco.um('atendimento_fluidos', AcoesAtendimento.idFluido(widget.atd['id'], equip['id']));
    final mudouFluido = fl == null
        ? (adicionado != 0 || recolhido != 0)
        : (fluido != '${fl['fluido']}' ||
            adicionado != (num.tryParse('${fl['adicionado_kg']}') ?? 0) ||
            recolhido != (num.tryParse('${fl['recolhido_kg']}') ?? 0));
    if (mudouFluido) {
      if (fluido.isEmpty) {
        if (mounted) _aviso(context, 'Informe o fluido (ex.: R-410A).');
        return;
      }
      await AcoesAtendimento.salvarFluido(widget.atd, equip,
          fluido: fluido, adicionadoKg: adicionado, recolhidoKg: recolhido);
      n++;
    }
    if (!mounted) return;
    setState(() => _sujo = false);
    _aviso(context, n == 0 ? 'Nada mudou.' : 'Medições salvas.');
  }

  @override
  Widget build(BuildContext context) {
    final banco = EstadoApp.instancia.banco!;
    final equipamentos = banco.equipamentosDoAtendimento(widget.atd);
    if (equipamentos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Identifique um equipamento (aba Equipamentos) para medir.',
              textAlign: TextAlign.center, style: TextStyle(color: Cores.neutro)),
        ),
      );
    }
    final equip = equipamentos.firstWhere((e) => e['id'] == _equipId, orElse: () => equipamentos.first);
    if (_equipId == null) {
      _carregar(equip); // primeiro desenho: os campos ainda não estão na tela
    } else if (_equipId != equip['id']) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _carregar(equip));
      });
    }
    final modelos = banco.modelosDoTipo(equip['tipo_equipamento_id']);

    return ListView(padding: const EdgeInsets.all(12), children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in equipamentos)
          ChoiceChip(
            label: Text('${e['codigo']}'),
            selected: e['id'] == equip['id'],
            onSelected: (_) {
              if (_sujo) {
                _aviso(context, 'Salve as medições deste equipamento antes de trocar.');
                return;
              }
              setState(() => _carregar(e));
            },
          ),
      ]),
      const SizedBox(height: 8),
      Text(_rotuloEquipamento(equip), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (modelos.isEmpty)
        const Text('O tipo deste equipamento não tem medições cadastradas (painel: Tipos de equipamento).',
            style: TextStyle(color: Cores.neutro)),
      for (final m in modelos) _campoMedicao(m),
      const Divider(height: 24),
      const Text('Fluido refrigerante', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      TextField(
        controller: _fluido,
        enabled: widget.habilitado,
        decoration: const InputDecoration(labelText: 'Fluido (ex.: R-410A)'),
        onChanged: (_) => setState(() => _sujo = true),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _adicionado,
            enabled: widget.habilitado,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Adicionado', suffixText: 'kg'),
            onChanged: (_) => setState(() => _sujo = true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _recolhido,
            enabled: widget.habilitado,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Recolhido', suffixText: 'kg'),
            onChanged: (_) => setState(() => _sujo = true),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      if (widget.habilitado)
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _sujo ? () => _salvar(equip) : null,
            icon: const Icon(Icons.save_outlined),
            label: Text(_sujo ? 'Salvar medições' : 'Medições salvas'),
          ),
        ),
    ]);
  }

  Widget _campoMedicao(Map<String, dynamic> m) {
    final controle = _campo(_equipId, m['id']);
    final min = m['faixa_min'], max = m['faixa_max'];
    final faixa = min != null && max != null
        ? 'Faixa ${_numeroTexto(min)} a ${_numeroTexto(max)}'
        : min != null
            ? 'Mínimo ${_numeroTexto(min)}'
            : max != null
                ? 'Máximo ${_numeroTexto(max)}'
                : null;
    final valor = _numero(controle.text);
    final fora = m['tipo_valor'] == 'numero' &&
        valor != null &&
        ((min != null && valor < num.parse('$min')) || (max != null && valor > num.parse('$max')));
    final unidade = m['unidade'] == 'c' ? '°C' : (m['unidade'] == 'outro' ? '' : '${m['unidade']}'.toUpperCase());
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controle,
        enabled: widget.habilitado,
        keyboardType: m['tipo_valor'] == 'numero'
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: '${m['nome']}',
          suffixText: unidade,
          helperText: fora ? 'Fora da faixa!' : faixa,
          helperStyle: TextStyle(color: fora ? Cores.erro : Cores.neutro, fontWeight: fora ? FontWeight.w700 : null),
          enabledBorder: fora ? const OutlineInputBorder(borderSide: BorderSide(color: Cores.erro, width: 2)) : null,
        ),
        onChanged: (_) => setState(() => _sujo = true),
      ),
    );
  }
}

// =====================================================================
// Itens (peças e serviços usados)
// =====================================================================

class AbaItens extends StatelessWidget {
  const AbaItens({super.key, required this.atd, required this.habilitado});

  final Map<String, dynamic> atd;
  final bool habilitado;

  String _dinheiro(num v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  Future<void> _adicionar(BuildContext context) async {
    final banco = EstadoApp.instancia.banco!;
    final produtos = banco.todos('produtos').where((p) => p['ativo'] != false).toList()
      ..sort((a, b) => '${a['descricao']}'.compareTo('${b['descricao']}'));
    final escolha = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _Busca(
        titulo: 'Peça ou serviço',
        itens: produtos,
        livre: true,
        texto: (p) => [
          p['codigo'],
          p['descricao'],
          ...((p['sinonimos'] as List?) ?? const []),
        ].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
      ),
    );
    if (escolha == null || !context.mounted) return;
    final livre = escolha['_livre'] as String?;
    final qtd = await _pedirQuantidade(context, livre ?? '${escolha['descricao']}', '${escolha['unidade'] ?? 'un'}');
    if (qtd == null) return;
    await AcoesAtendimento.salvarItem(atd, produto: livre == null ? escolha : null, descricao: livre, quantidade: qtd);
  }

  Future<num?> _pedirQuantidade(BuildContext context, String nome, String unidade) async {
    final c = TextEditingController(text: '1');
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
              final v = _numero(c.text);
              if (v != null && v > 0) Navigator.of(ctx).pop(v);
            },
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    // Sem dispose: o diálogo ainda anima a saída usando o campo.
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final banco = EstadoApp.instancia.banco!;
    final itens = banco.doAtendimento('os_itens', atd['id'])..sort((a, b) => '${a['descricao']}'.compareTo('${b['descricao']}'));
    final total = itens.fold<num>(0, (s, i) => s + (num.tryParse('${i['total']}') ?? 0));
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (habilitado)
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: () => _adicionar(context),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar peça ou serviço'),
          ),
        ),
      const SizedBox(height: 8),
      if (itens.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nenhum item usado neste atendimento.', style: TextStyle(color: Cores.neutro)),
        ),
      for (final i in itens)
        Card(
          child: ListTile(
            title: Text('${i['descricao']}'),
            subtitle: Text('${_numeroTexto(i['quantidade'])} ${i['unidade'] ?? ''}'
                '${i['produto_id'] == null ? ' · sem cadastro' : ' · ${_dinheiro(num.tryParse('${i['preco_unitario']}') ?? 0)} cada'}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_dinheiro(num.tryParse('${i['total']}') ?? 0), style: const TextStyle(fontWeight: FontWeight.w700)),
              if (habilitado)
                IconButton(
                  tooltip: 'Tirar',
                  onPressed: () => AcoesAtendimento.apagarItem(i),
                  icon: const Icon(Icons.delete_outline),
                ),
            ]),
          ),
        ),
      if (itens.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('Total: ${_dinheiro(total)}',
              textAlign: TextAlign.right, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
    ]);
  }
}

// =====================================================================
// Fotos
// =====================================================================

class AbaFotos extends StatefulWidget {
  const AbaFotos({super.key, required this.atd, required this.habilitado});

  final Map<String, dynamic> atd;
  final bool habilitado;

  @override
  State<AbaFotos> createState() => _AbaFotosState();
}

class _AbaFotosState extends State<AbaFotos> {
  bool _tirando = false;

  /// Foto só pela câmera, reduzida (1600 px, JPEG) e guardada na pasta
  /// do app até subir para a plataforma.
  Future<void> _tirar() async {
    setState(() => _tirando = true);
    try {
      final foto = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 70,
      );
      if (foto == null) return;
      final id = AcoesAtendimento.novoId();
      final pasta = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'fotos'));
      await pasta.create(recursive: true);
      final destino = p.join(pasta.path, '$id.jpg');
      final bytes = await foto.readAsBytes();
      await File(destino).writeAsBytes(bytes, flush: true);
      await AcoesAtendimento.registrarFoto(
        widget.atd,
        fotoId: id,
        arquivoLocal: destino,
        sha256: sha256.convert(bytes).toString(),
      );
    } catch (e) {
      if (mounted) _aviso(context, 'Não foi possível tirar a foto: $e');
    } finally {
      if (mounted) setState(() => _tirando = false);
    }
  }

  Future<void> _ver(Map<String, dynamic> f) async {
    final arquivo = f['arquivo_local'] == null ? null : File('${f['arquivo_local']}');
    final apagar = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (arquivo != null && arquivo.existsSync())
            Flexible(child: Image.file(arquivo, fit: BoxFit.contain))
          else
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('A foto está na plataforma (ver pelo painel).', textAlign: TextAlign.center),
            ),
          OverflowBar(alignment: MainAxisAlignment.end, children: [
            if (widget.habilitado)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Apagar', style: TextStyle(color: Cores.erro)),
              ),
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Fechar')),
          ]),
        ]),
      ),
    );
    if (apagar == true) await AcoesAtendimento.apagarFoto(f);
  }

  @override
  Widget build(BuildContext context) {
    final banco = EstadoApp.instancia.banco!;
    final fotos = banco.doAtendimento('atendimento_fotos', widget.atd['id'])
      ..sort((a, b) => '${a['tirada_em']}'.compareTo('${b['tirada_em']}'));
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (widget.habilitado)
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _tirando ? null : _tirar,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Tirar foto'),
          ),
        ),
      const SizedBox(height: 8),
      if (fotos.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nenhuma foto neste atendimento.', style: TextStyle(color: Cores.neutro)),
        ),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        children: [
          for (final f in fotos)
            InkWell(
              onTap: () => _ver(f),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: f['arquivo_local'] != null && File('${f['arquivo_local']}').existsSync()
                    ? Image.file(File('${f['arquivo_local']}'), fit: BoxFit.cover, cacheWidth: 300)
                    : const ColoredBox(
                        color: Cores.indigo100,
                        child: Center(child: Icon(Icons.cloud_done_outlined, color: Cores.indigo500)),
                      ),
              ),
            ),
        ],
      ),
    ]);
  }
}
