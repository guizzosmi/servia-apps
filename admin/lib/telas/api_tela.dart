import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';

import '../api.dart';
import '../widgets/comuns.dart';

/// Guia 53: o que a API OData permite, entidade por entidade (consultar,
/// incluir, alterar, excluir), e os parâmetros dos tokens e do limite.
class ApiTela extends StatefulWidget {
  const ApiTela({super.key});

  @override
  State<ApiTela> createState() => _ApiTelaState();
}

class _ApiTelaState extends State<ApiTela> {
  late Future<Map<String, dynamic>> _dados = rpcMapa('admin_api');
  String? _salvando;   // nome da entidade em gravação

  void _recarregar() => setState(() => _dados = rpcMapa('admin_api'));

  Future<void> _mudar(Map<String, dynamic> e, String campo, bool valor) async {
    setState(() => _salvando = '${e['nome']}');
    try {
      await rpcMapa('admin_api_entidade_salvar', {'p': {'nome': e['nome'], campo: valor}});
      if (mounted) avisar(context, '${e['nome']}: salvo. Vale em até 1 minuto.');
      _recarregar();
    } catch (err) {
      if (mounted) avisarErro(context, err);
    } finally {
      if (mounted) setState(() => _salvando = null);
    }
  }

  Future<void> _parametros(Map<String, dynamic> p) async {
    final campos = {
      'access_minutos': ('Validade do access token (minutos, 5 a 120)', TextEditingController(text: '${p['access_minutos']}')),
      'refresh_dias': ('Validade do refresh token (dias, 1 a 90)', TextEditingController(text: '${p['refresh_dias']}')),
      'limite_por_minuto': ('Limite de chamadas por minuto por credencial', TextEditingController(text: '${p['limite_por_minuto']}')),
      'pagina_padrao': ('Registros por página (sem \$top)', TextEditingController(text: '${p['pagina_padrao']}')),
      'pagina_maxima': ('Maior \$top aceito', TextEditingController(text: '${p['pagina_maxima']}')),
    };
    final ok = await dialogoForm(context, titulo: 'Parâmetros da API', campos: [
      for (final c in campos.values) campoTexto(c.$2, c.$1, teclado: TextInputType.number),
    ]);
    if (!ok) return;
    try {
      await rpcMapa('admin_api_parametros_salvar', {
        'p': {for (final c in campos.entries) c.key: int.tryParse(c.value.$2.text.trim()) ?? 0},
      });
      if (mounted) avisar(context, 'Parâmetros salvos. Valem em até 1 minuto.');
      _recarregar();
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Carregar<Map<String, dynamic>>(
        futuro: _dados,
        recarregar: _recarregar,
        construir: (d) {
          final p = mapa(d['parametros']);
          final entidades = lista(d['entidades']);
          final grupos = <String, List<Map<String, dynamic>>>{};
          for (final e in entidades) {
            grupos.putIfAbsent('${e['aplicacao_nome']}', () => []).add(e);
          }
          return ListView(padding: const EdgeInsets.all(24), children: [
            Row(children: [
              Expanded(child: Text('API (OData v4)', style: Theme.of(context).textTheme.headlineSmall)),
              OutlinedButton.icon(
                  onPressed: () => _parametros(p), icon: const Icon(Icons.tune), label: const Text('Tokens e limites')),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Desligue um método e ele deixa de valer para todas as empresas em até 1 minuto (a API responde 403). '
              'Entidades "só consulta" mudam pela entidade principal; as que gravam "pela regra" passam pelas mesmas '
              'regras do painel (ex.: incluir OS = abrir OS com agendamento) e têm as outras ações em /Acao.',
              style: TextStyle(color: Cores.neutro),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, children: [
              Indicador(rotulo: 'Credenciais ativas', valor: '${d['credenciais_ativas'] ?? 0}'),
              Indicador(rotulo: 'Chamadas em 24 h', valor: '${d['chamadas_24h'] ?? 0}'),
              Indicador(rotulo: 'Com erro em 24 h', valor: '${d['erros_24h'] ?? 0}',
                  cor: numero(d['erros_24h']) > 0 ? Cores.alerta : null),
              Indicador(rotulo: 'Access / refresh', valor: '${p['access_minutos']} min / ${p['refresh_dias']} d'),
              Indicador(rotulo: 'Limite por minuto', valor: '${p['limite_por_minuto']}'),
            ]),
            const SizedBox(height: 16),
            for (final g in grupos.entries)
              Secao(
                titulo: g.key == 'Núcleo' ? 'Núcleo do hub (todas as aplicações)' : g.key,
                child: Column(children: [
                  for (final e in g.value) _linha(e),
                ]),
              ),
          ]);
        },
      );

  Widget _linha(Map<String, dynamic> e) {
    final escrita = '${e['escrita']}';
    final podeGravar = escrita != 'leitura';
    final ocupado = _salvando != null;
    Widget chave(String rotulo, String campo, {bool habilitado = true}) => Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(rotulo, style: const TextStyle(fontSize: 11, color: Cores.neutro)),
            Switch(
              value: e[campo] == true,
              onChanged: (!habilitado || ocupado) ? null : (v) => _mudar(e, campo, v),
            ),
          ]),
        );
    final semRegra = <String>{
      if (escrita == 'regra' && e['regra_incluir'] == null) 'permite_incluir',
      if (escrita == 'regra' && e['regra_alterar'] == null) 'permite_alterar',
      if (escrita == 'regra' && e['regra_excluir'] == null) 'permite_excluir',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${e['nome']}${e['ativo'] == false ? ' (fora da API)' : ''}'),
      subtitle: Text([
        'tabela ${e['tabela']} · ${e['tipo']} · ${switch (escrita) {
          'tabela' => 'grava direto (RLS)',
          'regra' => 'grava pela regra ${e['regra']}',
          _ => 'só consulta',
        }}',
        if ('${e['descricao'] ?? ''}'.isNotEmpty) '${e['descricao']}',
      ].join('\n')),
      isThreeLine: '${e['descricao'] ?? ''}'.isNotEmpty,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        chave('GET', 'permite_consultar'),
        chave('POST', 'permite_incluir', habilitado: podeGravar && !semRegra.contains('permite_incluir')),
        chave('PATCH', 'permite_alterar', habilitado: podeGravar && !semRegra.contains('permite_alterar')),
        chave('DELETE', 'permite_excluir', habilitado: podeGravar && !semRegra.contains('permite_excluir')),
        chave('Ativa', 'ativo'),
      ]),
    );
  }
}
