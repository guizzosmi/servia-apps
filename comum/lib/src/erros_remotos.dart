import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Envia para a plataforma (tabela erros_app) os erros inesperados do app e
/// do painel (guia 40). Só a mensagem técnica e a pilha, cortadas; repetidos
/// na mesma sessão vão uma vez só, e no máximo 20 por sessão.
class ErrosRemotos {
  ErrosRemotos._();

  static String _origem = 'app';
  static String _versao = '';
  static String _plataforma = '';
  static final _enviados = <String>{};

  /// Liga o registro. Chame logo depois do Supabase.initialize.
  static void ligar({required String origem, required String versao, required String plataforma}) {
    _origem = origem;
    _versao = versao;
    _plataforma = plataforma;
    final anterior = FlutterError.onError;
    FlutterError.onError = (detalhes) {
      anterior?.call(detalhes);
      registrar(detalhes.exception, detalhes.stack, onde: detalhes.library ?? detalhes.context?.toDescription());
    };
    PlatformDispatcher.instance.onError = (erro, pilha) {
      registrar(erro, pilha, onde: 'assíncrono');
      return false; // o comportamento padrão continua (log no console)
    };
  }

  /// Registra um erro capturado (também dá para chamar à mão num catch).
  static void registrar(Object erro, StackTrace? pilha, {String? onde}) {
    final mensagem = '$erro';
    final chave = '${onde ?? ''}|$mensagem';
    if (_enviados.length >= 20 || !_enviados.add(chave)) return;
    if (Supabase.instance.client.auth.currentUser == null) return;
    unawaited(() async {
      try {
        await Supabase.instance.client.rpc('registrar_erro', params: {
          'p': {
            'origem': _origem,
            'versao': _versao,
            'plataforma': _plataforma,
            'onde': onde,
            'mensagem': mensagem.length > 1000 ? mensagem.substring(0, 1000) : mensagem,
            'pilha': pilha?.toString().split('\n').take(30).join('\n'),
          }
        });
      } catch (_) {
        // Sem internet ou sem sessão: o erro fica só no console.
      }
    }());
  }
}
