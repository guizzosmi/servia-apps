import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/estado.dart';

/// O administrador desconectou este aparelho. Nenhum dado é mostrado;
/// ao tocar em OK, o app apaga tudo e volta para o login.
class RevogadoTela extends StatelessWidget {
  const RevogadoTela({super.key});

  @override
  Widget build(BuildContext context) {
    final pendentes = EstadoApp.instancia.pendentes;
    return _Aviso(
      icone: Icons.phonelink_erase,
      titulo: 'Este aparelho foi desconectado pelo administrador.',
      texto: [
        'Fale com o gestor da sua empresa.',
        if (pendentes > 0)
          '$pendentes ação(ões) feitas neste aparelho não chegaram à plataforma. '
              'Conte ao gestor o que foi feito, para ele lançar no painel.',
      ].join('\n\n'),
      botao: 'OK',
      aoTocar: () => EstadoApp.instancia.sair(),
    );
  }
}

/// O administrador mandou apagar os dados: o app já apagou tudo (banco,
/// fila e fotos) antes de mostrar esta tela.
class ApagadoTela extends StatefulWidget {
  const ApagadoTela({super.key});

  @override
  State<ApagadoTela> createState() => _ApagadoTelaState();
}

class _ApagadoTelaState extends State<ApagadoTela> {
  bool _saindo = false;

  Future<void> _voltar() async {
    setState(() => _saindo = true);
    await EstadoApp.instancia.concluirApagado();
    if (mounted) setState(() => _saindo = false);
  }

  @override
  Widget build(BuildContext context) {
    return _Aviso(
      icone: Icons.delete_forever_outlined,
      titulo: 'Os dados deste app foram apagados por ordem do administrador.',
      texto: 'Serviços, fotos e ações que estavam neste aparelho foram removidos. '
          'Para voltar a usar, o administrador precisa reativar o aparelho.',
      botao: _saindo ? 'Aguarde...' : 'Voltar ao login',
      aoTocar: _saindo ? null : _voltar,
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icone, required this.titulo, required this.texto, required this.botao, this.aoTocar});

  final IconData icone;
  final String titulo;
  final String texto;
  final String botao;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(icone, size: 64, color: Cores.erro),
              const SizedBox(height: 16),
              Text(titulo, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(texto, textAlign: TextAlign.center, style: const TextStyle(color: Cores.neutro)),
              const SizedBox(height: 24),
              FilledButton(onPressed: aoTocar, child: Text(botao)),
            ]),
          ),
        ),
      ),
    );
  }
}
