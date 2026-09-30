import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../cadastros/definicoes.dart';
import '../servicos/status.dart';
import '../widgets/status_chip.dart';
import 'modelo.dart';

/// O que a coluna pede para a tela do quadro fazer.
abstract interface class AcoesQuadro {
  bool get podeEditar;
  String nomeColaborador(String? id);
  void arrastando(bool sim);
  Future<void> soltar(Arrasto a, ColunaQuadro destino, Map<String, dynamic>? itemAlvo);

  /// abrir, publicar, encerrar, reabrir, nova_os, incluir_pessoa
  Future<void> acaoEquipe(String acao, ColunaQuadro coluna);

  /// abrir_os, designar, apoio, remover, `status:<novo>`
  Future<void> acaoItem(String acao, Map<String, dynamic> item, ColunaQuadro coluna);

  /// lider, sair
  Future<void> acaoPessoa(String acao, Map<String, dynamic> comp, ColunaQuadro coluna);
}

const larguraColuna = 300.0;

/// Coluna de uma equipe: cabeçalho, composição do dia e serviços em ordem.
class ColunaEquipe extends StatelessWidget {
  const ColunaEquipe({super.key, required this.coluna, required this.acoes, required this.agora});

  final ColunaQuadro coluna;
  final AcoesQuadro acoes;
  final DateTime agora;

  bool _aceita(Arrasto a) {
    if (!acoes.podeEditar || !coluna.aceitaMudancas) return false;
    return switch (a) {
      ArrastoPessoa(:final parteId) => parteId != coluna.parteId,
      ArrastoItem() => true,
      ArrastoFila() => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cor = corDeTexto(coluna.equipe['cor']);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        width: larguraColuna,
        child: DragTarget<Arrasto>(
          onWillAcceptWithDetails: (d) => _aceita(d.data),
          onAcceptWithDetails: (d) => acoes.soltar(d.data, coluna, null),
          builder: (context, candidatos, _) {
            final destacar = candidatos.isNotEmpty;
            final conteudo = Container(
              decoration: BoxDecoration(
                color: destacar ? Cores.indigo100 : (coluna.rascunho ? const Color(0xFFFAFBFD) : Colors.white),
                borderRadius: BorderRadius.circular(14),
                border: coluna.rascunho
                    ? null
                    : Border.all(color: destacar ? Cores.indigo500 : Cores.linha, width: destacar ? 1.5 : 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(height: 5, color: cor),
                _Cabecalho(coluna: coluna, acoes: acoes, cor: cor),
                _Composicao(coluna: coluna, acoes: acoes),
                const Divider(height: 1),
                Expanded(child: _Servicos(coluna: coluna, acoes: acoes, agora: agora)),
                if (coluna.rascunho)
                  Container(
                    color: Cores.fundo,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: const Text('Rascunho: a equipe ainda não vê.',
                        style: TextStyle(fontSize: 12, color: Cores.neutro)),
                  ),
              ]),
            );
            if (!coluna.rascunho) return conteudo;
            return CustomPaint(
              foregroundPainter: BordaTracejada(cor: destacar ? Cores.indigo500 : Cores.neutro),
              child: conteudo,
            );
          },
        ),
      ),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.coluna, required this.acoes, required this.cor});

  final ColunaQuadro coluna;
  final AcoesQuadro acoes;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    final total = coluna.itens.length;
    final feitos = coluna.itens.where((i) => i['status'] == 'concluido').length;
    final opcoes = <PopupMenuEntry<String>>[
      if (coluna.parte == null)
        const PopupMenuItem(value: 'abrir', child: Text('Abrir parte deste dia')),
      if (coluna.rascunho) const PopupMenuItem(value: 'publicar', child: Text('Publicar')),
      if (coluna.aceitaMudancas) ...[
        const PopupMenuItem(value: 'nova_os', child: Text('Nova OS direto nesta equipe')),
        const PopupMenuItem(value: 'incluir_pessoa', child: Text('Incluir pessoa')),
      ],
      if (coluna.status == 'publicada' || coluna.status == 'em_andamento')
        const PopupMenuItem(value: 'encerrar', child: Text('Encerrar o dia')),
      if (coluna.encerrada) const PopupMenuItem(value: 'reabrir', child: Text('Reabrir')),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(coluna.nome,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            Row(children: [
              if (coluna.parte == null)
                const Text('Sem parte', style: TextStyle(fontSize: 12, color: Cores.neutro))
              else
                StatusChip(coluna.status, statusParte, compacto: true),
              const SizedBox(width: 8),
              if (total > 0)
                Flexible(
                  child: Text('$feitos/$total feito(s)',
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Cores.neutro)),
                ),
            ]),
          ]),
        ),
        if (coluna.rascunho && acoes.podeEditar)
          TextButton(onPressed: () => acoes.acaoEquipe('publicar', coluna), child: const Text('Publicar')),
        if (acoes.podeEditar && opcoes.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'Ações da equipe',
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (a) => acoes.acaoEquipe(a, coluna),
            itemBuilder: (_) => opcoes,
          ),
      ]),
    );
  }
}

class _Composicao extends StatelessWidget {
  const _Composicao({required this.coluna, required this.acoes});

  final ColunaQuadro coluna;
  final AcoesQuadro acoes;

  @override
  Widget build(BuildContext context) {
    final presentes = coluna.presentes;
    final sairam = coluna.composicao.where((c) => c['saida_em'] != null && !coluna.encerrada).toList();
    final podeMexer = acoes.podeEditar && coluna.aceitaMudancas && coluna.parte != null;

    // Dia encerrado: só mostra quem trabalhou.
    if (coluna.encerrada) {
      final nomes = {for (final c in coluna.composicao) acoes.nomeColaborador(c['colaborador_id'] as String?)};
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Text(nomes.isEmpty ? 'Ninguém registrado' : 'Trabalharam: ${nomes.join(', ')}',
            style: const TextStyle(fontSize: 12, color: Cores.neutro)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final c in presentes) _pessoa(context, c, podeMexer),
        for (final c in sairam)
          Tooltip(
            message: 'Saiu às ${horaDe(c['saida_em'])}',
            child: Text('${acoes.nomeColaborador(c['colaborador_id'] as String?)} ${horaDe(c['saida_em'])}',
                style: const TextStyle(
                    fontSize: 12, color: Cores.neutro, decoration: TextDecoration.lineThrough)),
          ),
        if (coluna.parte != null && presentes.isEmpty && coluna.composicao.isEmpty)
          const Text('Ninguém na equipe', style: TextStyle(fontSize: 12, color: Cores.alerta)),
        if (acoes.podeEditar && coluna.aceitaMudancas)
          ActionChip(
            avatar: const Icon(Icons.person_add_alt, size: 16),
            label: const Text('Pessoa'),
            visualDensity: VisualDensity.compact,
            onPressed: () => acoes.acaoEquipe('incluir_pessoa', coluna),
          ),
      ]),
    );
  }

  Widget _pessoa(BuildContext context, Map<String, dynamic> c, bool podeMexer) {
    final nome = acoes.nomeColaborador(c['colaborador_id'] as String?);
    final lider = c['papel'] == 'lider';
    final rotulo = entrouDuranteODia(c) ? '+ $nome ${horaDe(c['entrada_em'])}' : nome;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: lider ? Cores.indigo100 : Cores.fundo,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: lider ? Cores.indigo500 : Cores.linha),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (lider) const Padding(
          padding: EdgeInsets.only(right: 3),
          child: Icon(Icons.star, size: 14, color: Cores.indigo500),
        ),
        Text(rotulo, style: TextStyle(fontSize: 12, fontWeight: lider ? FontWeight.w700 : FontWeight.w500)),
      ]),
    );
    if (!podeMexer) return Tooltip(message: lider ? 'Líder' : 'Membro', child: chip);

    final menu = PopupMenuButton<String>(
      tooltip: '$nome: clique para opções, arraste para outra equipe',
      onSelected: (a) => acoes.acaoPessoa(a, c, coluna),
      itemBuilder: (_) => [
        if (!lider) const PopupMenuItem(value: 'lider', child: Text('Tornar líder')),
        const PopupMenuItem(value: 'sair', child: Text('Tirar da equipe')),
      ],
      child: chip,
    );
    return Draggable<Arrasto>(
      data: ArrastoPessoa(colaboradorId: c['colaborador_id'] as String, parteId: coluna.parteId!, nome: nome),
      onDragStarted: () => acoes.arrastando(true),
      onDragEnd: (_) => acoes.arrastando(false),
      feedback: Material(color: Colors.transparent, child: chip),
      childWhenDragging: Opacity(opacity: .35, child: chip),
      child: menu,
    );
  }
}

class _Servicos extends StatelessWidget {
  const _Servicos({required this.coluna, required this.acoes, required this.agora});

  final ColunaQuadro coluna;
  final AcoesQuadro acoes;
  final DateTime agora;

  @override
  Widget build(BuildContext context) {
    if (coluna.parte == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('Esta equipe ainda não tem parte neste dia.',
              textAlign: TextAlign.center, style: TextStyle(color: Cores.neutro)),
          if (acoes.podeEditar) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => acoes.acaoEquipe('abrir', coluna), child: const Text('Abrir parte')),
            const SizedBox(height: 8),
            const Text('Ou arraste um serviço da fila para cá.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Cores.neutro)),
          ],
        ]),
      );
    }
    if (coluna.itens.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Arraste serviços da fila para cá.',
              textAlign: TextAlign.center, style: TextStyle(color: Cores.neutro)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 48),
      itemCount: coluna.itens.length,
      itemBuilder: (_, i) => _ItemComAlvo(
        coluna: coluna,
        item: coluna.itens[i],
        posicao: i + 1,
        acoes: acoes,
        agora: agora,
      ),
    );
  }
}

/// Um serviço da coluna: aceita soltar outro "antes dele" e pode ser arrastado.
class _ItemComAlvo extends StatelessWidget {
  const _ItemComAlvo({
    required this.coluna,
    required this.item,
    required this.posicao,
    required this.acoes,
    required this.agora,
  });

  final ColunaQuadro coluna;
  final Map<String, dynamic> item;
  final int posicao;
  final AcoesQuadro acoes;
  final DateTime agora;

  @override
  Widget build(BuildContext context) {
    final cartao = CartaoItem(coluna: coluna, item: item, posicao: posicao, acoes: acoes, agora: agora);
    final arrastavel = acoes.podeEditar && coluna.aceitaMudancas && item['status'] == 'programado';

    return DragTarget<Arrasto>(
      onWillAcceptWithDetails: (d) {
        if (!acoes.podeEditar || !coluna.aceitaMudancas) return false;
        return switch (d.data) {
          // O próprio item também aceita (soltar no mesmo lugar não muda nada);
          // senão a coluna aceitaria e ele iria para o fim.
          ArrastoItem() => true,
          ArrastoFila() => true,
          ArrastoPessoa() => false,
        };
      },
      onAcceptWithDetails: (d) => acoes.soltar(d.data, coluna, item),
      builder: (context, candidatos, _) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (candidatos.any((c) => c is! ArrastoItem || c.id != item['id']))
            Container(
              height: 4,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(color: Cores.indigo500, borderRadius: BorderRadius.circular(2)),
            ),
          if (!arrastavel)
            cartao
          else
            Draggable<Arrasto>(
              data: ArrastoItem(item),
              onDragStarted: () => acoes.arrastando(true),
              onDragEnd: (_) => acoes.arrastando(false),
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(width: larguraColuna - 24, child: Opacity(opacity: .9, child: cartao)),
              ),
              childWhenDragging: Opacity(opacity: .35, child: cartao),
              child: cartao,
            ),
        ]),
      ),
    );
  }
}

/// Cartão de um serviço programado na parte.
class CartaoItem extends StatelessWidget {
  const CartaoItem({
    super.key,
    required this.coluna,
    required this.item,
    required this.posicao,
    required this.acoes,
    required this.agora,
  });

  final ColunaQuadro coluna;
  final Map<String, dynamic> item;
  final int posicao;
  final AcoesQuadro acoes;
  final DateTime agora;

  @override
  Widget build(BuildContext context) {
    final ag = item['agendamentos'] as Map? ?? const {};
    final os = ag['ordens_servico'] as Map? ?? const {};
    final local = os['locais'] as Map? ?? const {};
    final status = item['status'] as String?;
    final apoio = item['papel_equipe'] == 'apoio';
    final atrasado = itemAtrasado(item, coluna.parte?['data'] as String?, agora);
    final finalizado = status == 'concluido' || status == 'nao_realizado';
    final designados = (item['designados'] as List? ?? const []).cast<String>();
    final quando = [
      tiposAgendamento[ag['tipo']] ?? '',
      janela(ag['janela_inicio'], ag['janela_fim']),
      if (ag['duracao_estimada_min'] != null) '${ag['duracao_estimada_min']} min',
    ].where((x) => x.isNotEmpty).join(' · ');
    final onde = [local['nome'], local['cidade']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');

    final opcoes = <PopupMenuEntry<String>>[
      const PopupMenuItem(value: 'abrir_os', child: Text('Abrir OS')),
      if (acoes.podeEditar && coluna.aceitaMudancas) ...[
        if (!coluna.rascunho && proximosStatus(status).isNotEmpty) ...[
          const PopupMenuDivider(),
          for (final s in proximosStatus(status))
            PopupMenuItem(value: 'status:$s', child: Text(acaoDoStatus(s))),
        ],
        if (itemAberto(item)) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'designar', child: Text('Designar pessoas')),
          if (!apoio) const PopupMenuItem(value: 'apoio', child: Text('Pedir apoio de outra equipe')),
        ],
        if (status == 'programado' || status == 'em_deslocamento')
          const PopupMenuItem(value: 'remover', child: Text('Tirar da parte (volta para a fila)')),
      ],
    ];

    return Material(
      color: finalizado ? Cores.fundo : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: atrasado ? Cores.erro : Cores.linha, width: atrasado ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => acoes.acaoItem('abrir_os', item, coluna),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: Cores.indigo100,
                child: Text('$posicao',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Cores.indigo700)),
              ),
              const SizedBox(width: 6),
              Text('${os['codigo'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Flexible(child: StatusChip(status, statusItem, compacto: true)),
              const Spacer(),
              SizedBox(
                width: 32,
                height: 28,
                child: PopupMenuButton<String>(
                  tooltip: 'Ações do serviço',
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  icon: const Icon(Icons.more_vert),
                  onSelected: (a) => acoes.acaoItem(a, item, coluna),
                  itemBuilder: (_) => opcoes,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text('${(os['clientes'] as Map?)?['nome'] ?? ''}',
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (onde.isNotEmpty)
              Text(onde, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Cores.neutro)),
            if (quando.isNotEmpty)
              Text(quando, style: const TextStyle(fontSize: 12, color: Cores.indigo500)),
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 4, children: [
              if (ag['prioridade'] == 'urgente' || ag['prioridade'] == 'alta')
                StatusChip(ag['prioridade'] as String?, prioridades, compacto: true),
              if (apoio) const _Selo('Apoio', Cores.andamento),
              if (item['incluido_apos_publicacao'] == true) const _Selo('Encaixe', Cores.coral500),
              if (item['alterado_apos_publicacao'] == true) const _Selo('Alterado', Cores.alerta),
              if (atrasado) const _Selo('Atrasado', Cores.erro),
            ]),
            if (designados.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Só: ${designados.map(acoes.nomeColaborador).join(', ')}',
                    style: const TextStyle(fontSize: 12, color: Cores.neutro)),
              ),
            if (status == 'nao_realizado')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'Motivo: ${motivosNaoRealizado[item['resultado_motivo']] ?? item['resultado_motivo'] ?? ''}'
                    '${item['resultado_observacao'] != null ? ' · ${item['resultado_observacao']}' : ''}',
                    style: const TextStyle(fontSize: 12, color: Cores.erro)),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Selo extends StatelessWidget {
  const _Selo(this.texto, this.cor);
  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(texto, style: TextStyle(fontSize: 11, color: cor, fontWeight: FontWeight.w700)),
      );
}
