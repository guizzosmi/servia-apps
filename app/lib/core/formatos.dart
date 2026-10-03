import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

/// Nome e cor de cada status (mesmos códigos do banco).
class Rotulo {
  const Rotulo(this.texto, this.cor);
  final String texto;
  final Color cor;
}

const statusItem = {
  'programado': Rotulo('Programado', Cores.info),
  'em_deslocamento': Rotulo('A caminho', Cores.andamento),
  'em_atendimento': Rotulo('Em atendimento', Cores.andamento),
  'pausado': Rotulo('Pausado', Cores.alerta),
  'concluido': Rotulo('Concluído', Cores.sucesso),
  'nao_realizado': Rotulo('Não realizado', Cores.erro),
  'removido': Rotulo('Retirado', Cores.neutro),
};

const statusParte = {
  'rascunho': Rotulo('Rascunho', Cores.neutro),
  'publicada': Rotulo('Publicada', Cores.info),
  'em_andamento': Rotulo('Em andamento', Cores.andamento),
  'encerrada': Rotulo('Encerrada', Cores.sucesso),
};

const prioridades = {
  'urgente': Rotulo('Urgente', Cores.erro),
  'alta': Rotulo('Alta', Cores.alerta),
  'media': Rotulo('Média', Cores.info),
  'baixa': Rotulo('Baixa', Cores.neutro),
};

const tiposAgendamento = {
  'visita_tecnica': 'Visita técnica',
  'analise': 'Análise',
  'reparo': 'Reparo',
  'retorno': 'Retorno',
  'preventiva': 'Preventiva',
  'retirada': 'Retirada',
  'entrega': 'Entrega',
  'outro': 'Outro',
};

const motivosNaoRealizado = {
  'cliente_ausente': 'Cliente ausente',
  'falta_peca': 'Falta de peça',
  'aguardando_orcamento': 'Aguardando orçamento',
  'tempo': 'Faltou tempo',
  'clima': 'Clima',
  'outro': 'Outro',
};

/// Número da OS; a aberta no app fica "OS nova" até a plataforma numerar.
String codigoOs(Map? os) => os == null ? '' : '${os['codigo'] ?? 'OS nova'}';

/// Nome das operações da fila, para a tela de sincronização.
const nomesOperacoes = {
  'os_abrir': 'Abrir OS',
  'cadastro_app': 'Cadastro (equipamento ou contato)',
  'mensagem': 'Mensagem ao cliente',
  'link_app': 'Link para o cliente',
  'item_status': 'Andamento do serviço',
  'checkin': 'Check-in',
  'checkout': 'Saída do serviço',
  'atendimento_salvar': 'Relato',
  'equipamento_identificado': 'Equipamento identificado',
  'foto_registrada': 'Foto',
  'medicao_salvar': 'Medição',
  'fluido_salvar': 'Fluido refrigerante',
  'item_os_salvar': 'Item usado',
  'atendimento_concluir': 'Concluir atendimento',
  'atendimento_nao_realizado': 'Não realizado',
  'orcamento_app': 'Orçamento',
  'orcamento_assinar': 'Assinatura do orçamento',
  'aceite_conclusao': 'Assinatura da conclusão',
  'checklist_marcar': 'Checklist da preventiva',
};

const statusOrcamento = {
  'rascunho': Rotulo('Rascunho (gestor)', Cores.neutro),
  'enviado': Rotulo('Aguardando o cliente', Cores.alerta),
  'aprovado': Rotulo('Aprovado', Cores.sucesso),
  'reprovado': Rotulo('Recusado', Cores.erro),
  'expirado': Rotulo('Vencido', Cores.neutro),
  'substituido': Rotulo('Substituído', Cores.neutro),
  'cancelado': Rotulo('Cancelado', Cores.neutro),
};

/// 1234.5 -> 'R\$ 1.234,50'
String dinheiro(Object? v) {
  final n = (v is num ? v : num.tryParse('${v ?? ''}')) ?? 0;
  final negativo = n < 0;
  final partes = n.abs().toStringAsFixed(2).split('.');
  final inteiro = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${negativo ? '- ' : ''}R\$ $inteiro,${partes[1]}';
}

/// Número com vírgula, sem casas à toa: 2 -> '2', 1.5 -> '1,5'.
String numeroBr(Object? v) {
  final n = v is num ? v : num.tryParse('${v ?? ''}');
  if (n == null) return '${v ?? ''}';
  return (n == n.roundToDouble() ? n.toInt().toString() : n.toString()).replaceAll('.', ',');
}

/// Arredonda em centavos (como o banco).
num centavos(num v) => (v * 100).round() / 100;

String _dd(int n) => n.toString().padLeft(2, '0');

const _diasDaSemana = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];

/// '2026-11-05' -> '05/11/2026'
String dataBr(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  if (d == null) return '';
  return '${_dd(d.day)}/${_dd(d.month)}/${d.year}';
}

/// '2026-11-05' -> 'quinta, 05/11'
String dataComDia(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${_diasDaSemana[d.weekday - 1]}, ${_dd(d.day)}/${_dd(d.month)}';
}

/// Data e hora local: '05/11/2026 14:30'
String dataHoraBr(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
  if (d == null) return '';
  return '${_dd(d.day)}/${_dd(d.month)}/${d.year} ${_dd(d.hour)}:${_dd(d.minute)}';
}

/// Hora local de um horário do banco: '14:30'
String horaDe(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
  if (d == null) return '';
  return '${_dd(d.hour)}:${_dd(d.minute)}';
}

/// '08:00:00' -> '08:00'
String horaCurta(Object? v) {
  final s = '${v ?? ''}';
  return s.length >= 5 ? s.substring(0, 5) : s;
}

/// Janela de horário: '08:00–12:00', 'a partir de 08:00' ou ''.
String janela(Object? inicio, Object? fim) {
  final i = horaCurta(inicio), f = horaCurta(fim);
  if (i.isNotEmpty && f.isNotEmpty) return '$i–$f';
  if (i.isNotEmpty) return 'a partir de $i';
  if (f.isNotEmpty) return 'até $f';
  return '';
}

/// Data no formato do banco (aaaa-mm-dd).
String dataIso(DateTime d) => '${d.year}-${_dd(d.month)}-${_dd(d.day)}';

/// Soma dias a uma data do banco ('2026-11-05' + 1 = '2026-11-06').
String somarDias(String iso, int dias) {
  final d = DateTime.parse(iso);
  return dataIso(DateTime(d.year, d.month, d.day + dias));
}

/// "há 5 min", "há 2 h", "ontem 14:30"...
String haQuanto(DateTime? quando, {DateTime? agora}) {
  if (quando == null) return 'nunca';
  final a = agora ?? DateTime.now();
  final dif = a.difference(quando);
  if (dif.inSeconds < 60) return 'agora há pouco';
  if (dif.inMinutes < 60) return 'há ${dif.inMinutes} min';
  if (dif.inHours < 24) return 'há ${dif.inHours} h';
  return dataHoraBr(quando.toIso8601String());
}
