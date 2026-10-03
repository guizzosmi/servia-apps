import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/planos.dart';
import '../servicos/status.dart';

Color _corLote(String? nivel) => niveisPrazo[nivel]?.cor ?? Cores.neutro;

String _dias(int d) => d < 0
    ? 'venceu há ${-d} dia(s)'
    : d == 0
        ? 'vence hoje'
        : 'faltam $d dia(s)';

/// Prazos das preventivas por APARELHO: cards (vencidos, vencem em breve,
/// em dia, feitos no mês), a lista dos aparelhos de cada card e os lotes
/// abertos. Na Início, sem [planoId]; no plano, com ele (lotes de todo o
/// plano, inclusive os encerrados).
class PrazosPreventivas extends StatefulWidget {
  const PrazosPreventivas({super.key, this.planoId, this.titulo = true});

  final String? planoId;
  final bool titulo;

  @override
  State<PrazosPreventivas> createState() => PrazosPreventivasState();
}

class PrazosPreventivasState extends State<PrazosPreventivas> {
  late Future<Map<String, dynamic>> _dados = situacaoPreventivas(planoId: widget.planoId);
  String? _filtro; // nível escolhido nos cards
  bool _todos = false;

  /// Busca de novo (ex.: depois de "Gerar agora" ou de mudar um vencimento).
  void recarregar() => setState(() => _dados = situacaoPreventivas(planoId: widget.planoId));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _dados,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator(minHeight: 2);
        if (snap.hasError) {
          return Text('Prazos das preventivas: ${mensagemDeErro(snap.error!)}', style: const TextStyle(color: Cores.erro));
        }
        final r = snap.data ?? const {};
        final resumo = (r['resumo'] as Map?) ?? const {};
        final gerais = (r['resumo_gerais'] as Map?) ?? const {};
        final unidades = ((r['unidades'] as List?) ?? const []).cast<Map<String, dynamic>>();
        final lotes = ((r['lotes'] as List?) ?? const []).cast<Map<String, dynamic>>();
        final gerou = ((r['gerou'] as Map?)?['os_criadas'] as num?)?.toInt() ?? 0;
        final total = (resumo['total'] as num?)?.toInt() ?? 0;

        // Aparelhos do card escolhido (sem escolha: os vencidos e os que vencem em breve).
        final aparelhos = unidades.where((u) => u['geral'] != true).where((u) {
          if (_filtro == null) return u['nivel'] == 'vencido' || u['nivel'] == 'a_vencer';
          if (_filtro == 'feitos_mes') return u['feito_mes'] == true;
          return u['nivel'] == _filtro;
        }).toList();
        final mostrar = _todos ? aparelhos : aparelhos.take(15).toList();
        final geraisAlerta = [
          for (final u in unidades)
            if (u['geral'] == true && (u['nivel'] == 'vencido' || u['nivel'] == 'a_vencer')) u,
        ];

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.titulo)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Preventivas: $total aparelho(s)${gerou > 0 ? ' · $gerou lote(s) novo(s) gerado(s) agora' : ''}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final n in const ['vencido', 'a_vencer', 'em_dia', 'feitos_mes'])
              _Resumo(
                nivel: n,
                quantos: (resumo[n] as num?)?.toInt() ?? 0,
                escolhido: _filtro == n,
                aoTocar: () => setState(() {
                  _filtro = _filtro == n ? null : n;
                  _todos = false;
                }),
              ),
          ]),
          if (geraisAlerta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Atividades gerais: ${geraisAlerta.map((u) => '${u['descricao']} (${_dias((u['dias'] as num).toInt())})').join('; ')}',
                style: TextStyle(
                    color: geraisAlerta.any((u) => u['nivel'] == 'vencido') ? Cores.erro : const Color(0xFFE07B00)),
              ),
            )
          else if (((gerais['total'] as num?) ?? 0) > 0 && widget.planoId != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Atividades gerais: ${gerais['total']} em dia.', style: const TextStyle(color: Cores.neutro)),
            ),
          const SizedBox(height: 12),
          if (total == 0)
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('Nenhum aparelho em plano ativo. Os planos ativos geram os lotes sozinhos.',
                  style: TextStyle(color: Cores.neutro)),
              if (widget.planoId == null)
                TextButton(onPressed: () => context.go('/planos'), child: const Text('Ver os planos')),
            ])
          else ...[
            Text(
              _filtro == null
                  ? (aparelhos.isEmpty ? 'Nenhum aparelho vencido ou vencendo.' : 'Vencidos e vencendo')
                  : '${niveisAparelho[_filtro]?.texto ?? ''} (${aparelhos.length})',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: _filtro == null && aparelhos.isEmpty ? Cores.sucesso : null),
            ),
            for (final u in mostrar) _LinhaAparelho(u, comPlano: widget.planoId == null),
            if (aparelhos.length > mostrar.length)
              TextButton(
                onPressed: () => setState(() => _todos = true),
                child: Text('Ver todos (${aparelhos.length})'),
              ),
          ],
          if (lotes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(widget.planoId == null ? 'Lotes abertos' : 'Lotes',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final l in lotes) _CartaoLote(l, comPlano: widget.planoId == null),
          ],
        ]);
      },
    );
  }
}

class _Resumo extends StatelessWidget {
  const _Resumo({required this.nivel, required this.quantos, required this.escolhido, required this.aoTocar});

  final String nivel;
  final int quantos;
  final bool escolhido;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final cor = niveisAparelho[nivel]?.cor ?? Cores.neutro;
    // Vencidos e vencendo "acendem" (fundo cheio) quando há algum.
    final aceso = quantos > 0 && (nivel == 'vencido' || nivel == 'a_vencer');
    return SizedBox(
      width: 200,
      child: Card(
        margin: EdgeInsets.zero,
        color: aceso ? cor : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: escolhido ? Cores.tinta : cor.withValues(alpha: .5), width: escolhido ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(
                switch (nivel) {
                  'vencido' => Icons.error,
                  'a_vencer' => Icons.warning_amber_rounded,
                  'em_dia' => Icons.check_circle_outline,
                  _ => Icons.task_alt,
                },
                color: aceso ? Colors.white : cor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$quantos',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: aceso ? Colors.white : cor)),
                  Text(niveisAparelho[nivel]!.texto,
                      style: TextStyle(color: aceso ? Colors.white : Cores.neutro)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Um aparelho: código, ambiente, vencimento e o lote em que está.
class _LinhaAparelho extends StatelessWidget {
  const _LinhaAparelho(this.u, {required this.comPlano});

  final Map<String, dynamic> u;
  final bool comPlano;

  @override
  Widget build(BuildContext context) {
    final nivel = u['nivel'] as String?;
    final cor = niveisAparelho[nivel]?.cor ?? Cores.neutro;
    final dias = (u['dias'] as num?)?.toInt() ?? 0;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.circle, size: 12, color: cor),
      title: Text([u['codigo'], u['descricao']].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
      subtitle: Text([
        if (u['ambiente'] != null) '${u['ambiente']}',
        if (comPlano) '${u['plano_nome']}',
        'vence ${dataBr(u['proximo_vencimento'])} (${_dias(dias)})',
        if (u['ultimo_ciclo_em'] != null) 'último ciclo ${dataBr(u['ultimo_ciclo_em'])}',
      ].join(' · ')),
      trailing: u['lote_os_id'] != null
          ? TextButton(onPressed: () => context.push('/os/${u['lote_os_id']}'), child: Text('${u['lote']}'))
          : null,
    );
  }
}

/// Um lote: saldo de aparelhos, prazo, ritmo e a barra do feito.
class _CartaoLote extends StatelessWidget {
  const _CartaoLote(this.i, {required this.comPlano});

  final Map<String, dynamic> i;
  final bool comPlano;

  @override
  Widget build(BuildContext context) {
    final nivel = i['nivel'] as String?;
    final cor = _corLote(nivel);
    final total = (i['total'] as num?)?.toInt() ?? 0;
    final feitas = (i['feitas'] as num?)?.toInt() ?? 0;
    final pendentes = (i['pendentes'] as num?)?.toInt() ?? 0;
    final vencidas = (i['vencidas'] as num?)?.toInt() ?? 0;
    final ritmo = (i['ritmo_semana'] as num?)?.toInt() ?? 0;
    final dias = (i['dias_restantes'] as num?)?.toInt() ?? 0;
    final naoConf = (i['nao_conformes'] as num?)?.toInt() ?? 0;
    final aberto = nivel != 'encerrado';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cor.withValues(alpha: .6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/os/${i['os_id']}'),
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: cor, width: 6))),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(comPlano ? '${i['plano_nome']}' : 'Lote ${dataBr(i['inicio'])} a ${dataBr(i['prazo'])}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${i['codigo']}', style: const TextStyle(color: Cores.indigo500)),
              _Etiqueta(niveisPrazo[nivel]?.texto ?? '$nivel', cor),
            ]),
            if (comPlano)
              Text('${i['cliente']} · ${i['local']} · até ${dataBr(i['prazo'])}${aberto ? ' (${_dias(dias)})' : ''}',
                  style: const TextStyle(color: Cores.neutro)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : feitas / total,
                minHeight: 8,
                color: cor,
                backgroundColor: Cores.linha,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              [
                '$feitas de $total pronto(s)',
                if (pendentes > 0) 'faltam $pendentes',
                if (vencidas > 0) '$vencidas vencido(s)',
                if (pendentes > 0 && aberto && dias >= 0) 'ritmo: $ritmo por semana',
                if (naoConf > 0) '$naoConf com não conformidade',
              ].join(' · '),
              style: TextStyle(color: nivel == 'vencido' || nivel == 'atencao' ? cor : Cores.tinta, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto, this.cor);
  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: cor.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
        child: Text(texto, style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}
