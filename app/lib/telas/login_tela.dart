import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/estado.dart';

/// Login: e-mail e senha, ou código da empresa + matrícula + PIN.
class LoginTela extends StatefulWidget {
  const LoginTela({super.key, this.reentrar = false});

  /// Entrar de novo com o app já em uso (sessão vencida): mantém os dados.
  final bool reentrar;

  @override
  State<LoginTela> createState() => _LoginTelaState();
}

class _LoginTelaState extends State<LoginTela> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _codigo = TextEditingController();
  final _matricula = TextEditingController();
  final _pin = TextEditingController();
  bool _porPin = false;
  bool _entrando = false;
  String? _erro;

  @override
  void dispose() {
    for (final c in [_email, _senha, _codigo, _matricula, _pin]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Mesma regra da função usuarios-admin: `<matricula>@<codigo>.servia.app`
  String _emailDoPin() {
    final codigo = _codigo.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final matricula = _matricula.text.trim().toLowerCase();
    return '$matricula@$codigo.${Config.dominioEmailApp}';
  }

  Future<void> _entrar() async {
    final email = _porPin ? _emailDoPin() : _email.text.trim();
    final senha = _porPin ? _pin.text : _senha.text;
    if ((_porPin && (_codigo.text.trim().isEmpty || _matricula.text.trim().isEmpty)) ||
        (!_porPin && email.isEmpty) ||
        senha.isEmpty) {
      setState(() => _erro = 'Preencha todos os campos.');
      return;
    }
    setState(() {
      _entrando = true;
      _erro = null;
    });
    try {
      await EstadoApp.instancia.entrar(email: email, senha: senha);
      // Primeiro login: as rotas levam para a tela Hoje sozinhas.
      if (widget.reentrar && mounted) context.go('/hoje');
    } catch (e) {
      if (mounted) setState(() => _erro = e is ErroLogin ? e.mensagem : mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.reentrar ? AppBar(title: const Text('Entrar de novo')) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.handyman_outlined, size: 56, color: Cores.indigo700),
                const SizedBox(height: 8),
                Text('ServPilot',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800, color: Cores.indigo700)),
                const SizedBox(height: 24),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('E-mail')),
                    ButtonSegment(value: true, label: Text('Matrícula e PIN')),
                  ],
                  selected: {_porPin},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _porPin = s.first;
                    _erro = null;
                  }),
                ),
                const SizedBox(height: 16),
                if (!_porPin) ...[
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _senha,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Senha'),
                    onSubmitted: (_) => _entrar(),
                  ),
                ] else ...[
                  TextField(
                    controller: _codigo,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Código da empresa'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _matricula,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Matrícula'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(labelText: 'PIN (6 números)'),
                    onSubmitted: (_) => _entrar(),
                  ),
                ],
                if (_erro != null) ...[
                  const SizedBox(height: 12),
                  Text(_erro!, style: const TextStyle(color: Cores.erro)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _entrando ? null : _entrar,
                    child: _entrando
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('Entrar'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                    widget.reentrar
                        ? 'Use o mesmo usuário: assim as ações que ainda não subiram continuam na fila.'
                        : 'O primeiro acesso precisa de internet. Depois, o app funciona sem sinal.',
                    textAlign: TextAlign.center, style: const TextStyle(color: Cores.neutro, fontSize: 13)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
