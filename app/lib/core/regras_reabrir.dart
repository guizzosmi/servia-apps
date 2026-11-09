/// Reabrir OS pelo app (guia 109): quem vê o botão e o que acontece. Dart puro
/// (testável sem Flutter). A plataforma confere tudo de novo (regra_os).
library;

import 'dart:convert';

/// Papéis do usuário no token da sessão (app_metadata.papeis); null = token ilegível.
List<String>? papeisDoToken(String token) {
  try {
    final partes = token.split('.');
    if (partes.length != 3) return null;
    final dados = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1])))) as Map<String, dynamic>;
    final papeis = (dados['app_metadata'] as Map?)?['papeis'];
    return papeis is List ? [for (final p in papeis) '$p'] : const [];
  } catch (_) {
    return null;
  }
}

/// Gestor (ou administrador), como o tem_papel('gestor') da plataforma.
bool ehGestor(List<String>? papeis) => papeis != null && (papeis.contains('gestor') || papeis.contains('admin'));

/// O botão "Reabrir OS" aparece? Serviço concluído, OS que não foi cancelada
/// nem é a do aparelho no ciclo do plano (essa não reabre: desmarca-se o item
/// no lote), e quem vê é o gestor ou o líder da parte daquele serviço.
bool podeReabrirServico({
  required Object? itemStatus,
  required Object? osStatus,
  required Object? planoPapel,
  required bool gestor,
  required bool lider,
}) =>
    itemStatus == 'concluido' && osStatus != 'cancelada' && planoPapel != 'ciclo' && (gestor || lider);

/// O que acontece, para a confirmação. [equipeHoje]: a equipe da parte de
/// hoje para onde o serviço volta (null = vai para a fila do escritório; no
/// modo simples, guia 62, a fila é o "Para agendar" da Agenda).
String textoDaReabertura({required bool osConcluida, String? equipeHoje, bool modoSimples = false}) {
  final os = osConcluida
      ? 'A OS volta para "em andamento" e a garantia é zerada (se já foi cobrada, a cobrança não muda). '
      : '';
  final destino = equipeHoje != null
      ? 'O serviço volta para o fim da parte de hoje da $equipeHoje, para refazer.'
      : modoSimples
          ? 'Uma visita nova vai para "Para agendar" (Agenda), onde o escritório escolhe o dia.'
          : 'Uma visita nova vai para a fila do escritório, que escolhe o dia e a equipe.';
  return '$os$destino O escritório vê quem reabriu e o motivo.';
}
