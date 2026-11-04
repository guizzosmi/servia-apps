import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Notas fiscais (guia 81): o que as telas de notas usam em comum.
/// As regras ficam no banco (notas_preparar, notas_lista...) e a conversa
/// com a Focus NFe na função "notas".

const rotuloStatusNota = {
  'rascunho': 'Rascunho',
  'processando': 'Emitindo',
  'autorizada': 'Autorizada',
  'erro': 'Com erro',
  'cancelando': 'Cancelando',
  'cancelada': 'Cancelada',
};

const corStatusNota = {
  'rascunho': Cores.neutro,
  'processando': Cores.info,
  'autorizada': Cores.sucesso,
  'erro': Cores.erro,
  'cancelando': Cores.alerta,
  'cancelada': Cores.neutro,
};

const rotuloTipoNota = {'nfse': 'NFS-e', 'nfe': 'NF-e'};

/// Chama a função "notas" e devolve o JSON. Erros viram FunctionException,
/// que mensagemDeErro() traduz.
Future<Map<String, dynamic>> funcaoNotas(Map<String, dynamic> corpo) async {
  final r = await Supabase.instance.client.functions.invoke('notas', body: corpo);
  final d = r.data;
  return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
}

/// Envia os rascunhos para a Focus. Devolve (enviadas, falhas com a mensagem).
Future<(int, List<String>)> emitirNotas(List<String> ids) async {
  var ok = 0;
  final falhas = <String>[];
  for (var i = 0; i < ids.length; i += 50) {
    final lote = ids.sublist(i, i + 50 > ids.length ? ids.length : i + 50);
    final r = await funcaoNotas({'acao': 'emitir', 'nota_ids': lote});
    for (final x in (r['resultados'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(x as Map);
      if (m['ok'] == true) {
        ok++;
      } else {
        falhas.add('${m['mensagem'] ?? 'Não foi enviada.'}');
      }
    }
  }
  return (ok, falhas);
}

/// Etiqueta colorida do status.
class SeloNota extends StatelessWidget {
  const SeloNota(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final cor = corStatusNota[status] ?? Cores.neutro;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(rotuloStatusNota[status] ?? status,
          style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}
