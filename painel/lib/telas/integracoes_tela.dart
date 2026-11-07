import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/status.dart' show dataHoraBr;
import '../widgets/margem.dart';

/// Guia 53: Integrações (API OData) — só o admin da empresa.
///  - Credenciais (client_id + client_secret) para o ERP, BI ou outro sistema.
///  - Estrutura: código curto da empresa, matriz e os códigos no ERP
///    (Protheus: grupo, empresa, unidade, filial), usados no header TenantId.
///  - O que a API oferece (consultar, incluir, alterar, excluir) por entidade.
class IntegracoesTela extends StatefulWidget {
  const IntegracoesTela({super.key});

  @override
  State<IntegracoesTela> createState() => _IntegracoesTelaState();
}

String get urlApi => '${Config.supabaseUrl}/functions/v1/api';

const _rotulosPapeis = {'gestor': 'Gestor', 'financeiro': 'Financeiro', 'tecnico': 'Técnico'};

class _IntegracoesTelaState extends State<IntegracoesTela> {
  SupabaseClient get _db => Supabase.instance.client;
  Map<String, dynamic>? _cred;
  List<Map<String, dynamic>> _empresas = [];
  List<Map<String, dynamic>> _entidades = [];
  String? _erro;
  bool _carregando = true;
  bool _ocupado = false;

  // Estrutura da empresa atual
  final _codigo = TextEditingController();
  final _grupo = TextEditingController();
  final _empExt = TextEditingController();
  final _unidade = TextEditingController();
  final _filial = TextEditingController();
  String? _matriz;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in [_codigo, _grupo, _empExt, _unidade, _filial]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> _lista(dynamic v) =>
      v is List ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await Future.wait([
        _db.rpc('api_credenciais'),
        _db.rpc('empresa_estrutura'),
        _db.rpc('api_entidades_disponiveis'),
      ]);
      if (!mounted) return;
      final cred = Map<String, dynamic>.from(r[0] as Map);
      final empresas = _lista(r[1]);
      final atual = empresas.firstWhere((e) => e['atual'] == true, orElse: () => <String, dynamic>{});
      final protheus = _lista(atual['externos']).firstWhere((x) => x['sistema'] == 'protheus', orElse: () => {});
      setState(() {
        _cred = cred;
        _empresas = empresas;
        _entidades = _lista(r[2]);
        _codigo.text = '${atual['codigo'] ?? ''}';
        _matriz = atual['matriz_id'] as String?;
        _grupo.text = '${protheus['grupo'] ?? ''}';
        _empExt.text = '${protheus['empresa_externa'] ?? ''}';
        _unidade.text = '${protheus['unidade'] ?? ''}';
        _filial.text = '${protheus['filial'] ?? ''}';
      });
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _avisar(String texto, {bool erro = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));

  Future<void> _copiar(String texto, String oque) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (mounted) _avisar('$oque copiado.');
  }

  // ---------------------------------------------------------------- credenciais
  Future<void> _nova() async {
    final nome = TextEditingController();
    final papeis = <String>{'gestor'};
    final outras = <String>{};
    var leitura = false;
    final atual = Sessao.atual?.empresaId;
    final filiais = _empresas.where((e) => e['id'] != atual).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, definir) => AlertDialog(
          title: const Text('Nova credencial da API'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: nome,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nome (ex.: ERP, Power BI)'),
                ),
                const SizedBox(height: 16),
                const Text('A API age como você, só com os papéis marcados:', style: TextStyle(color: Cores.neutro)),
                Wrap(spacing: 8, children: [
                  for (final p in _rotulosPapeis.entries)
                    FilterChip(
                      label: Text(p.value),
                      selected: papeis.contains(p.key),
                      onSelected: (v) => definir(() => v ? papeis.add(p.key) : papeis.remove(p.key)),
                    ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Só consulta'),
                  subtitle: const Text('Ligado: a credencial só lê (bom para BI e relatórios).'),
                  value: leitura,
                  onChanged: (v) => definir(() => leitura = v),
                ),
                if (filiais.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Também vale para (escolha a empresa em cada chamada pelo header TenantId):',
                      style: TextStyle(color: Cores.neutro)),
                  for (final e in filiais)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: outras.contains(e['id']),
                      onChanged: (v) => definir(() => v == true ? outras.add(e['id'] as String) : outras.remove(e['id'])),
                      title: Text('${e['codigo'] != null ? '${e['codigo']} · ' : ''}${e['nome']}'),
                    ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(papeis.isNotEmpty && nome.text.trim().isNotEmpty),
              child: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _executar(() async {
      final r = await _db.rpc('api_credencial_criar', params: {
        'p': {'nome': nome.text.trim(), 'papeis': papeis.toList(), 'somente_leitura': leitura, 'empresas': outras.toList()},
      });
      if (mounted) await _mostrarSegredo(Map<String, dynamic>.from(r as Map));
    });
  }

  Future<void> _mostrarSegredo(Map<String, dynamic> r) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Copie o segredo agora'),
          content: SizedBox(
            width: 560,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'O client_secret aparece só esta vez. Guarde num cofre de senhas ou na configuração do sistema '
                'que vai usar a API. Se perder, gere outro (o antigo deixa de valer).',
                style: TextStyle(color: Cores.erro),
              ),
              const SizedBox(height: 12),
              _linhaCopiar('client_id', '${r['client_id']}'),
              _linhaCopiar('client_secret', '${r['client_secret']}'),
              _linhaCopiar('URL do token', '$urlApi/token'),
              _linhaCopiar('URL da API (OData)', '$urlApi/odata'),
            ]),
          ),
          actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Já copiei'))],
        ),
      );

  Widget _linhaCopiar(String rotulo, String valor) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(rotulo, style: const TextStyle(color: Cores.neutro)),
        subtitle: SelectableText(valor, style: const TextStyle(fontFamily: 'monospace')),
        trailing: IconButton(tooltip: 'Copiar', icon: const Icon(Icons.copy), onPressed: () => _copiar(valor, rotulo)),
      );

  Future<void> _acao(Map<String, dynamic> c, String acao) async {
    if (acao == 'revogar' || acao == 'novo_segredo') {
      final revogar = acao == 'revogar';
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(revogar ? 'Revogar "${c['nome']}"?' : 'Gerar outro segredo para "${c['nome']}"?'),
          content: Text(revogar
              ? 'O sistema que usa esta credencial para de acessar na hora. Não dá para desfazer: '
                  'se precisar de novo, crie outra credencial.'
              : 'O segredo atual deixa de valer na hora e as sessões abertas caem. '
                  'Atualize o sistema com o novo segredo.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
            FilledButton(
              style: revogar ? FilledButton.styleFrom(backgroundColor: Cores.erro) : null,
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(revogar ? 'Revogar' : 'Gerar outro'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _executar(() async {
      final r = Map<String, dynamic>.from(
          await _db.rpc('api_credencial_acao', params: {'p': {'id': c['id'], 'acao': acao}}) as Map);
      if (!mounted) return;
      if (acao == 'novo_segredo') await _mostrarSegredo(r);
      if (acao == 'chamadas') await _mostrarChamadas(c, _lista(r['itens']));
      if (acao == 'revogar') _avisar('Credencial revogada.');
    }, recarregar: acao != 'chamadas');
  }

  Future<void> _mostrarChamadas(Map<String, dynamic> c, List<Map<String, dynamic>> itens) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Últimas chamadas · ${c['nome']}'),
          content: SizedBox(
            width: 720,
            height: 420,
            // Column dentro de SingleChildScrollView: o AlertDialog mede a largura do conteúdo
            // (IntrinsicWidth), e ListView não sabe responder isso (a tela travava).
            child: itens.isEmpty
                ? const Text('Nenhuma chamada ainda.')
                : SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (final i in itens)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(
                              width: 44,
                              child: Text('${i['status']}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: (i['status'] as num? ?? 0) >= 400 ? Cores.erro : Cores.sucesso)),
                            ),
                            Expanded(
                              child: Text([
                                '${i['metodo']} ${i['caminho']}',
                                [
                                  dataHoraBr(i['criado_em']),
                                  if (i['ms'] != null) '${i['ms']} ms',
                                  if (i['erro'] != null) '${i['erro']}',
                                ].join(' · '),
                              ].join('\n')),
                            ),
                          ]),
                        ),
                    ]),
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fechar'))],
        ),
      );

  Future<void> _executar(Future<void> Function() f, {bool recarregar = true}) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await f();
      if (recarregar && mounted) await _carregar();
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ---------------------------------------------------------------- estrutura
  Future<void> _salvarEstrutura() => _executar(() async {
        await _db.rpc('empresa_estrutura_salvar', params: {
          'p': {
            'codigo': _codigo.text.trim(),
            'matriz_id': _matriz,
            'externos': [
              if ([_grupo, _empExt, _unidade, _filial].every((c) => c.text.trim().isEmpty))
                {'sistema': 'protheus', 'remover': true}
              else
                {
                  'sistema': 'protheus',
                  'grupo': _grupo.text.trim(),
                  'empresa_externa': _empExt.text.trim(),
                  'unidade': _unidade.text.trim(),
                  'filial': _filial.text.trim(),
                },
            ],
          },
        });
        if (mounted) _avisar('Estrutura salva.');
      });

  // ---------------------------------------------------------------- tela
  @override
  Widget build(BuildContext context) {
    final titulo = Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700);
    return SingleChildScrollView(
      padding: margemDaTela(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Integrações (API)', style: titulo)),
          IconButton(tooltip: 'Atualizar', onPressed: _carregando ? null : _carregar, icon: const Icon(Icons.refresh)),
        ]),
        const Text(
          'Ligue o ServPilot ao seu ERP, ao BI ou a outro sistema pela API no padrão OData v4. '
          'Cada sistema usa uma credencial própria; dá para revogar a qualquer momento.',
          style: TextStyle(color: Cores.neutro),
        ),
        const SizedBox(height: 12),
        if (_carregando) const LinearProgressIndicator(minHeight: 2),
        if (_erro != null)
          Card(child: Padding(padding: const EdgeInsets.all(24), child: Text(_erro!, style: const TextStyle(color: Cores.erro)))),
        if (_cred != null) ...[
          _cartaoCredenciais(),
          const SizedBox(height: 16),
          _cartaoEstrutura(),
          const SizedBox(height: 16),
          _cartaoEntidades(),
        ],
      ]),
    );
  }

  Widget _cartao({required String titulo, String? ajuda, List<Widget> acoes = const [], required Widget filho}) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(titulo, style: Theme.of(context).textTheme.titleMedium)),
              ...acoes,
            ]),
            if (ajuda != null) ...[
              const SizedBox(height: 4),
              Text(ajuda, style: const TextStyle(color: Cores.neutro)),
            ],
            const SizedBox(height: 12),
            filho,
          ]),
        ),
      );

  Widget _cartaoCredenciais() {
    final itens = _lista(_cred!['itens']);
    final p = Map<String, dynamic>.from((_cred!['parametros'] as Map?) ?? {});
    return _cartao(
      titulo: 'Credenciais',
      ajuda: 'O sistema pede um token (POST $urlApi/token, grant_type=client_credentials) e usa '
          '"Authorization: Bearer <token>". O token vale ${p['access_minutos'] ?? 15} minutos e é renovado com o '
          'refresh_token (vale ${p['refresh_dias'] ?? 30} dias e muda a cada uso). Limite: '
          '${p['limite_por_minuto'] ?? 120} chamadas por minuto por credencial.',
      acoes: [
        FilledButton.icon(
          onPressed: _ocupado ? null : _nova,
          icon: const Icon(Icons.add),
          label: const Text('Nova credencial'),
        ),
      ],
      filho: itens.isEmpty
          ? const Text('Nenhuma credencial ainda.')
          : Column(children: [
              for (final c in itens) ...[
                _linhaCredencial(c),
                if (c != itens.last) const Divider(height: 1),
              ],
            ]),
    );
  }

  Widget _linhaCredencial(Map<String, dynamic> c) {
    final revogada = c['revogada_em'] != null;
    final papeis = (c['papeis'] as List? ?? []).map((x) => _rotulosPapeis[x] ?? '$x').join(', ');
    final outras = (c['empresas'] as List? ?? []).join(', ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.key, color: revogada ? Cores.neutro : Cores.indigo500),
      title: Text('${c['nome']}${revogada ? ' (revogada)' : ''}${c['somente_leitura'] == true ? ' · só consulta' : ''}',
          style: TextStyle(decoration: revogada ? TextDecoration.lineThrough : null)),
      subtitle: Text([
        'client_id: ${c['id']}  ·  segredo ${c['segredo_inicio']}',
        'Papéis: $papeis${outras.isNotEmpty ? '  ·  também em: $outras' : ''}  ·  criada por ${c['usuario'] ?? '?'} em ${dataHoraBr(c['criado_em'])}',
        'Último uso: ${c['ultimo_uso_em'] == null ? 'nunca' : dataHoraBr(c['ultimo_uso_em'])}  ·  24 h: '
            '${c['chamadas_24h']} chamada(s), ${c['erros_24h']} com erro',
      ].join('\n')),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        enabled: !_ocupado,
        onSelected: (a) => a == 'copiar' ? _copiar('${c['id']}', 'client_id') : _acao(c, a),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'copiar', child: Text('Copiar o client_id')),
          const PopupMenuItem(value: 'chamadas', child: Text('Ver as últimas chamadas')),
          if (!revogada) const PopupMenuItem(value: 'novo_segredo', child: Text('Gerar outro segredo')),
          if (!revogada) const PopupMenuItem(value: 'revogar', child: Text('Revogar')),
        ],
      ),
    );
  }

  Widget _cartaoEstrutura() {
    final atual = Sessao.atual?.empresaId;
    final matrizes = _empresas.where((e) => e['id'] != atual && e['matriz_id'] == null).toList();
    Widget campo(TextEditingController c, String rotulo, {double largura = 160}) => SizedBox(
          width: largura,
          child: TextField(controller: c, decoration: InputDecoration(labelText: rotulo)),
        );
    return _cartao(
      titulo: 'Estrutura e códigos no ERP (esta empresa)',
      ajuda: 'A conta é o grupo de empresas; cada empresa (CNPJ) pode ser matriz ou filial. Os códigos do ERP '
          'deixam o sistema escolher a filial em cada chamada com o header "TenantId: grupo,filial" (ex.: 01,0101).',
      acoes: [
        FilledButton(onPressed: _ocupado ? null : _salvarEstrutura, child: const Text('Salvar')),
      ],
      filho: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
        campo(_codigo, 'Código desta empresa', largura: 190),
        SizedBox(
          width: 320,
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Matriz (se esta for filial)'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
            isDense: true,
            isExpanded: true,
            value: matrizes.any((m) => m['id'] == _matriz) ? _matriz : null,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Esta é a matriz / independente')),
              for (final m in matrizes)
                DropdownMenuItem<String?>(
                    value: m['id'] as String, child: Text('${m['codigo'] != null ? '${m['codigo']} · ' : ''}${m['nome']}')),
            ],
            onChanged: (v) => setState(() => _matriz = v),
              ),
            ),
          ),
        ),
        campo(_grupo, 'Grupo no ERP'),
        campo(_empExt, 'Empresa no ERP'),
        campo(_unidade, 'Unidade no ERP'),
        campo(_filial, 'Filial no ERP'),
      ]),
    );
  }

  Widget _cartaoEntidades() {
    Widget metodo(String rotulo, bool ok) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(rotulo,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ok ? Cores.sucesso : Cores.neutro.withValues(alpha: .5),
                  decoration: ok ? null : TextDecoration.lineThrough)),
        );
    return _cartao(
      titulo: 'O que a API oferece',
      ajuda: 'Consultas com \$filter, \$select, \$orderby, \$top, \$skip, \$count e \$expand. '
          'Modelo completo em $urlApi/odata/\$metadata. Documentação: servpilot.com.br/api',
      acoes: [
        TextButton.icon(
          onPressed: () => _copiar('$urlApi/odata', 'Endereço da API'),
          icon: const Icon(Icons.copy),
          label: const Text('Copiar o endereço'),
        ),
      ],
      filho: Column(children: [
        for (final e in _entidades)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${e['nome']}  ·  ${e['aplicacao']}'),
            subtitle: Text('${e['descricao'] ?? ''}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              metodo('GET', e['consultar'] == true),
              metodo('POST', e['incluir'] == true),
              metodo('PATCH', e['alterar'] == true),
              metodo('DELETE', e['excluir'] == true),
              if (e['acao'] == true) metodo('Ação', true),
            ]),
          ),
      ]),
    );
  }
}
