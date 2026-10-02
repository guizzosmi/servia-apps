import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';


class LoginTela extends StatefulWidget {
  const LoginTela({super.key});

  @override
  State<LoginTela> createState() => _LoginTelaState();
}

class _LoginTelaState extends State<LoginTela> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _entrando = false;
  bool _verSenha = false;
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _entrando = true;
      _erro = null;
    });
    try {
      await Sessao.entrar(_email.text, _senha.text);
      // O roteador percebe a nova sessão e leva para a tela certa.
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _form,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: Marca(layout: MarcaLayout.horizontal, altura: 72)),
                        const SizedBox(height: 8),
                        const SizedBox(height: 4),
                        Text('Painel de gestão',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Cores.neutro)),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _email,
                          decoration: const InputDecoration(labelText: 'E-mail'),
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          validator: (v) => (v == null || !v.contains('@'))
                              ? 'Informe o e-mail'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _senha,
                          obscureText: !_verSenha,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Senha',
                            suffixIcon: IconButton(
                              tooltip: _verSenha ? 'Esconder' : 'Mostrar',
                              icon: Icon(_verSenha
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () =>
                                  setState(() => _verSenha = !_verSenha),
                            ),
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Informe a senha' : null,
                          onFieldSubmitted: (_) => _entrar(),
                        ),
                        if (_erro != null) ...[
                          const SizedBox(height: 12),
                          Text(_erro!, style: const TextStyle(color: Cores.erro)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _entrando ? null : _entrar,
                          child: _entrando
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Entrar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
