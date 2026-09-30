import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/status.dart';
import 'status_chip.dart';

/// Colunas lidas para a fila (usadas também no quadro da parte diária).
const selectFila = 'id, os_id, tipo, status, data_prevista, janela_inicio, janela_fim, duracao_estimada_min, '
    'prioridade, orientacoes, tentativas, ultimo_motivo, motivo_suspensao, criado_em, '
    'ordens_servico(codigo, problema_relatado, garantia_status, requer_orcamento, '
    'clientes(nome), locais(nome, cidade, regiao))';

/// Agendamentos na fila (pendentes) e, se pedido, os suspensos.
/// Ordem: prioridade (urgente primeiro), data desejada, mais antigos.
Future<List<Map<String, dynamic>>> carregarFila({bool comSuspensos = false}) async {
  final dados = await Supabase.instance.client
      .from('agendamentos')
      .select(selectFila)
      .inFilter('status', comSuspensos ? ['pendente', 'suspenso'] : ['pendente'])
      .isFilter('excluido_em', null)
      .limit(500);
  dados.sort(compararFila);
  return dados;
}

int compararFila(Map<String, dynamic> a, Map<String, dynamic> b) {
  final p = pesoPrioridade(a['prioridade'] as String?).compareTo(pesoPrioridade(b['prioridade'] as String?));
  if (p != 0) return p;
  final da = a['data_prevista'] as String?, db = b['data_prevista'] as String?;
  if (da != db) {
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }
  return '${a['criado_em']}'.compareTo('${b['criado_em']}');
}

/// Texto que a busca da fila procura (código, cliente, local, cidade, região, problema).
String textoDeBuscaFila(Map<String, dynamic> a) {
  final os = a['ordens_servico'] as Map? ?? const {};
  final local = os['locais'] as Map? ?? const {};
  return [
    os['codigo'],
    (os['clientes'] as Map?)?['nome'],
    local['nome'],
    local['cidade'],
    local['regiao'],
    os['problema_relatado'],
  ].where((x) => x != null).join(' ').toLowerCase();
}

/// Cartão de um agendamento da fila.
class CartaoFila extends StatelessWidget {
  const CartaoFila({super.key, required this.ag, this.aoTocar, this.compacto = false, this.acoes});

  final Map<String, dynamic> ag;
  final VoidCallback? aoTocar;
  final bool compacto;

  /// Botões extras (ex.: menu de ações), à direita do título.
  final Widget? acoes;

  @override
  Widget build(BuildContext context) {
    final os = ag['ordens_servico'] as Map? ?? const {};
    final local = os['locais'] as Map? ?? const {};
    final cliente = (os['clientes'] as Map?)?['nome'] ?? '';
    final quando = [
      if (ag['data_prevista'] != null) dataBr(ag['data_prevista']),
      if (janela(ag['janela_inicio'], ag['janela_fim']).isNotEmpty) janela(ag['janela_inicio'], ag['janela_fim']),
      if (ag['duracao_estimada_min'] != null) '${ag['duracao_estimada_min']} min',
    ].join(' · ');
    final onde = [local['nome'], local['cidade'], local['regiao']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
    final suspenso = ag['status'] == 'suspenso';
    final tentativas = (ag['tentativas'] ?? 0) as int;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: suspenso ? Cores.alerta : Cores.linha),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: aoTocar,
        child: Padding(
          padding: EdgeInsets.all(compacto ? 10 : 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${os['codigo'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              StatusChip(ag['prioridade'] as String?, prioridades, compacto: true),
              if (os['garantia_status'] == 'sugerida' || os['garantia_status'] == 'confirmada')
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Tooltip(
                      message: 'Retorno em garantia',
                      child: Icon(Icons.verified_user_outlined, size: 16, color: Cores.alerta)),
                ),
              const Spacer(),
              Text(tiposAgendamento[ag['tipo']] ?? '', style: const TextStyle(fontSize: 12, color: Cores.neutro)),
              if (acoes != null) acoes!,
            ]),
            const SizedBox(height: 4),
            Text('$cliente', style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            if (onde.isNotEmpty)
              Text(onde, style: const TextStyle(fontSize: 12, color: Cores.neutro), overflow: TextOverflow.ellipsis),
            if (!compacto && (os['problema_relatado'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${os['problema_relatado']}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              ),
            if (quando.isNotEmpty || tentativas > 0 || suspenso)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 8, children: [
                  if (quando.isNotEmpty)
                    Text(quando, style: const TextStyle(fontSize: 12, color: Cores.indigo500)),
                  if (tentativas > 0)
                    Text('$tentativas tentativa(s)'
                        '${ag['ultimo_motivo'] != null ? ': ${motivosNaoRealizado[ag['ultimo_motivo']] ?? ag['ultimo_motivo']}' : ''}',
                        style: const TextStyle(fontSize: 12, color: Cores.alerta)),
                  if (suspenso)
                    Text('Suspenso: ${motivosSuspensao[ag['motivo_suspensao']] ?? ''}',
                        style: const TextStyle(fontSize: 12, color: Cores.alerta, fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
