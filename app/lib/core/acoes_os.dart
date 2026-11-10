import 'package:supabase_flutter/supabase_flutter.dart';

import 'acoes_atendimento.dart';
import 'acoes_cadastro.dart';
import 'acoes_orcamento.dart';
import 'acoes_parte.dart';
import 'acoes_relato.dart';
import 'banco_local.dart';
import 'consultas.dart';
import 'estado.dart';
import 'formatos.dart';
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
    this.retornoDeOsId,
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

  /// Guia 59: retorno de um serviço anterior (a OS que o técnico citou no áudio).
  final String? retornoDeOsId;
}

/// Guia 80: uma OS em aberto do cliente, como a proposta da OS falada traz
/// (onde ela está e o que foi pedido). [clienteId]: o cliente da proposta.
class OsAberta {
  const OsAberta(this.dados, {required this.clienteId});

  final Map dados;
  final String clienteId;

  String get osId => '${dados['os_id']}';
  String get codigo => '${dados['codigo'] ?? 'OS'}';
  String get problema => '${dados['problema'] ?? ''}'.trim();
  String? get agendamentoId => dados['agendamento_id'] as String?;
  String? get itemId => dados['parte_item_id'] as String?;
  String get _equipe => '${dados['equipe'] ?? 'outra equipe'}';

  /// fila | agenda_hoje | outro_dia | dia_anterior | suspensa | sem_agendamento
  String get onde => '${dados['onde'] ?? 'sem_agendamento'}';

  /// Já está numa parte minha de hoje.
  bool get naMinhaParte =>
      dados['parte_id'] != null && AcoesOs.partesParaAtender().any((p) => p['id'] == dados['parte_id']);

  /// Está na parte de outra equipe (ou de outro dia): trazer precisa da confirmação do técnico.
  bool get comOutraEquipe => itemId != null && !naMinhaParte;

  /// "Na fila do escritório", "Hoje, na parte da Equipe 2", "Dia 12/11, na parte da Equipe 2"...
  String get ondeEsta {
    final d = '${dados['data'] ?? ''}';
    final dia = d.length >= 10 ? '${d.substring(8, 10)}/${d.substring(5, 7)}' : d;
    final texto = switch (onde) {
      'fila' => 'Na fila do escritório',
      'agenda_hoje' => naMinhaParte ? 'Hoje, na sua parte' : 'Hoje, na parte da $_equipe',
      'outro_dia' => 'Dia $dia, na parte da $_equipe',
      'dia_anterior' => 'Ficou do dia $dia, na parte da $_equipe',
      'suspensa' => 'Suspensa (peça ou orçamento)',
      _ => 'Sem visita marcada',
    };
    final status = dados['item_status'];
    return itemId != null && status != 'programado' ? '$texto · ${statusItem[status]?.texto ?? status}' : texto;
  }

  /// Por que não dá para trazer para a minha parte (null = dá).
  String? get impedimento {
    if (onde == 'suspensa') return 'Esta OS está suspensa (peça ou orçamento): fale com o escritório.';
    if (agendamentoId == null) return 'Esta OS está sem visita em aberto: fale com o escritório.';
    if (comOutraEquipe && dados['item_status'] != 'programado') {
      return 'Já está em andamento na parte da $_equipe: fale com o escritório.';
    }
    return null;
  }
}

/// Abrir OS pelo app. Como as outras ações: entra na fila, aparece no
/// celular na hora (com "OS nova" até a plataforma dar o número) e sobe
/// quando houver internet. Os ids nascem aqui, para o atendimento poder
/// começar antes de sincronizar.
/// Guia 113: não deu para abrir o dia de hoje (o motivo vai para o técnico).
class FalhaMeuDia implements Exception {
  const FalhaMeuDia(this.motivo);

  final String motivo;

  @override
  String toString() => motivo;
}

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

  /// Guia 113: no modo simples não existe dia publicado pelo escritório (o
  /// dia só existe quando a Agenda põe algo nele). Quem está numa equipe abre
  /// o próprio dia de hoje para atender agora (com internet).
  static bool get possoAbrirMeuDia => AcoesOrcamento.config.modoSimples && tenhoEquipe;

  /// Dá para "atender agora"? (tem parte publicada hoje ou pode abrir o dia).
  static bool get possoAtenderAgora => partesParaAtender().isNotEmpty || possoAbrirMeuDia;

  /// Por que não dá para atender agora (null = dá).
  static String? get semParteHoje {
    if (partesParaAtender().isNotEmpty) return null;
    if (AcoesOrcamento.config.modoSimples) {
      return tenhoEquipe ? null : 'Para atender agora, você precisa estar numa equipe: fale com o escritório.';
    }
    return 'Para atender agora, você precisa estar numa parte publicada de hoje.';
  }

  /// O que acontece no "atender agora" sem parte hoje (modo simples).
  static const abreMeuDia = 'Abre o seu dia de hoje (precisa de internet) e entra no serviço.';

  /// As partes para atender agora. Sem nenhuma, no modo simples, abre o meu
  /// dia de hoje na plataforma (app_abrir_meu_dia), sincroniza e espera ele
  /// chegar no celular. Não deu: [FalhaMeuDia] com o motivo.
  static Future<List<Map<String, dynamic>>> partesParaAtenderAgora() async {
    final ja = partesParaAtender();
    if (ja.isNotEmpty || !possoAbrirMeuDia) return ja;
    try {
      await Supabase.instance.client.rpc('app_abrir_meu_dia', params: {
        'p': {'dispositivo_id': _estado.conta!.dispositivoId},
      }).timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      throw FalhaMeuDia(e.message);
    } catch (_) {
      throw const FalhaMeuDia('Sem internet: para abrir o seu dia de hoje, conecte-se e tente de novo.');
    }
    for (var i = 0; i < 24; i++) {
      if (i % 8 == 0) await _sync.sincronizar();
      final partes = partesParaAtender();
      if (partes.isNotEmpty) return partes;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw const FalhaMeuDia('O seu dia de hoje foi aberto, mas ainda não chegou no celular: sincronize e tente de novo.');
  }

  /// Guia 95: a minha parte (não encerrada) num dia, se ela já está no aparelho.
  static Map<String, dynamic>? minhaParteNoDia(String data) {
    for (final p in _banco.partesDoDia(data)) {
      if (p['status'] != 'encerrada' && _banco.presentes(p['id'] as String).any((c) => c['colaborador_id'] == _eu)) {
        return p;
      }
    }
    return null;
  }

  /// Guia 95: estou em alguma equipe (no cadastro)? Sem equipe, a OS que não
  /// é "atender agora" vai para a fila do escritório.
  static bool get tenhoEquipe => _banco.todos('equipe_membros').any((m) => m['colaborador_id'] == _eu && _vivo(m));

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
    final interno = AcoesOrcamento.config.manutencaoPropria;
    final lista = _banco.todos('clientes').where(_vivo).where((c) => interno || c['interno'] != true).where((c) {
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
  /// devolve o id do serviço (para abrir a tela dele); sem, devolve null e ela
  /// vai para a agenda da equipe no [dia] (aaaa-mm-dd; sem dia ou passado:
  /// hoje), guia 95. Se a minha parte desse dia já está no aparelho, a OS já
  /// aparece nela; senão, quando a plataforma devolver o dia. Sem equipe (ou
  /// dia encerrado), a plataforma deixa na fila do escritório e avisa.
  /// [audioId]: a OS falada que deu origem a esta (guia 17b); [audioComoRelato]:
  /// o mesmo áudio também é o relato do serviço.
  static Future<String?> abrir(PedidoOs pedido,
      {Map<String, dynamic>? parte, String? dia, String? audioId, bool audioComoRelato = false}) async {
    final osId = AcoesAtendimento.novoId();
    final agId = AcoesAtendimento.novoId();
    final itemId = parte == null ? null : AcoesAtendimento.novoId();
    final dataAgenda = parte != null ? null : (dia == null || dia.compareTo(_sync.hoje) < 0 ? _sync.hoje : dia);
    final naAgenda = dataAgenda == null ? null : minhaParteNoDia(dataAgenda);
    final agendaItemId = parte == null ? AcoesAtendimento.novoId() : null;
    // A parte em que o serviço já aparece no aparelho (a de "atender agora" ou a do dia).
    final parteLocal = parte ?? naAgenda;
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
      if (parte != null)
        ...{'parte_id': parte['id'], 'parte_item_id': itemId}
      else
        ...{'data_prevista': dataAgenda, 'parte_item_id': agendaItemId},
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
      if (pedido.retornoDeOsId != null) 'retorno_de_os_id': pedido.retornoDeOsId,
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
          'status': parteLocal == null ? 'aberta' : 'agendada',
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
          'status': parteLocal == null ? 'pendente' : 'programado',
          'prioridade': pedido.prioridade,
          'data_prevista': dataAgenda ?? hoje,
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
      if (parteLocal != null) {
        await _banco.gravar('partes_itens', [
          {
            'id': itemId ?? agendaItemId,
            'parte_id': parteLocal['id'],
            'agendamento_id': agId,
            'data': parteLocal['data'],
            'ordem': _proximaOrdem(parteLocal),
            'papel_equipe': 'responsavel',
            'status': 'programado',
            'designados': const <String>[],
            // Na parte que o escritório ainda monta (rascunho), não é encaixe.
            'incluido_apos_publicacao': parteLocal['status'] != 'rascunho',
            'alterado_apos_publicacao': false,
          }
        ], avisar: false);
      }
      _banco.avisar();
    });
    if (audioId != null) await AcoesRelato.vincular(audioId, osId, comoRelato: audioComoRelato);
    return itemId;
  }

  /// O fim da parte (o serviço encaixado entra por último).
  static num _proximaOrdem(Map<String, dynamic> parte) =>
      _banco.itensDaParte(parte['id'] as String).fold<num>(0, (m, i) => (i['ordem'] ?? 0) as num > m ? (i['ordem'] as num) : m) + 1;

  /// Guia 80: o serviço desta OS que já está numa parte minha de hoje (ou null).
  static Map<String, dynamic>? servicoNaMinhaParte(OsAberta os) {
    if (!os.naMinhaParte) return null;
    final item = _banco.um('partes_itens', os.itemId);
    return item != null && AcoesParte.statusAbertos.contains(item['status']) ? item : null;
  }

  /// Guia 80: usar a OS que já existe (os_puxar). O serviço entra no fim da
  /// [parte] de hoje; da outra equipe (ou de outro dia) só com [confirmado]
  /// (o técnico confirmou; o escritório é avisado). [aCaminho]: já sai "a
  /// caminho". Devolve o id do serviço (nasce aqui, como no abrir).
  static Future<String> puxar(OsAberta os,
      {required Map<String, dynamic> parte, bool confirmado = false, bool aCaminho = false}) async {
    final itemId = AcoesAtendimento.novoId();
    final agora = _agora();
    await _sync.registrar(
      'os_puxar',
      {
        'agendamento_id': os.agendamentoId,
        'parte_id': parte['id'],
        'parte_item_id': itemId,
        if (confirmado) 'confirmado': true,
        if (aCaminho) 'status': 'em_deslocamento',
        // Só para o app (a plataforma ignora): o aviso da sincronização.
        'os_id': os.osId,
      },
      aplicarLocal: () async {
        // Da fila do escritório (ou de outra equipe), a OS pode não estar no celular.
        if (_banco.um('ordens_servico', os.osId) == null) {
          await _banco.gravar('ordens_servico', [
            {
              'id': os.osId,
              'codigo': os.dados['codigo'],
              'tipo': os.dados['tipo'],
              'status': 'agendada',
              'cliente_id': os.clienteId,
              'local_id': os.dados['local_id'],
              'problema_relatado': os.dados['problema'],
            }
          ], avisar: false);
        }
        final ag = _banco.um('agendamentos', os.agendamentoId);
        await _banco.gravar('agendamentos', [
          {
            ...?ag,
            'id': os.agendamentoId,
            'os_id': os.osId,
            if (ag == null) 'tipo': os.dados['tipo'] == 'preventiva' ? 'preventiva' : 'visita_tecnica',
            'status': 'programado',
            'data_prevista': parte['data'],
          }
        ], avisar: false);
        // Sai da parte onde estava (outra equipe ou outro dia).
        final antes = _banco.um('partes_itens', os.itemId);
        if (antes != null) {
          await _banco.gravar('partes_itens', [
            {...antes, 'status': 'removido'}
          ], avisar: false);
        }
        await _banco.gravar('partes_itens', [
          {
            'id': itemId,
            'parte_id': parte['id'],
            'agendamento_id': os.agendamentoId,
            'data': parte['data'],
            'ordem': _proximaOrdem(parte),
            'papel_equipe': 'responsavel',
            'status': aCaminho ? 'em_deslocamento' : 'programado',
            if (aCaminho) 'iniciado_em': agora,
            'designados': const <String>[],
            'incluido_apos_publicacao': true,
            'alterado_apos_publicacao': false,
          }
        ], avisar: false);
        final dia = _banco.um('partes_diarias', parte['id']);
        if (aCaminho && dia != null && dia['status'] == 'publicada') {
          await _banco.gravar('partes_diarias', [
            {...dia, 'status': 'em_andamento'}
          ], avisar: false);
        }
        _banco.avisar();
      },
    );
    return itemId;
  }
}
