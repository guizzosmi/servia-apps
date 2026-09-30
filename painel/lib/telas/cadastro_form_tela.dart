import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../cadastros/campos.dart';
import '../cadastros/catalogo.dart';
import '../cadastros/definicoes.dart';
import '../cadastros/lista.dart';
import '../cadastros/servico.dart';

/// Formulário genérico de cadastro (incluir, alterar, excluir) com as
/// listas filhas embaixo (ex.: locais e contatos do cliente).
class CadastroFormTela extends StatefulWidget {
  const CadastroFormTela({
    super.key,
    required this.def,
    required this.id,
    required this.herdados,
    this.sugestoes = const {},
  });

  final CadastroDef def;
  final String? id;

  /// Valores vindos do pai (?cliente_id=...). Ficam travados.
  final Map<String, String> herdados;

  /// Valores sugeridos para um registro novo (ex.: o nome digitado na busca).
  /// Diferente dos herdados, estes podem ser alterados.
  final Map<String, String> sugestoes;

  @override
  State<CadastroFormTela> createState() => _CadastroFormTelaState();
}

class _CadastroFormTelaState extends State<CadastroFormTela> {
  late final CadastroServico _servico = CadastroServico(widget.def);
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _textos = {};
  final Map<String, dynamic> _valores = {};

  String? _id;
  Map<String, dynamic>? _registro;
  bool _carregando = true;
  bool _salvando = false;
  String? _erro;

  CadastroDef get def => widget.def;
  bool get _novo => _id == null;

  static const _tiposTexto = {
    TipoCampo.texto,
    TipoCampo.textoLongo,
    TipoCampo.numero,
    TipoCampo.inteiro,
    TipoCampo.listaTexto,
    TipoCampo.email,
    TipoCampo.telefone,
    TipoCampo.documento,
    TipoCampo.data,
  };

  @override
  void initState() {
    super.initState();
    _id = widget.id;
    for (final c in def.campos) {
      if (_tiposTexto.contains(c.tipo)) _textos[c.nome] = TextEditingController();
    }
    _carregar();
  }

  @override
  void dispose() {
    for (final t in _textos.values) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      if (_id == null) {
        _preencher({
          for (final c in def.campos)
            if (c.padrao != null) c.nome: c.padrao,
          ...widget.sugestoes,
          ...widget.herdados,
        });
      } else {
        final r = await _servico.obter(_id!);
        _registro = r;
        _preencher(r);
      }
    } catch (e) {
      _erro = mensagemDeErro(e);
    }
    if (mounted) setState(() => _carregando = false);
  }

  // ---------- conversão banco <-> tela ----------

  void _preencher(Map<String, dynamic> dados) {
    for (final c in def.campos) {
      final v = dados[c.nome];
      _valores[c.nome] = v;
      _textos[c.nome]?.text = _paraTexto(c, v);
    }
  }

  String _paraTexto(CampoDef c, Object? v) {
    if (v == null) return '';
    switch (c.tipo) {
      case TipoCampo.listaTexto:
        return v is List ? v.join(', ') : v.toString();
      case TipoCampo.numero:
        return v.toString().replaceAll('.', ',');
      case TipoCampo.data:
      case TipoCampo.documento:
      case TipoCampo.telefone:
        return formatarValor(v, c.tipo);
      default:
        return v.toString();
    }
  }

  static String _digitos(String s) => s.replaceAll(RegExp(r'\D'), '');

  static num? _lerNumero(String s, {bool inteiro = false}) {
    var t = s.trim();
    if (t.isEmpty) return null;
    if (inteiro) return int.tryParse(t);
    // "1.234,5" -> 1234.5 ; "12.5" -> 12.5
    if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(t);
  }

  Object? _daTela(CampoDef c) {
    final t = _textos[c.nome]?.text.trim() ?? '';
    switch (c.tipo) {
      case TipoCampo.texto:
      case TipoCampo.textoLongo:
        return t.isEmpty ? null : t;
      case TipoCampo.email:
        return t.isEmpty ? null : t.toLowerCase();
      case TipoCampo.telefone:
      case TipoCampo.documento:
        final d = _digitos(t);
        return d.isEmpty ? null : d;
      case TipoCampo.numero:
        return _lerNumero(t);
      case TipoCampo.inteiro:
        return _lerNumero(t, inteiro: true);
      case TipoCampo.listaTexto:
        return t
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      case TipoCampo.data:
        return _valores[c.nome];
      case TipoCampo.simNao:
        return _valores[c.nome] == true;
      case TipoCampo.multiOpcoes:
        return List<String>.from((_valores[c.nome] as List?) ?? const []);
      case TipoCampo.opcoes:
      case TipoCampo.lookup:
      case TipoCampo.cor:
        return _valores[c.nome];
    }
  }

  String? _validar(CampoDef c, String? texto) {
    final t = (texto ?? '').trim();
    if (c.obrigatorio && t.isEmpty) return 'Obrigatório';
    if (t.isNotEmpty) {
      switch (c.tipo) {
        case TipoCampo.email:
          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
            return 'E-mail inválido';
          }
        case TipoCampo.numero:
          if (_lerNumero(t) == null) return 'Número inválido';
        case TipoCampo.inteiro:
          if (_lerNumero(t, inteiro: true) == null) return 'Use só números inteiros';
        case TipoCampo.telefone:
          final d = _digitos(t);
          if (d.length < 10 || d.length > 11) return 'Informe DDD + número';
        case TipoCampo.documento:
          final d = _digitos(t);
          if (d.length != 11 && d.length != 14) return 'CPF (11) ou CNPJ (14) dígitos';
        default:
          break;
      }
    }
    return c.validar?.call(_daTela(c));
  }

  // ---------- regras de tela ----------

  bool _travado(CampoDef c) =>
      widget.herdados.containsKey(c.nome) ||
      (!_novo && colunasPaiDe(def.chave).contains(c.nome));

  /// Ao trocar um campo, limpa os que dependem dele (cliente -> local -> ambiente).
  void _mudou(String nome, Object? valor) {
    setState(() {
      _valores[nome] = valor;
      _limparDependentes(nome);
    });
  }

  void _limparDependentes(String nome) {
    for (final c in def.campos) {
      if (c.lookup?.campoPai == nome && _valores[c.nome] != null) {
        _valores[c.nome] = null;
        _limparDependentes(c.nome);
      }
    }
  }

  /// Registro incluído nesta tela: o id volta para quem abriu (ex.: a busca
  /// de cliente da Nova OS, que já deixa ele escolhido).
  bool _criadoAqui = false;

  void _voltar() {
    if (context.canPop()) {
      context.pop(_criadoAqui ? _id : null);
    } else {
      context.go('/c/${def.chave}');
    }
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    final dados = <String, dynamic>{
      for (final c in def.campos)
        if (!c.somenteLeitura && !(c.somenteNaEdicao && _novo)) c.nome: _daTela(c),
    };
    def.antesDeSalvar?.call(dados, _registro);
    setState(() => _salvando = true);
    try {
      final eraNovo = _novo;
      final salvo = await _servico.salvar(
        dados,
        id: _id,
        versao: _registro?['versao'] as int?,
      );
      if (!mounted) return;
      if (eraNovo && def.filhos.isNotEmpty) {
        // Fica na tela para já incluir os filhos (ex.: locais do cliente).
        setState(() {
          _id = salvo['id'] as String;
          _registro = salvo;
          _criadoAqui = true;
          _preencher(salvo);
        });
        _avisar('Salvo. Agora você pode incluir os itens abaixo.');
      } else {
        if (eraNovo) {
          _id = salvo['id'] as String;
          _criadoAqui = true;
        }
        _avisar('Salvo.');
        _voltar();
      }
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _excluir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir ${def.singular.toLowerCase()}?'),
        content: const Text(
            'O registro deixa de aparecer nas listas e na escolha dos formulários. '
            'O histórico já registrado (atendimentos, relatórios) é mantido.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Cores.erro),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _servico.excluir(_id!);
      _criadoAqui = false;
      if (!mounted) return;
      _avisar('Excluído.');
      _voltar();
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    }
  }

  void _avisar(String texto, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: erro ? Cores.erro : null,
    ));
  }

  // ---------- construção dos campos ----------

  String _rotulo(CampoDef c) => c.obrigatorio ? '${c.rotulo} *' : c.rotulo;

  Widget _campo(CampoDef c, bool editar) {
    final habilitado = editar && !c.somenteLeitura && !_travado(c);
    switch (c.tipo) {
      case TipoCampo.simNao:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(c.rotulo),
          subtitle: c.ajuda == null ? null : Text(c.ajuda!),
          value: _valores[c.nome] == true,
          onChanged: habilitado ? (v) => _mudou(c.nome, v) : null,
        );
      case TipoCampo.opcoes:
        final bruto = _valores[c.nome]?.toString();
        final atual = c.opcoes.any((o) => o.valor == bruto) ? bruto : null;
        return FormField<String>(
          validator: (_) => (c.obrigatorio && _valores[c.nome] == null)
              ? 'Obrigatório'
              : null,
          builder: (estado) => InputDecorator(
            decoration: InputDecoration(
              labelText: _rotulo(c),
              helperText: c.ajuda,
              errorText: estado.errorText,
              enabled: habilitado,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: atual,
                isDense: true,
                isExpanded: true,
                items: [
                  for (final o in c.opcoes)
                    DropdownMenuItem(value: o.valor, child: Text(o.rotulo)),
                ],
                onChanged: habilitado ? (v) => _mudou(c.nome, v) : null,
              ),
            ),
          ),
        );
      case TipoCampo.cor:
        return CampoCor(
          campo: c,
          valor: _valores[c.nome] as String?,
          habilitado: habilitado,
          aoMudar: (v) => _mudou(c.nome, v),
        );
      case TipoCampo.multiOpcoes:
        return CampoMultiOpcoes(
          campo: c,
          valor: List<String>.from((_valores[c.nome] as List?) ?? const []),
          habilitado: habilitado,
          aoMudar: (v) => _mudou(c.nome, v),
        );
      case TipoCampo.lookup:
        final pai = c.lookup!.campoPai;
        return CampoLookup(
          campo: c,
          valor: _valores[c.nome] as String?,
          valorPai: pai == null ? null : _valores[pai] as String?,
          rotuloPai: pai == null
              ? null
              : def.campos.where((x) => x.nome == pai).firstOrNull?.rotulo,
          habilitado: habilitado,
          aoMudar: (v) => _mudou(c.nome, v),
        );
      case TipoCampo.data:
        return TextFormField(
          controller: _textos[c.nome],
          readOnly: true,
          enabled: habilitado,
          decoration: InputDecoration(
            labelText: _rotulo(c),
            helperText: c.ajuda,
            suffixIcon: (habilitado && _valores[c.nome] != null && !c.obrigatorio)
                ? IconButton(
                    tooltip: 'Limpar',
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _textos[c.nome]!.text = '';
                      _mudou(c.nome, null);
                    },
                  )
                : const Icon(Icons.calendar_today, size: 18),
          ),
          validator: (t) => _validar(c, t),
          onTap: () async {
            final atual = DateTime.tryParse('${_valores[c.nome] ?? ''}');
            final d = await showDatePicker(
              context: context,
              initialDate: atual ?? DateTime.now(),
              firstDate: DateTime(1990),
              lastDate: DateTime(2100),
            );
            if (d == null || !mounted) return;
            final iso =
                '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
            _textos[c.nome]!.text = formatarValor(iso, TipoCampo.data);
            _mudou(c.nome, iso);
          },
        );
      default:
        final teclado = switch (c.tipo) {
          TipoCampo.numero => const TextInputType.numberWithOptions(decimal: true),
          TipoCampo.inteiro => TextInputType.number,
          TipoCampo.email => TextInputType.emailAddress,
          TipoCampo.telefone => TextInputType.phone,
          TipoCampo.textoLongo => TextInputType.multiline,
          _ => TextInputType.text,
        };
        return TextFormField(
          controller: _textos[c.nome],
          enabled: habilitado,
          keyboardType: teclado,
          minLines: c.tipo == TipoCampo.textoLongo ? 3 : 1,
          maxLines: c.tipo == TipoCampo.textoLongo ? 8 : 1,
          decoration: InputDecoration(
            labelText: _rotulo(c),
            helperText: c.ajuda ??
                (c.tipo == TipoCampo.listaTexto ? 'Separe por vírgula' : null),
          ),
          validator: (t) => _validar(c, t),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_erro!, style: const TextStyle(color: Cores.erro)),
            TextButton(onPressed: _voltar, child: const Text('Voltar')),
          ],
        ),
      );
    }

    final editar = podeEditarCadastros();
    final podeExcluir = editar &&
        !_novo &&
        (def.podeExcluir == null || def.podeExcluir!(_registro ?? const {}));
    final titulo = _novo
        ? 'Novo ${def.singular.toLowerCase()}'
        : (_registro?[def.colunaTitulo] ?? def.singular).toString();

    final campos = def.campos.where((c) => !(c.somenteNaEdicao && _novo)).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Voltar',
                    onPressed: _voltar,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(def.singular.toUpperCase(),
                            style: const TextStyle(
                                fontSize: 11,
                                letterSpacing: .8,
                                color: Cores.neutro,
                                fontWeight: FontWeight.w700)),
                        Text(titulo,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
              if (!editar)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Somente leitura: seu papel não permite alterar cadastros.',
                      style: TextStyle(color: Cores.alerta)),
                ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _form,
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final duas = box.maxWidth >= 640;
                        final meia = (box.maxWidth - 16) / 2;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (final c in campos)
                              SizedBox(
                                width: (duas && c.metade) ? meia : box.maxWidth,
                                child: _campo(c, editar),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (podeExcluir)
                    TextButton.icon(
                      onPressed: _salvando ? null : _excluir,
                      style: TextButton.styleFrom(foregroundColor: Cores.erro),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Excluir'),
                    ),
                  const Spacer(),
                  OutlinedButton(onPressed: _voltar, child: const Text('Voltar')),
                  if (editar) ...[
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _salvando ? null : _salvar,
                      icon: _salvando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check),
                      label: const Text('Salvar'),
                    ),
                  ],
                ],
              ),
              if (!_novo)
                for (final f in def.filhos) ...[
                  const SizedBox(height: 32),
                  _Filho(filho: f, paiId: _id!, pai: _registro ?? const {}),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Filho extends StatelessWidget {
  const _Filho({required this.filho, required this.paiId, required this.pai});

  final FilhoDef filho;
  final String paiId;
  final Map<String, dynamic> pai;

  @override
  Widget build(BuildContext context) {
    final defFilho = cadastroPorChave(filho.cadastro);
    if (defFilho == null) return const SizedBox.shrink();
    final herdados = <String, String>{filho.colunaPai: paiId};
    filho.herdar.forEach((colFilho, colPai) {
      final v = pai[colPai];
      if (v != null) herdados[colFilho] = v.toString();
    });
    return ListaCadastro(
      key: ValueKey('${filho.cadastro}:$paiId'),
      def: defFilho,
      filtros: {filho.colunaPai: paiId},
      herdados: herdados,
      embutida: true,
    );
  }
}
