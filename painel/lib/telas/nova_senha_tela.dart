import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../rotas.dart';

/// Senha nova (guia 58): a pessoa chega aqui pelo link de "Esqueci minha
/// senha" que recebeu por e-mail (já entra com o link) e grava outra senha.
class NovaSenhaTela extends StatefulWidget {
  const NovaSenhaTela({super.key});

  @override
  State<NovaSenhaTela> createState() => _NovaSenhaTelaState();
}

class _NovaSenhaTelaState extends State<NovaSenhaTela> {
  final _form = GlobalKey<FormState>();
  final _senha = TextEditingController();
  final _confirma = TextEditingController();
  bool _ver = false;
  bool _gravando = false;
  String? _erro;

  @override
  void dispose() {
    _senha.dispose();
    _confirma.dispose();
    super.dispose();
  }

  Future<void> _gravar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _gravando = true;
      _erro = null;
    });
    try {
      await Sessao.trocarSenha(_senha.text);
      sessaoMudou.senhaTrocada();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Senha nova gravada.')));
      context.go('/');
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _gravando = false);
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
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Center(child: Marca(layout: MarcaLayout.horizontal, altura: 64)),
                    const SizedBox(height: 16),
                    Text('Crie a senha nova', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(Sessao.atual?.email ?? '',
                        textAlign: TextAlign.center, style: const TextStyle(color: Cores.neutro)),
                    const SizedBox(height: 20),
                    TextFormField(
                      key: const ValueKey('senhaNova'),
                      controller: _senha,
                      obscureText: !_ver,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Senha nova',
                        helperText: 'Pelo menos 8 caracteres, com letras e números',
                        suffixIcon: IconButton(
                          tooltip: _ver ? 'Esconder' : 'Mostrar',
                          icon: Icon(_ver ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _ver = !_ver),
                        ),
                      ),
                      validator: (v) {
                        final t = v ?? '';
                        if (t.length < 8) return 'Pelo menos 8 caracteres';
                        if (!RegExp(r'[A-Za-z]').hasMatch(t) || !RegExp(r'\d').hasMatch(t)) {
                          return 'Use letras e números';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirma,
                      obscureText: !_ver,
                      decoration: const InputDecoration(labelText: 'Repita a senha nova'),
                      validator: (v) => v != _senha.text ? 'As senhas não são iguais' : null,
                      onFieldSubmitted: (_) => _gravar(),
                    ),
                    if (_erro != null) ...[
                      const SizedBox(height: 12),
                      Text(_erro!, style: const TextStyle(color: Cores.erro)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _gravando ? null : _gravar,
                      child: _gravando
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Gravar a senha nova'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _gravando
                          ? null
                          : () async {
                              sessaoMudou.senhaTrocada();
                              await Sessao.sair();
                            },
                      child: const Text('Cancelar e sair'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
