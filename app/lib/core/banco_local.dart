import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'cofre.dart';

/// Tabelas do "dia" (partes publicadas e o que elas usam). Chegam inteiras
/// a cada sincronização e substituem as que estavam no aparelho.
const tabelasDoDia = [
  'partes_diarias',
  'partes_composicao',
  'partes_itens',
  'agendamentos',
  'ordens_servico',
  'os_equipamentos',
  'atendimentos',
  'atendimento_participantes',
  'atendimento_equipamentos',
  'atendimento_medicoes',
  'atendimento_fluidos',
  'atendimento_fotos',
  'os_itens',
];

/// Uma ação feita no app, esperando para subir para a plataforma.
class Operacao {
  const Operacao({
    required this.opId,
    required this.tipo,
    required this.em,
    required this.dados,
    this.situacao = 'pendente',
    this.tentativas = 0,
    this.erro,
  });

  final String opId;
  final String tipo;

  /// Horário da ação no aparelho (ISO, UTC).
  final String em;
  final Map<String, dynamic> dados;

  /// pendente | recusada
  final String situacao;
  final int tentativas;
  final String? erro;

  Map<String, dynamic> paraEnvio() => {'op_id': opId, 'tipo': tipo, 'em': em, 'dados': dados};

  static Operacao daLinha(Map<String, Object?> l) => Operacao(
        opId: l['op_id'] as String,
        tipo: l['tipo'] as String,
        em: l['em'] as String,
        dados: jsonDecode(l['dados'] as String) as Map<String, dynamic>,
        situacao: l['situacao'] as String,
        tentativas: (l['tentativas'] as int?) ?? 0,
        erro: l['erro'] as String?,
      );
}

/// Banco do aparelho, criptografado (SQLCipher).
///
/// Guarda cada registro da plataforma como JSON, numa tabela só
/// (registros: tabela + id + dados), mais a fila de operações e alguns
/// valores de controle (meta). Tudo fica também em memória, para as telas
/// lerem na hora; quem grava avisa as telas (ChangeNotifier).
class BancoLocal extends ChangeNotifier {
  BancoLocal._(this._db);

  final Database _db;
  final Map<String, Map<String, Map<String, dynamic>>> _cache = {};
  final Map<String, String> _meta = {};
  List<Operacao> _fila = [];

  static const _arquivo = 'servia_local.db';
  static BancoLocal? _aberto;

  static Future<String> _caminho() async => p.join(await getDatabasesPath(), _arquivo);

  /// Abre (ou cria) o banco. Se a chave não abrir o arquivo (ex.: app
  /// reinstalado), o arquivo é recriado: os dados voltam na sincronização.
  static Future<BancoLocal> abrir() async {
    if (_aberto != null) return _aberto!;
    var chave = await Cofre.ler(Cofre.chaveBanco);
    if (chave == null) {
      chave = Cofre.aleatorio();
      await Cofre.gravar(Cofre.chaveBanco, chave);
    }
    final caminho = await _caminho();
    Database db;
    try {
      db = await _abrirArquivo(caminho, chave);
    } catch (_) {
      await deleteDatabase(caminho);
      db = await _abrirArquivo(caminho, chave);
    }
    final banco = BancoLocal._(db);
    await banco._carregar();
    _aberto = banco;
    return banco;
  }

  static Future<Database> _abrirArquivo(String caminho, String chave) => openDatabase(
        caminho,
        password: chave,
        version: 1,
        onCreate: (db, versao) async {
          await db.execute('create table registros (tabela text not null, id text not null, '
              'dados text not null, primary key (tabela, id))');
          await db.execute('create table fila (seq integer primary key autoincrement, op_id text not null unique, '
              'tipo text not null, em text not null, dados text not null, '
              "situacao text not null default 'pendente', tentativas integer not null default 0, erro text)");
          await db.execute('create table meta (chave text primary key, valor text)');
        },
      );

  /// Apaga o banco inteiro (sair do app, aparelho revogado, outro usuário).
  static Future<void> apagarTudo() async {
    final aberto = _aberto;
    _aberto = null;
    if (aberto != null) await aberto._db.close();
    await deleteDatabase(await _caminho());
    await Cofre.apagar(Cofre.chaveBanco);
  }

  Future<void> _carregar() async {
    for (final l in await _db.query('registros')) {
      final tabela = l['tabela'] as String;
      _cache.putIfAbsent(tabela, () => {})[l['id'] as String] =
          jsonDecode(l['dados'] as String) as Map<String, dynamic>;
    }
    for (final l in await _db.query('meta')) {
      final v = l['valor'] as String?;
      if (v != null) _meta[l['chave'] as String] = v;
    }
    await _carregarFila();
  }

  Future<void> _carregarFila() async {
    final linhas = await _db.query('fila', orderBy: 'seq');
    _fila = linhas.map(Operacao.daLinha).toList();
  }

  // ------------------------------------------------------------------
  // Leitura (da memória)
  // ------------------------------------------------------------------

  /// Todos os registros de uma tabela.
  List<Map<String, dynamic>> todos(String tabela) => _cache[tabela]?.values.toList() ?? const [];

  /// Um registro pelo id (ou null).
  Map<String, dynamic>? um(String tabela, Object? id) => id == null ? null : _cache[tabela]?['$id'];

  /// Quantos registros há em cada tabela (tela de diagnóstico).
  Map<String, int> contagens() => {for (final e in _cache.entries) e.key: e.value.length};

  String? meta(String chave) => _meta[chave];

  /// Chaves de controle que começam com [prefixo] (ex.: 'foto_subiu:').
  List<String> chavesMeta(String prefixo) => _meta.keys.where((k) => k.startsWith(prefixo)).toList();

  List<Operacao> get fila => List.unmodifiable(_fila);
  int get pendentes => _fila.where((o) => o.situacao == 'pendente').length;
  List<Operacao> get recusadas => _fila.where((o) => o.situacao == 'recusada').toList();

  // ------------------------------------------------------------------
  // Gravação
  // ------------------------------------------------------------------

  /// Avisa as telas depois de várias gravações feitas com `avisar: false`.
  void avisar() => notifyListeners();

  /// Grava (inclui ou substitui) registros de uma tabela.
  Future<void> gravar(String tabela, Iterable<Map<String, dynamic>> linhas, {bool avisar = true}) async {
    final batch = _db.batch();
    final memoria = _cache.putIfAbsent(tabela, () => {});
    for (final l in linhas) {
      final id = '${l['id']}';
      memoria[id] = l;
      batch.insert('registros', {'tabela': tabela, 'id': id, 'dados': jsonEncode(l)},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    if (avisar) notifyListeners();
  }

  /// Altera campos de um registro (ex.: status do serviço, na hora da ação).
  Future<void> alterar(String tabela, Object? id, Map<String, dynamic> campos) async {
    final atual = um(tabela, id);
    if (atual == null) return;
    await gravar(tabela, [
      {...atual, ...campos}
    ]);
  }

  Future<void> apagarIds(String tabela, Iterable<String> ids, {bool avisar = true}) async {
    final batch = _db.batch();
    for (final id in ids) {
      _cache[tabela]?.remove(id);
      batch.delete('registros', where: 'tabela = ? and id = ?', whereArgs: [tabela, id]);
    }
    await batch.commit(noResult: true);
    if (avisar) notifyListeners();
  }

  /// Troca o conteúdo inteiro das tabelas informadas (o "dia").
  Future<void> substituir(Map<String, List<Map<String, dynamic>>> dados) async {
    await _db.transaction((tx) async {
      final batch = tx.batch();
      for (final e in dados.entries) {
        batch.delete('registros', where: 'tabela = ?', whereArgs: [e.key]);
        for (final l in e.value) {
          batch.insert('registros', {'tabela': e.key, 'id': '${l['id']}', 'dados': jsonEncode(l)},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await batch.commit(noResult: true);
    });
    for (final e in dados.entries) {
      _cache[e.key] = {for (final l in e.value) '${l['id']}': l};
    }
    notifyListeners();
  }

  Future<void> gravarMeta(String chave, String? valor, {bool avisar = false}) async {
    if (valor == null) {
      _meta.remove(chave);
      await _db.delete('meta', where: 'chave = ?', whereArgs: [chave]);
    } else {
      _meta[chave] = valor;
      await _db.insert('meta', {'chave': chave, 'valor': valor}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    if (avisar) notifyListeners();
  }

  // ------------------------------------------------------------------
  // Fila de operações
  // ------------------------------------------------------------------

  Future<void> enfileirar(Operacao op) async {
    await _db.insert('fila', {
      'op_id': op.opId,
      'tipo': op.tipo,
      'em': op.em,
      'dados': jsonEncode(op.dados),
    });
    await _carregarFila();
    notifyListeners();
  }

  /// As próximas operações a enviar, na ordem em que foram feitas.
  List<Operacao> proximas(int limite) =>
      _fila.where((o) => o.situacao == 'pendente').take(limite).toList();

  /// A plataforma aceitou: sai da fila.
  Future<void> removerDaFila(Iterable<String> opIds) async {
    final batch = _db.batch();
    for (final id in opIds) {
      batch.delete('fila', where: 'op_id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
    await _carregarFila();
    notifyListeners();
  }

  /// A plataforma recusou (regra): fica na fila como recusada, com o motivo.
  Future<void> marcarRecusada(String opId, String motivo) async {
    await _db.update('fila', {'situacao': 'recusada', 'erro': motivo}, where: 'op_id = ?', whereArgs: [opId]);
    await _carregarFila();
    notifyListeners();
  }

  /// Falha passageira: continua pendente, com mais uma tentativa contada.
  Future<void> marcarTentativa(String opId, String motivo) async {
    await _db.rawUpdate('update fila set tentativas = tentativas + 1, erro = ? where op_id = ?', [motivo, opId]);
    await _carregarFila();
    notifyListeners();
  }
}
