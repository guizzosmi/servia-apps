import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/funcoes.dart';

/// Inclusão e manutenção de um usuário (só o admin).
/// Toda gravação passa pela função usuarios-admin.
class UsuarioTela extends StatefulWidget {
  const UsuarioTela({super.key, required this.id});

  /// null = usuário novo.
  final String? id;

  @override
  State<UsuarioTela> createState() => _UsuarioTelaState();
}

class _Vinculo {
  _Vinculo({required this.ativo, required this.papeis, required String? matricula})
      : matricula = TextEditingController(text: matricula ?? '');
  bool ativo;
  Set<String> papeis;
  final TextEditingController matricula;
}

class _UsuarioTelaState extends State<UsuarioTela> {
  SupabaseClient get _db => Supabase.instance.client;
  final _form = GlobalKey<FormState>();

  final _nome = TextEditingController();
  final _telefone = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _matricula = TextEditingController();
  final _pin = TextEditingController();

  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;

  bool _porPin = false;
  final Set<String> _papeisNovo = {'tecnico'};
  String? _colaboradorId; // escolhido na tela
  String? _colaboradorAtual; // gravado no banco

  String _codigoConta = '';
  Map<String, dynamic>? _usuario;
  List<Map<String, dynamic>> _empresas = [];
  List<Map<String, dynamic>> _colaboradores = [];
  final Map<String, _Vinculo> _vinculos = {};

  bool get _novo => widget.id == null;
  String? get _empresaAtiva => Sessao.atual?.empresaId;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in [_nome, _telefone, _email, _senha, _matricula, _pin]) {
      c.dispose();
    }
    for (final v in _vinculos.values) {
      v.matricula.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final conta = await _db.from('contas').select('codigo').maybeSingle();
      _codigoConta = (conta?['codigo'] ?? '').toString();

      _empresas = await _db
          .from('empresas')
          .select('id, razao_social, nome_fantasia')
          .isFilter('excluido_em', null)
          .order('razao_social', ascending: true);

      _colaboradores = await _db
          .from('colaboradores')
          .select('id, nome, usuario_id')
          .isFilter('excluido_em', null)
          .eq('ativo', true)
          .order('nome', ascending: true);

      if (!_novo) {
        final u = await _db
            .from('usuarios')
            .select('id, nome, email, telefone, ativo, '
                'usuario_empresas(empresa_id, papeis, matricula, ativo)')
            .eq('id', widget.id!)
            .single();
        _usuario = u;
        _nome.text = (u['nome'] ?? '') as String;
        _telefone.text = (u['telefone'] ?? '') as String;
        for (final v in _vinculos.values) {
          v.matricula.dispose();
        }
        _vinculos.clear();
        for (final e in _empresas) {
          final id = e['id'] as String;
          final v = ((u['usuario_empresas'] as List?) ?? const [])
              .cast<Map<String, dynamic>>()
              .where((x) => x['empresa_id'] == id)
              .firstOrNull;
          _vinculos[id] = _Vinculo(
            ativo: v?['ativo'] == true,
            papeis: {...((v?['papeis'] as List?) ?? const []).map((p) => p.toString())},
            matricula: v?['matricula'] as String?,
          );
        }
        _colaboradorAtual = _colaboradores
            .where((c) => c['usuario_id'] == widget.id)
            .map((c) => c['id'] as String)
            .firstOrNull;
        _colaboradorId = _colaboradorAtual;
      }
    } catch (e) {
      _erro = mensagemDeErro(e);
    }
    if (mounted) setState(() => _carregando = false);
  }

  String _nomeEmpresa(Map<String, dynamic> e) =>
      (e['nome_fantasia'] ?? e['razao_social'] ?? '') as String;

  void _avisar(String texto, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: erro ? Cores.erro : null,
    ));
  }

  /// Executa uma ação da função e recarrega a tela.
  Future<bool> _executar(Map<String, dynamic> corpo, String sucesso) async {
    setState(() => _ocupado = true);
    try {
      await chamarFuncao('usuarios-admin', corpo);
      if (!mounted) return false;
      _avisar(sucesso);
      if (!_novo) await _carregar();
      return true;
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
      return false;
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ---------------- ações ----------------

  Future<void> _criar() async {
    if (!_form.currentState!.validate()) return;
    if (_papeisNovo.isEmpty) {
      _avisar('Escolha pelo menos um papel.', erro: true);
      return;
    }
    final ok = await _executar({
      'acao': 'criar',
      'nome': _nome.text.trim(),
      'telefone': _telefone.text.trim(),
      if (_porPin) ...{
        'matricula': _matricula.text.trim(),
        'pin': _pin.text.trim(),
      } else ...{
        'email': _email.text.trim(),
        'senha': _senha.text,
        if (_matricula.text.trim().isNotEmpty) 'matricula': _matricula.text.trim(),
      },
      'empresa_id': _empresaAtiva,
      'papeis': _papeisNovo.toList(),
      if (_colaboradorId != null) 'colaborador_id': _colaboradorId,
    }, 'Usuário criado.');
    if (ok && mounted) _voltar();
  }

  Future<void> _salvarDados() async {
    if (!_form.currentState!.validate()) return;
    await _executar({
      'acao': 'alterar',
      'usuario_id': widget.id,
      'nome': _nome.text.trim(),
      'telefone': _telefone.text.trim(),
    }, 'Dados salvos.');
  }

  Future<void> _ativar(bool ativo) async {
    if (!ativo) {
      final ok = await _confirmar(
        'Desativar usuário?',
        'Ele deixa de conseguir entrar no painel e no app, em todas as empresas. '
            'O histórico dele é mantido. Para bloquear um celular perdido, use Aparelhos.',
        'Desativar',
      );
      if (!ok || !mounted) return;
    }
    await _executar({'acao': 'alterar', 'usuario_id': widget.id, 'ativo': ativo},
        ativo ? 'Usuário reativado.' : 'Usuário desativado.');
  }

  Future<void> _redefinirSenha() async {
    final pin = ehLoginPorPin(_usuario?['email'] as String?);
    final campo = TextEditingController();
    final nova = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(pin ? 'Novo PIN' : 'Nova senha'),
        content: TextField(
          controller: campo,
          autofocus: true,
          keyboardType: pin ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            labelText: pin ? 'PIN (6 números)' : 'Senha (mínimo 6 caracteres)',
            helperText: 'Passe para a pessoa por um canal seguro.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(campo.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (nova == null || !mounted) return;
    await _executar({'acao': 'senha', 'usuario_id': widget.id, 'senha': nova},
        pin ? 'PIN alterado.' : 'Senha alterada.');
  }

  Future<void> _salvarVinculo(String empresaId) async {
    final v = _vinculos[empresaId]!;
    await _executar({
      'acao': 'vincular',
      'usuario_id': widget.id,
      'empresa_id': empresaId,
      'papeis': v.papeis.toList(),
      'ativo': v.ativo,
      'matricula': v.matricula.text.trim(),
    }, 'Acesso salvo.');
  }

  Future<void> _salvarColaborador() async {
    await _executar({
      'acao': 'colaborador',
      'usuario_id': widget.id,
      'colaborador_id': _colaboradorId,
    }, _colaboradorId == null ? 'Colaborador desligado.' : 'Colaborador ligado.');
  }

  Future<bool> _confirmar(String titulo, String texto, String botao) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Cores.erro),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(botao),
          ),
        ],
      ),
    );
    return r == true;
  }

  void _voltar() {
    if (context.canPop()) {
      context.pop(true);
    } else {
      context.go('/usuarios');
    }
  }

  // ---------------- tela ----------------

  Widget _papeis(Set<String> selecionados, void Function(String, bool) aoMudar,
      {bool habilitado = true}) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final p in rotulosPapeis.entries)
          FilterChip(
            label: Text(p.value),
            selected: selecionados.contains(p.key),
            onSelected: habilitado && !_ocupado ? (s) => aoMudar(p.key, s) : null,
          ),
      ],
    );
  }

  Widget _escolhaColaborador() {
    final opcoes = _colaboradores
        .where((c) => c['usuario_id'] == null || c['id'] == _colaboradorAtual)
        .toList();
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Colaborador (nesta empresa)',
        helperText: 'Liga o login à pessoa que aparece nas equipes, check-ins e comissões',
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: opcoes.any((c) => c['id'] == _colaboradorId) ? _colaboradorId : null,
          isDense: true,
          isExpanded: true,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Nenhum')),
            for (final c in opcoes)
              DropdownMenuItem<String?>(
                value: c['id'] as String,
                child: Text((c['nome'] ?? '') as String),
              ),
          ],
          onChanged: _ocupado ? null : (v) => setState(() => _colaboradorId = v),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_erro!, style: const TextStyle(color: Cores.erro)),
          TextButton(onPressed: _voltar, child: const Text('Voltar')),
        ]),
      );
    }
    final email = (_usuario?['email'] ?? '') as String;
    final ativo = _usuario?['ativo'] == true;
    final ehVoce = widget.id != null && widget.id == Sessao.atual?.usuarioId;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  IconButton(onPressed: _voltar, icon: const Icon(Icons.arrow_back)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _novo ? 'Novo usuário' : (_usuario?['nome'] ?? '') as String,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (!_novo && !ativo)
                    const Chip(label: Text('Desativado')),
                ]),
                const SizedBox(height: 16),

                // ---------- dados ----------
                _Secao(
                  titulo: 'Dados',
                  children: [
                    TextFormField(
                      controller: _nome,
                      decoration: const InputDecoration(labelText: 'Nome *'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Obrigatório' : null,
                    ),
                    TextFormField(
                      controller: _telefone,
                      decoration: const InputDecoration(labelText: 'Telefone'),
                      keyboardType: TextInputType.phone,
                    ),
                    if (!_novo)
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: _ocupado ? null : _salvarDados,
                          child: const Text('Salvar dados'),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // ---------- acesso ----------
                if (_novo)
                  _Secao(
                    titulo: 'Como vai entrar',
                    children: [
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                              value: false,
                              icon: Icon(Icons.email_outlined),
                              label: Text('E-mail e senha')),
                          ButtonSegment(
                              value: true,
                              icon: Icon(Icons.pin_outlined),
                              label: Text('Matrícula e PIN')),
                        ],
                        selected: {_porPin},
                        onSelectionChanged: (s) => setState(() => _porPin = s.first),
                      ),
                      if (!_porPin) ...[
                        TextFormField(
                          controller: _email,
                          decoration: const InputDecoration(labelText: 'E-mail *'),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                  .hasMatch((v ?? '').trim())
                              ? null
                              : 'E-mail inválido',
                        ),
                        TextFormField(
                          controller: _senha,
                          decoration: const InputDecoration(
                              labelText: 'Senha inicial *',
                              helperText: 'Mínimo 6 caracteres. Passe para a pessoa por um canal seguro.'),
                          validator: (v) => (v ?? '').length < 6 ? 'Mínimo 6 caracteres' : null,
                        ),
                        TextFormField(
                          controller: _matricula,
                          decoration: const InputDecoration(
                              labelText: 'Matrícula (opcional)'),
                        ),
                      ] else ...[
                        TextFormField(
                          controller: _matricula,
                          decoration: const InputDecoration(
                              labelText: 'Matrícula *', helperText: 'Letras e números, sem espaço'),
                          validator: (v) => RegExp(r'^[A-Za-z0-9]{1,20}$').hasMatch((v ?? '').trim())
                              ? null
                              : 'Só letras e números',
                          onChanged: (_) => setState(() {}),
                        ),
                        TextFormField(
                          controller: _pin,
                          decoration: const InputDecoration(labelText: 'PIN inicial * (6 números)'),
                          keyboardType: TextInputType.number,
                          validator: (v) =>
                              RegExp(r'^\d{6}$').hasMatch((v ?? '').trim()) ? null : 'Use 6 números',
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Cores.indigo100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'No app, o técnico vai digitar: código da empresa '
                            '"$_codigoConta", matrícula '
                            '"${_matricula.text.trim().isEmpty ? '…' : _matricula.text.trim().toLowerCase()}" e o PIN.',
                          ),
                        ),
                      ],
                    ],
                  )
                else
                  _Secao(
                    titulo: 'Acesso',
                    children: [
                      Text(ehLoginPorPin(email)
                          ? 'Entra no app com código da empresa "$_codigoConta", '
                              'matrícula "${matriculaDoEmail(email)}" e PIN.'
                          : 'Entra com o e-mail $email.'),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _ocupado ? null : _redefinirSenha,
                            icon: const Icon(Icons.key_outlined),
                            label: Text(ehLoginPorPin(email) ? 'Redefinir PIN' : 'Redefinir senha'),
                          ),
                          if (!ehVoce)
                            OutlinedButton.icon(
                              onPressed: _ocupado ? null : () => _ativar(!ativo),
                              style: ativo
                                  ? OutlinedButton.styleFrom(foregroundColor: Cores.erro)
                                  : null,
                              icon: Icon(ativo ? Icons.block : Icons.check_circle_outline),
                              label: Text(ativo ? 'Desativar usuário' : 'Reativar usuário'),
                            ),
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 16),

                // ---------- papéis ----------
                if (_novo)
                  _Secao(
                    titulo: 'Papéis nesta empresa',
                    children: [
                      _papeis(_papeisNovo, (p, s) => setState(() {
                            s ? _papeisNovo.add(p) : _papeisNovo.remove(p);
                          })),
                      const Text(
                        'Admin: tudo, inclusive usuários e aparelhos. Gestor: cadastros e planejamento. '
                        'Financeiro: cobrança e faturas. Técnico: usa o app.',
                        style: TextStyle(color: Cores.neutro),
                      ),
                      _escolhaColaborador(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _ocupado ? null : _criar,
                          icon: const Icon(Icons.check),
                          label: const Text('Criar usuário'),
                        ),
                      ),
                    ],
                  )
                else ...[
                  _Secao(
                    titulo: 'Empresas e papéis',
                    children: [
                      for (final e in _empresas) _linhaEmpresa(e),
                      const Text(
                        'Aparecem só as empresas em que você também tem acesso.',
                        style: TextStyle(color: Cores.neutro, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Secao(
                    titulo: 'Colaborador',
                    children: [
                      _escolhaColaborador(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: _ocupado || _colaboradorId == _colaboradorAtual
                              ? null
                              : _salvarColaborador,
                          child: const Text('Salvar colaborador'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _linhaEmpresa(Map<String, dynamic> e) {
    final id = e['id'] as String;
    final v = _vinculos[id]!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Cores.linha),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(_nomeEmpresa(e),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (id == _empresaAtiva)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Chip(label: Text('atual'), visualDensity: VisualDensity.compact),
              ),
            const Text('Acesso'),
            Switch(
              value: v.ativo,
              onChanged: _ocupado ? null : (s) => setState(() => v.ativo = s),
            ),
          ]),
          if (v.ativo) ...[
            _papeis(v.papeis, (p, s) => setState(() {
                  s ? v.papeis.add(p) : v.papeis.remove(p);
                })),
            const SizedBox(height: 8),
            SizedBox(
              width: 220,
              child: TextField(
                controller: v.matricula,
                decoration: const InputDecoration(labelText: 'Matrícula'),
              ),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _ocupado ? null : () => _salvarVinculo(id),
              child: const Text('Salvar acesso'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.children});

  final String titulo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titulo,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            for (final (i, w) in children.indexed) ...[
              if (i > 0) const SizedBox(height: 12),
              w,
            ],
          ],
        ),
      ),
    );
  }
}
