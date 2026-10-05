import 'package:flutter/material.dart';

import '../servicos/status.dart';

/// O que está sendo arrastado no quadro.
sealed class Arrasto {
  const Arrasto();
}

/// Um cartão da fila (agendamento pendente).
class ArrastoFila extends Arrasto {
  const ArrastoFila(this.ag);
  final Map<String, dynamic> ag;
}

/// Um serviço que já está na coluna de uma equipe.
class ArrastoItem extends Arrasto {
  const ArrastoItem(this.item);
  final Map<String, dynamic> item;
  String get id => item['id'] as String;
  String get parteId => item['parte_id'] as String;
}

/// Uma pessoa da composição de uma equipe.
class ArrastoPessoa extends Arrasto {
  const ArrastoPessoa({required this.colaboradorId, required this.parteId, required this.nome});
  final String colaboradorId;
  final String parteId;
  final String nome;
}

/// Uma coluna do quadro: a equipe e, se já existe, a parte do dia.
class ColunaQuadro {
  ColunaQuadro({
    required this.equipe,
    this.parte,
    this.itens = const [],
    this.composicao = const [],
  });

  final Map<String, dynamic> equipe;
  final Map<String, dynamic>? parte;

  /// Serviços da parte (sem os removidos), na ordem.
  final List<Map<String, dynamic>> itens;

  /// Composição do dia, incluindo quem já saiu (saida_em preenchida).
  final List<Map<String, dynamic>> composicao;

  String get equipeId => equipe['id'] as String;
  String get nome => (equipe['nome'] ?? '') as String;
  String? get parteId => parte?['id'] as String?;
  String? get status => parte?['status'] as String?;
  bool get rascunho => status == 'rascunho';
  bool get encerrada => status == 'encerrada';

  /// Publicada ou em andamento: falta encerrar o dia.
  bool get semFechar => status == 'publicada' || status == 'em_andamento';

  /// Dá para mexer (programar, mover, compor)? Sem parte também: ela é aberta na hora.
  bool get aceitaMudancas => !encerrada;

  /// Quem está na equipe agora.
  List<Map<String, dynamic>> get presentes => composicao.where((c) => c['saida_em'] == null).toList();
}

/// Serviço ainda aberto (conta para "a fazer" e para o encerramento).
bool itemAberto(Map item) =>
    const {'programado', 'em_deslocamento', 'em_atendimento', 'pausado'}.contains(item['status']);

/// Próximos status possíveis de um item (mesma regra do banco, _item_transicao_ok).
List<String> proximosStatus(String? atual) => switch (atual) {
      'programado' => ['em_deslocamento', 'em_atendimento', 'nao_realizado'],
      'em_deslocamento' => ['em_atendimento', 'programado', 'nao_realizado'],
      'em_atendimento' => ['pausado', 'concluido', 'nao_realizado'],
      'pausado' => ['em_atendimento', 'nao_realizado'],
      _ => const [],
    };

/// Texto do menu para ir a um status.
String acaoDoStatus(String status) => switch (status) {
      'em_deslocamento' => 'A caminho',
      'em_atendimento' => 'Em atendimento',
      'pausado' => 'Pausar',
      'concluido' => 'Concluído',
      'nao_realizado' => 'Não realizado...',
      'programado' => 'Voltar para programado',
      _ => statusItem[status]?.texto ?? status,
    };

/// O serviço passou do fim da janela e ainda não começou?
bool itemAtrasado(Map item, String? dataParte, DateTime agora) {
  if (!const {'programado', 'em_deslocamento'}.contains(item['status'])) return false;
  final dia = DateTime.tryParse(dataParte ?? '');
  if (dia == null) return false;
  final ag = item['agendamentos'] as Map? ?? const {};
  final fim = horaCurta(ag['janela_fim']);
  var limite = DateTime(dia.year, dia.month, dia.day, 23, 59);
  if (fim.length == 5) {
    limite = DateTime(dia.year, dia.month, dia.day, int.parse(fim.substring(0, 2)), int.parse(fim.substring(3, 5)));
  }
  return agora.isAfter(limite);
}

/// Hora local curta de um timestamp do banco ('13:05').
String horaDe(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
  if (d == null) return '';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Entrou depois do começo do dia? (no rascunho todos entram 00:00)
bool entrouDuranteODia(Map comp) {
  final d = DateTime.tryParse('${comp['entrada_em'] ?? ''}')?.toLocal();
  return d != null && (d.hour != 0 || d.minute != 0);
}

/// Borda tracejada (coluna em rascunho).
class BordaTracejada extends CustomPainter {
  const BordaTracejada({required this.cor, this.raio = 14});
  final Color cor;
  final double raio;

  @override
  void paint(Canvas canvas, Size size) {
    final tinta = Paint()
      ..color = cor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final caminho = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(raio)));
    for (final m in caminho.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 7), tinta);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(BordaTracejada oldDelegate) => oldDelegate.cor != cor || oldDelegate.raio != raio;
}
