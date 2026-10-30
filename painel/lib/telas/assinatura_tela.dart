import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

import '../servicos/funcoes.dart';
import '../widgets/aviso_plano.dart';

/// Plano e consumo (guia 44): situação da assinatura, o que já foi usado no ciclo,
/// usuários que contam, pacotes extras, cupom e faturas com o botão de pagar.
class AssinaturaTela extends StatefulWidget {
  const AssinaturaTela({super.key, this.pagamento});

  /// Volta do Mercado Pago: ok, pendente ou falhou.
  final String? pagamento;

  @override
  State<AssinaturaTela> createState() => _AssinaturaTelaState();
}

class _AssinaturaTelaState extends State<AssinaturaTela> {
  late Future<Map<String, dynamic>> _dados = _carregar();
  bool _ocupado = false;

  Future<Map<String, dynamic>> _carregar() async {
    final r = await Supabase.instance.client.rpc('consumo_atual');
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  void _recarregar() {
    AvisoPlano.esquecer();
    setState(() => _dados = _carregar());
  }

  @override
  void initState() {
    super.initState();
    final p = widget.pagamento;
    if (p != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _avisar(switch (p) {
          'ok' => 'Pagamento aprovado. Pode levar alguns minutos para a fatura aparecer como paga.',
          'pendente' => 'Pagamento em processamento (boleto ou Pix ainda não compensado).',
          _ => 'O pagamento não foi concluído. Tente de novo ou escolha outra forma.',
        });
        if (p == 'ok') Future.delayed(const Duration(seconds: 6), () { if (mounted) _recarregar(); });
      });
    }
  }

  void _avisar(String texto, {bool erro = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));

  Future<void> _acao(Future<void> Function() f) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await f();
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Vai para o Mercado Pago na mesma aba (ele volta para cá no fim).
  void _irPara(String link) => web.window.location.assign(link);

  Future<void> _pagar(String faturaId) => _acao(() async {
        final r = await chamarFuncao('cobranca', {'acao': 'pagar', 'fatura_id': faturaId});
        _irPara(r['link'] as String);
      });

  Future<void> _conferir(String faturaId) => _acao(() async {
        final r = await chamarFuncao('cobranca', {'acao': 'conferir', 'fatura_id': faturaId});
        if (!mounted) return;
        _avisar(r['situacao'] == 'paga'
            ? 'Pagamento encontrado: fatura paga.'
            : 'O Mercado Pago ainda não confirmou. Pix cai em minutos; boleto, em até 2 dias úteis.');
        if (mounted) _recarregar();
      });

  Future<void> _comprar(Map<String, dynamic> pacote) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Comprar ${pacote['nome']}?'),
        content: Text('${_moeda(pacote['valor'])}, pago agora pelo Mercado Pago (Pix, boleto ou cartão). '
            'Vale até o fim do ciclo; comprado na última semana, vale também o ciclo seguinte.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Ir para o pagamento')),
        ],
      ),
    );
    if (ok != true) return;
    await _acao(() async {
      final r = await chamarFuncao('cobranca', {'acao': 'comprar_pacote', 'pacote': pacote['codigo']});
      if (r['pago'] == true) {
        if (mounted) _avisar('Pacote liberado (cupom de 100%).');
        if (mounted) _recarregar();
      } else {
        _irPara(r['link'] as String);
      }
    });
  }

  Future<void> _cupom() async {
    final codigo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usar um cupom'),
        content: TextField(controller: codigo, decoration: const InputDecoration(labelText: 'Código do cupom'),
            textCapitalization: TextCapitalization.characters),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Aplicar')),
        ],
      ),
    );
    if (ok != true) return;
    await _acao(() async {
      final r = await Supabase.instance.client.rpc('cupom_aplicar', params: {'p_codigo': codigo.text.trim()});
      if (mounted) _avisar('Cupom ${(r as Map)['codigo']}: ${r['resumo']}. Vale nas próximas faturas.');
      if (mounted) _recarregar();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _dados,
        builder: (context, s) {
          if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (s.hasError) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(mensagemDeErro(s.error!)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _recarregar, child: const Text('Tentar de novo')),
            ]));
          }
          final d = s.data!;
          if (d['sem_assinatura'] == true) {
            return const Center(child: Text('Esta conta ainda não tem assinatura. Fale com o suporte do ServPilot.'));
          }
          final financeiro = Sessao.atual?.tem(Papel.financeiro) ?? false;
          return ListView(padding: const EdgeInsets.all(24), children: [
            Row(children: [
              Expanded(child: Text('Plano e consumo', style: Theme.of(context).textTheme.headlineSmall)),
              if (financeiro) TextButton.icon(onPressed: _cupom, icon: const Icon(Icons.local_offer_outlined), label: const Text('Tenho um cupom')),
              IconButton(onPressed: _recarregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
            ]),
            const SizedBox(height: 12),
            _Situacao(d),
            _Consumo(d),
            _Pacotes(lista(d['pacotes']), aoComprar: _ocupado ? null : _comprar),
            _Usuarios(d),
            _Faturas(lista(d['faturas']), aoPagar: _ocupado ? null : _pagar, aoConferir: _ocupado ? null : _conferir),
            const SizedBox(height: 8),
            const Text('Preços, regras e perguntas frequentes: servpilot.com.br/precos', style: TextStyle(color: Cores.neutro)),
          ]);
        },
      );
}

// ---------------------------------------------------------------- partes

List<Map<String, dynamic>> lista(dynamic v) =>
    v is List ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];
num _n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;

String _moeda(dynamic v) {
  final partes = _n(v).toDouble().toStringAsFixed(2).split('.');
  final inteiro = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return 'R\$ $inteiro,${partes[1]}';
}

String _data(dynamic v) {
  final d = DateTime.tryParse('${v ?? ''}');
  if (d == null) return '';
  final l = '$v'.length > 10 ? d.toLocal() : d;
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.titulo, required this.child});

  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );
}

class _Situacao extends StatelessWidget {
  const _Situacao(this.d);

  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    final p = Map<String, dynamic>.from(d['plano'] as Map);
    final c = Map<String, dynamic>.from(d['consumo'] as Map);
    final est = Map<String, dynamic>.from(d['estimativa'] as Map);
    final (texto, cor) = switch (d['situacao']) {
      _ when d['cobrar'] == false => ('Cortesia: sem mensalidade', Cores.andamento),
      'teste' => ('Teste grátis: faltam ${d['dias_teste_restantes']} dia(s), até ${_data(d['teste_ate'])}', Cores.info),
      'atrasada' => ('Fatura em atraso', Cores.erro),
      'cancelada' => ('Assinatura cancelada', Cores.neutro),
      _ => ('Assinatura ativa', Cores.sucesso),
    };
    return _Cartao(
      titulo: 'Plano ${p['nome']}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(texto, style: TextStyle(color: cor, fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 8),
        Text('${_moeda(p['valor_mensal'])}/mês com ${p['usuarios_incluidos']} usuários, ${p['minutos_incluidos']} minutos de IA '
            'e ${p['mensagens_incluidas']} mensagens de WhatsApp. Usuário a mais: ${_moeda(p['valor_usuario_extra'])}/mês, '
            'com +${p['minutos_por_usuario_extra']} minutos e +${p['mensagens_por_usuario_extra']} mensagens.'
            '${_n(p['desconto_pct']) > 0 ? ' Desconto de ${_n(p['desconto_pct'])}%.' : ''}'),
        const SizedBox(height: 4),
        Text('Ciclo atual: ${_data(c['ciclo_inicio'])} a ${_data(c['ciclo_fim'])}.', style: const TextStyle(color: Cores.neutro)),
        if (d['cobrar'] != false && d['situacao'] != 'cancelada') ...[
          const SizedBox(height: 8),
          Text('Próxima mensalidade estimada: ${_moeda(est['valor'])} '
              '(${est['usuarios_cobrados']} usuário(s) contando a regra dos ${_n(d['dias_minimos'])} dias, se nada mudar).',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }
}

class _Consumo extends StatelessWidget {
  const _Consumo(this.d);

  final Map<String, dynamic> d;

  Widget _barra(String rotulo, num usado, num total, String extra) {
    final pct = total > 0 ? usado / total : 0.0;
    final cor = pct >= 1 ? Cores.erro : (pct >= .8 ? Cores.alerta : Cores.sucesso);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(rotulo, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text('$usado de $total', style: TextStyle(color: cor, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: pct.clamp(0, 1).toDouble(), minHeight: 10, color: cor, backgroundColor: Cores.linha,
            borderRadius: BorderRadius.circular(5)),
        if (extra.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(extra, style: const TextStyle(color: Cores.neutro, fontSize: 12))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Map<String, dynamic>.from(d['consumo'] as Map);
    return _Cartao(
      titulo: 'Uso neste ciclo',
      child: Column(children: [
        _barra('Usuários que contam', _n(c['usuarios_cobrados']), _n(c['usuarios_incluidos']),
            'Contam os usuários com login ativo em ${_n(d['dias_minimos'])} dias ou mais do ciclo, ou que participaram de algum atendimento. '
            'Hoje há ${c['usuarios_ativos']} usuário(s) com login.'),
        _barra('Minutos de IA (relato e OS por áudio)', _n(c['minutos_usados']), _n(c['minutos_incluidos']),
            '${_n(c['minutos_pacotes']) > 0 ? 'Inclui ${c['minutos_pacotes']} de pacotes. ' : ''}'
            'Passou de 100%: tolerância de 20%. Depois disso os áudios esperam um pacote (dá para digitar).'),
        _barra('Mensagens automáticas de WhatsApp', _n(c['mensagens_usadas']), _n(c['mensagens_incluidas']),
            'As mensagens que o técnico envia pelo próprio WhatsApp não contam.'),
      ]),
    );
  }
}

class _Pacotes extends StatelessWidget {
  const _Pacotes(this.pacotes, {required this.aoComprar});

  final List<Map<String, dynamic>> pacotes;
  final void Function(Map<String, dynamic>)? aoComprar;

  @override
  Widget build(BuildContext context) => _Cartao(
        titulo: 'Pacotes extras',
        child: Wrap(spacing: 12, runSpacing: 12, children: [
          for (final k in pacotes)
            SizedBox(
              width: 260,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16), alignment: Alignment.centerLeft),
                onPressed: aoComprar == null ? null : () => aoComprar!(k),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${k['nome']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${_moeda(k['valor'])} · comprar'),
                ]),
              ),
            ),
        ]),
      );
}

class _Usuarios extends StatelessWidget {
  const _Usuarios(this.d);

  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) => _Cartao(
        titulo: 'Usuários no ciclo',
        child: Column(children: [
          for (final u in lista(d['usuarios']))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${u['nome']}${u['ativo'] == true ? '' : ' (desligado)'}'),
              subtitle: Text('${u['dias']} dia(s) com login ativo${u['trabalhou'] == true ? ' · participou de atendimento' : ''}'),
              trailing: Text(u['cobrado'] == true ? 'conta' : 'ainda não conta',
                  style: TextStyle(color: u['cobrado'] == true ? Cores.tinta : Cores.neutro, fontWeight: FontWeight.w600)),
            ),
        ]),
      );
}

class _Faturas extends StatelessWidget {
  const _Faturas(this.faturas, {required this.aoPagar, required this.aoConferir});

  final List<Map<String, dynamic>> faturas;
  final void Function(String)? aoPagar;
  final void Function(String)? aoConferir;

  @override
  Widget build(BuildContext context) => _Cartao(
        titulo: 'Faturas',
        child: faturas.isEmpty
            ? const Text('Nenhuma fatura ainda. A primeira sai 2 dias antes do fim do teste grátis.', style: TextStyle(color: Cores.neutro))
            : Column(children: [
                for (final f in faturas)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Nº ${f['numero']} · ${{'mensalidade': 'Mensalidade', 'pacote': 'Pacote extra', 'avulsa': 'Cobrança'}[f['tipo']] ?? ''}'
                        '${f['periodo_inicio'] != null ? ' · ${_data(f['periodo_inicio'])} a ${_data(f['periodo_fim'])}' : ''}'),
                    subtitle: Text(f['situacao'] == 'paga'
                        ? 'Paga em ${_data(f['pago_em'])} · ${_moeda(f['valor_total'])}${f['nf_numero'] != null ? ' · nota ${f['nf_numero']}' : ''}'
                        : '${f['vencida'] == true ? 'VENCIDA em' : 'Vence em'} ${_data(f['vencimento'])} · ${_moeda(f['valor_total'])}',
                        style: TextStyle(color: f['vencida'] == true ? Cores.erro : null)),
                    trailing: f['situacao'] == 'aberta'
                        ? Wrap(spacing: 4, children: [
                            TextButton(onPressed: aoConferir == null ? null : () => aoConferir!(f['id'] as String), child: const Text('Já paguei')),
                            FilledButton(onPressed: aoPagar == null ? null : () => aoPagar!(f['id'] as String), child: const Text('Pagar')),
                          ])
                        : null,
                    children: [
                      for (final i in lista(f['itens']))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            Expanded(child: Text('${i['descricao']}')),
                            Text('${_n(i['quantidade']) == 1 ? '' : '${_n(i['quantidade'])} x ${_moeda(i['valor_unitario'])} = '}${_moeda(i['total'])}'),
                          ]),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
              ]),
      );
}
