import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../api.dart';
import '../widgets/comuns.dart';

/// Guia 52: o ServPilot como hub. Cada aplicação (Refrigeração, Equipamentos...)
/// usa a mesma base de contas, empresas, usuários, assinatura e cadastros.
class AplicacoesTela extends StatefulWidget {
  const AplicacoesTela({super.key});

  @override
  State<AplicacoesTela> createState() => _AplicacoesTelaState();
}

const _situacoes = {'ativa': 'Ativa', 'em_breve': 'Em breve', 'desativada': 'Desativada'};

class _AplicacoesTelaState extends State<AplicacoesTela> {
  late Future<List<Map<String, dynamic>>> _dados = _carregar();

  Future<List<Map<String, dynamic>>> _carregar() async => lista(await db.rpc('admin_aplicacoes'));

  void _recarregar() => setState(() => _dados = _carregar());

  Future<void> _editar([Map<String, dynamic>? a]) async {
    final codigo = TextEditingController(text: '${a?['codigo'] ?? ''}');
    final nome = TextEditingController(text: '${a?['nome'] ?? ''}');
    final curto = TextEditingController(text: '${a?['nome_curto'] ?? ''}');
    final desc = TextEditingController(text: '${a?['descricao'] ?? ''}');
    final ordem = TextEditingController(text: '${a?['ordem'] ?? 99}');
    var situacao = '${a?['situacao'] ?? 'em_breve'}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, definir) => AlertDialog(
          title: Text(a == null ? 'Nova aplicação' : 'Aplicação ${a['codigo']}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (a == null) campoTexto(codigo, 'Código', ajuda: 'Minúsculas, sem espaço (ex.: equipamentos). Não muda depois.'),
                campoTexto(nome, 'Nome'),
                campoTexto(curto, 'Nome curto (menus)'),
                campoTexto(desc, 'Descrição'),
                campoTexto(ordem, 'Ordem', teclado: TextInputType.number),
                Wrap(spacing: 8, children: [
                  for (final s in _situacoes.entries)
                    ChoiceChip(
                      label: Text(s.value),
                      selected: situacao == s.key,
                      onSelected: (_) => definir(() => situacao = s.key),
                    ),
                ]),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await rpcMapa('admin_aplicacao_salvar', {
        'p': {
          'codigo': a?['codigo'] ?? codigo.text.trim(),
          'nome': nome.text.trim(),
          'nome_curto': curto.text.trim(),
          'descricao': desc.text.trim(),
          'situacao': situacao,
          'ordem': int.tryParse(ordem.text.trim()) ?? 99,
        },
      });
      if (mounted) avisar(context, 'Aplicação salva.');
      _recarregar();
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Carregar<List<Map<String, dynamic>>>(
        futuro: _dados,
        recarregar: _recarregar,
        construir: (itens) => ListView(padding: const EdgeInsets.all(24), children: [
          Row(children: [
            Expanded(child: Text('Aplicações do hub', style: Theme.of(context).textTheme.headlineSmall)),
            FilledButton.icon(onPressed: () => _editar(), icon: const Icon(Icons.add), label: const Text('Nova aplicação')),
          ]),
          const SizedBox(height: 4),
          const Text(
            'Todas usam a mesma base: contas (grupo de empresas), empresas e filiais, usuários e papéis, assinatura e '
            'faturas, e os cadastros do núcleo (clientes, locais, contatos, colaboradores, equipes, equipamentos, '
            'produtos). Cada conta liga as aplicações que contratou (na tela do cliente). Os planos indicam a aplicação.',
            style: TextStyle(color: Cores.neutro),
          ),
          const SizedBox(height: 16),
          for (final a in itens)
            Secao(
              titulo: '${a['nome']}',
              acoes: [
                _Situacao('${a['situacao']}'),
                const SizedBox(width: 8),
                IconButton(tooltip: 'Editar', onPressed: () => _editar(a), icon: const Icon(Icons.edit_outlined)),
              ],
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Campo('Código', '${a['codigo']}'),
                Campo('Situação', _situacoes['${a['situacao']}'] ?? '${a['situacao']}'),
                Campo('Descrição', '${a['descricao'] ?? ''}'),
                Campo('Contas com a aplicação', '${a['contas']}'),
                Campo('Planos ativos', '${a['planos']}'),
              ]),
            ),
        ]),
      );
}

/// Etiqueta da situação da aplicação (ativa, em breve, desativada).
class _Situacao extends StatelessWidget {
  const _Situacao(this.situacao);

  final String situacao;

  @override
  Widget build(BuildContext context) {
    final cor = switch (situacao) { 'ativa' => Cores.sucesso, 'em_breve' => Cores.info, _ => Cores.neutro };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: .08),
        border: Border.all(color: cor.withValues(alpha: .5)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(_situacoes[situacao] ?? situacao, style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
