import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cadastros/campos.dart';
import '../cadastros/definicoes.dart';
import '../servicos/arquivo_web.dart';
import '../servicos/parametros.dart';
import '../servicos/planilha.dart';
import '../servicos/planos.dart';
import '../servicos/status.dart';
import '../widgets/campos_data_hora.dart';
import '../widgets/margem.dart';

/// Endereço da planilha modelo do PMOC (site).
const urlModeloPmoc = 'https://servpilot.com.br/modelos/planilha-pmoc.xlsx';

/// Assistente do plano (guia 55): em 3 passos o gestor sai com o plano (PMOC
/// ou preventiva) ativo, com os aparelhos e as atividades. Os aparelhos vêm
/// do cadastro do local e/ou da planilha do PMOC (ambientes com área e
/// ocupantes, um aparelho por linha). "Conferir" simula sem gravar; "Criar"
/// grava tudo de uma vez (plano_assistente: com erro numa linha, nada entra).
class PlanoAssistenteTela extends StatefulWidget {
  const PlanoAssistenteTela({super.key});

  @override
  State<PlanoAssistenteTela> createState() => _PlanoAssistenteTelaState();
}

class _Coluna {
  const _Coluna(this.nome, this.ajuda);
  final String nome;
  final String ajuda;
}

/// Colunas da planilha do PMOC (a ordem não importa).
const colunasPmoc = [
  _Coluna('ambiente', 'Sala ou setor atendido (é criado se não existir)'),
  _Coluna('setor_andar', 'Andar, bloco ou setor'),
  _Coluna('area_m2', 'Área climatizada em m² (ex.: 42,5)'),
  _Coluna('ocupantes_fixos', 'Ocupantes fixos'),
  _Coluna('ocupantes_variaveis', 'Ocupantes flutuantes (visitantes)'),
  _Coluna('codigo', 'TAG, plaqueta ou patrimônio do aparelho'),
  _Coluna('tipo', 'Tipo (Split hi-wall, Split cassete, Split piso-teto, Câmara fria...)'),
  _Coluna('descricao', 'Descrição (ex.: Split da recepção)'),
  _Coluna('marca', 'Marca'),
  _Coluna('modelo', 'Modelo'),
  _Coluna('serie', 'Número de série'),
  _Coluna('capacidade', 'Capacidade (ex.: 12.000)'),
  _Coluna('unidade_capacidade', 'BTU/h, TR ou kW (vazio = BTU/h)'),
  _Coluna('fluido', 'Fluido refrigerante (ex.: R-410A)'),
  _Coluna('instalacao', 'Data de instalação (dd/mm/aaaa)'),
];

/// Outros nomes que as planilhas de PMOC costumam usar.
const _apelidosPmoc = {
  'sala': 'ambiente', 'setor': 'ambiente', 'local': 'ambiente', 'ambiente_climatizado': 'ambiente',
  'identificacao_do_ambiente': 'ambiente', 'andar': 'setor_andar', 'pavimento': 'setor_andar', 'bloco': 'setor_andar',
  'area': 'area_m2', 'area_m': 'area_m2', 'm2': 'area_m2', 'area_climatizada': 'area_m2',
  'area_climatizada_m2': 'area_m2', 'ocupantes': 'ocupantes_fixos', 'n_ocupantes': 'ocupantes_fixos',
  'ocupantes_fixo': 'ocupantes_fixos', 'flutuantes': 'ocupantes_variaveis', 'ocupantes_flutuantes': 'ocupantes_variaveis',
  'variaveis': 'ocupantes_variaveis', 'tag': 'codigo', 'plaqueta': 'codigo', 'patrimonio': 'codigo',
  'identificacao': 'codigo', 'tipo_equipamento': 'tipo', 'tipo_de_equipamento': 'tipo', 'equipamento': 'tipo',
  'fabricante': 'marca', 'n_serie': 'serie', 'numero_serie': 'serie', 'numero_de_serie': 'serie', 'btus': 'capacidade',
  'btu': 'capacidade', 'btu_h': 'capacidade', 'capacidade_btu': 'capacidade', 'capacidade_btu_h': 'capacidade',
  'unidade': 'unidade_capacidade', 'gas': 'fluido', 'fluido_refrigerante': 'fluido', 'refrigerante': 'fluido',
  'data_instalacao': 'instalacao', 'data_de_instalacao': 'instalacao',
};

String _normal(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñº°²';
  const para = 'aaaaaeeeeiiiiooooouuuucnoo2';
  var t = s.trim().toLowerCase();
  for (var i = 0; i < de.length; i++) {
    t = t.replaceAll(de[i], para[i]);
  }
  return t.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
}

class _PlanoAssistenteTelaState extends State<PlanoAssistenteTela> {
  SupabaseClient get _db => Supabase.instance.client;

  static const _campoCliente = CampoDef('cliente_id', 'Cliente',
      tipo: TipoCampo.lookup, obrigatorio: true, lookup: Lookup(tabela: 'clientes'));
  static const _campoLocal = CampoDef('local_id', 'Local',
      tipo: TipoCampo.lookup,
      obrigatorio: true,
      lookup: Lookup(tabela: 'locais', colunaDetalhe: 'cidade', colunaFiltro: 'cliente_id', campoPai: 'cliente_id',
          escolherUnico: true));

  int _passo = 0;

  // Passo 1: o plano
  final _form = GlobalKey<FormState>();
  late String _tipo = ParametrosEmpresa.instancia.atendePmoc ? 'pmoc' : 'preventiva';
  final _nome = TextEditingController();
  bool _nomeMexido = false;
  String? _clienteId;
  String? _localId;
  String _clienteNome = '';
  late DateTime? _inicio = _hoje();
  late DateTime? _fim = DateTime(_hoje().year + 1, _hoje().month, _hoje().day).subtract(const Duration(days: 1));
  String? _periodicidade;
  final _rtNome = TextEditingController();
  final _rtRegistro = TextEditingController();
  final _art = TextEditingController();
  bool _ativar = true;

  // Passo 2: aparelhos
  List<Map<String, dynamic>> _doLocal = [];
  final Set<String> _marcados = {};
  final Map<String, String> _tipoEscolhido = {}; // aparelho sem tipo -> tipo
  List<Map<String, dynamic>> _tipos = [];
  bool _carregandoLocal = false;
  String? _localCarregado;
  final _texto = TextEditingController();
  List<Map<String, String>> _linhas = [];
  List<String> _ignoradas = [];
  String? _arquivo;

  // Passo 3: conferência
  Map<String, dynamic>? _resultado;
  bool _ocupado = false;

  static DateTime _hoje() {
    final h = DateTime.now();
    return DateTime(h.year, h.month, h.day);
  }

  bool _tipoMexido = false;

  /// Parâmetros da empresa (PMOC ligado e o RT padrão). Quando a tela abre
  /// direto pelo endereço, eles chegam depois: preenche o que ainda está vazio.
  void _usarParametros() {
    final par = ParametrosEmpresa.instancia;
    if (!par.carregado || !mounted) return;
    final pmoc = Map<String, dynamic>.from((par.valores['pmoc'] as Map?) ?? const {});
    setState(() {
      if (!_tipoMexido) _tipo = par.atendePmoc ? 'pmoc' : 'preventiva';
      if (_rtNome.text.isEmpty) _rtNome.text = '${pmoc['rt_nome'] ?? ''}';
      if (_rtRegistro.text.isEmpty) _rtRegistro.text = '${pmoc['rt_registro'] ?? ''}';
      if (_art.text.isEmpty) _art.text = '${pmoc['art_numero'] ?? ''}';
    });
  }

  @override
  void initState() {
    super.initState();
    ParametrosEmpresa.instancia.addListener(_usarParametros);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ParametrosEmpresa.instancia.garantir();
      _usarParametros();
    });
    _carregarTipos();
  }

  @override
  void dispose() {
    ParametrosEmpresa.instancia.removeListener(_usarParametros);
    for (final c in [_nome, _rtNome, _rtRegistro, _art, _texto]) {
      c.dispose();
    }
    super.dispose();
  }

  void _avisar(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));
  }

  Future<void> _carregarTipos() async {
    try {
      final t = await _db
          .from('tipos_equipamento')
          .select('id, nome, categoria')
          .isFilter('excluido_em', null)
          .order('nome', ascending: true);
      if (mounted) setState(() => _tipos = t);
    } catch (_) {}
  }

  Future<void> _nomeDoCliente(String? id) async {
    if (id == null) return;
    try {
      final c = await _db.from('clientes').select('nome, nome_fantasia').eq('id', id).maybeSingle();
      _clienteNome = '${c?['nome_fantasia'] ?? c?['nome'] ?? ''}'.trim();
      if (!_nomeMexido && mounted) setState(() => _nome.text = _sugestaoNome());
    } catch (_) {}
  }

  String _sugestaoNome() {
    final ano = _inicio?.year ?? DateTime.now().year;
    final anos = _fim != null && _fim!.year != ano ? '$ano/${_fim!.year}' : '$ano';
    return '${_tipo == 'pmoc' ? 'PMOC' : 'Preventiva'} $_clienteNome $anos'.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<void> _carregarLocal() async {
    final loc = _localId;
    if (loc == null || loc == _localCarregado) return;
    setState(() => _carregandoLocal = true);
    try {
      final d = await _db
          .from('equipamentos')
          .select('id, codigo, descricao, marca, capacidade_valor, tipo_equipamento_id, ambientes(nome), tipos_equipamento(nome)')
          .eq('local_id', loc)
          .eq('situacao', 'ativo')
          .isFilter('excluido_em', null)
          .order('codigo', ascending: true)
          .limit(2000);
      if (!mounted) return;
      setState(() {
        _doLocal = d;
        _marcados
          ..clear()
          ..addAll(d.map((e) => '${e['id']}'));
        _tipoEscolhido.clear();
        _localCarregado = loc;
      });
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _carregandoLocal = false);
    }
  }

  // ---------------- planilha ----------------

  /// Lê o que foi colado (ou o arquivo): acha a linha do cabeçalho (pode haver
  /// título antes) e monta as linhas com as colunas conhecidas.
  bool _ler() {
    final brutas = _texto.text.replaceAll('\r', '').split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (brutas.isEmpty) {
      setState(() {
        _linhas = [];
        _ignoradas = [];
      });
      return true;
    }
    final conhecidas = {for (final c in colunasPmoc) c.nome};
    String? nomeDe(String h) {
      final n = _normal(h);
      final k = _apelidosPmoc[n] ?? n;
      return conhecidas.contains(k) ? k : null;
    }

    final sep = brutas.first.contains('\t') ? '\t' : (';'.allMatches(brutas.first).length >= ','.allMatches(brutas.first).length ? ';' : ',');
    List<String> campos(String l) => l.split(sep).map((x) => x.trim().replaceAll(RegExp(r'^"|"$'), '')).toList();
    var iCab = -1;
    for (var i = 0; i < brutas.length && i < 15; i++) {
      final achadas = campos(brutas[i]).map(nomeDe).whereType<String>().toSet();
      if (achadas.length >= 2 && (achadas.contains('codigo') || achadas.contains('descricao') || achadas.contains('tipo'))) {
        iCab = i;
        break;
      }
    }
    if (iCab < 0) {
      _avisar('Não achei o cabeçalho: a planilha precisa das colunas "codigo" (ou "descricao") e "tipo". '
          'Use a planilha modelo.', erro: true);
      return false;
    }
    final nomes = <String?>[];
    final ignoradas = <String>[];
    for (final h in campos(brutas[iCab])) {
      final n = nomeDe(h);
      nomes.add(n);
      if (n == null && h.trim().isNotEmpty) ignoradas.add(h.trim());
    }
    final dados = <Map<String, String>>[];
    for (final l in brutas.skip(iCab + 1)) {
      final v = campos(l);
      final m = <String, String>{};
      for (var i = 0; i < nomes.length && i < v.length; i++) {
        if (nomes[i] != null && v[i].isNotEmpty) {
          m[nomes[i]!] = nomes[i] == 'instalacao' ? dataDoExcel(v[i]) : v[i];
        }
      }
      // Linha só com o ambiente (sem aparelho) não entra: ex.: linha de total.
      if (m.containsKey('codigo') || m.containsKey('descricao') || m.containsKey('tipo')) dados.add(m);
    }
    setState(() {
      _linhas = dados;
      _ignoradas = ignoradas;
    });
    return true;
  }

  Future<void> _escolherArquivo() async {
    try {
      final a = await escolherArquivo(aceitar: '.xlsx,.xlsm,.csv,.txt');
      if (a == null) return;
      final linhas = lerPlanilha(a.nome, a.bytes);
      _texto.text = linhasComoTexto(linhas);
      _arquivo = a.nome;
      if (_ler() && mounted) _avisar('${a.nome}: ${_linhas.length} aparelho(s) na planilha.');
    } on FormatException catch (e) {
      _avisar(e.message, erro: true);
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  // ---------------- conferir e criar ----------------

  Map<String, dynamic> _pedido({required bool simular}) => {
        'simular': simular,
        'plano': {
          'tipo': _tipo,
          'nome': _nome.text.trim(),
          'cliente_id': _clienteId,
          'local_id': _localId,
          'vigencia_inicio': _inicio == null ? null : dataIso(_inicio!),
          'vigencia_fim': _fim == null ? null : dataIso(_fim!),
          if (_tipo == 'pmoc') ...{
            'responsavel_tecnico_nome': _rtNome.text.trim(),
            'responsavel_tecnico_registro': _rtRegistro.text.trim(),
            'art_numero': _art.text.trim(),
          },
        },
        'equipamentos': _marcados.toList(),
        'tipos': [
          for (final e in _tipoEscolhido.entries)
            if (_marcados.contains(e.key)) {'equipamento_id': e.key, 'tipo_equipamento_id': e.value},
        ],
        'linhas': _linhas,
        'periodicidade': _periodicidade,
        'ativar': _ativar,
      };

  Future<void> _conferir() async {
    setState(() {
      _ocupado = true;
      _resultado = null;
    });
    try {
      final r = await _db.rpc('plano_assistente', params: {'p': _pedido(simular: true)});
      if (mounted) setState(() => _resultado = Map<String, dynamic>.from(r as Map));
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _criar() async {
    setState(() => _ocupado = true);
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('plano_assistente', params: {'p': _pedido(simular: false)}) as Map);
      if (!mounted) return;
      if (r['ok'] != true || r['plano_id'] == null) {
        setState(() => _resultado = r);
        _avisar('Nada foi gravado: corrija as linhas com problema.', erro: true);
        return;
      }
      final res = Map<String, dynamic>.from(r['resumo'] as Map);
      _avisar('Plano criado${res['situacao'] == 'ativo' ? ' e ativo' : ''}: ${res['aparelhos_no_plano']} aparelho(s), '
          '${res['atividades']} atividade(s).');
      context.pushReplacement('/planos/${r['plano_id']}');
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ---------------- navegação entre os passos ----------------

  Future<void> _avancar() async {
    if (_passo == 0) {
      if (!(_form.currentState?.validate() ?? false)) return;
      if (_clienteId == null || _localId == null) {
        _avisar('Escolha o cliente e o local.', erro: true);
        return;
      }
      if (_inicio == null) {
        _avisar('Informe o início da vigência.', erro: true);
        return;
      }
      setState(() => _passo = 1);
      await _carregarLocal();
      return;
    }
    if (_passo == 1) {
      if (!_ler()) return;
      if (_marcados.isEmpty && _linhas.isEmpty) {
        _avisar('Marque os aparelhos do local ou traga a planilha do PMOC.', erro: true);
        return;
      }
      setState(() => _passo = 2);
      await _conferir();
    }
  }

  @override
  Widget build(BuildContext context) {
    final gestor = Sessao.atual?.tem(Papel.gestor) ?? false;
    return ListView(padding: margemDaTela(context), children: [
      Row(children: [
        IconButton(
          tooltip: 'Voltar aos planos',
          onPressed: () => context.canPop() ? context.pop() : context.go('/planos'),
          icon: const Icon(Icons.arrow_back),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(ParametrosEmpresa.instancia.atendePmoc ? 'Novo plano ou PMOC' : 'Novo plano de preventiva',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        TextButton(
          onPressed: () => context.pushReplacement('/planos/novo'),
          child: const Text('Plano em branco'),
        ),
      ]),
      const SizedBox(height: 4),
      const Text('Três passos: o plano, os aparelhos (do cadastro ou da planilha do PMOC) e a conferência. '
          'As atividades da Portaria entram sozinhas.', style: TextStyle(color: Cores.neutro)),
      const SizedBox(height: 16),
      _Passos(atual: _passo, aoTocar: (i) {
        if (i < _passo) setState(() => _passo = i);
      }),
      const SizedBox(height: 16),
      if (!gestor)
        const Text('Só o gestor cria planos.', style: TextStyle(color: Cores.neutro))
      else
        switch (_passo) {
          0 => _passoPlano(),
          1 => _passoAparelhos(),
          _ => _passoConferir(),
        },
    ]);
  }

  Widget _cartao(List<Widget> filhos) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: filhos),
        ),
      );

  Widget _botoes({required String avancar, VoidCallback? aoAvancar, IconData icone = Icons.arrow_forward}) =>
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (_passo > 0)
            OutlinedButton.icon(
              onPressed: _ocupado ? null : () => setState(() => _passo--),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Voltar'),
            ),
          FilledButton.icon(
            key: ValueKey('avancar$_passo'),
            onPressed: _ocupado ? null : aoAvancar,
            icon: Icon(icone),
            label: Text(avancar),
          ),
          if (_ocupado) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
      );

  // ---------------- passo 1 ----------------

  Widget _passoPlano() {
    final pmoc = _tipo == 'pmoc';
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cartao([
          LayoutBuilder(builder: (context, box) {
            final cheio = box.maxWidth;
            final metade = cheio >= 640 ? (cheio - 16) / 2 : cheio;
            final quarto = cheio >= 640 ? (cheio - 48) / 4 : metade;
            Widget caixa(double w, Widget f) => SizedBox(width: w, child: f);
            return Wrap(spacing: 16, runSpacing: 16, children: [
              if (ParametrosEmpresa.instancia.atendePmoc)
                caixa(
                  cheio,
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'pmoc', label: Text('PMOC (climatização)')),
                      ButtonSegment(value: 'preventiva', label: Text('Preventiva')),
                    ],
                    selected: {_tipo},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() {
                      _tipo = s.first;
                      _tipoMexido = true;
                      if (!_nomeMexido) _nome.text = _sugestaoNome();
                    }),
                  ),
                ),
              caixa(
                metade,
                CampoLookup(
                  campo: _campoCliente,
                  valor: _clienteId,
                  valorPai: null,
                  rotuloPai: null,
                  habilitado: true,
                  aoMudar: (v) {
                    setState(() {
                      _clienteId = v;
                      _localId = null;
                    });
                    _nomeDoCliente(v);
                  },
                ),
              ),
              caixa(
                metade,
                CampoLookup(
                  campo: _campoLocal,
                  valor: _localId,
                  valorPai: _clienteId,
                  rotuloPai: 'Cliente',
                  habilitado: true,
                  aoMudar: (v) => setState(() => _localId = v),
                ),
              ),
              caixa(
                metade,
                TextFormField(
                  controller: _nome,
                  decoration: const InputDecoration(labelText: 'Nome do plano *'),
                  onChanged: (_) => _nomeMexido = true,
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Dê um nome ao plano' : null,
                ),
              ),
              caixa(
                  quarto,
                  CampoData(
                      rotulo: 'Vigência: início *',
                      valor: _inicio,
                      aoMudar: (d) => setState(() {
                            _inicio = d;
                            if (!_nomeMexido) _nome.text = _sugestaoNome();
                          }))),
              caixa(
                  quarto,
                  CampoData(
                      rotulo: 'Fim',
                      valor: _fim,
                      aoMudar: (d) => setState(() {
                            _fim = d;
                            if (!_nomeMexido) _nome.text = _sugestaoNome();
                          }))),
              caixa(
                metade,
                InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'Frequência das visitas',
                      helperText: 'O contrato com o cliente manda: todas as atividades por aparelho seguem esta'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _periodicidade,
                      isDense: true,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Cada atividade na sua (padrão da Portaria)')),
                        for (final e in periodicidades.entries)
                          DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) => setState(() => _periodicidade = v),
                    ),
                  ),
                ),
              ),
              if (pmoc) ...[
                caixa(
                  metade,
                  TextFormField(
                    controller: _rtNome,
                    decoration: const InputDecoration(labelText: 'Responsável técnico (RT)', hintText: 'Eng. Fulano de Tal'),
                  ),
                ),
                caixa(
                  quarto,
                  TextFormField(
                    controller: _rtRegistro,
                    decoration: const InputDecoration(labelText: 'CREA / CFT do RT'),
                  ),
                ),
                caixa(
                  quarto,
                  TextFormField(
                    controller: _art,
                    decoration: const InputDecoration(labelText: 'ART / TRT'),
                  ),
                ),
              ],
            ]);
          }),
          if (pmoc && _rtNome.text.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Dica: guarde o RT em Configurações > Preventivas; ele já vem preenchido nos próximos.',
                  style: TextStyle(color: Cores.neutro, fontSize: 12)),
            ),
        ]),
        _botoes(avancar: 'Aparelhos', aoAvancar: _avancar),
      ]),
    );
  }

  // ---------------- passo 2 ----------------

  Widget _passoAparelhos() {
    final semTipo = _doLocal.where((e) => e['tipo_equipamento_id'] == null && _marcados.contains('${e['id']}')).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _cartao([
        Row(children: [
          Expanded(
            child: Text('Aparelhos já cadastrados neste local (${_doLocal.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          if (_doLocal.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                if (_marcados.length == _doLocal.length) {
                  _marcados.clear();
                } else {
                  _marcados.addAll(_doLocal.map((e) => '${e['id']}'));
                }
              }),
              child: Text(_marcados.length == _doLocal.length ? 'Desmarcar todos' : 'Marcar todos'),
            ),
        ]),
        if (_carregandoLocal) const LinearProgressIndicator(minHeight: 2),
        if (!_carregandoLocal && _doLocal.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nenhum aparelho cadastrado ainda: traga a planilha abaixo (os aparelhos são cadastrados junto).',
                style: TextStyle(color: Cores.neutro)),
          ),
        if (semTipo.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('${semTipo.length} aparelho(s) sem tipo: escolha o tipo para receberem as atividades.',
                style: const TextStyle(color: Cores.alerta)),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView(shrinkWrap: true, children: [
            for (final e in _doLocal) _linhaAparelho(e),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      _cartao([
        Row(children: [
          const Expanded(
            child: Text('Planilha do PMOC (opcional)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          TextButton.icon(
            onPressed: () => abrirEmNovaAba(urlModeloPmoc),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Baixar a planilha modelo'),
          ),
        ]),
        const Text('Um aparelho por linha, com o ambiente (área e ocupantes entram no documento do PMOC). '
            'Aparelho que já existe (mesmo código) não é duplicado: só entra no plano.',
            style: TextStyle(color: Cores.neutro)),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.tonalIcon(
            key: const ValueKey('escolherPlanilha'),
            onPressed: _escolherArquivo,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Escolher a planilha (.xlsx ou .csv)'),
          ),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: colunasPmoc.map((c) => c.nome).join('\t')));
              _avisar('Cabeçalho copiado: cole na primeira linha da sua planilha.');
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copiar cabeçalho'),
          ),
          if (_arquivo != null) Text(_arquivo!, style: const TextStyle(color: Cores.neutro)),
        ]),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('textoPmoc'),
          controller: _texto,
          minLines: 4,
          maxLines: 10,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'Ou copie as linhas da planilha (com o cabeçalho) e cole aqui',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) {
            if (_linhas.isNotEmpty) setState(() => _linhas = []);
          },
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final c in colunasPmoc) Tooltip(message: c.ajuda, child: Chip(label: Text(c.nome))),
        ]),
        if (_linhas.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${_linhas.length} aparelho(s) na planilha.', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        if (_ignoradas.isNotEmpty)
          Text('Colunas ignoradas: ${_ignoradas.join(', ')}', style: const TextStyle(color: Cores.alerta)),
      ]),
      _botoes(avancar: 'Conferir', aoAvancar: _avancar, icone: Icons.fact_check_outlined),
    ]);
  }

  Widget _linhaAparelho(Map<String, dynamic> e) {
    final id = '${e['id']}';
    final semTipo = e['tipo_equipamento_id'] == null;
    final detalhe = [
      (e['ambientes'] as Map?)?['nome'],
      (e['tipos_equipamento'] as Map?)?['nome'],
      e['marca'],
      if (e['capacidade_valor'] != null) '${e['capacidade_valor']}',
    ].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
    return Row(children: [
      Checkbox(
        value: _marcados.contains(id),
        onChanged: (v) => setState(() => v == true ? _marcados.add(id) : _marcados.remove(id)),
      ),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text([e['codigo'], e['descricao']].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (detalhe.isNotEmpty) Text(detalhe, style: const TextStyle(color: Cores.neutro, fontSize: 12)),
        ]),
      ),
      if (semTipo && _marcados.contains(id))
        SizedBox(
          width: 220,
          child: DropdownButton<String>(
            value: _tipoEscolhido[id],
            hint: const Text('Escolha o tipo'),
            isExpanded: true,
            items: [for (final t in _tipos) DropdownMenuItem(value: '${t['id']}', child: Text('${t['nome']}'))],
            onChanged: (v) => setState(() => v == null ? _tipoEscolhido.remove(id) : _tipoEscolhido[id] = v),
          ),
        ),
    ]);
  }

  // ---------------- passo 3 ----------------

  Widget _passoConferir() {
    final r = _resultado;
    if (r == null) {
      return _cartao([
        if (_ocupado) const LinearProgressIndicator(minHeight: 2) else const Text('Toque em Conferir de novo.'),
        if (!_ocupado) _botoes(avancar: 'Conferir', aoAvancar: _conferir, icone: Icons.fact_check_outlined),
      ]);
    }
    final res = Map<String, dynamic>.from((r['resumo'] as Map?) ?? const {});
    final linhas = ((r['linhas'] as List?) ?? const []).cast<Map>();
    final avisos = ((r['avisos'] as List?) ?? const []).map((x) => '$x').toList();
    final erros = (res['erros'] as num?)?.toInt() ?? 0;
    final problemas = linhas.where((l) => l['situacao'] == 'erro' || l['mensagem'] != null).toList();
    Widget numero(String rotulo, Object? valor) => SizedBox(
          width: 150,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${valor ?? 0}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            Text(rotulo, style: const TextStyle(color: Cores.neutro)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _cartao([
        Text(erros > 0 ? 'Há $erros linha(s) com problema: corrija na planilha e confira de novo' : 'Tudo certo. Nada foi gravado ainda.',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: erros > 0 ? Cores.erro : Cores.sucesso)),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 12, children: [
          numero('aparelhos no plano', res['aparelhos_no_plano']),
          numero('atividades', res['atividades']),
          numero('aparelhos novos', res['aparelhos_novos']),
          numero('ambientes novos', res['ambientes_novos']),
          numero('tipos novos', res['tipos_novos']),
        ]),
        if (avisos.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final a in avisos)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, size: 18, color: Cores.alerta),
                const SizedBox(width: 6),
                Expanded(child: Text(a)),
              ]),
            ),
        ],
        if (problemas.isNotEmpty) ...[
          const Divider(height: 24),
          const Text('Linhas da planilha', style: TextStyle(fontWeight: FontWeight.w700)),
          for (final l in problemas.take(200))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 70, child: Text('Linha ${l['n']}', style: const TextStyle(color: Cores.neutro))),
                Expanded(
                  flex: 2,
                  child: Text(_rotuloLinha((l['n'] as num).toInt()), overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  flex: 3,
                  child: Text('${l['mensagem'] ?? ''}',
                      style: TextStyle(color: l['situacao'] == 'erro' ? Cores.erro : Cores.alerta, fontSize: 13)),
                ),
              ]),
            ),
        ],
        const Divider(height: 24),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ativar o plano ao criar'),
          subtitle: const Text('Ativo: os lotes de OS começam a nascer na Fila. Desligado: fica como rascunho.'),
          value: _ativar,
          onChanged: (v) => setState(() => _ativar = v),
        ),
      ]),
      _botoes(
        avancar: _ativar ? 'Criar e ativar' : 'Criar como rascunho',
        aoAvancar: erros > 0 ? null : _criar,
        icone: Icons.check,
      ),
    ]);
  }

  String _rotuloLinha(int n) {
    if (n < 1 || n > _linhas.length) return '';
    final l = _linhas[n - 1];
    return [l['codigo'], l['descricao'] ?? l['tipo'], l['ambiente']].where((x) => x != null).join(' · ');
  }
}

/// Os 3 passos no alto da tela (dá para voltar tocando num passo feito).
class _Passos extends StatelessWidget {
  const _Passos({required this.atual, required this.aoTocar});

  final int atual;
  final void Function(int) aoTocar;

  @override
  Widget build(BuildContext context) {
    const nomes = ['O plano', 'Aparelhos', 'Conferir e criar'];
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (var i = 0; i < nomes.length; i++)
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => aoTocar(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: i == atual ? Cores.indigo700 : (i < atual ? Cores.indigo100 : null),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: i <= atual ? Cores.indigo700 : Cores.linha),
            ),
            child: Text('${i + 1}. ${nomes[i]}',
                style: TextStyle(
                    color: i == atual ? Colors.white : (i < atual ? Cores.indigo700 : Cores.neutro),
                    fontWeight: FontWeight.w600)),
          ),
        ),
    ]);
  }
}
