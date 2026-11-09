import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/estado.dart';
import '../core/filtro_aparelhos.dart';

export '../core/filtro_aparelhos.dart';

/// Guia 108: a partir de quantos aparelhos a busca aparece nas listas
/// (abaixo disso, a lista cabe na tela e o campo só atrapalha).
const minimoParaBusca = 5;

/// O ambiente de um aparelho (banco do celular).
Map<String, dynamic>? ambienteDoAparelho(Object? ambienteId) => EstadoApp.instancia.banco?.um('ambientes', ambienteId);

/// "AC-12 · Split hi-wall"
String rotuloAparelho(Map e) => [e['codigo'], e['descricao']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');

/// "Câmara fria 1 · Térreo · Springer 42AFCA12M5 · 12.000 BTU/h"
String detalheAparelho(Map e, {bool comAmbiente = true}) {
  final cap = num.tryParse('${e['capacidade_valor'] ?? ''}');
  return [
    if (comAmbiente) nomeDoAmbiente(ambienteDoAparelho(e['ambiente_id'])),
    [e['marca'], e['modelo']].where((x) => x != null && '$x'.isNotEmpty).join(' '),
    if (cap != null) '${_milhar(cap)} ${unidadesCapacidade[e['capacidade_unidade']] ?? ''}'.trim(),
  ].where((x) => x.isNotEmpty).join(' · ');
}

/// 12000 -> '12.000'; 1.5 -> '1,5'
String _milhar(num n) {
  if (n != n.roundToDouble()) return '$n'.replaceAll('.', ',');
  return '${n.toInt()}'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
}

/// O campo de busca de aparelhos, com o botão de ler a etiqueta ao lado e o
/// "x de y" embaixo. Filtra enquanto digita (sem acento, sem maiúscula).
class CampoBuscaAparelhos extends StatelessWidget {
  const CampoBuscaAparelhos({
    super.key,
    required this.controle,
    required this.aoMudar,
    required this.achados,
    required this.total,
    this.aoLerEtiqueta,
    this.autofoco = false,
  });

  final TextEditingController controle;
  final ValueChanged<String> aoMudar;
  final int achados;
  final int total;

  /// O botão da etiqueta (sem isto, ele não aparece).
  final VoidCallback? aoLerEtiqueta;
  final bool autofoco;

  @override
  Widget build(BuildContext context) {
    final buscando = controle.text.trim().isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: controle,
            autofocus: autofoco,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Código, ambiente, marca, capacidade, série',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: buscando
                  ? IconButton(
                      tooltip: 'Limpar',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        controle.clear();
                        aoMudar('');
                      },
                    )
                  : null,
            ),
            onChanged: aoMudar,
          ),
        ),
        if (aoLerEtiqueta != null) ...[
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Achar pela etiqueta',
            onPressed: aoLerEtiqueta,
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Text(
          buscando ? '$achados de $total aparelho(s)' : '$total aparelho(s)',
          style: const TextStyle(color: Cores.neutro, fontSize: 12),
        ),
      ),
    ]);
  }
}

/// Lista de aparelhos com busca (guia 108): o campo fica no topo e a lista
/// vem agrupada por ambiente (com quantos em cada um), na ordem natural do
/// código (AC-2 antes de AC-10). Com menos de [minimo] aparelhos, só a lista,
/// na ordem do código. Não rola sozinha: entra no ListView da tela.
class BuscaAparelhos extends StatefulWidget {
  const BuscaAparelhos({
    super.key,
    required this.aparelhos,
    required this.item,
    this.controle,
    this.aoMudar,
    this.aoLerEtiqueta,
    this.aoAcharPorEtiqueta,
    this.leitor = true,
    this.minimo = minimoParaBusca,
    this.abaixoDoCampo,
    this.textoVazio,
    this.autofoco = false,
  });

  final List<Map<String, dynamic>> aparelhos;

  /// Como cada aparelho aparece (cartão, caixa de marcar...).
  final Widget Function(Map<String, dynamic> aparelho) item;

  /// O texto da busca, quando a tela também precisa dele (senão fica aqui dentro).
  final TextEditingController? controle;
  final ValueChanged<String>? aoMudar;

  /// O botão da etiqueta faz isto (em vez de ler e procurar nesta lista).
  final VoidCallback? aoLerEtiqueta;

  /// Achou nesta lista o aparelho da etiqueta lida. Sem isto, a busca fica
  /// com o código dele.
  final Future<void> Function(Map<String, dynamic> aparelho, String lido)? aoAcharPorEtiqueta;

  /// Mostra o botão da etiqueta ao lado do campo.
  final bool leitor;
  final int minimo;

  /// Entre o campo e a lista (filtros da tela).
  final Widget? abaixoDoCampo;

  /// Lista vazia sem busca (null = nada).
  final String? textoVazio;
  final bool autofoco;

  @override
  State<BuscaAparelhos> createState() => _BuscaAparelhosState();
}

class _BuscaAparelhosState extends State<BuscaAparelhos> {
  TextEditingController? _proprio;

  TextEditingController get _controle => widget.controle ?? (_proprio ??= TextEditingController());

  @override
  void dispose() {
    _proprio?.dispose();
    super.dispose();
  }

  void _mudou(String texto) {
    setState(() {});
    widget.aoMudar?.call(texto);
  }

  Future<void> _lerEtiqueta() async {
    final lido = await context.push<String>('/ler-codigo');
    if (lido == null || !mounted) return;
    final achado = aparelhosDaEtiqueta(widget.aparelhos, lido).firstOrNull;
    if (achado == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Esta etiqueta não é de um aparelho desta lista: $lido')));
      return;
    }
    final acao = widget.aoAcharPorEtiqueta;
    if (acao != null) {
      await acao(achado, lido);
      return;
    }
    _controle.text = '${achado['codigo'] ?? ''}';
    _mudou(_controle.text);
  }

  @override
  Widget build(BuildContext context) {
    final comCampo = widget.aparelhos.length >= widget.minimo;
    final busca = comCampo ? _controle.text.trim() : '';
    final achados = filtrarAparelhos(widget.aparelhos, busca, ambienteDoAparelho);
    final filhos = <Widget>[
      if (comCampo)
        CampoBuscaAparelhos(
          controle: _controle,
          aoMudar: _mudou,
          achados: achados.length,
          total: widget.aparelhos.length,
          autofoco: widget.autofoco,
          aoLerEtiqueta: widget.leitor ? (widget.aoLerEtiqueta ?? _lerEtiqueta) : null,
        ),
      ?widget.abaixoDoCampo,
      if (achados.isEmpty && busca.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text("Nenhum aparelho com '$busca'.", style: const TextStyle(color: Cores.neutro)),
        )
      else if (achados.isEmpty && widget.textoVazio != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(widget.textoVazio!, style: const TextStyle(color: Cores.neutro)),
        ),
    ];
    if (comCampo) {
      for (final g in agruparPorAmbiente(achados, ambienteDoAparelho)) {
        filhos.add(_CabecalhoAmbiente(nome: g.nome, quantos: g.aparelhos.length));
        filhos.addAll(g.aparelhos.map(widget.item));
      }
    } else {
      final ordem = [...achados]..sort((a, b) => compararCodigo(a['codigo'], b['codigo']));
      filhos.addAll(ordem.map(widget.item));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: filhos);
  }
}

class _CabecalhoAmbiente extends StatelessWidget {
  const _CabecalhoAmbiente({required this.nome, required this.quantos});

  final String nome;
  final int quantos;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
        child: Row(children: [
          const Icon(Icons.meeting_room_outlined, size: 18, color: Cores.neutro),
          const SizedBox(width: 6),
          Expanded(
            child: Text(nome.isEmpty ? 'Sem ambiente' : nome, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          Text('$quantos', style: const TextStyle(color: Cores.neutro, fontWeight: FontWeight.w700)),
        ]),
      );
}
