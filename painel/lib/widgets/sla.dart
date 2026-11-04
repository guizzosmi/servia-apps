import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/status.dart';

/// SLA por contrato (guia 70): o prazo para chegar no cliente numa corretiva.

/// Na tela do contrato: as horas do SLA (e a da urgente).
class SlaDoContrato extends StatefulWidget {
  const SlaDoContrato({super.key, required this.contratoId, this.horas, this.horasUrgente, this.habilitado = true});

  final String contratoId;
  final Object? horas;
  final Object? horasUrgente;
  final bool habilitado;

  @override
  State<SlaDoContrato> createState() => _SlaDoContratoState();
}

class _SlaDoContratoState extends State<SlaDoContrato> {
  late final _h = TextEditingController(text: widget.horas == null ? '' : '${widget.horas}');
  late final _u = TextEditingController(text: widget.horasUrgente == null ? '' : '${widget.horasUrgente}');
  bool _salvando = false;

  @override
  void dispose() {
    _h.dispose();
    _u.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      await Supabase.instance.client.rpc('contrato_sla', params: {
        'p': {
          'contrato_id': widget.contratoId,
          'sla_horas': int.tryParse(_h.text.trim()),
          'sla_urgente_horas': int.tryParse(_u.text.trim()),
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SLA salvo: vale para as corretivas em aberto e as novas.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagemDeErro(e)), backgroundColor: Cores.erro));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Prazo para chegar no cliente numa corretiva, contado da abertura da OS até o primeiro check-in. '
          'Vazio = sem SLA.', style: TextStyle(color: Cores.neutro)),
      const SizedBox(height: 8),
      Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 180,
          child: TextField(
            controller: _h,
            enabled: widget.habilitado,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'SLA', suffixText: 'horas'),
          ),
        ),
        SizedBox(
          width: 180,
          child: TextField(
            controller: _u,
            enabled: widget.habilitado,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Urgente', suffixText: 'horas'),
          ),
        ),
        if (widget.habilitado)
          FilledButton.tonal(onPressed: _salvando ? null : _salvar, child: const Text('Salvar o SLA')),
      ]),
    ]);
  }
}

/// Na Início: as OS com o SLA vencido ou vencendo (4 h).
class AlertasSla extends StatefulWidget {
  const AlertasSla({super.key});

  @override
  State<AlertasSla> createState() => _AlertasSlaState();
}

class _AlertasSlaState extends State<AlertasSla> {
  List<Map<String, dynamic>> _abertas = [];

  @override
  void initState() {
    super.initState();
    if (!(Sessao.atual?.tem(Papel.gestor) ?? false)) return;
    Supabase.instance.client.rpc('sla_situacao', params: {'p': {}}).then((r) {
      if (mounted) setState(() => _abertas = List<Map<String, dynamic>>.from(((r as Map)['abertas'] as List?) ?? const []));
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_abertas.isEmpty) return const SizedBox.shrink();
    final vencidas = _abertas.where((a) => a['situacao'] == 'vencido').length;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        color: vencidas > 0 ? const Color(0xFFFDECEA) : const Color(0xFFFFF4E5),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.timer_outlined, color: vencidas > 0 ? Cores.erro : Cores.alerta),
              const SizedBox(width: 8),
              Text(
                vencidas > 0
                    ? 'SLA: $vencidas vencido(s)${_abertas.length > vencidas ? ', ${_abertas.length - vencidas} vencendo' : ''}'
                    : 'SLA: ${_abertas.length} vencendo nas próximas 4 h',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ]),
            const SizedBox(height: 4),
            for (final a in _abertas.take(6))
              InkWell(
                onTap: () => context.push('/os/${a['os_id']}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('${a['codigo']} · ${a['cliente']} · prazo ${dataHoraBr(a['prazo'])}'
                      '${a['situacao'] == 'vencido' ? ' (vencido)' : ''}'),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Na OS: o prazo do SLA (ou se foi cumprido).
Widget chipSla(Map os) {
  final prazo = DateTime.tryParse('${os['sla_prazo']}');
  final atendido = DateTime.tryParse('${os['sla_atendido_em'] ?? ''}');
  final String texto;
  final Color cor;
  if (atendido != null && prazo != null) {
    final ok = !atendido.isAfter(prazo);
    texto = ok ? 'SLA cumprido' : 'SLA estourado';
    cor = ok ? Cores.sucesso : Cores.erro;
  } else {
    final vencido = prazo != null && prazo.isBefore(DateTime.now());
    texto = '${vencido ? 'SLA vencido' : 'SLA até'} ${dataHoraBr(os['sla_prazo'])}';
    cor = vencido ? Cores.erro : Cores.alerta;
  }
  return Chip(
    avatar: Icon(Icons.timer_outlined, size: 16, color: cor),
    label: Text(texto, style: TextStyle(color: cor, fontWeight: FontWeight.w600)),
    visualDensity: VisualDensity.compact,
  );
}
