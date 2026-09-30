import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/estado.dart';
import '../core/sincronizacao.dart';

/// Ícone da barra de cima: situação da sincronização e quantas ações
/// ainda não subiram. Toque para abrir a tela de sincronização.
class IndicadorSync extends StatelessWidget {
  const IndicadorSync({super.key});

  @override
  Widget build(BuildContext context) {
    final estado = EstadoApp.instancia;
    final sync = estado.sync;
    final banco = estado.banco;
    if (sync == null || banco == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([sync, banco]),
      builder: (context, _) {
        final pendentes = banco.pendentes;
        final recusadas = banco.recusadas.length;
        final (IconData icone, Color cor, String dica) = switch (sync.situacao) {
          SituacaoSync.sincronizando => (Icons.sync, Cores.indigo500, 'Sincronizando...'),
          SituacaoSync.ok => (Icons.cloud_done_outlined, Cores.sucesso, 'Sincronizado'),
          SituacaoSync.semConexao => (Icons.cloud_off_outlined, Cores.alerta, 'Sem conexão: tudo fica salvo no aparelho'),
          SituacaoSync.precisaEntrar => (Icons.lock_clock_outlined, Cores.alerta, 'Entre de novo para sincronizar'),
          SituacaoSync.erro || SituacaoSync.revogado => (Icons.error_outline, Cores.erro, 'Erro na sincronização'),
          SituacaoSync.parado => (Icons.cloud_outlined, Cores.neutro, 'Sincronização'),
        };
        return IconButton(
          tooltip: dica,
          onPressed: () => context.push('/sincronizacao'),
          icon: Badge(
            isLabelVisible: pendentes > 0 || recusadas > 0,
            backgroundColor: recusadas > 0 ? Cores.erro : Cores.alerta,
            label: Text('${pendentes + recusadas}'),
            child: Icon(icone, color: cor),
          ),
        );
      },
    );
  }
}
