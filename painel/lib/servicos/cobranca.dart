import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/itens_os.dart' show dinheiro, numeroBr;
import 'status.dart';

/// A cobrar (guia 31): as chamadas do banco e o texto para a nota fiscal.
/// A nota continua no sistema de notas da empresa (ex.: MarketUP).

Future<Map<String, dynamic>> _rpc(String funcao, Map<String, dynamic> p) async {
  final r = await Supabase.instance.client.rpc(funcao, params: {'p': p});
  return r is Map<String, dynamic> ? r : <String, dynamic>{};
}

/// OS concluídas sem cobrança e mensalidades (e, com [resolvidas], o
/// histórico do período).
Future<Map<String, dynamic>> listaACobrar({bool resolvidas = false, String? de, String? ate}) => _rpc('cobranca_lista', {
      if (resolvidas) 'resolvidas': true,
      if (de != null) 'de': de,
      if (ate != null) 'ate': ate,
    });

Future<Map<String, dynamic>> registrarCobranca(Map<String, dynamic> p) => _rpc('cobranca_registrar', p);
Future<Map<String, dynamic>> naoCobrar(List<String> osIds, String motivo) =>
    _rpc('cobranca_nao_cobrar', {'os_ids': osIds, 'motivo': motivo});
Future<Map<String, dynamic>> desfazerCobranca({String? cobrancaId, String? osId}) => _rpc('cobranca_desfazer', {
      if (cobrancaId != null) 'cobranca_id': cobrancaId,
      if (osId != null) 'os_id': osId,
    });

/// O laudo final (ou, sem ele, o problema relatado).
String oQueFoiFeito(Map o) => [o['laudo_final'], o['problema_relatado']]
    .map((x) => '${x ?? ''}'.trim())
    .firstWhere((x) => x.isNotEmpty, orElse: () => '');

/// "1.234,56" ou "1234.56" -> 1234.56 (vazio ou inválido = null).
num? lerValor(String texto) {
  var t = texto.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
  return num.tryParse(t);
}

/// Data local (aaaa-mm-dd ou data e hora ISO) -> dd/mm/aaaa.
String diaBr(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  if (d == null) return '';
  return dataBr(dataIso(d.isUtc ? d.toLocal() : d));
}

/// O texto para colar na nota: cada OS com o que foi feito e os itens, a
/// mensalidade (com o excedente) e o total.
String textoParaNota({
  required List<Map<String, dynamic>> os,
  required List<Map<String, dynamic>> contratos,
}) {
  final linhas = <String>['Serviços prestados de manutenção em refrigeração e climatização:'];
  num total = 0;
  for (final o in os) {
    final onde = [o['local'], o['cidade']].where((x) => x != null && '$x'.isNotEmpty).join(' - ');
    final oque = oQueFoiFeito(o);
    linhas.add('');
    linhas.add('${o['codigo']} (${diaBr(o['concluida_em'])})${onde.isEmpty ? '' : ' - $onde'}'
        '${oque.isEmpty ? '' : ': $oque'}');
    for (final i in ((o['itens'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      final qtd = [numeroBr(i['quantidade']), '${i['unidade'] ?? ''}'].where((x) => x.isNotEmpty).join(' ');
      linhas.add('  ${i['descricao']} - $qtd - ${dinheiro(i['total'])}');
    }
    total += num.tryParse('${o['valor_total'] ?? 0}') ?? 0;
  }
  for (final c in contratos) {
    linhas.add('');
    linhas.add('Mensalidade do contrato ${c['codigo']} (${diaBr(c['competencia_ini'])} a ${diaBr(c['competencia_fim'])}): '
        '${dinheiro(c['valor_mensal'])}');
    final exc = num.tryParse('${c['excedente_valor'] ?? 0}') ?? 0;
    if (exc > 0) {
      linhas.add('Excedente da franquia: ${numeroBr(c['excedente_visitas'])} visita(s), '
          '${numeroBr(c['excedente_horas'])} h - ${dinheiro(exc)}');
    }
    total += num.tryParse('${c['valor'] ?? 0}') ?? 0;
  }
  linhas.add('');
  linhas.add('Total: ${dinheiro(total)}');
  return linhas.join('\n');
}
