import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_parte.dart';
import '../core/banco_local.dart';
import '../core/consultas.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import '../widgets/indicador_sync.dart';

/// Encerrar o dia (guia 30): o líder diz o motivo de cada serviço que não
/// foi feito (volta para a fila), escreve o resumo do dia e encerra.
class EncerrarDiaTela extends StatefulWidget {
  const EncerrarDiaTela({super.key, required this.parteId});

  final String parteId;

  @override
  State<EncerrarDiaTela> createState() => _EncerrarDiaTelaState();
}

class _EncerrarDiaTelaState extends State<EncerrarDiaTela> {
  final _motivos = <String, String>{};
  final _resumo = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _resumo.dispose();
    super.dispose();
  }

  Future<void> _encerrar(Map<String, dynamic> parte, List<String> noServico) async {
    if (_enviando) return;
    setState(() => _enviando = true);
    final banco = EstadoApp.instancia.banco!;
    if (noServico.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ainda tem gente no serviço'),
          content: Text('${noServico.map(banco.nomeColaborador).join(', ')} '
              '${noServico.length == 1 ? 'sai' : 'saem'} do serviço agora. '
              'Se alguém terminou um serviço e o app ainda não sincronizou, peça para sincronizar antes.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Encerrar mesmo assim')),
          ],
        ),
      );
      if (!mounted) return;
      if (ok != true) {
        setState(() => _enviando = false);
        return;
      }
    }
    final abertos = {for (final i in AcoesParte.abertos(widget.parteId)) '${i['id']}'};
    try {
      await AcoesParte.encerrar(
        parte,
        motivos: {
          for (final e in _motivos.entries)
            if (abertos.contains(e.key)) e.key: e.value,
        },
        resumo: _resumo.text,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não deu para encerrar: $e')));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dia encerrado.')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final banco = EstadoApp.instancia.banco!;
    return ListenableBuilder(
      listenable: banco,
      builder: (context, _) {
        final parte = banco.um('partes_diarias', widget.parteId);
        final titulo = AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Encerrar o dia', style: TextStyle(fontWeight: FontWeight.w800)),
            if (parte != null)
              Text('${banco.nomeEquipe(parte['equipe_id'])} · ${dataComDia('${parte['data']}')}',
                  style: const TextStyle(fontSize: 13, color: Cores.neutro)),
          ]),
          actions: const [IndicadorSync()],
        );
        if (parte == null || (!_enviando && !AcoesParte.podeEncerrar(parte))) {
          final texto = parte == null
              ? 'Esta parte não está mais no aparelho.'
              : parte['status'] == 'encerrada'
                  ? 'Este dia já foi encerrado.'
                  : !AcoesParte.souLider(parte)
                      ? 'Só o líder da equipe encerra o dia.'
                      : parte['status'] == 'rascunho'
                          ? 'Esta parte ainda não foi publicada.'
                          : 'Este dia ainda não chegou.';
          return Scaffold(
            appBar: titulo,
            body: Center(child: Text(texto, style: const TextStyle(color: Cores.neutro))),
          );
        }

        final itens = banco.itensDaParte(widget.parteId);
        final abertos = AcoesParte.abertos(widget.parteId);
        final feitos = itens.where((i) => i['status'] == 'concluido').length;
        final naoFeitos = itens.where((i) => i['status'] == 'nao_realizado').length;
        final noServico = AcoesParte.noServico(widget.parteId);
        final faltaMotivo = abertos.where((i) => !_motivos.containsKey('${i['id']}')).length;

        return Scaffold(
          appBar: titulo,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    [
                      '$feitos concluído(s)',
                      if (naoFeitos > 0) '$naoFeitos não realizado(s)',
                      '${abertos.length} sem resultado',
                    ].join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              if (noServico.isNotEmpty)
                Card(
                  color: Cores.alerta.withValues(alpha: .08),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Ainda no serviço: ${noServico.map(banco.nomeColaborador).join(', ')}. '
                        'Ao encerrar, saem do serviço.'),
                  ),
                ),
              if (abertos.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
                  child: Text('O que não foi feito', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text('Volta para a fila com o motivo. Falta de peça ou aguardando orçamento: fica suspenso '
                      'até o escritório liberar.', style: TextStyle(color: Cores.neutro)),
                ),
                if (abertos.length > 1)
                  _Motivos(
                    titulo: 'O mesmo motivo para todos',
                    valor: _motivoComum(abertos),
                    aoEscolher: (m) => setState(() {
                      for (final i in abertos) {
                        _motivos['${i['id']}'] = m;
                      }
                    }),
                  ),
                for (final i in abertos) _cartaoItem(banco, i),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _resumo,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Resumo do dia (opcional)',
                  hintText: 'Como foi o dia? Dá para ditar pelo microfone do teclado.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: faltaMotivo > 0 || _enviando ? null : () => _encerrar(parte, noServico),
                  icon: const Icon(Icons.nightlight_round),
                  label: Text(faltaMotivo > 0 ? 'Escolha o motivo ($faltaMotivo)' : 'Encerrar o dia'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// O motivo, quando todos os serviços abertos estão com o mesmo.
  String? _motivoComum(List<Map<String, dynamic>> abertos) {
    final usados = {for (final i in abertos) _motivos['${i['id']}']};
    return usados.length == 1 ? usados.first : null;
  }

  Widget _cartaoItem(BancoLocal banco, Map<String, dynamic> item) {
    final os = banco.osDo(item) ?? const {};
    final cliente = banco.um('clientes', os['cliente_id']);
    final local = banco.um('locais', os['local_id']);
    final id = '${item['id']}';
    return _Motivos(
      titulo: [codigoOs(os), cliente?['nome'], local?['nome']]
          .where((x) => x != null && '$x'.isNotEmpty)
          .join(' · '),
      subtitulo: statusItem[item['status']]?.texto,
      valor: _motivos[id],
      aoEscolher: (m) => setState(() => _motivos[id] = m),
    );
  }
}

/// Um cartão com os motivos em botões (um toque escolhe).
class _Motivos extends StatelessWidget {
  const _Motivos({required this.titulo, this.subtitulo, required this.valor, required this.aoEscolher});

  final String titulo;
  final String? subtitulo;
  final String? valor;
  final ValueChanged<String> aoEscolher;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (subtitulo != null) Text(subtitulo!, style: const TextStyle(color: Cores.neutro, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final m in motivosNaoRealizado.entries)
                ChoiceChip(
                  label: Text(m.value),
                  selected: valor == m.key,
                  onSelected: (_) => aoEscolher(m.key),
                ),
            ]),
          ]),
        ),
      );
}
