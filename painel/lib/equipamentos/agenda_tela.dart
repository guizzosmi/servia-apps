import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/comercial.dart' show reais;
import '../servicos/status.dart';
import '../widgets/margem.dart';
import 'servico.dart';
import 'widgets.dart';

/// Disponibilidade ("quem está livre de tal a tal data") e a agenda em barras (equipamentos × dias).
class EqpAgendaTela extends StatefulWidget {
  const EqpAgendaTela({super.key});

  @override
  State<EqpAgendaTela> createState() => _EqpAgendaTelaState();
}

class _EqpAgendaTelaState extends State<EqpAgendaTela> {
  final _busca = TextEditingController();
  DateTime _inicio = DateTime.now();
  DateTime _fim = DateTime.now().add(const Duration(days: 6));
  int _dias = 21;
  Map<String, dynamic>? _disp;
  Map<String, dynamic>? _agenda;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final b = _busca.text.trim();
      final r = await Future.wait([
        eqp('eqp_disponibilidade', {'inicio': iso(_inicio), 'fim': iso(_fim), if (b.isNotEmpty) 'busca': b}),
        eqp('eqp_agenda', {'inicio': iso(_inicio), 'dias': _dias, if (b.isNotEmpty) 'busca': b}),
      ]);
      if (mounted) {
        setState(() {
          _disp = r[0];
          _agenda = r[1];
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!temEquipamentos()) return const SemAplicacaoEqp();
    final disp = _disp;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(padding: margemDaTela(context), children: [
        Text('Agenda e disponibilidade', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const Text('O banco não deixa reservar o mesmo equipamento duas vezes no mesmo período: o que aparece livre aqui '
            'pode entrar num contrato.', style: TextStyle(color: Cores.neutro)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          CampoDataEqp(rotulo: 'De', data: _inicio, aoMudar: (d) {
            setState(() {
              _inicio = d;
              if (_fim.isBefore(d)) _fim = d;
            });
            _carregar();
          }),
          CampoDataEqp(rotulo: 'Até', data: _fim, aoMudar: (d) {
            setState(() => _fim = d.isBefore(_inicio) ? _inicio : d);
            _carregar();
          }),
          SizedBox(
            width: 260,
            child: TextField(
              controller: _busca,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: 'Tipo, descrição ou código',
                suffixIcon: IconButton(onPressed: _carregar, icon: const Icon(Icons.arrow_forward)),
              ),
              onSubmitted: (_) => _carregar(),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (_carregando) const LinearProgressIndicator(minHeight: 2),
        if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
        if (disp != null) ...[
          SecaoEqp(
            titulo: 'Livres de ${dataBr(disp['inicio'])} a ${dataBr(disp['fim'])} (${listaDe(disp['livres']).length})',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final t in listaDe(disp['por_tipo'])) Chip(label: Text('${t['tipo']}: ${t['livres']} de ${t['total']}')),
              ]),
              for (final e in listaDe(disp['livres']))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${e['codigo']} · ${e['descricao']}'),
                  subtitle: Text([
                    '${e['local'] ?? ''}',
                    if (e['preco_diaria'] != null) '${reais(e['preco_diaria'])}/dia',
                    if (e['aviso'] != null) '${e['aviso']}',
                  ].join(' · '), style: TextStyle(color: e['aviso'] != null ? Cores.alerta : Cores.neutro)),
                  onTap: () => context.go('/equipamentos/ativo/${e['equipamento_id']}'),
                ),
            ]),
          ),
          if (listaDe(disp['ocupados']).isNotEmpty)
            SecaoEqp(
              titulo: 'Ocupados no período (${listaDe(disp['ocupados']).length})',
              child: Column(children: [
                for (final e in listaDe(disp['ocupados']))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${e['codigo']} · ${e['descricao']}'),
                    subtitle: Text(e['reserva'] is Map
                        ? '${(e['reserva'] as Map)['com'] ?? ''} · ${dataBr((e['reserva'] as Map)['inicio'])} a '
                            '${(e['reserva'] as Map)['fim_previsto'] == null ? 'sem data' : dataBr((e['reserva'] as Map)['fim_previsto'])}'
                            '${(e['reserva'] as Map)['locacao'] != null ? ' · ${(e['reserva'] as Map)['locacao']}' : ''}'
                        : '${e['motivo']}'),
                    onTap: () => context.go('/equipamentos/ativo/${e['equipamento_id']}'),
                  ),
              ]),
            ),
        ],
        if (_agenda != null)
          SecaoEqp(
            titulo: 'Agenda',
            acoes: [
              for (final d in const [14, 21, 31, 62])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ChoiceChip(
                    label: Text('$d dias'),
                    selected: _dias == d,
                    onSelected: (_) {
                      setState(() => _dias = d);
                      _carregar();
                    },
                  ),
                ),
            ],
            child: _Grade(agenda: _agenda!, dias: _dias),
          ),
      ]),
    );
  }
}

/// Grade simples: uma linha por equipamento, uma coluna por dia, as reservas e usos coloridos.
class _Grade extends StatelessWidget {
  const _Grade({required this.agenda, required this.dias});

  final Map<String, dynamic> agenda;
  final int dias;

  static const _larguraDia = 26.0;
  static const _larguraNome = 190.0;

  @override
  Widget build(BuildContext context) {
    final inicio = DateTime.tryParse('${agenda['inicio']}') ?? DateTime.now();
    final hoje = '${agenda['hoje']}';
    final linhas = listaDe(agenda['equipamentos']);
    if (linhas.isEmpty) return const Text('Nenhum equipamento.', style: TextStyle(color: Cores.neutro));
    final datas = [for (var i = 0; i < dias; i++) DateTime(inicio.year, inicio.month, inicio.day + i)];

    Color? corDoDia(Map<String, dynamic> e, String dia) {
      for (final b in listaDe(e['barras'])) {
        if ('${b['inicio']}'.compareTo(dia) <= 0 && '${b['fim']}'.compareTo(dia) >= 0) {
          if (b['atrasado'] == true && dia.compareTo('${b['fim_previsto']}') > 0) return Cores.erro;
          return b['situacao'] == 'ativa' ? Cores.andamento : Cores.info;
        }
      }
      return null;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const SizedBox(width: _larguraNome),
            for (final d in datas)
              SizedBox(
                width: _larguraDia,
                child: Text('${d.day}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: iso(d) == hoje ? FontWeight.w800 : FontWeight.w400,
                        color: d.weekday >= 6 ? Cores.neutro : Cores.tinta)),
              ),
          ]),
          for (final e in linhas)
            InkWell(
              onTap: () => context.go('/equipamentos/ativo/${e['equipamento_id']}'),
              child: Row(children: [
                SizedBox(
                  width: _larguraNome,
                  child: Text('${e['codigo']} · ${e['descricao']}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ),
                for (final d in datas)
                  Tooltip(
                    message: _dica(e, iso(d)),
                    child: Container(
                      width: _larguraDia - 2,
                      height: 18,
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: corDoDia(e, iso(d)) ?? Cores.fundo,
                        borderRadius: BorderRadius.circular(3),
                        border: iso(d) == hoje ? Border.all(color: Cores.tinta) : null,
                      ),
                    ),
                  ),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      const Wrap(spacing: 12, children: [
        _Legenda(cor: Cores.info, texto: 'Reservado'),
        _Legenda(cor: Cores.andamento, texto: 'Fora (em uso)'),
        _Legenda(cor: Cores.erro, texto: 'Atrasado'),
      ]),
    ]);
  }

  String _dica(Map<String, dynamic> e, String dia) {
    for (final b in listaDe(e['barras'])) {
      if ('${b['inicio']}'.compareTo(dia) <= 0 && '${b['fim']}'.compareTo(dia) >= 0) {
        return '${b['com'] ?? ''}${b['locacao'] != null ? ' · ${b['locacao']}' : ''} · até '
            '${b['fim_previsto'] == null ? 'sem data' : dataBr(b['fim_previsto'])}';
      }
    }
    return 'Livre em ${dataBr(dia)}';
  }
}

class _Legenda extends StatelessWidget {
  const _Legenda({required this.cor, required this.texto});

  final Color cor;
  final String texto;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(texto, style: const TextStyle(fontSize: 12)),
      ]);
}
