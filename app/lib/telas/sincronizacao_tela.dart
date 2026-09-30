import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/estado.dart';
import '../core/formatos.dart';
import '../core/sincronizacao.dart';

/// Situação da sincronização: fila de ações, recusas e diagnóstico.
class SincronizacaoTela extends StatelessWidget {
  const SincronizacaoTela({super.key});

  @override
  Widget build(BuildContext context) {
    final estado = EstadoApp.instancia;
    final banco = estado.banco!;
    final sync = estado.sync!;
    return ListenableBuilder(
      listenable: Listenable.merge([banco, sync]),
      builder: (context, _) {
        final pendentes = banco.fila.where((o) => o.situacao == 'pendente').toList();
        final recusadas = banco.recusadas;
        final (String titulo, Color cor) = switch (sync.situacao) {
          SituacaoSync.sincronizando => ('Sincronizando...', Cores.indigo500),
          SituacaoSync.ok => ('Tudo sincronizado', Cores.sucesso),
          SituacaoSync.semConexao => ('Sem conexão: tudo fica salvo no aparelho', Cores.alerta),
          SituacaoSync.precisaEntrar => ('Entre de novo para sincronizar', Cores.alerta),
          SituacaoSync.revogado => ('Aparelho desconectado', Cores.erro),
          SituacaoSync.erro => ('Erro na sincronização', Cores.erro),
          SituacaoSync.parado => ('Aguardando', Cores.neutro),
        };
        final contagens = banco.contagens().entries.toList()..sort((a, b) => a.key.compareTo(b.key));

        return Scaffold(
          appBar: AppBar(title: const Text('Sincronização')),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(titulo, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cor)),
                    if (sync.mensagem != null) ...[
                      const SizedBox(height: 4),
                      Text(sync.mensagem!),
                    ],
                    const SizedBox(height: 8),
                    Text('Última sincronização: ${haQuanto(sync.ultimaSync)}'),
                    Text('${pendentes.length} ação(ões) esperando para subir'),
                    const SizedBox(height: 12),
                    Row(children: [
                      FilledButton.icon(
                        onPressed: sync.situacao == SituacaoSync.sincronizando ? null : sync.sincronizar,
                        icon: const Icon(Icons.sync),
                        label: const Text('Sincronizar agora'),
                      ),
                      const SizedBox(width: 8),
                      if (sync.situacao == SituacaoSync.precisaEntrar)
                        OutlinedButton(onPressed: () => context.push('/reentrar'), child: const Text('Entrar')),
                    ]),
                  ]),
                ),
              ),
              if (recusadas.isNotEmpty) ...[
                const _Titulo('Recusadas pela plataforma'),
                for (final o in recusadas)
                  Card(
                    color: Cores.erro.withValues(alpha: .06),
                    child: ListTile(
                      leading: const Icon(Icons.error_outline, color: Cores.erro),
                      title: Text(nomesOperacoes[o.tipo] ?? o.tipo),
                      subtitle: Text('${dataHoraBr(o.em)}\n${o.erro ?? ''}'),
                      isThreeLine: true,
                      trailing: TextButton(onPressed: () => sync.descartar(o.opId), child: const Text('OK')),
                    ),
                  ),
              ],
              if (pendentes.isNotEmpty) ...[
                const _Titulo('Esperando para subir'),
                for (final o in pendentes)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.schedule, color: Cores.alerta),
                      title: Text(nomesOperacoes[o.tipo] ?? o.tipo),
                      subtitle: Text([
                        dataHoraBr(o.em),
                        if (o.tentativas > 0) '${o.tentativas} tentativa(s): ${o.erro ?? ''}',
                      ].join('\n')),
                    ),
                  ),
              ],
              const _Titulo('Dados neste aparelho'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    for (final e in contagens)
                      Row(children: [
                        Expanded(child: Text(e.key)),
                        Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                    const Divider(),
                    const Row(children: [
                      Expanded(child: Text('Versão do app')),
                      Text(versaoApp, style: TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                    Row(children: [
                      const Expanded(child: Text('Usuário')),
                      Flexible(child: Text(estado.conta?.email ?? '', overflow: TextOverflow.ellipsis)),
                    ]),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(texto.toUpperCase(),
            style: const TextStyle(fontSize: 12, letterSpacing: .6, fontWeight: FontWeight.w700, color: Cores.neutro)),
      );
}
