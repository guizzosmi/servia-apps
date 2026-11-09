import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/acoes_atendimento.dart';
import '../core/acoes_etiqueta.dart';
import '../core/acoes_os.dart';
import '../core/consultas.dart';
import '../core/estado.dart';
import 'busca_aparelhos.dart';
import 'entrar_no_servico.dart';

void _aviso(BuildContext context, String texto) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

/// Guia 108: "Ler etiqueta" da tela Hoje (fora da OS). Lê o QR, acha o
/// aparelho no celular e: com uma OS só, e ela no meu dia, abre o atendimento
/// já no checklist do aparelho; senão, abre a ficha do aparelho com as OS em
/// aberto (ou o "Abrir OS para este aparelho").
Future<void> lerEtiquetaForaDaOs(BuildContext context) async {
  final lido = await context.push<String>('/ler-codigo');
  if (lido == null || !context.mounted) return;
  final achados = AcoesEtiqueta.aparelhos(lido);
  if (achados.isEmpty) {
    _aviso(context, 'Etiqueta não encontrada: sincronize ou confira se é desta empresa.');
    return;
  }
  final aparelho = achados.length == 1 ? achados.first : await _escolherAparelho(context, achados);
  if (aparelho == null || !context.mounted) return;
  final oss = AcoesEtiqueta.osAbertas(aparelho['id']);
  if (oss.length == 1 && oss.first.noMeuDia) {
    await atenderOsDoAparelho(context, oss.first, aparelho, lido: lido);
    return;
  }
  await context.push(Uri(path: '/aparelho/${aparelho['id']}', queryParameters: {'lido': lido}).toString());
}

/// O mesmo código em dois aparelhos (o QR de um, o código de outro): qual é?
Future<Map<String, dynamic>?> _escolherAparelho(BuildContext context, List<Map<String, dynamic>> achados) {
  final banco = EstadoApp.instancia.banco!;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Qual aparelho?'),
      children: [
        for (final e in achados)
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(e),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(rotuloAparelho(e)),
              subtitle: Text([
                banco.um('clientes', e['cliente_id'])?['nome'],
                banco.um('locais', e['local_id'])?['nome'],
                nomeDoAmbiente(ambienteDoAparelho(e['ambiente_id'])),
              ].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
            ),
          ),
      ],
    ),
  );
}

/// Atende a OS deste aparelho: a que já está no meu dia, direto; a que está
/// em outro dia, na fila ou com outra equipe, trazendo para a minha parte de
/// hoje (guia 80, com a confirmação de quem está com ela). Depois entra no
/// serviço e abre o atendimento no checklist do aparelho.
Future<void> atenderOsDoAparelho(BuildContext context, OsDoAparelho o, Map<String, dynamic> aparelho,
    {String? lido}) async {
  final banco = EstadoApp.instancia.banco!;
  var item = o.item;
  if (!o.noMeuDia) {
    final motivo = o.impedimento;
    if (motivo != null) {
      _aviso(context, motivo);
      return;
    }
    final partes = AcoesOs.partesParaAtender();
    final parte = partes.length == 1 ? partes.first : await _escolherParte(context, partes);
    if (parte == null || !context.mounted) return;
    final aberta = o.comoOsAberta;
    var confirmado = false;
    if (aberta.comOutraEquipe) {
      confirmado = await _confirmarTrazer(context, aberta);
      if (!confirmado || !context.mounted) return;
    }
    final itemId = await AcoesOs.puxar(aberta, parte: parte, confirmado: confirmado);
    if (!context.mounted) return;
    item = banco.um('partes_itens', itemId);
  }
  if (item == null) return;
  await _entrarEAbrir(context, Map<String, dynamic>.from(item), aparelho, lido: lido);
}

/// Entra no serviço (se ainda não está nele), registra o aparelho como
/// identificado pela etiqueta e abre o atendimento nele.
Future<void> _entrarEAbrir(BuildContext context, Map<String, dynamic> item, Map<String, dynamic> aparelho,
    {String? lido}) async {
  final banco = EstadoApp.instancia.banco!;
  final parte = banco.um('partes_diarias', item['parte_id']) ?? const {};
  final atdId = AcoesAtendimento.idAtendimento(item['id']);
  final estouNele = banco.participantes(atdId, soAbertos: true).any((p) => p['colaborador_id'] == AcoesAtendimento.eu);
  if (!estouNele) {
    // Parte ainda em montagem (ou encerrada): o check-in não libera; mostra o serviço.
    if (parte['status'] != 'publicada' && parte['status'] != 'em_andamento') {
      await context.push('/servico/${item['id']}');
      return;
    }
    final entrou = await entrarNoServico(context, item, abrir: false);
    if (!entrou || !context.mounted) return;
  }
  final atd = banco.um('atendimentos', atdId);
  if (atd == null) return;
  final aberto = atd['status'] == 'em_andamento' || atd['status'] == 'pausado';
  // A leitura da etiqueta fica registrada (prova de que o técnico esteve no aparelho).
  if (aberto && banco.identificacao(atdId, aparelho['id']) == null) {
    await AcoesAtendimento.identificarEquipamento(atd, aparelho,
        leitura: lido == null ? 'lista' : 'qr', valorLido: lido);
    if (!context.mounted) return;
  }
  await context.push(Uri(path: '/atendimento/$atdId', queryParameters: {'aparelho': '${aparelho['id']}'}).toString());
}

Future<Map<String, dynamic>?> _escolherParte(BuildContext context, List<Map<String, dynamic>> partes) {
  final banco = EstadoApp.instancia.banco!;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Em qual equipe?'),
      children: [
        for (final p in partes)
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(p),
            child: Text(banco.nomeEquipe(p['equipe_id'])),
          ),
      ],
    ),
  );
}

/// Guia 80: a OS está com outra equipe (ou em outro dia): trazer só confirmando.
Future<bool> _confirmarTrazer(BuildContext context, OsAberta os) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Trazer a ${os.codigo} para você?'),
      content: Text('${os.ondeEsta}. Ela sai de lá e entra no fim da sua parte de hoje. O escritório é avisado.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Trazer para mim')),
      ],
    ),
  );
  return ok == true;
}
