import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/status.dart';
import 'status_chip.dart';

const statusAtendimento = {
  'em_andamento': Rotulo('Em andamento', Cores.andamento),
  'pausado': Rotulo('Pausado', Cores.alerta),
  'concluido': Rotulo('Concluído', Cores.sucesso),
  'nao_realizado': Rotulo('Não realizado', Cores.erro),
  'cancelado': Rotulo('Cancelado', Cores.neutro),
};

const _camposRelato = {
  'problema_identificado': 'Problema identificado',
  'causa': 'Causa',
  'solucao': 'Solução',
  'observacoes': 'Observações',
};

String _hora(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
  if (d == null) return '';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// "1 h 25 min", "40 min"
String _duracao(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

String _num(Object? v) {
  final n = num.tryParse('${v ?? ''}');
  if (n == null) return '';
  return (n == n.roundToDouble() ? n.toInt().toString() : n.toString()).replaceAll('.', ',');
}

/// Equipamento e depois a ordem da medição no cadastro ("2" antes de "10").
String _ordemMedicao(Map m) =>
    '${(m['equipamentos'] as Map?)?['codigo']}:${'${(m['modelos_medicao'] as Map?)?['ordem'] ?? 0}'.padLeft(5, '0')}';

String _dinheiro(Object? v) => 'R\$ ${(num.tryParse('${v ?? 0}') ?? 0).toStringAsFixed(2).replaceAll('.', ',')}';

/// O que aconteceu no campo, por atendimento: quem esteve lá e quanto
/// tempo, relato, equipamentos identificados, medições, fluido, itens e fotos.
class AtendimentosDaOs extends StatefulWidget {
  const AtendimentosDaOs({super.key, required this.osId});

  final String osId;

  @override
  State<AtendimentosDaOs> createState() => _AtendimentosDaOsState();
}

class _AtendimentosDaOsState extends State<AtendimentosDaOs> {
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _atendimentos = [];
  Map<String, List<Map<String, dynamic>>> _filhos = {};
  Map<String, String> _urls = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final db = Supabase.instance.client;
    try {
      final atds = await db
          .from('atendimentos')
          .select('*, partes_itens(data, partes_diarias(equipes(nome, cor)))')
          .eq('os_id', widget.osId)
          .isFilter('excluido_em', null)
          .order('iniciado_em', ascending: true);
      final ids = atds.map((a) => a['id'] as String).toList();
      final filhos = <String, List<Map<String, dynamic>>>{};
      var urls = <String, String>{};
      if (ids.isNotEmpty) {
        final r = await Future.wait<List<Map<String, dynamic>>>([
          db.from('atendimento_participantes').select('*, colaboradores(nome)').inFilter('atendimento_id', ids)
              .isFilter('excluido_em', null).order('entrada_em', ascending: true),
          db.from('atendimento_equipamentos').select('*, equipamentos(codigo, descricao)').inFilter('atendimento_id', ids)
              .isFilter('excluido_em', null),
          db.from('atendimento_medicoes')
              .select('*, equipamentos(codigo), modelos_medicao(nome, unidade, faixa_min, faixa_max, ordem)')
              .inFilter('atendimento_id', ids).isFilter('excluido_em', null),
          db.from('atendimento_fluidos').select('*, equipamentos(codigo)').inFilter('atendimento_id', ids)
              .isFilter('excluido_em', null),
          db.from('os_itens').select().eq('os_id', widget.osId).isFilter('excluido_em', null)
              .order('criado_em', ascending: true),
          db.from('atendimento_fotos').select().inFilter('atendimento_id', ids).isFilter('excluido_em', null)
              .order('tirada_em', ascending: true),
        ]);
        const nomes = ['participantes', 'equipamentos', 'medicoes', 'fluidos', 'itens', 'fotos'];
        for (var i = 0; i < nomes.length; i++) {
          filhos[nomes[i]] = r[i];
        }
        final caminhos = r[5].map((f) => f['caminho'] as String).toList();
        if (caminhos.isNotEmpty) {
          try {
            final assinadas = await db.storage.from('fotos').createSignedUrlsResult(caminhos, 600);
            urls = {
              for (final a in assinadas)
                if (a is SignedUrlSuccess) a.path: a.signedUrl,
            };
          } catch (_) {
            // Sem as miniaturas, o resto aparece normalmente.
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _atendimentos = atds;
        _filhos = filhos;
        _urls = urls;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  List<Map<String, dynamic>> _de(String tabela, Object? atdId) =>
      (_filhos[tabela] ?? const []).where((r) => r['atendimento_id'] == atdId).toList();

  void _verFoto(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: InkWell(
          onTap: () => Navigator.of(ctx).pop(),
          child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const LinearProgressIndicator(minHeight: 2);
    if (_erro != null) return Text(_erro!, style: const TextStyle(color: Cores.erro));
    if (_atendimentos.isEmpty) {
      return const Text('Nenhum atendimento ainda (começa no check-in do app).', style: TextStyle(color: Cores.neutro));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final a in _atendimentos) _atendimento(a),
    ]);
  }

  Widget _atendimento(Map<String, dynamic> a) {
    final item = a['partes_itens'] as Map? ?? const {};
    final equipe = ((item['partes_diarias'] as Map?)?['equipes'] as Map?) ?? const {};
    final pessoas = _de('participantes', a['id']);
    final agora = DateTime.now();
    var total = Duration.zero;
    for (final p in pessoas) {
      final ent = DateTime.tryParse('${p['entrada_em']}');
      final sai = DateTime.tryParse('${p['saida_em'] ?? ''}') ?? agora;
      if (ent != null) total += sai.difference(ent);
    }
    final medicoes = _de('medicoes', a['id'])
      ..sort((x, y) => _ordemMedicao(x).compareTo(_ordemMedicao(y)));
    final itens = _de('itens', a['id']);
    final fotos = _de('fotos', a['id']);
    final relato = _camposRelato.entries.where((e) => '${a[e.key] ?? ''}'.isNotEmpty).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Cores.linha), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              '${equipe['nome'] ?? 'Equipe'} · ${dataBr(item['data'])} · ${_hora(a['iniciado_em'])}'
              '${a['concluido_em'] != null ? '–${_hora(a['concluido_em'])}' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          StatusChip(a['status'] as String?, statusAtendimento),
        ]),
        if (a['resultado_motivo'] != null)
          Text('Motivo: ${motivosNaoRealizado[a['resultado_motivo']] ?? a['resultado_motivo']}'
              '${a['resultado_observacao'] != null ? ' · ${a['resultado_observacao']}' : ''}',
              style: const TextStyle(color: Cores.erro)),
        const SizedBox(height: 8),
        const _Titulo('Pessoas e horas'),
        for (final p in pessoas)
          Text(
            '${(p['colaboradores'] as Map?)?['nome'] ?? '?'}: ${_hora(p['entrada_em'])}–'
            '${p['saida_em'] == null ? 'agora' : _hora(p['saida_em'])} '
            '(${_duracao((DateTime.tryParse('${p['saida_em'] ?? ''}') ?? agora).difference(DateTime.parse('${p['entrada_em']}')))})'
            '${p['origem'] == 'auto_lider' ? ' · entrou com o líder' : ''}',
          ),
        if (pessoas.isNotEmpty)
          Text('Total: ${_duracao(total)} de trabalho', style: const TextStyle(fontWeight: FontWeight.w700)),
        if (relato.isNotEmpty) ...[
          const _Titulo('Relato'),
          for (final e in relato) Text('${e.value}: ${a[e.key]}'),
          if (a['contato_cliente_nome'] != null) Text('Acompanhou: ${a['contato_cliente_nome']}'),
        ],
        if (_de('equipamentos', a['id']).isNotEmpty) ...[
          const _Titulo('Equipamentos identificados'),
          Text(_de('equipamentos', a['id'])
              .map((e) => '${(e['equipamentos'] as Map?)?['codigo'] ?? ''} (${e['leitura']})')
              .join(', ')),
        ],
        if (medicoes.isNotEmpty) ...[
          const _Titulo('Medições'),
          for (final m in medicoes)
            Builder(builder: (_) {
              final mod = m['modelos_medicao'] as Map? ?? const {};
              final fora = m['fora_faixa'] == true;
              return Text(
                '${(m['equipamentos'] as Map?)?['codigo'] ?? ''} · ${mod['nome'] ?? ''}: '
                '${m['valor_numero'] != null ? _num(m['valor_numero']) : m['valor_texto'] ?? ''} ${m['unidade'] ?? ''}'
                '${fora ? '  (fora da faixa ${_num(mod['faixa_min'])}–${_num(mod['faixa_max'])})' : ''}',
                style: TextStyle(color: fora ? Cores.erro : null, fontWeight: fora ? FontWeight.w700 : null),
              );
            }),
        ],
        if (_de('fluidos', a['id']).isNotEmpty) ...[
          const _Titulo('Fluido refrigerante'),
          for (final f in _de('fluidos', a['id']))
            Text('${(f['equipamentos'] as Map?)?['codigo'] ?? ''} · ${f['fluido']}: '
                '+${_num(f['adicionado_kg'])} kg / recolhido ${_num(f['recolhido_kg'])} kg'),
        ],
        if (itens.isNotEmpty) ...[
          const _Titulo('Itens usados'),
          for (final i in itens)
            Text('${i['descricao']}: ${_num(i['quantidade'])} ${i['unidade'] ?? ''} · ${_dinheiro(i['total'])}'
                '${i['produto_id'] == null ? ' (sem cadastro)' : ''}'),
        ],
        if (fotos.isNotEmpty) ...[
          _Titulo('Fotos (${fotos.length})'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in fotos)
              if (_urls[f['caminho']] case final String url)
                InkWell(
                  onTap: () => _verFoto(url),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(url, width: 96, height: 96, fit: BoxFit.cover),
                  ),
                )
              else
                const SizedBox(
                  width: 96,
                  height: 96,
                  child: ColoredBox(color: Cores.fundo, child: Icon(Icons.image_not_supported_outlined)),
                ),
          ]),
        ],
      ]),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 2),
        child: Text(texto.toUpperCase(),
            style: const TextStyle(fontSize: 11, letterSpacing: .6, fontWeight: FontWeight.w700, color: Cores.neutro)),
      );
}
