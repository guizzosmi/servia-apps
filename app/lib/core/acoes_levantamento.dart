import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'acoes_atendimento.dart';
import 'acoes_cadastro.dart';
import 'banco_local.dart';
import 'estado.dart';
import 'sincronizacao.dart';

/// Levantamento do local (guia 57): o técnico percorre o cliente e cadastra
/// os ambientes (com andar, área e ocupantes) e os aparelhos, sem OS. Tudo
/// entra na fila e sobe na sincronização (funciona sem internet); só a
/// leitura da plaqueta pela IA precisa de internet.
class AcoesLevantamento {
  AcoesLevantamento._();

  static EstadoApp get _estado => EstadoApp.instancia;
  static BancoLocal get _banco => _estado.banco!;
  static Sincronizador get _sync => _estado.sync!;

  static bool _vivo(Map<String, dynamic> r) => r['excluido_em'] == null && r['ativo'] != false;

  /// Aparelhos ativos do local (de um ambiente; '' = sem ambiente).
  static List<Map<String, dynamic>> aparelhosDo(Object? localId, {String? ambienteId}) => _banco
      .todos('equipamentos')
      .where((e) =>
          e['local_id'] == localId &&
          e['excluido_em'] == null &&
          e['situacao'] != 'removido' &&
          (ambienteId == null || '${e['ambiente_id'] ?? ''}' == ambienteId))
      .toList()
    ..sort((a, b) => '${a['codigo']}'.compareTo('${b['codigo']}'));

  /// Ambientes do local, por nome.
  static List<Map<String, dynamic>> ambientesDo(Object? localId) =>
      _banco.todos('ambientes').where((a) => a['local_id'] == localId && _vivo(a)).toList()
        ..sort((a, b) => '${a['nome']}'.toLowerCase().compareTo('${b['nome']}'.toLowerCase()));

  /// Cria ou completa um ambiente. [id] null = novo. Vai só o que foi informado.
  static Future<String> salvarAmbiente({
    required String clienteId,
    required String localId,
    String? id,
    required String nome,
    String? setorAndar,
    num? areaM2,
    int? ocupantesFixos,
    int? ocupantesVariaveis,
  }) async {
    final ambienteId = id ?? AcoesAtendimento.novoId();
    final dados = <String, dynamic>{
      'id': ambienteId,
      'nome': nome.trim(),
      'setor_andar': (setorAndar ?? '').trim().isEmpty ? null : setorAndar!.trim(),
      'area_m2': areaM2,
      'ocupantes_fixos': ocupantesFixos,
      'ocupantes_variaveis': ocupantesVariaveis,
    };
    await _sync.registrar(
      'cadastro_app',
      {'tipo': 'ambiente', 'cliente_id': clienteId, 'local_id': localId, 'dados': dados},
      aplicarLocal: () async {
        final atual = _banco.um('ambientes', ambienteId) ?? {'origem': 'app', 'ativo': true};
        await _banco.gravar('ambientes', [
          {...atual, ...dados, 'local_id': localId}
        ]);
      },
    );
    return ambienteId;
  }

  /// Aparelho novo no local (fora de um atendimento).
  static Future<void> aparelhoNoLocal({
    required String clienteId,
    required String localId,
    required EquipamentoNovo e,
  }) =>
      _sync.registrar(
        'cadastro_app',
        {'tipo': 'equipamento', 'cliente_id': clienteId, 'local_id': localId, 'dados': e.paraEnvio()},
        aplicarLocal: () async {
          await e.gravarLocal(_banco, clienteId: clienteId, localId: localId);
          _banco.avisar();
        },
      );

  /// Lê a plaqueta com a IA (precisa de internet). Devolve os campos achados
  /// (marca, modelo, numero_serie, capacidade_valor, capacidade_unidade,
  /// fluido, tipo_sugerido, codigo, legivel).
  static Future<Map<String, dynamic>> lerPlaqueta(Uint8List jpeg) async {
    final r = await Supabase.instance.client.functions
        .invoke('plaqueta-ler', body: {'imagem': base64Encode(jpeg)})
        .timeout(const Duration(seconds: 60));
    final d = r.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    throw StateError('A leitura da plaqueta não respondeu.');
  }

  /// Etiqueta QR em branco: só letras e números (6 a 32).
  static bool etiquetaValida(String texto) => RegExp(r'^[A-Za-z0-9]{6,32}$').hasMatch(texto.trim());

  /// A etiqueta já está num aparelho deste aparelho/celular? Devolve o rótulo dele.
  static String? etiquetaUsada(String token) {
    final t = token.trim();
    for (final e in _banco.todos('equipamentos')) {
      if ('${e['qr_token'] ?? ''}' == t) return [e['codigo'], e['descricao']].where((x) => x != null).join(' · ');
    }
    return null;
  }
}
