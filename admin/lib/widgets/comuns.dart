import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../api.dart';

/// Cartão com título (e ações à direita).
class Secao extends StatelessWidget {
  const Secao({super.key, required this.titulo, required this.child, this.acoes = const []});

  final String titulo;
  final Widget child;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(titulo, style: Theme.of(context).textTheme.titleMedium)),
              ...acoes,
            ]),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );
}

/// Subtítulo dentro de uma [Secao] (separa grupos de campos), com a fonte do tema
/// e espaço para o rótulo flutuante do campo de baixo não encostar no texto.
class Subtitulo extends StatelessWidget {
  const Subtitulo(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 16),
        child: Text(texto, style: Theme.of(context).textTheme.titleSmall),
      );
}

class ChipSituacao extends StatelessWidget {
  const ChipSituacao(this.situacao, {super.key});

  final String situacao;

  @override
  Widget build(BuildContext context) {
    final cor = corSituacao(situacao);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: .08),
        border: Border.all(color: cor.withValues(alpha: .5)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(rotulosSituacao[situacao] ?? situacao,
          style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// Número grande com rótulo (resumo).
class Indicador extends StatelessWidget {
  const Indicador({super.key, required this.rotulo, required this.valor, this.cor, this.aoTocar});

  final String rotulo;
  final String valor;
  final Color? cor;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        child: Card(
          child: InkWell(
            onTap: aoTocar,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(valor, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: cor ?? Cores.tinta)),
                const SizedBox(height: 4),
                Text(rotulo, style: const TextStyle(color: Cores.neutro)),
              ]),
            ),
          ),
        ),
      );
}

/// Linha "rótulo: valor".
class Campo extends StatelessWidget {
  const Campo(this.rotulo, this.valor, {super.key});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 190, child: Text(rotulo, style: const TextStyle(color: Cores.neutro))),
          Expanded(child: SelectableText(valor.isEmpty ? '—' : valor)),
        ]),
      );
}

/// Barra de consumo (usado x incluído).
class Medidor extends StatelessWidget {
  const Medidor({super.key, required this.rotulo, required this.usado, required this.incluido});

  final String rotulo;
  final num usado;
  final num incluido;

  @override
  Widget build(BuildContext context) {
    final pct = incluido > 0 ? usado / incluido : 0.0;
    final cor = pct >= 1 ? Cores.erro : (pct >= .8 ? Cores.alerta : Cores.sucesso);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(rotulo)),
          Text('$usado de $incluido (${(pct * 100).round()}%)', style: TextStyle(color: cor, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: pct.clamp(0, 1).toDouble(), color: cor, backgroundColor: Cores.linha, minHeight: 8),
      ]),
    );
  }
}

/// Carrega um futuro e mostra carregando / erro com "Tentar de novo".
class Carregar<T> extends StatelessWidget {
  const Carregar({super.key, required this.futuro, required this.construir, required this.recarregar});

  final Future<T> futuro;
  final Widget Function(T dados) construir;
  final VoidCallback recarregar;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: futuro,
        builder: (context, s) {
          if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (s.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(mensagemDeErro(s.error!), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: recarregar, child: const Text('Tentar de novo')),
              ]),
            );
          }
          return construir(s.data as T);
        },
      );
}

/// Caixa de diálogo com um formulário; devolve true se confirmou.
Future<bool> dialogoForm(BuildContext context,
    {required String titulo, required List<Widget> campos, String confirmar = 'Salvar'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: campos)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(confirmar)),
      ],
    ),
  );
  return ok == true;
}

Widget campoTexto(TextEditingController c, String rotulo, {String? ajuda, TextInputType? teclado}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: teclado,
        decoration: InputDecoration(labelText: rotulo, helperText: ajuda),
      ),
    );
