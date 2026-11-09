import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/comercial.dart';
import '../servicos/status.dart';

/// Linha do tempo do cliente (guia 97): OS, orçamentos, contratos, cobranças, oportunidades e conversas
/// num lugar só, do mais novo para o mais antigo, com um resumo do cliente. É o que um CRM separado
/// não tem: o histórico de serviço.
class LinhaDoTempoCliente extends StatefulWidget {
  const LinhaDoTempoCliente({super.key, this.clienteId, this.oportunidadeId});

  final String? clienteId;
  final String? oportunidadeId;

  @override
  State<LinhaDoTempoCliente> createState() => _LinhaDoTempoClienteState();
}

class _LinhaDoTempoClienteState extends State<LinhaDoTempoCliente> {
  late Future<Map<String, dynamic>> _dados = _carregar();
  bool _tudo = false;

  Future<Map<String, dynamic>> _carregar() async {
    final r = await Supabase.instance.client.rpc('comercial_linha_do_tempo', params: {
      'p': {'cliente_id': widget.clienteId, 'oportunidade_id': widget.oportunidadeId, 'limite': 100}
    });
    return Map<String, dynamic>.from(r as Map);
  }

  static IconData _icone(String tipo) {
    if (tipo.startsWith('os')) return Icons.build_outlined;
    if (tipo.startsWith('orcamento')) return Icons.request_quote_outlined;
    if (tipo == 'contrato') return Icons.handshake_outlined;
    if (tipo == 'cobranca') return Icons.payments_outlined;
    if (tipo.startsWith('oportunidade')) return Icons.filter_alt_outlined;
    if (tipo == 'atividade_whatsapp') return Icons.chat_outlined;
    if (tipo == 'atividade_ligacao') return Icons.call_outlined;
    if (tipo == 'atividade_visita') return Icons.place_outlined;
    return Icons.sticky_note_2_outlined;
  }

  static Color _cor(String tipo) {
    if (tipo == 'oportunidade_ganha' || tipo == 'orcamento_aprovado' || tipo == 'os_concluida') return Cores.sucesso;
    if (tipo == 'oportunidade_perdida' || tipo == 'orcamento_reprovado') return Cores.erro;
    if (tipo.startsWith('os') || tipo.startsWith('orcamento') || tipo == 'contrato' || tipo == 'cobranca') return Cores.andamento;
    return Cores.indigo700;
  }

  Widget _chip(String t) => Chip(label: Text(t, style: const TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _dados,
            builder: (context, s) {
              final d = s.data;
              final resumo = d?['resumo'] is Map ? Map<String, dynamic>.from(d!['resumo'] as Map) : null;
              final eventos = listaDeMapas(d?['eventos']);
              final visiveis = _tudo ? eventos : eventos.take(12).toList();
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Expanded(child: Text('Histórico do cliente', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                  IconButton(
                    tooltip: 'Atualizar',
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () => setState(() => _dados = _carregar()),
                  ),
                ]),
                if (s.connectionState != ConnectionState.done) const LinearProgressIndicator(minHeight: 2),
                if (s.hasError) Text(mensagemDeErro(s.error!), style: const TextStyle(color: Cores.erro)),
                if (resumo != null)
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    _chip('${resumo['os_total']} OS${(resumo['os_abertas'] ?? 0) != 0 ? ' (${resumo['os_abertas']} abertas)' : ''}'),
                    if ((num.tryParse('${resumo['contratos_ativos']}') ?? 0) > 0)
                      _chip('${resumo['contratos_ativos']} contrato(s) · ${reais(resumo['mensal_contratos'])}/mês'),
                    _chip('Cobrado em 12 meses: ${reais(resumo['cobrado_12_meses'])}'),
                    if (resumo['ultima_os_em'] != null) _chip('Última OS: ${dataBr(resumo['ultima_os_em'])}'),
                  ]),
                if (d != null && eventos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Nada ainda além desta oportunidade.', style: TextStyle(color: Cores.neutro)),
                  ),
                for (final e in visiveis)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_icone('${e['tipo']}'), color: _cor('${e['tipo']}'), size: 20),
                    title: Text('${e['titulo']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      dataHoraBr(e['em']),
                      if (e['codigo'] != null) '${e['codigo']}',
                      if ((num.tryParse('${e['valor'] ?? ''}') ?? 0) > 0) reais(e['valor']),
                      if (e['detalhe'] != null && '${e['detalhe']}'.trim().isNotEmpty) '${e['detalhe']}',
                    ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                if (eventos.length > visiveis.length)
                  TextButton(onPressed: () => setState(() => _tudo = true), child: Text('Ver tudo (${eventos.length})')),
              ]);
            },
          ),
        ),
      );
}
