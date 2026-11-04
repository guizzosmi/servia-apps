import 'package:flutter/foundation.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Parâmetros da empresa ativa (empresa_config.parametros) que mudam o que o
/// painel mostra: o menu fica só com o que a empresa usa.
///
/// Carrega quando a empresa ativa muda e de novo quando as Configurações
/// são salvas ([recarregar]).
class ParametrosEmpresa extends ChangeNotifier {
  ParametrosEmpresa._();
  static final instancia = ParametrosEmpresa._();

  String? _empresaId;
  Map<String, dynamic> _p = const {};
  bool _carregando = false;

  Map<String, dynamic> get valores => _p;

  /// Já carregou os parâmetros da empresa ativa.
  bool get carregado => _empresaId != null && _empresaId == Sessao.atual?.empresaId;

  Map<String, dynamic> get _preventivas => Map<String, dynamic>.from((_p['preventivas'] as Map?) ?? const {});

  /// Planos de preventiva (menu e cards de prazo na Início). Padrão: ligado.
  bool get usaPreventivas => _preventivas['usa'] != false;

  /// PMOC (climatização): tipo PMOC, responsável técnico e o padrão da Portaria.
  bool get atendePmoc => usaPreventivas && _preventivas['pmoc'] == true;

  /// Guia 58: faz manutenção própria? (sem: o cliente "interno" some das buscas e da lista).
  bool _manutencaoPropria = false;
  bool get manutencaoPropria => _manutencaoPropria;

  /// Guia 62: modo simples (Agenda no lugar do quadro e da fila, sem fechar o dia).
  bool get modoSimples => _p['modo_simples'] == true;

  /// Guia 63: controla estoque (menu Estoque e baixa automática pela OS).
  bool get usaEstoque => (_p['estoque'] as Map?)?['usa'] == true;

  /// Guia 64: lembrete de limpeza (menu Lembretes).
  bool get usaLembretes => (_p['lembrete_limpeza'] as Map?)?['usa'] == true;

  /// Nome do menu conforme a empresa.
  String get nomePlanos => atendePmoc ? 'Planos e PMOC' : 'Planos de preventiva';

  /// Garante os parâmetros da empresa da sessão (chame no build: só busca
  /// quando a empresa muda).
  void garantir() {
    final emp = Sessao.atual?.empresaId;
    if (emp == null || emp == _empresaId || _carregando) return;
    _carregar(emp);
  }

  Future<void> recarregar() async {
    final emp = Sessao.atual?.empresaId;
    if (emp != null) await _carregar(emp);
  }

  Future<void> _carregar(String emp) async {
    _carregando = true;
    try {
      final c = await Supabase.instance.client
          .from('empresa_config')
          .select('parametros')
          .eq('empresa_id', emp)
          .maybeSingle();
      _p = Map<String, dynamic>.from((c?['parametros'] as Map?) ?? const {});
      try {
        _manutencaoPropria = await Supabase.instance.client.rpc('manutencao_propria') == true;
      } catch (_) {
        _manutencaoPropria = true; // banco sem a função: mostra (como antes)
      }
      _empresaId = emp;
      notifyListeners();
    } catch (e) {
      debugPrint('Parâmetros da empresa: $e');
    } finally {
      _carregando = false;
    }
  }
}
