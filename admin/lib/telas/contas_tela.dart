import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../api.dart';
import '../widgets/comuns.dart';

/// Lista de clientes (contas), com busca e filtro de situação.
class ContasTela extends StatefulWidget {
  const ContasTela({super.key, this.situacao});

  final String? situacao;

  @override
  State<ContasTela> createState() => _ContasTelaState();
}

class _ContasTelaState extends State<ContasTela> {
  final _busca = TextEditingController();
  late String _situacao = widget.situacao ?? '';
  late Future<List<Map<String, dynamic>>> _dados = _carregar();

  Future<List<Map<String, dynamic>>> _carregar() =>
      rpcLista('admin_contas', {'p': {'busca': _busca.text, 'situacao': _situacao}});

  void _recarregar() => setState(() => _dados = _carregar());

  @override
  void didUpdateWidget(covariant ContasTela old) {
    super.didUpdateWidget(old);
    if (old.situacao != widget.situacao) {
      _situacao = widget.situacao ?? '';
      _dados = _carregar();
    }
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Clientes', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: _busca,
                decoration: const InputDecoration(labelText: 'Buscar (nome, código, CNPJ)', prefixIcon: Icon(Icons.search)),
                onSubmitted: (_) => _recarregar(),
              ),
            ),
            DropdownButton<String>(
              value: _situacao,
              onChanged: (v) {
                _situacao = v ?? '';
                _recarregar();
              },
              items: const [
                DropdownMenuItem(value: '', child: Text('Todas as situações')),
                DropdownMenuItem(value: 'teste', child: Text('Teste grátis')),
                DropdownMenuItem(value: 'ativa', child: Text('Ativa')),
                DropdownMenuItem(value: 'atrasada', child: Text('Atrasada')),
                DropdownMenuItem(value: 'cortesia', child: Text('Cortesia')),
                DropdownMenuItem(value: 'bloqueada', child: Text('Bloqueada')),
                DropdownMenuItem(value: 'cancelada', child: Text('Cancelada')),
              ],
            ),
            IconButton(onPressed: _recarregar, icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: Carregar<List<Map<String, dynamic>>>(
              futuro: _dados,
              recarregar: _recarregar,
              construir: (contas) => contas.isEmpty
                  ? const Center(child: Text('Nenhum cliente encontrado.'))
                  : Card(
                      child: ListView.separated(
                        itemCount: contas.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _Linha(contas[i]),
                      ),
                    ),
            ),
          ),
        ]),
      );
}

class _Linha extends StatelessWidget {
  const _Linha(this.c);

  final Map<String, dynamic> c;

  @override
  Widget build(BuildContext context) {
    final cortesia = c['cobrar'] == false && c['situacao'] != 'cancelada';
    final aberto = numero(c['em_aberto']);
    return ListTile(
      onTap: () => context.go('/contas/${c['conta_id']}'),
      title: Row(children: [
        Flexible(child: Text('${c['nome']}', overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Text('· ${c['codigo']}', style: const TextStyle(color: Cores.neutro)),
      ]),
      subtitle: Text([
        if ((c['cidade'] ?? '') != '') '${c['cidade']}/${c['uf'] ?? ''}',
        '${c['usuarios_ativos']} usuário(s)',
        cortesia ? 'sem cobrança' : '${moeda(c['valor_mensal'])}/mês',
        if (c['situacao'] == 'teste') 'teste até ${dataBr(c['teste_ate'])}',
        if (c['cupom'] != null) 'cupom ${c['cupom']}',
      ].join(' · ')),
      trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (aberto > 0) Text(moeda(aberto), style: const TextStyle(color: Cores.alerta, fontWeight: FontWeight.w600)),
        if (c['conta_situacao'] == 'bloqueada') const ChipSituacao('bloqueada'),
        ChipSituacao(cortesia ? 'cortesia' : '${c['situacao']}'),
        const Icon(Icons.chevron_right),
      ]),
    );
  }
}
