import 'dart:math';

import 'acoes_atendimento.dart';
import 'banco_local.dart';
import 'estado.dart';
import 'sincronizacao.dart';

/// Equipamento cadastrado na hora (na Nova OS ou no atendimento). O id nasce
/// aqui; ambiente e tipo podem ser da lista ou novos (só com o nome).
class EquipamentoNovo {
  EquipamentoNovo({
    required this.descricao,
    String codigo = '',
    this.marca = '',
    this.modelo = '',
    this.numeroSerie = '',
    this.fluido = '',
    this.ambienteId,
    this.ambienteNovo,
    this.tipoId,
    this.tipoNovo,
  })  : id = AcoesAtendimento.novoId(),
        provisorio = codigo.trim().isEmpty,
        codigo = codigo.trim().isEmpty ? codigoProvisorio() : codigo.trim();

  final String id;
  final String descricao;

  /// Plaqueta ou patrimônio; sem plaqueta, um provisório feito aqui
  /// (PROV-XXXXX), que já aparece sem internet e o escritório troca depois.
  final String codigo;
  final bool provisorio;

  /// PROV- e 5 letras/números (sem 0/O e 1/I, para não confundir ao anotar).
  static String codigoProvisorio() {
    const letras = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return 'PROV-${List.generate(5, (_) => letras[r.nextInt(letras.length)]).join()}';
  }
  final String marca;
  final String modelo;
  final String numeroSerie;
  final String fluido;
  final String? ambienteId;
  final String? ambienteNovo; // nome do ambiente novo
  final String? tipoId;
  final String? tipoNovo; // nome do tipo novo

  /// Ids do ambiente e do tipo novos (outro equipamento novo da mesma OS
  /// pode usar o mesmo, antes de sincronizar).
  late final String ambienteNovoId = AcoesAtendimento.novoId();
  late final String tipoNovoId = AcoesAtendimento.novoId();

  /// "BEB-01 · Bebedouro do refeitório" (sem código: só a descrição).
  String get rotulo => [codigo.trim(), descricao.trim()].where((x) => x.isNotEmpty).join(' · ');

  /// O que vai na operação (o mesmo formato da plataforma).
  Map<String, dynamic> paraEnvio() {
    String? v(String s) => s.trim().isEmpty ? null : s.trim();
    return {
      'id': id,
      'descricao': descricao.trim(),
      if (v(codigo) != null) 'codigo': v(codigo),
      if (v(marca) != null) 'marca': v(marca),
      if (v(modelo) != null) 'modelo': v(modelo),
      if (v(numeroSerie) != null) 'numero_serie': v(numeroSerie),
      if (v(fluido) != null) 'fluido_refrigerante': v(fluido),
      if (ambienteNovo != null)
        'ambiente_novo': {'id': ambienteNovoId, 'nome': ambienteNovo!.trim()}
      else if (ambienteId != null)
        'ambiente_id': ambienteId,
      if (tipoNovo != null)
        'tipo_novo': {'id': tipoNovoId, 'nome': tipoNovo!.trim()}
      else if (tipoId != null)
        'tipo_equipamento_id': tipoId,
    };
  }

  /// Grava no celular, para aparecer na hora (a plataforma manda a versão
  /// final, com o código provisório ou o QR, na próxima sincronização).
  Future<void> gravarLocal(BancoLocal banco, {required String clienteId, required String localId}) async {
    final agora = DateTime.now().toUtc().toIso8601String();
    String? v(String s) => s.trim().isEmpty ? null : s.trim();
    if (ambienteNovo != null) {
      await banco.gravar('ambientes', [
        {'id': ambienteNovoId, 'local_id': localId, 'nome': ambienteNovo!.trim(), 'origem': 'app', 'ativo': true}
      ], avisar: false);
    }
    if (tipoNovo != null) {
      await banco.gravar('tipos_equipamento', [
        {'id': tipoNovoId, 'nome': tipoNovo!.trim(), 'origem': 'app', 'ativo': true}
      ], avisar: false);
    }
    await banco.gravar('equipamentos', [
      {
        'id': id,
        'cliente_id': clienteId,
        'local_id': localId,
        'ambiente_id': ambienteNovo != null ? ambienteNovoId : ambienteId,
        'tipo_equipamento_id': tipoNovo != null ? tipoNovoId : tipoId,
        'codigo': v(codigo),
        'descricao': descricao.trim(),
        'marca': v(marca),
        'modelo': v(modelo),
        'numero_serie': v(numeroSerie),
        'fluido_refrigerante': v(fluido),
        'situacao': 'ativo',
        'origem': 'app',
        'criado_em': agora,
      }
    ], avisar: false);
  }
}

/// Contato do cliente cadastrado na hora ("quem pediu").
class ContatoNovo {
  ContatoNovo({required this.nome, this.telefone = '', this.cargo = '', this.aceitaWhatsapp = false})
      : id = AcoesAtendimento.novoId();

  final String id;
  final String nome;
  final String telefone;
  final String cargo;
  final bool aceitaWhatsapp;

  String get _telefone => telefone.replaceAll(RegExp(r'\D'), '');

  Map<String, dynamic> paraEnvio() => {
        'id': id,
        'nome': nome.trim(),
        if (_telefone.isNotEmpty) 'telefone': _telefone,
        if (cargo.trim().isNotEmpty) 'cargo': cargo.trim(),
        'aceita_whatsapp': aceitaWhatsapp,
      };

  Future<void> gravarLocal(BancoLocal banco, {required String clienteId, String? localId}) => banco.gravar('contatos', [
        {
          'id': id,
          'cliente_id': clienteId,
          'local_id': localId,
          'nome': nome.trim(),
          'telefone': _telefone.isEmpty ? null : _telefone,
          'cargo': cargo.trim().isEmpty ? null : cargo.trim(),
          'aceita_whatsapp': aceitaWhatsapp,
          'origem': 'app',
          'ativo': true,
        }
      ], avisar: false);
}

/// Listas para os cadastros rápidos e o cadastro feito no atendimento.
class AcoesCadastro {
  AcoesCadastro._();

  static EstadoApp get _estado => EstadoApp.instancia;
  static BancoLocal get _banco => _estado.banco!;
  static Sincronizador get _sync => _estado.sync!;

  static bool _vivo(Map<String, dynamic> r) => r['excluido_em'] == null && r['ativo'] != false;

  static List<Map<String, dynamic>> tipos() =>
      _banco.todos('tipos_equipamento').where(_vivo).toList()..sort((a, b) => '${a['nome']}'.compareTo('${b['nome']}'));

  static String _simples(Object? t) => '${t ?? ''}'.trim().toLowerCase();

  /// Códigos já usados no cliente (o código é único por cliente): {código: rótulo}.
  static Map<String, String> codigosDoCliente(Object? clienteId) => {
        for (final e in _banco.todos('equipamentos'))
          if (e['cliente_id'] == clienteId && e['excluido_em'] == null && e['situacao'] != 'removido' && e['codigo'] != null)
            _simples(e['codigo']): [e['codigo'], e['descricao']].where((x) => x != null).join(' · '),
      };

  /// Contato do cliente com este celular (para não cadastrar duas vezes).
  static Map<String, dynamic>? contatoComTelefone(Object? clienteId, String telefone) {
    final n = telefone.replaceAll(RegExp(r'\D'), '');
    if (n.isEmpty) return null;
    for (final c in _banco.todos('contatos')) {
      if (c['cliente_id'] == clienteId && _vivo(c) && '${c['telefone'] ?? ''}'.replaceAll(RegExp(r'\D'), '') == n) return c;
    }
    return null;
  }

  static List<Map<String, dynamic>> ambientesDo(Object? localId) =>
      _banco.todos('ambientes').where((a) => a['local_id'] == localId && _vivo(a)).toList()
        ..sort((a, b) => '${a['nome']}'.compareTo('${b['nome']}'));

  /// Contatos do cliente (os do local primeiro).
  static List<Map<String, dynamic>> contatosDo(Object? clienteId, {Object? localId}) =>
      _banco.todos('contatos').where((c) => c['cliente_id'] == clienteId && _vivo(c)).toList()
        ..sort((a, b) {
          final la = a['local_id'] == localId ? 0 : 1, lb = b['local_id'] == localId ? 0 : 1;
          return la != lb ? la.compareTo(lb) : '${a['nome']}'.compareTo('${b['nome']}');
        });

  /// Equipamento novo no atendimento: cadastra e já identifica (no
  /// atendimento e na OS). Quem está no serviço pode, sem outra permissão.
  static Future<void> equipamentoNoAtendimento(Map<String, dynamic> atd, EquipamentoNovo e) async {
    final os = _banco.um('ordens_servico', atd['os_id']);
    if (os == null) throw StateError('A OS deste atendimento não está no aparelho. Sincronize e tente de novo.');
    await _sync.registrar(
      'cadastro_app',
      {'tipo': 'equipamento', 'atendimento_id': atd['id'], 'dados': e.paraEnvio()},
      aplicarLocal: () async {
        await e.gravarLocal(_banco, clienteId: '${os['cliente_id']}', localId: '${os['local_id']}');
        await _banco.gravar('atendimento_equipamentos', [
          {
            'id': AcoesAtendimento.novoId(),
            'atendimento_id': atd['id'],
            'equipamento_id': e.id,
            'leitura': 'digitado',
            'lido_em': DateTime.now().toUtc().toIso8601String(),
          }
        ], avisar: false);
        await _banco.gravar('os_equipamentos', [
          {'id': AcoesAtendimento.novoId(), 'os_id': atd['os_id'], 'equipamento_id': e.id, 'principal': false}
        ], avisar: false);
        _banco.avisar();
      },
    );
  }
}
