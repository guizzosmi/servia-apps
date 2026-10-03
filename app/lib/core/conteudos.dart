import 'acoes_orcamento.dart';
import 'consultas.dart';
import 'estado.dart';
import 'formatos.dart';
import 'resumo.dart';

/// Monta o que o cliente vê e assina (orçamento ou recibo da conclusão),
/// a partir do banco do aparelho.
class Conteudos {
  Conteudos._();

  static Map<String, dynamic>? _um(String tabela, Object? id) => EstadoApp.instancia.banco!.um(tabela, id);

  static String _endereco(Map<String, dynamic>? l) {
    if (l == null) return '';
    final rua = [l['logradouro'], l['numero']].where((x) => x != null && '$x'.isNotEmpty).join(', ');
    final cidade = [l['cidade'], l['uf']].where((x) => x != null && '$x'.isNotEmpty).join('/');
    return [l['nome'], rua, l['bairro'], cidade].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
  }

  /// Cliente, local, contato e OS (comuns aos dois documentos).
  static List<(String, String)> _cabecalho(Map<String, dynamic> atd, {Object? contatoId, String? aprovadorNome}) {
    final banco = EstadoApp.instancia.banco!;
    final os = _um('ordens_servico', atd['os_id']) ?? const {};
    final contato = _um('contatos', contatoId);
    final equipamentos = banco.equipamentosDoAtendimento(atd);
    return [
      ('Cliente', '${_um('clientes', os['cliente_id'])?['nome'] ?? ''}'),
      ('Local', _endereco(_um('locais', os['local_id']))),
      if (contato != null) ('Contato', '${contato['nome']}'),
      if (contato == null && (aprovadorNome ?? '').trim().isNotEmpty) ('Quem aprova', aprovadorNome!.trim()),
      ('Ordem de serviço', codigoOs(os)),
      if (equipamentos.isNotEmpty)
        ('Equipamentos', equipamentos.map((e) => [e['codigo'], e['descricao']].where((x) => x != null).join(' ')).join('; ')),
    ];
  }

  static List<(String, String)> _totais(List<LinhaResumo> itens) {
    final bruto = itens.fold<num>(0, (s, i) => s + centavos((i.total ?? 0) + (i.desconto ?? 0)));
    final desconto = itens.fold<num>(0, (s, i) => s + (i.desconto ?? 0));
    final total = itens.fold<num>(0, (s, i) => s + (i.total ?? 0));
    return [
      if (desconto > 0) ('Subtotal', dinheiro(bruto)),
      if (desconto > 0) ('Descontos', '- ${dinheiro(desconto)}'),
      ('Total', dinheiro(total)),
    ];
  }

  /// Orçamento montado agora no app (ainda sem número: ele vem da plataforma).
  static ConteudoResumo orcamentoNovo({
    required Map<String, dynamic> atd,
    required String diagnostico,
    required Object? contatoId,
    String? aprovadorNome,
    required List<ItemOrcamento> itens,
    required num descontoPct,
  }) {
    final cfg = AcoesOrcamento.config;
    final linhas = [
      for (final i in itens)
        LinhaResumo(
          descricao: i.descricao,
          quantidade: '${numeroBr(i.quantidade)} ${i.unidade}',
          unitario: i.preco,
          desconto: i.desconto(descontoPct),
          total: i.total(descontoPct),
        ),
    ];
    final hoje = EstadoApp.instancia.sync!.hoje;
    return ConteudoResumo(
      titulo: 'ORÇAMENTO',
      subtitulo: 'feito no local · ${dataBr(hoje)}',
      empresa: AcoesOrcamento.empresa,
      campos: [
        ..._cabecalho(atd, contatoId: contatoId, aprovadorNome: aprovadorNome),
        ('Validade', 'até ${dataBr(somarDias(hoje, cfg.validadeDias))}'),
      ],
      blocos: [('Diagnóstico', diagnostico)],
      itens: linhas,
      comValores: true,
      totais: _totais(linhas),
      termo: cfg.termo ?? termoPadrao,
    );
  }

  /// Orçamento que o gestor enviou (como está no aparelho).
  static ConteudoResumo orcamentoEnviado(Map<String, dynamic> orc, Map<String, dynamic> atd) {
    final linhas = [
      for (final i in AcoesOrcamento.itensDe(orc['id']))
        LinhaResumo(
          descricao: '${i['descricao']}',
          quantidade: '${numeroBr(i['quantidade'])} ${i['unidade'] ?? 'un'}',
          unitario: num.tryParse('${i['preco_unitario']}') ?? 0,
          desconto: num.tryParse('${i['desconto']}') ?? 0,
          total: num.tryParse('${i['total']}') ?? 0,
        ),
    ];
    return ConteudoResumo(
      titulo: 'ORÇAMENTO',
      subtitulo: '${AcoesOrcamento.codigo(orc)} · ${dataBr(EstadoApp.instancia.sync!.hoje)}',
      empresa: AcoesOrcamento.empresa,
      campos: [
        ..._cabecalho(atd, contatoId: orc['contato_id']),
        ('Validade', orc['validade_ate'] == null ? '' : 'até ${dataBr(orc['validade_ate'])}'),
        ('Prazo de execução', orc['prazo_execucao_dias'] == null ? '' : '${orc['prazo_execucao_dias']} dia(s) após a aprovação'),
        ('Pagamento', '${orc['condicoes_pagamento'] ?? ''}'),
      ],
      blocos: [('Diagnóstico', '${orc['diagnostico'] ?? ''}'), ('Observações', '${orc['observacoes'] ?? ''}')],
      itens: linhas,
      comValores: true,
      totais: _totais(linhas),
      termo: AcoesOrcamento.config.termo ?? termoPadrao,
    );
  }

  /// Recibo da conclusão do atendimento: o que foi feito, sem valores.
  static ConteudoResumo conclusao(Map<String, dynamic> atd) {
    final banco = EstadoApp.instancia.banco!;
    final nomes = <String>{
      for (final p in banco.participantes(atd['id'])) banco.nomeColaborador(p['colaborador_id']),
    };
    final itens = banco.doAtendimento('os_itens', atd['id'])
      ..sort((a, b) => '${a['descricao']}'.compareTo('${b['descricao']}'));
    return ConteudoResumo(
      titulo: 'RECIBO DE SERVIÇO',
      subtitulo: '${codigoOs(_um('ordens_servico', atd['os_id']))} · ${dataBr(EstadoApp.instancia.sync!.hoje)}',
      empresa: AcoesOrcamento.empresa,
      campos: [
        ..._cabecalho(atd),
        ('Equipe', nomes.join(', ')),
      ],
      blocos: [
        ('Problema', '${atd['problema_identificado'] ?? ''}'),
        ('Causa', '${atd['causa'] ?? ''}'),
        ('Solução', '${atd['solucao'] ?? ''}'),
        ('Observações', '${atd['observacoes'] ?? ''}'),
      ],
      itens: [
        for (final i in itens)
          LinhaResumo(descricao: '${i['descricao']}', quantidade: '${numeroBr(i['quantidade'])} ${i['unidade'] ?? ''}'.trim()),
      ],
      termo: declaracaoConclusao,
    );
  }
}
