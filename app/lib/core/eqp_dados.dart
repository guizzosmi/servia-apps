import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'banco_local.dart';
import 'formatos.dart';

/// Gestão de Equipamentos no app (guia 104): o que o aparelho guarda para
/// funcionar sem internet (fichas, conjunto, reservas, locais da empresa,
/// checklists e parâmetros) e as consultas das telas.
///
/// Só aparece para quem tem a aplicação "equipamentos" no login (o admin
/// liga na conta). O banco confere de novo em toda gravação.
class EqpDados {
  EqpDados._();

  static const tabelas = ['eqp_fichas', 'eqp_reservas', 'eqp_componentes', 'eqp_locais', 'eqp_checklists'];

  /// A aplicação está no token desta sessão? (sem sessão aberta, vale o que
  /// ficou guardado da última sincronização, para funcionar sem internet).
  static bool ligada(BancoLocal? banco) {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token != null) {
      final apps = aplicacoesDoToken(token);
      if (apps != null) return apps.contains('equipamentos');
    }
    return banco?.meta('eqp_ligada') == '1';
  }

  /// Aplicações do hub que vêm no token (null = token ilegível).
  @visibleForTesting
  static List<String>? aplicacoesDoToken(String token) {
    try {
      final partes = token.split('.');
      if (partes.length != 3) return null;
      final dados = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1])))) as Map<String, dynamic>;
      final apps = (dados['app_metadata'] as Map?)?['aplicacoes'];
      // Token antigo, sem a lista: só a Refrigeração.
      if (apps is! List) return const ['refrigeracao'];
      return [for (final a in apps) '$a'];
    } catch (_) {
      return null;
    }
  }

  /// Chamado no fim de cada sincronização. Com registros ainda na fila, não
  /// troca as fichas (a tela continua mostrando o que o técnico já fez).
  static Future<void> baixar(
    BancoLocal banco,
    Future<Map<String, dynamic>> Function(String funcao, Map<String, dynamic> p) rpc,
    Map<String, dynamic> base,
  ) async {
    if (!ligada(banco)) {
      if (banco.meta('eqp_ligada') != null) {
        await banco.substituir({for (final t in tabelas) t: const []});
        await banco.gravarMeta('eqp_ligada', null);
        await banco.gravarMeta('eqp_parametros', null);
      }
      return;
    }
    if (banco.fila.any((o) => o.tipo == 'eqp_registrar' && o.situacao == 'pendente')) return;
    try {
      final r = await rpc('eqp_app_dados', base);
      if (banco.fila.any((o) => o.tipo == 'eqp_registrar' && o.situacao == 'pendente')) return;
      List<Map<String, dynamic>> lista(String chave) =>
          ((r[chave] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await banco.substituir({
        'eqp_fichas': lista('fichas'),
        'eqp_reservas': lista('reservas'),
        'eqp_componentes': lista('componentes'),
        'eqp_locais': lista('locais_empresa'),
        'eqp_checklists': lista('checklists'),
      });
      await banco.gravarMeta('eqp_parametros', jsonEncode(r['parametros'] ?? const {}));
      await banco.gravarMeta('eqp_ligada', '1', avisar: true);
    } catch (e) {
      // Sem internet ou a aplicação foi desligada: fica o que já estava.
      debugPrint('Equipamentos: $e');
    }
  }
}

/// Parâmetros da empresa para a Gestão de Equipamentos (vêm da plataforma).
class EqpParametros {
  const EqpParametros(this._d);
  final Map<String, dynamic> _d;

  static EqpParametros de(BancoLocal banco) {
    try {
      return EqpParametros(jsonDecode(banco.meta('eqp_parametros') ?? '{}') as Map<String, dynamic>);
    } catch (_) {
      return const EqpParametros({});
    }
  }

  int get fotosMinimas => int.tryParse('${_d['fotos_minimas_entrega'] ?? 1}') ?? 1;
  bool get gpsObrigatorio => _d['gps_entrega'] != false;
  bool get aceiteObrigatorio => _d['aceite_entrega'] != false;
  bool get checklistObrigatorio => _d['checklist_obrigatorio'] != false;
  bool get fotosObrigatoriasOs => _d['fotos_obrigatorias_os'] != false;
  num get precisaoBoaM => num.tryParse('${_d['precisao_boa_m'] ?? 50}') ?? 50;
}

/// Nomes e cores (mesmos códigos do banco).
const statusEqp = {
  'disponivel': Rotulo('Disponível', Cores.sucesso),
  'reservado': Rotulo('Reservado', Cores.info),
  'em_transito': Rotulo('Em trânsito', Cores.andamento),
  'em_uso': Rotulo('Em uso', Cores.andamento),
  'retornado': Rotulo('Aguardando conferência', Cores.alerta),
  'em_manutencao': Rotulo('Em manutenção', Cores.coral500),
  'bloqueado': Rotulo('Bloqueado', Cores.erro),
  'baixado': Rotulo('Baixado', Cores.neutro),
};

const destinosEqp = {
  'locacao': 'Locação',
  'obra_propria': 'Obra própria',
  'uso_proprio': 'Uso próprio',
};

const eventosEqp = {
  'saida': 'Saída / entrega',
  'chegada': 'Chegada no destino',
  'transferencia': 'Transferência',
  'recolher': 'Recolher',
  'retorno': 'Retorno ao depósito',
  'mover': 'Mover (entre locais da empresa)',
  'iniciar_manutencao': 'Iniciar manutenção',
};

const tiposApontamento = {
  'avaria': 'Avaria',
  'falta': 'Falta',
  'sujeira': 'Sujeira',
  'uso_acima': 'Uso acima do combinado',
};

/// Consultas das telas de equipamentos (banco do aparelho).
extension ConsultasEqp on BancoLocal {
  List<Map<String, dynamic>> get eqpFichas =>
      todos('eqp_fichas')..sort((a, b) => '${a['codigo']}'.compareTo('${b['codigo']}'));

  Map<String, dynamic>? eqpFicha(Object? equipamentoId) => um('eqp_fichas', equipamentoId);

  /// Etiqueta lida (QR ou código digitado): a ficha, ou o componente e o conjunto dele.
  ({Map<String, dynamic>? ficha, Map<String, dynamic>? componente}) eqpPorEtiqueta(String lido) {
    var valor = lido.trim();
    // Etiqueta com link (…/q/<token>): vale o último pedaço.
    if (valor.contains('/')) valor = valor.split('/').where((x) => x.isNotEmpty).lastOrNull ?? valor;
    final v = valor.toLowerCase();
    bool bate(Map e) =>
        '${e['qr_token'] ?? ''}'.toLowerCase() == v ||
        '${e['codigo'] ?? ''}'.toLowerCase() == v ||
        '${e['patrimonio'] ?? ''}'.toLowerCase() == v;
    final ficha = todos('eqp_fichas').where(bate).firstOrNull;
    if (ficha != null) {
      final pai = ficha['equipamento_pai_id'] == null ? null : eqpFicha(ficha['equipamento_pai_id']);
      return pai == null ? (ficha: ficha, componente: null) : (ficha: pai, componente: ficha);
    }
    final comp = todos('eqp_componentes').where(bate).firstOrNull;
    if (comp != null) return (ficha: eqpFicha(comp['equipamento_pai_id']), componente: comp);
    return (ficha: null, componente: null);
  }

  /// Reservas (e o uso ativo) de um equipamento, da mais próxima para a mais longe.
  List<Map<String, dynamic>> eqpReservas(Object? equipamentoId) =>
      todos('eqp_reservas').where((r) => r['equipamento_id'] == equipamentoId).toList()
        ..sort((a, b) => '${a['inicio']}'.compareTo('${b['inicio']}'));

  Map<String, dynamic>? eqpReservaAtiva(Object? equipamentoId) =>
      eqpReservas(equipamentoId).where((r) => r['situacao'] == 'ativa').firstOrNull;

  List<Map<String, dynamic>> get eqpLocaisEmpresa =>
      todos('eqp_locais')..sort((a, b) => '${a['nome']}'.compareTo('${b['nome']}'));

  /// O checklist que vale (a mesma ordem da plataforma): o do equipamento, o
  /// do modelo, o do tipo de equipamento ou o geral.
  Map<String, dynamic>? eqpChecklist(Map<String, dynamic> ficha, String tipo) {
    final candidatos = todos('eqp_checklists')
        .where((c) => c['tipo'] == tipo && c['ativo'] != false && ((c['itens'] as List?) ?? const []).isNotEmpty)
        .toList();
    int prioridade(Map c) {
      if (c['equipamento_id'] != null) return c['equipamento_id'] == ficha['id'] ? 0 : 99;
      if (c['modelo_id'] != null) return c['modelo_id'] == ficha['modelo_id'] ? 1 : 99;
      if (c['tipo_equipamento_id'] != null) return c['tipo_equipamento_id'] == ficha['tipo_equipamento_id'] ? 2 : 99;
      return 3;
    }

    final validos = candidatos.where((c) => prioridade(c) < 99).toList()
      ..sort((a, b) {
        final p = prioridade(a).compareTo(prioridade(b));
        return p != 0 ? p : '${b['criado_em']}'.compareTo('${a['criado_em']}');
      });
    return validos.firstOrNull;
  }

  /// Registros de equipamento ainda na fila (aguardando internet ou recusados).
  List<Operacao> eqpNaFila(Object? equipamentoId) =>
      fila.where((o) => o.tipo == 'eqp_registrar' && o.dados['equipamento_id'] == equipamentoId).toList();
}

/// Eventos que o técnico pode fazer no app, pelo status (como a plataforma).
List<String> eventosPermitidos(Map<String, dynamic> ficha, {bool temReserva = false, bool temAtiva = false}) {
  final s = '${ficha['status']}';
  return [
    if ((s == 'disponivel' || s == 'reservado') && temReserva) 'saida',
    if (s == 'em_transito') 'chegada',
    if (s == 'em_uso') 'transferencia',
    if (s == 'em_uso' || s == 'em_transito' || (s == 'em_manutencao' && temAtiva)) 'recolher',
    if (s == 'em_uso' || s == 'em_transito' || (s == 'em_manutencao' && temAtiva)) 'retorno',
    if (const ['disponivel', 'reservado', 'retornado', 'em_manutencao', 'bloqueado'].contains(s) && !temAtiva) 'mover',
    if (const ['disponivel', 'reservado', 'retornado', 'em_uso', 'bloqueado'].contains(s)) 'iniciar_manutencao',
  ];
}

/// Leitura com unidade: '1.262 h', '850 km'.
String leituraEqp(Object? valor, Object? medidor) {
  if (valor == null) return '—';
  final unidade = switch ('$medidor') { 'horas' => ' h', 'km' => ' km', 'ciclos' => ' ciclos', _ => '' };
  return '${numeroBr(valor)}$unidade';
}
