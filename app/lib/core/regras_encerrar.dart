/// O gestor encerra a OS pelo app (guia 111): quando a opção liga e o que
/// acontece. Dart puro (testável sem Flutter). A plataforma confere tudo de
/// novo com a regra do "Concluir OS" do painel (regra_os).
library;

/// Por que não dá para encerrar a OS agora (null = dá): outra visita dela na
/// agenda (programada ou em andamento), que a regra do painel não deixa.
String? bloqueioDoEncerramento(List<Map> naAgenda) {
  if (naAgenda.isEmpty) return null;
  final d = '${naAgenda.first['data'] ?? ''}';
  final dia = d.length >= 10 ? ' (dia ${d.substring(8, 10)}/${d.substring(5, 7)})' : '';
  return 'Esta OS tem outra visita na agenda$dia: encerre a OS depois dela.';
}

/// Ligada por padrão quando não há outra visita em aberto (nem na fila).
bool encerrarPorPadrao({required bool bloqueado, required int naFila}) => !bloqueado && naFila == 0;

/// O que acontece ao encerrar (o mesmo do "Concluir OS" do painel).
String textoDoEncerramento({required int naFila}) =>
    'A OS fica concluída: a garantia começa a contar hoje e ela vai para o "A cobrar" do financeiro, '
    'como no "Concluir OS" do painel.${naFila > 0 ? ' A visita que ainda estava na fila é cancelada.' : ''}';
