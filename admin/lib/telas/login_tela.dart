import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

/// Entrada do admin: o mesmo login do painel, mas só passa quem é dono do ServPilot.
class LoginTela extends StatefulWidget {
  const LoginTela({super.key});

  @override
  State<LoginTela> createState() => _LoginTelaState();
}

class _LoginTelaState extends State<LoginTela> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _entrando = false;
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    setState(() {
      _entrando = true;
      _erro = null;
    });
    try {
      await Sessao.entrar(_email.text, _senha.text);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: AutofillGroup(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Center(child: Marca(layout: MarcaLayout.horizontal, altura: 64)),
                      const SizedBox(height: 8),
                      const Text('Administração da plataforma',
                          textAlign: TextAlign.center, style: TextStyle(color: Cores.neutro)),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _email,
                        decoration: const InputDecoration(labelText: 'E-mail'),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _senha,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Senha'),
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _entrar(),
                      ),
                      if (_erro != null) ...[
                        const SizedBox(height: 12),
                        Text(_erro!, style: const TextStyle(color: Cores.erro)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _entrando ? null : _entrar,
                        child: Text(_entrando ? 'Entrando...' : 'Entrar'),
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

class SemAcessoTela extends StatelessWidget {
  const SemAcessoTela({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline, size: 48, color: Cores.neutro),
              SizedBox(height: 12),
              Text('Esta área é só da administração do ServPilot.', textAlign: TextAlign.center),
              SizedBox(height: 4),
              Text('Para usar o sistema da sua empresa, entre em painel.servpilot.com.br.',
                  textAlign: TextAlign.center, style: TextStyle(color: Cores.neutro)),
              SizedBox(height: 20),
              OutlinedButton(onPressed: Sessao.sair, child: Text('Sair')),
            ]),
          ),
        ),
      );
}
