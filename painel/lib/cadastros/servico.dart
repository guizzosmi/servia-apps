import 'package:supabase_flutter/supabase_flutter.dart';

import 'definicoes.dart';

class Pagina {
  Pagina(this.itens, this.temMais);
  final List<Map<String, dynamic>> itens;
  final bool temMais;
}

/// Registro foi alterado por outra pessoa depois que você abriu.
class ConflitoDeVersao implements Exception {
  @override
  String toString() =>
      'Este registro foi alterado por outra pessoa enquanto você editava. '
      'Feche e abra de novo para ver a versão atual.';
}

/// O banco não deixou gravar (papel sem permissão ou registro de outra empresa).
class SemPermissao implements Exception {
  @override
  String toString() => 'Sem permissão para alterar este registro.';
}

/// Acesso ao banco para qualquer cadastro. O RLS do banco garante que só
/// aparecem (e só gravam) registros da empresa ativa; o painel não precisa
/// filtrar por empresa nem enviar empresa_id.
class CadastroServico {
  CadastroServico(this.def);
  final CadastroDef def;

  SupabaseClient get _db => Supabase.instance.client;

  /// Tira da busca os caracteres que têm significado especial no filtro.
  static String limparBusca(String texto) =>
      texto.replaceAll(RegExp(r'[,()"*%\\:]'), ' ').trim();

  Future<Pagina> listar({
    String busca = '',
    Map<String, Object?> filtros = const {},
    int pagina = 0,
    int tamanho = 25,
  }) async {
    var q = _db.from(def.tabela).select(def.select).isFilter('excluido_em', null);
    filtros.forEach((coluna, valor) {
      q = valor == null ? q.isFilter(coluna, null) : q.eq(coluna, valor);
    });
    final b = limparBusca(busca);
    if (b.isNotEmpty && def.colunasBusca.isNotEmpty) {
      q = q.or(def.colunasBusca.map((c) => '$c.ilike."*$b*"').join(','));
    }
    final inicio = pagina * tamanho;
    // Pede 1 a mais só para saber se existe próxima página.
    final dados = await q
        .order(def.ordem, ascending: def.ordemCrescente)
        .range(inicio, inicio + tamanho);
    final temMais = dados.length > tamanho;
    return Pagina(temMais ? dados.sublist(0, tamanho) : dados, temMais);
  }

  Future<Map<String, dynamic>> obter(String id) =>
      _db.from(def.tabela).select(def.select).eq('id', id).single();

  /// Inclui (id nulo) ou altera. Na alteração confere a versão para não
  /// sobrescrever a mudança de outra pessoa.
  Future<Map<String, dynamic>> salvar(
    Map<String, dynamic> dados, {
    String? id,
    int? versao,
  }) async {
    if (id == null) {
      return await _db.from(def.tabela).insert(dados).select(def.select).single();
    }
    var q = _db.from(def.tabela).update(dados).eq('id', id);
    if (versao != null) q = q.eq('versao', versao);
    final linhas = await q.select(def.select);
    if (linhas.isNotEmpty) return linhas.first;
    // Nenhuma linha alterada: ou a versão mudou, ou o banco negou (RLS).
    final atual = await _db
        .from(def.tabela)
        .select('versao')
        .eq('id', id)
        .maybeSingle();
    if (atual != null && versao != null && atual['versao'] != versao) {
      throw ConflitoDeVersao();
    }
    throw SemPermissao();
  }

  /// Exclusão lógica: o registro some das listas, mas fica no banco
  /// (histórico, relatórios antigos e prazos de retenção da LGPD).
  Future<void> excluir(String id) async {
    final linhas = await _db
        .from(def.tabela)
        .update({'excluido_em': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .select('id');
    if (linhas.isEmpty) throw SemPermissao();
  }
}
