import 'package:supabase_flutter/supabase_flutter.dart';

import 'acoes_atendimento.dart';
import 'consultas.dart';
import 'estado.dart';
import 'formatos.dart';

/// Assistente com o Claude no app (guia 93): o técnico fala ou escreve
/// ("estou indo na OS 21", "adiciona um capacitor de 35", "quais são minhas
/// OS de amanhã") e a função assistente-claude responde. Só com internet.
/// Junto vão os serviços do técnico que estão no celular (ontem a depois de
/// amanhã): as ações do próprio app (a caminho, estou no serviço, peça no
/// atendimento) voltam para o app executar pelo caminho normal (fila offline).
class Assistente {
  Assistente._();

  static EstadoApp get _estado => EstadoApp.instancia;

  /// Os serviços das partes do técnico, como o assistente precisa.
  static List<Map<String, dynamic>> servicos() {
    final banco = _estado.banco;
    final sync = _estado.sync;
    if (banco == null || sync == null) return const [];
    final hoje = sync.hoje;
    final lista = <Map<String, dynamic>>[];
    for (var d = -1; d <= 2; d++) {
      final data = somarDias(hoje, d);
      for (final parte in banco.partesDoDia(data)) {
        for (final item in banco.itensDaParte('${parte['id']}')) {
          final os = banco.osDo(item) ?? const <String, dynamic>{};
          final cliente = banco.um('clientes', os['cliente_id']) ?? const <String, dynamic>{};
          final local = banco.um('locais', os['local_id']) ?? const <String, dynamic>{};
          final atd = banco.atendimentoDoItem(item['id']);
          lista.add({
            'item_id': item['id'],
            'data': data,
            'os': codigoOs(os),
            'cliente': cliente['nome_fantasia'] ?? cliente['nome'],
            'local': local['nome'],
            'status': item['status'],
            'tipo': os['tipo'],
            'problema': os['problema_relatado'],
            'equipe': banco.nomeEquipe(parte['equipe_id']),
            if (atd != null) 'atendimento': atd['status'],
          });
        }
      }
    }
    return lista.length > 60 ? lista.sublist(0, 60) : lista;
  }

  /// Código da OS em que o técnico está agora (check-in aberto), ou null.
  static String? emQueOsEstou() {
    final banco = _estado.banco;
    if (banco == null || _estado.conta == null) return null;
    final c = AcoesAtendimento.meuCheckin();
    final atd = banco.um('atendimentos', c?['atendimento_id']);
    final os = banco.um('ordens_servico', atd?['os_id']);
    return os == null ? null : codigoOs(os);
  }

  static Future<Map<String, dynamic>> _chamar(Map<String, dynamic> corpo) async {
    final r = await Supabase.instance.client.functions
        .invoke('assistente-claude', body: {'origem': 'app', ...corpo})
        .timeout(const Duration(seconds: 90));
    final d = r.data;
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  /// Um pedido por texto ou por áudio (m4a em base64).
  static Future<Map<String, dynamic>> pedir({
    String? texto,
    String? audioBase64,
    required List<Map<String, String>> mensagens,
  }) {
    final checkin = emQueOsEstou();
    return _chamar({
      'mensagens': mensagens,
      if (texto != null) 'texto': texto,
      if (audioBase64 != null) ...{'audio': audioBase64, 'audio_tipo': 'audio/mp4'},
      'servicos': servicos(),
      if (checkin != null) 'checkin': checkin,
    });
  }

  /// O técnico tocou em Confirmar (ação que desfaz ou encerra).
  static Future<Map<String, dynamic>> confirmar(Map<String, dynamic> pendente) => _chamar({
        'confirmado': {'ferramenta': pendente['ferramenta'], 'argumentos': pendente['argumentos'] ?? const {}},
      });
}
