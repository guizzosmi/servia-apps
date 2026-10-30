import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/margem.dart';

/// Importar planilha (guia 42): o gestor copia as linhas do Excel (ou do
/// Google Planilhas, ou de um CSV) e cola aqui. "Conferir" simula linha a
/// linha sem gravar; "Importar" grava. O que já existe não muda.
class ImportarTela extends StatefulWidget {
  const ImportarTela({super.key});

  @override
  State<ImportarTela> createState() => _ImportarTelaState();
}

class _Coluna {
  const _Coluna(this.nome, this.ajuda, {this.obrigatoria = false});
  final String nome;
  final String ajuda;
  final bool obrigatoria;
}

const _tipos = {
  'clientes': 'Clientes e locais',
  'equipamentos': 'Equipamentos',
  'produtos': 'Produtos e serviços',
};

const _colunas = <String, List<_Coluna>>{
  'clientes': [
    _Coluna('cliente', 'Nome (razão social ou nome da pessoa)', obrigatoria: true),
    _Coluna('documento', 'CNPJ ou CPF (com ou sem pontos)'),
    _Coluna('fantasia', 'Nome fantasia'),
    _Coluna('telefone', 'Telefone do cliente'),
    _Coluna('email', 'E-mail do cliente'),
    _Coluna('local', 'Nome do local (vazio = Principal). Uma linha por local'),
    _Coluna('endereco', 'Rua ou rodovia'),
    _Coluna('numero', 'Número'),
    _Coluna('complemento', 'Complemento'),
    _Coluna('bairro', 'Bairro'),
    _Coluna('cidade', 'Cidade'),
    _Coluna('uf', 'Estado (PR, SC...)'),
    _Coluna('cep', 'CEP'),
    _Coluna('regiao', 'Região (para o quadro)'),
    _Coluna('acesso', 'Como chegar / acesso'),
    _Coluna('contato', 'Nome de um contato'),
    _Coluna('contato_cargo', 'Cargo do contato'),
    _Coluna('contato_telefone', 'Telefone do contato'),
    _Coluna('contato_email', 'E-mail do contato'),
  ],
  'equipamentos': [
    _Coluna('cliente', 'Nome do cliente, como foi cadastrado', obrigatoria: true),
    _Coluna('documento', 'CNPJ ou CPF do cliente (ajuda quando há nomes parecidos)'),
    _Coluna('local', 'Nome do local (vazio se o cliente tem um só)'),
    _Coluna('ambiente', 'Sala, setor (é criado se não existir)'),
    _Coluna('tipo', 'Tipo de equipamento (é criado se não existir)'),
    _Coluna('codigo', 'Plaqueta ou patrimônio (vazio = código automático)'),
    _Coluna('descricao', 'Descrição (ex.: Split da recepção)'),
    _Coluna('marca', 'Marca'),
    _Coluna('modelo', 'Modelo'),
    _Coluna('serie', 'Número de série'),
    _Coluna('capacidade', 'Capacidade (ex.: 12000)'),
    _Coluna('unidade_capacidade', 'BTU/h, TR ou kW'),
    _Coluna('fluido', 'Fluido refrigerante (ex.: R-410A)'),
    _Coluna('instalacao', 'Data de instalação (dd/mm/aaaa)'),
  ],
  'produtos': [
    _Coluna('tipo', 'Produto ou Serviço (vazio = Produto)'),
    _Coluna('codigo', 'Código interno'),
    _Coluna('descricao', 'Descrição', obrigatoria: true),
    _Coluna('unidade', 'un, kg, m, h, visita... (vazio = un)'),
    _Coluna('preco', 'Preço de venda (ex.: 1.234,56)'),
    _Coluna('custo', 'Preço de custo'),
    _Coluna('garantia_dias', 'Garantia em dias'),
    _Coluna('apelidos', 'Como os técnicos chamam, separado por vírgula'),
  ],
};

/// Outros nomes de coluna que a planilha costuma usar.
const _apelidos = {
  'nome': '#1', 'razao_social': 'cliente', 'cnpj': 'documento', 'cpf': 'documento', 'cpf_cnpj': 'documento',
  'cnpj_cpf': 'documento', 'nome_fantasia': 'fantasia', 'fone': 'telefone', 'celular': 'telefone', 'e_mail': 'email',
  'rua': 'endereco', 'logradouro': 'endereco', 'n': 'numero', 'no': 'numero', 'estado': 'uf', 'instrucoes': 'acesso',
  'telefone_contato': 'contato_telefone', 'email_contato': 'contato_email', 'cargo': 'contato_cargo',
  'plaqueta': 'codigo', 'patrimonio': 'codigo', 'numero_serie': 'serie', 'n_serie': 'serie', 'btus': 'capacidade',
  'btu': 'capacidade', 'gas': 'fluido', 'fluido_refrigerante': 'fluido', 'data_instalacao': 'instalacao',
  'sala': 'ambiente', 'setor': 'ambiente', 'tipo_equipamento': 'tipo', 'preco_venda': 'preco', 'valor': 'preco',
  'preco_custo': 'custo', 'garantia': 'garantia_dias', 'sinonimos': 'apelidos', 'unidade_de_medida': 'unidade',
};

class _ImportarTelaState extends State<ImportarTela> {
  SupabaseClient get _db => Supabase.instance.client;

  String _tipo = 'clientes';
  final _texto = TextEditingController();
  List<Map<String, String>> _linhas = [];
  List<String> _ignoradas = [];
  Map<String, dynamic>? _resultado;
  bool _simulado = false;
  bool _ocupado = false;
  bool _soProblemas = false;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  // ---------------- leitura do que foi colado ----------------

  static String _normal(String s) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñº°';
    const para = 'aaaaaeeeeiiiiooooouuuucnoo';
    var t = s.trim().toLowerCase();
    for (var i = 0; i < de.length; i++) {
      t = t.replaceAll(de[i], para[i]);
    }
    return t.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  }

  /// Divide uma linha respeitando aspas ("Rua A, 10" fica num campo só).
  static List<String> _campos(String linha, String sep) {
    final out = <String>[];
    final atual = StringBuffer();
    var aspas = false;
    for (var i = 0; i < linha.length; i++) {
      final c = linha[i];
      if (c == '"') {
        if (aspas && i + 1 < linha.length && linha[i + 1] == '"') {
          atual.write('"');
          i++;
        } else {
          aspas = !aspas;
        }
      } else if (c == sep && !aspas) {
        out.add(atual.toString());
        atual.clear();
      } else {
        atual.write(c);
      }
    }
    out.add(atual.toString());
    return out.map((x) => x.trim()).toList();
  }

  void _ler() {
    final linhas = _texto.text.replaceAll('\r', '').split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (linhas.length < 2) {
      _avisar('Cole o cabeçalho e pelo menos uma linha.', erro: true);
      return;
    }
    final cab = linhas.first;
    final sep = cab.contains('\t') ? '\t' : (';'.allMatches(cab).length >= ','.allMatches(cab).length ? ';' : ',');
    final conhecidas = {for (final c in _colunas[_tipo]!) c.nome};
    final primeira = _colunas[_tipo]!.firstWhere((c) => c.obrigatoria).nome;
    final nomes = <String?>[];
    final ignoradas = <String>[];
    for (final h in _campos(cab, sep)) {
      var n = _normal(h);
      n = _apelidos[n] == '#1' ? primeira : (_apelidos[n] ?? n);
      if (conhecidas.contains(n)) {
        nomes.add(n);
      } else {
        nomes.add(null);
        if (h.trim().isNotEmpty) ignoradas.add(h.trim());
      }
    }
    if (!nomes.contains(primeira)) {
      _avisar('Falta a coluna "$primeira" no cabeçalho.', erro: true);
      return;
    }
    final dados = <Map<String, String>>[];
    for (final l in linhas.skip(1)) {
      final v = _campos(l, sep);
      final m = <String, String>{};
      for (var i = 0; i < nomes.length && i < v.length; i++) {
        if (nomes[i] != null && v[i].isNotEmpty) m[nomes[i]!] = v[i];
      }
      if (m.isNotEmpty) dados.add(m);
    }
    setState(() {
      _linhas = dados;
      _ignoradas = ignoradas;
      _resultado = null;
      _simulado = false;
    });
  }

  // ---------------- conferir e importar ----------------

  Future<void> _chamar({required bool simular}) async {
    if (!simular) {
      final novos = (_resultado?['resumo'] as Map?)?['novos'] ?? 0;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Importar agora?'),
          content: Text('Vão entrar $novos cadastro(s) novo(s). As linhas com problema ficam de fora '
              'e o que já existia não muda.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Importar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _ocupado = true);
    try {
      final r = await _db.rpc('importar', params: {
        'p': {'tipo': _tipo, 'simular': simular, 'linhas': _linhas},
      });
      if (!mounted) return;
      setState(() {
        _resultado = Map<String, dynamic>.from(r as Map);
        _simulado = simular;
      });
      if (!simular) {
        final res = _resultado!['resumo'] as Map;
        _avisar('Importação feita: ${res['novos']} novo(s), ${res['existentes']} já existia(m), '
            '${res['erros']} com problema.');
      }
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _avisar(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));
  }

  // ---------------- tela ----------------

  @override
  Widget build(BuildContext context) {
    final podeImportar = (Sessao.atual?.tem(Papel.gestor) ?? false);
    final colunas = _colunas[_tipo]!;
    return ListView(padding: margemDaTela(context), children: [
      Text('Importar planilha', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Copie as linhas da planilha, com o cabeçalho, e cole abaixo. Primeiro os clientes, depois os '
          'equipamentos. O que já está cadastrado não muda.', style: TextStyle(color: Cores.neutro)),
      const SizedBox(height: 16),
      SegmentedButton<String>(
        segments: [for (final e in _tipos.entries) ButtonSegment(value: e.key, label: Text(e.value))],
        selected: {_tipo},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() {
          _tipo = s.first;
          _linhas = [];
          _resultado = null;
          _simulado = false;
        }),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Colunas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              TextButton.icon(
                key: const ValueKey('copiarCabecalho'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: colunas.map((c) => c.nome).join('\t')));
                  _avisar('Cabeçalho copiado: cole na primeira linha da planilha.');
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copiar cabeçalho'),
              ),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in colunas)
                Tooltip(
                  message: c.ajuda,
                  child: Chip(
                    label: Text(c.obrigatoria ? '${c.nome} *' : c.nome),
                    backgroundColor: c.obrigatoria ? Cores.indigo100 : null,
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            const Text('* obrigatória. A ordem não importa e as colunas a mais são ignoradas.',
                style: TextStyle(fontSize: 12, color: Cores.neutro)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('textoPlanilha'),
        controller: _texto,
        minLines: 6,
        maxLines: 12,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        decoration: const InputDecoration(
          labelText: 'Cole aqui (com o cabeçalho)',
          alignLabelWithHint: true,
          border: OutlineInputBorder(),
        ),
        onChanged: (_) {
          if (_linhas.isNotEmpty || _resultado != null) {
            setState(() {
              _linhas = [];
              _resultado = null;
            });
          }
        },
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.tonalIcon(
          key: const ValueKey('btnConferir'),
          onPressed: _ocupado || !podeImportar
              ? null
              : () async {
                  _ler();
                  if (_linhas.isNotEmpty) await _chamar(simular: true);
                },
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Conferir'),
        ),
        FilledButton.icon(
          key: const ValueKey('btnImportar'),
          onPressed: _ocupado || !_simulado || _resultado == null ? null : () => _chamar(simular: false),
          icon: const Icon(Icons.upload_outlined),
          label: Text('Importar ${_linhas.length} linha(s)'),
        ),
        if (_ocupado) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        if (!podeImportar) const Text('Só o gestor importa.', style: TextStyle(color: Cores.neutro)),
      ]),
      if (_ignoradas.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Colunas ignoradas: ${_ignoradas.join(', ')}', style: const TextStyle(color: Cores.alerta)),
        ),
      if (_resultado != null) ...[const SizedBox(height: 16), _resultadoCard()],
    ]);
  }

  Widget _resultadoCard() {
    final res = Map<String, dynamic>.from(_resultado!['resumo'] as Map);
    final linhas = ((_resultado!['linhas'] as List?) ?? const []).cast<Map>();
    final mostrar = _soProblemas
        ? linhas.where((l) => l['situacao'] == 'erro' || l['mensagem'] != null).toList()
        : linhas;
    final primeira = _colunas[_tipo]!.firstWhere((c) => c.obrigatoria).nome;
    Widget chip(String s) {
      final (String t, Color c) = switch (s) {
        'novo' => (_simulado ? 'Vai entrar' : 'Entrou', Cores.sucesso),
        'existe' => ('Já existe', Cores.neutro),
        _ => ('Problema', Cores.erro),
      };
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(999), border: Border.all(color: c)),
        child: Text(t, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
      );
    }

    return Card(
      key: const ValueKey('resultado'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_simulado ? 'Conferência (nada foi gravado ainda)' : 'Importação feita',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('${res['novos']} ${_simulado ? 'vão entrar' : 'entraram'} · ${res['existentes']} já existem · '
              '${res['erros']} com problema${(res['avisos'] ?? 0) > 0 ? ' · ${res['avisos']} aviso(s)' : ''}'),
          Row(children: [
            const Spacer(),
            const Text('Só os problemas e avisos'),
            Switch(value: _soProblemas, onChanged: (v) => setState(() => _soProblemas = v)),
          ]),
          const Divider(height: 1),
          for (final l in mostrar.take(300))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 44, child: Text('${l['n']}', style: const TextStyle(color: Cores.neutro))),
                Expanded(
                  flex: 3,
                  child: Text(_linhas.length >= (l['n'] as int) ? (_linhas[(l['n'] as int) - 1][primeira] ?? '') : '',
                      overflow: TextOverflow.ellipsis),
                ),
                SizedBox(width: 110, child: Align(alignment: Alignment.centerLeft, child: chip('${l['situacao']}'))),
                Expanded(
                  flex: 4,
                  child: Text('${l['mensagem'] ?? ''}',
                      style: TextStyle(color: l['situacao'] == 'erro' ? Cores.erro : Cores.alerta, fontSize: 13)),
                ),
              ]),
            ),
          if (mostrar.length > 300)
            Text('E mais ${mostrar.length - 300} linha(s).', style: const TextStyle(color: Cores.neutro)),
        ]),
      ),
    );
  }
}
