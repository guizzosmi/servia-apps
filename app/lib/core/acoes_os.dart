import 'acoes_atendimento.dart';
import 'acoes_cadastro.dart';
import 'banco_local.dart';
import 'consultas.dart';
import 'estado.dart';
import 'sincronizacao.dart';

/// Tipos de OS (mesmos códigos do banco).
const tiposOs = {
  'corretiva': 'Corretiva',
  'preventiva': 'Preventiva',
  'instalacao': 'Instalação',
  'outro': 'Outro',
};

/// Cliente novo, cadastrado na hora pelo técnico.
class ClienteNovo {
  const ClienteNovo({required this.nome, this.telefone = '', this.documento = ''});
  final String nome;
  final String telefone;
  final String documento;

  /// Só números (CPF: 11, CNPJ: 14).
  String get documentoNumeros => documento.replaceAll(RegExp(r'\D'), '');
}

/// Local novo (endereço), cadastrado na hora pelo técnico.
class LocalNovo {
  const LocalNovo({
    this.nome = '',
    this.logradouro = '',
    this.numero = '',
    this.bairro = '',
    this.cidade = '',
    this.uf = '',
    this.instrucoes = '',
  });
  final String nome;
  final String logradouro;
  final String numero;
  final String bairro;
  final String cidade;
  final String uf;
  final String instrucoes;

  String get nomeOuPadrao => nome.trim().isEmpty ? 'Principal' : nome.trim();
}

/// O que o técnico preencheu na tela de Nova OS (à mão ou, depois, pela IA).
class PedidoOs {
  const PedidoOs({
    this.clienteId,
    this.clienteNovo,
    this.localId,
    this.localNovo,
    this.tipo = 'corretiva',
    this.prioridade = 'media',
    required this.problema,
    this.equipamentos = const [],
    this.equipamentosNovos = const [],
    this.contatoId,
    this.contatoNovo,
  });

  final String? clienteId;
  final ClienteNovo? clienteNovo;
  final String? localId;
  final LocalNovo? localNovo;
  final String tipo;
  final String prioridade;
  final String problema;
  final List<String> equipamentos;

  /// Cadastrados na hora (entram na OS junto com os escolhidos).
  final List<EquipamentoNovo> equipamentosNovos;

  /// Quem pediu: um contato do cliente ou um cadastrado na hora.
  final String? contatoId;
  final ContatoNovo? contatoNovo;
}

/// Abrir OS pelo app. Como as outras ações: entra na fila, aparece no
/// celular na hora (com "OS nova" até a plataforma dar o número) e sobe
/// quando houver internet. Os ids nascem aqui, para o atendimento poder
/// começar antes de sincronizar.
class AcoesOs {
  AcoesOs._();

  static EstadoApp get _estado => EstadoApp.instancia;
  static BancoLocal get _banco => _estado.banco!;
  static Sincronizador get _sync => _estado.sync!;
  static String get _eu => AcoesAtendimento.eu;
  static String _agora() => DateTime.now().toUtc().toIso8601String();

  /// O gestor liberou esta pessoa para abrir OS pelo app?
  static bool get possoAbrir => _banco.um('colaboradores', _eu)?['pode_abrir_os'] == true;

  /// Partes de hoje em que a pessoa está e que aceitam serviço novo.
  static List<Map<String, dynamic>> partesParaAtender() => [
        for (final p in _banco.partesDoDia(_sync.hoje))
          if ((p['status'] == 'publicada' || p['status'] == 'em_andamento') &&
              _banco.presentes(p['id'] as String).any((c) => c['colaborador_id'] == _eu))
            p,
      ];

  static bool _vivo(Map<String, dynamic> r) => r['excluido_em'] == null && r['ativo'] != false;

  /// Minúsculas e sem acento, para a busca.
  static String simples(Object? texto) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';
    final t = '${texto ?? ''}'.toLowerCase();
    final b = StringBuffer();
    for (final c in t.split('')) {
      final i = de.indexOf(c);
      b.write(i < 0 ? c : para[i]);
    }
    return b.toString();
  }

  /// Clientes ativos, por nome (filtrando pela busca: nome, fantasia, cidade dos locais).
  static List<Map<String, dynamic>> clientes(String busca) {
    final b = simples(busca.trim());
    final cidades = <Object?, String>{};
    if (b.isNotEmpty) {
      for (final l in _banco.todos('locais').where(_vivo)) {
        cidades[l['cliente_id']] = '${cidades[l['cliente_id']] ?? ''} ${simples(l['nome'])} ${simples(l['cidade'])}';
      }
    }
    final lista = _banco.todos('clientes').where(_vivo).where((c) {
      if (b.isEmpty) return true;
      final texto = '${simples(c['nome'])} ${simples(c['nome_fantasia'])} ${cidades[c['id']] ?? ''}';
      return b.split(' ').where((p) => p.isNotEmpty).every(texto.contains);
    }).toList()
      ..sort((a, b) => simples(a['nome']).compareTo(simples(b['nome'])));
    return lista;
  }

  static List<Map<String, dynamic>> locaisDo(Object? clienteId) =>
      _banco.todos('locais').where((l) => l['cliente_id'] == clienteId && _vivo(l)).toList()
        ..sort((a, b) => simples(a['nome']).compareTo(simples(b['nome'])));

  static List<Map<String, dynamic>> equipamentosDo(Object? localId) => _banco
      .todos('equipamentos')
      .where((e) => e['local_id'] == localId && e['excluido_em'] == null && e['situacao'] != 'removido')
      .toList()
    ..sort((a, b) => '${a['codigo']}'.compareTo('${b['codigo']}'));

  /// Abre a OS. Com [parte] ("atender agora"), ela entra no fim da parte e
  /// devolve o id do serviço (para abrir a tela dele); sem, vai para a fila
  /// do escritório e devolve null.
  static Future<String?> abrir(PedidoOs pedido, {Map<String, dynamic>? parte}) async {
    final osId = AcoesAtendimento.novoId();
    final agId = AcoesAtendimento.novoId();
    final itemId = parte == null ? null : AcoesAtendimento.novoId();
    final clienteId = pedido.clienteNovo != null ? AcoesAtendimento.novoId() : pedido.clienteId!;
    final localId = pedido.localNovo != null ? AcoesAtendimento.novoId() : pedido.localId!;
    final agora = _agora();
    final hoje = _sync.hoje;
    final cn = pedido.clienteNovo;
    final ln = pedido.localNovo;
    final doc = cn?.documentoNumeros ?? '';

    final dados = <String, dynamic>{
      'os_id': osId,
      'agendamento_id': agId,
      'destino': parte == null ? 'escritorio' : 'agora',
      if (parte != null) ...{'parte_id': parte['id'], 'parte_item_id': itemId},
      if (cn != null)
        'cliente_novo': {
          'id': clienteId,
          'nome': cn.nome.trim(),
          if (cn.telefone.trim().isNotEmpty) 'telefone': cn.telefone.trim(),
          if (doc.isNotEmpty) 'documento': doc,
        }
      else
        'cliente_id': clienteId,
      if (ln != null)
        'local_novo': {
          'id': localId,
          'nome': ln.nomeOuPadrao,
          'logradouro': ln.logradouro.trim(),
          'numero': ln.numero.trim(),
          'bairro': ln.bairro.trim(),
          'cidade': ln.cidade.trim(),
          'uf': ln.uf.trim().toUpperCase(),
          'instrucoes_acesso': ln.instrucoes.trim(),
        }
      else
        'local_id': localId,
      'tipo': pedido.tipo,
      'prioridade': pedido.prioridade,
      'problema_relatado': pedido.problema.trim(),
      'equipamentos': pedido.equipamentos,
      if (pedido.equipamentosNovos.isNotEmpty)
        'equipamentos_novos': [for (final e in pedido.equipamentosNovos) e.paraEnvio()],
      if (pedido.contatoNovo != null)
        'contato_novo': pedido.contatoNovo!.paraEnvio()
      else if (pedido.contatoId != null)
        'solicitante_contato_id': pedido.contatoId,
    };

    await _sync.registrar('os_abrir', dados, aplicarLocal: () async {
      String? vazio(String s) => s.trim().isEmpty ? null : s.trim();
      if (cn != null) {
        await _banco.gravar('clientes', [
          {
            'id': clienteId,
            'nome': cn.nome.trim(),
            'tipo': doc.length == 11 ? 'pf' : 'pj',
            'telefone': vazio(cn.telefone.replaceAll(RegExp(r'\D'), '')),
            'origem': 'app',
            'ativo': true,
            'criado_em': agora,
          }
        ], avisar: false);
      }
      if (ln != null) {
        await _banco.gravar('locais', [
          {
            'id': localId,
            'cliente_id': clienteId,
            'nome': ln.nomeOuPadrao,
            'logradouro': vazio(ln.logradouro),
            'numero': vazio(ln.numero),
            'bairro': vazio(ln.bairro),
            'cidade': vazio(ln.cidade),
            'uf': vazio(ln.uf.toUpperCase()),
            'instrucoes_acesso': vazio(ln.instrucoes),
            'origem': 'app',
            'ativo': true,
            'criado_em': agora,
          }
        ], avisar: false);
      }
      for (final e in pedido.equipamentosNovos) {
        await e.gravarLocal(_banco, clienteId: clienteId, localId: localId);
      }
      await pedido.contatoNovo?.gravarLocal(_banco, clienteId: clienteId, localId: localId);
      await _banco.gravar('ordens_servico', [
        {
          'id': osId,
          'codigo': null, // a plataforma dá o número
          'origem': 'app',
          'tipo': pedido.tipo,
          'status': parte == null ? 'aberta' : 'agendada',
          'cliente_id': clienteId,
          'local_id': localId,
          'prioridade': pedido.prioridade,
          'problema_relatado': pedido.problema.trim(),
          'solicitante_contato_id': pedido.contatoNovo?.id ?? pedido.contatoId,
          'criado_em': agora,
        }
      ], avisar: false);
      await _banco.gravar('agendamentos', [
        {
          'id': agId,
          'os_id': osId,
          'tipo': pedido.tipo == 'preventiva' ? 'preventiva' : 'visita_tecnica',
          'status': parte == null ? 'pendente' : 'programado',
          'prioridade': pedido.prioridade,
          if (parte != null) 'data_prevista': hoje,
          'criado_em': agora,
        }
      ], avisar: false);
      final todos = [...pedido.equipamentos, for (final e in pedido.equipamentosNovos) e.id];
      await _banco.gravar('os_equipamentos', [
        for (var i = 0; i < todos.length; i++)
          {
            'id': AcoesAtendimento.novoId(),
            'os_id': osId,
            'equipamento_id': todos[i],
            'principal': i == 0,
          }
      ], avisar: false);
      if (parte != null) {
        final itens = _banco.itensDaParte(parte['id'] as String);
        final ultima = itens.fold<num>(0, (m, i) => (i['ordem'] ?? 0) as num > m ? (i['ordem'] as num) : m);
        await _banco.gravar('partes_itens', [
          {
            'id': itemId,
            'parte_id': parte['id'],
            'agendamento_id': agId,
            'data': parte['data'],
            'ordem': ultima + 1,
            'papel_equipe': 'responsavel',
            'status': 'programado',
            'designados': const <String>[],
            'incluido_apos_publicacao': true,
            'alterado_apos_publicacao': false,
          }
        ], avisar: false);
      }
      _banco.avisar();
    });
    return itemId;
  }
}
