import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/acoes_atendimento.dart';
import '../core/acoes_mensagens.dart';
import '../core/consultas.dart';
import '../core/estado.dart';
import '../core/posicao.dart';

/// "Estou neste serviço": confere se a pessoa está em outro serviço (e
/// pergunta se sai de lá), deixa o líder escolher quem entra junto e abre
/// o atendimento (com [abrir]). O serviço que ele já fez (guia 80): entra em
/// [inicio] e sai em [fim], com quem estava junto. true = entrou.
Future<bool> entrarNoServico(BuildContext context, Map<String, dynamic> item,
    {bool abrir = true, DateTime? inicio, DateTime? fim}) async {
  final banco = EstadoApp.instancia.banco!;
  final atdId = AcoesAtendimento.idAtendimento(item['id']);
  final parte = banco.um('partes_diarias', item['parte_id']) ?? const {};

  // Já está em outro serviço? Sai de lá no mesmo instante. (O serviço que
  // ele já fez, antes daquele: aquele continua.)
  final atual = AcoesAtendimento.meuCheckin();
  final entrada = DateTime.tryParse('${atual?['entrada_em'] ?? ''}');
  final antes = inicio != null && entrada != null && entrada.isAfter(inicio);
  if (atual != null && atual['atendimento_id'] != atdId && !antes) {
    final outro = banco.um('atendimentos', atual['atendimento_id']);
    final osOutro = outro == null ? null : banco.um('ordens_servico', outro['os_id']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Você está em outro serviço'),
        content: Text('Ao entrar aqui, você sai de ${osOutro?['codigo'] ?? 'outro serviço'} agora.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Entrar aqui')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;
  }

  // O líder leva junto quem está livre (pode desmarcar alguém).
  var acompanhantes = <String>[];
  if (parte['lider_colaborador_id'] == AcoesAtendimento.eu) {
    final livres = AcoesAtendimento.membrosLivres('${parte['id']}');
    if (livres.isNotEmpty) {
      final escolha = await showModalBottomSheet<List<String>>(
        context: context,
        builder: (ctx) => _QuemEntra(livres: livres, nome: banco.nomeColaborador),
      );
      if (escolha == null || !context.mounted) return false;
      acompanhantes = escolha;
    }
  }

  // Guia 104: na manutenção de equipamento, o ponto do check-in (só agora, com o app aberto).
  Posicao? posicao;
  if (inicio == null && banco.osDo(item)?['aplicacao'] == 'equipamentos') {
    posicao = await _posicaoDoCheckin(context);
    if (!context.mounted) return false;
  }

  final id = await AcoesAtendimento.checkin(item, acompanhantes: acompanhantes, em: inicio, posicao: posicao);
  if (fim != null) {
    final quem = {AcoesAtendimento.eu, ...acompanhantes};
    for (final p in banco.participantes(id, soAbertos: true)) {
      if (quem.contains(p['colaborador_id'])) await AcoesAtendimento.checkout(p, em: fim);
    }
  }
  if (abrir && context.mounted) await context.push('/atendimento/$id');
  return true;
}

/// Lê o GPS uma vez, com um aviso na tela. Sem sinal ou sem permissão,
/// o check-in segue sem a posição (ela não trava o serviço).
Future<Posicao?> _posicaoDoCheckin(BuildContext context) async {
  final mensageiro = ScaffoldMessenger.of(context);
  mensageiro.showSnackBar(const SnackBar(
    content: Text('Marcando o ponto do check-in (GPS)...'),
    duration: Duration(seconds: 20),
  ));
  final leitura = await Gps.ler(limite: const Duration(seconds: 15));
  mensageiro.hideCurrentSnackBar();
  if (!leitura.ok) {
    mensageiro.showSnackBar(SnackBar(content: Text('Check-in sem o ponto do GPS: ${leitura.motivo}')));
  }
  return leitura.posicao;
}

/// "Estou a caminho": oferece o aviso ao cliente pelo WhatsApp (modelo da
/// empresa). true = mandou.
Future<bool> avisarACaminho(BuildContext context, Map<String, dynamic> item) async {
  final os = EstadoApp.instancia.banco!.osDo(item);
  if (os == null) return false;
  final mandou = await AcoesMensagens.mandar(
    context,
    modelo: 'a_caminho',
    titulo: 'Avisar que está a caminho',
    os: os,
    entidade: 'parte_item',
    entidadeId: '${item['id']}',
  );
  if (!mandou || !context.mounted) return mandou;
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aviso registrado na OS.')));
  return true;
}

class _QuemEntra extends StatefulWidget {
  const _QuemEntra({required this.livres, required this.nome});

  final List<String> livres;
  final String Function(Object?) nome;

  @override
  State<_QuemEntra> createState() => _QuemEntraState();
}

class _QuemEntraState extends State<_QuemEntra> {
  late final Set<String> _sel = {...widget.livres};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // Rola se a equipe for grande (a folha tem altura máxima).
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ListTile(
            title: Text('Quem entra com você?', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Membros da equipe que não estão em outro serviço.'),
          ),
          for (final c in widget.livres)
            CheckboxListTile(
              value: _sel.contains(c),
              title: Text(widget.nome(c)),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _sel.add(c);
                } else {
                  _sel.remove(c);
                }
              }),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_sel.toList()),
                child: Text(_sel.isEmpty ? 'Entrar só eu' : 'Entrar com ${_sel.length}'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
