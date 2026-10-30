import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

/// Abre a central de tutoriais (guia 47) numa aba nova, já com o perfil do usuário.
/// A aba é aberta antes de esperar a plataforma (o navegador bloqueia janelas
/// abertas depois de uma espera) e recebe o endereço quando o link chega.
Future<void> abrirTutoriais() async {
  final aba = web.window.open('', '_blank');
  try {
    final r = await Supabase.instance.client.rpc('tutoriais_link');
    final url = (r as Map)['url'] as String;
    if (aba != null) {
      aba.location.href = url;
    } else {
      web.window.location.assign(url);
    }
  } catch (_) {
    aba?.close();
    rethrow;
  }
}
