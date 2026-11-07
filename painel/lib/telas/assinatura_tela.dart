import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

import '../servicos/arquivo_web.dart';
import '../servicos/funcoes.dart';
import '../widgets/aviso_plano.dart';

/// Plano e consumo (guia 44): situação da assinatura, o que já foi usado no ciclo,
/// usuários que contam, pacotes extras, cupom e faturas com o botão de pagar.
/// Guia 89: pagamento anual (2 meses grátis), desistência em 7 dias e "Indique e ganhe".
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
  String? _planoAtual;
  Map<String, dynamic>? _cupomAtivo;

  Future<Map<String, dynamic>> _carregar() async {
    final cliente = Supabase.instance.client;
    final r = await cliente.rpc('consumo_atual');
    final d = r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
    // Guia 49: plano que sai mais em conta para os usuários de agora (ex.: Autônomo com 2+ usuários).
    try {
      final s = await cliente.rpc('plano_sugestao');
      if (s is Map) d['sugestao'] = Map<String, dynamic>.from(s);
    } catch (_) {/* sem sugestão */}
    // Guia 51: o cupom que vale na conta (mostra e desconta a estimativa e os pacotes).
    try {
      final cp = await cliente.rpc('cupom_ativo');
      if (cp is Map) d['cupom'] = Map<String, dynamic>.from(cp);
    } catch (_) {/* sem cupom */}
    // Guia 89: link de indicação, meses grátis e indicados.
    try {
      final ind = await cliente.rpc('indicacao_painel');
      if (ind is Map) d['indicacao'] = Map<String, dynamic>.from(ind);
    } catch (_) {/* sem indicação */}
    _planoAtual = d['plano'] is Map ? '${(d['plano'] as Map)['nome']}' : null;
    _cupomAtivo = d['cupom'] as Map<String, dynamic>?;
    return d;
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
    final cupom = _cupomAtivo;
    final valor = _comCupom(pacote['valor'], cupom, 'pacote');
    final temDesconto = valor < _n(pacote['valor']);
    final gratis = valor <= 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Comprar ${pacote['nome']}?'),
        content: Text(gratis
            ? 'Com o cupom ${cupom?['codigo']}, este pacote sai de graça e é liberado na hora. '
                'Vale até o fim do ciclo; liberado na última semana, vale também o ciclo seguinte.'
            : '${_moeda(valor)}${temDesconto ? ' (de ${_moeda(pacote['valor'])}, com o cupom ${cupom?['codigo']})' : ''}, '
                'pago agora pelo Mercado Pago (Pix, boleto ou cartão). '
                'Vale até o fim do ciclo; comprado na última semana, vale também o ciclo seguinte.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(gratis ? 'Liberar pacote' : 'Ir para o pagamento')),
        ],
      ),
    );
    if (ok != true) return;
    await _acao(() async {
      final r = await chamarFuncao('cobranca', {'acao': 'comprar_pacote', 'pacote': pacote['codigo']});
      if (r['pago'] == true) {
        if (mounted) _avisar('Pacote liberado com o cupom.');
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

  /// Troca de plano pelo próprio cliente (guia 49). Vale a partir da próxima mensalidade.
  Future<void> _trocarPlano([String? sugerido]) async {
    var planos = <Map<String, dynamic>>[];
    try {
      final r = await Supabase.instance.client.rpc('precos_publicos');
      planos = lista((r as Map)['planos']);
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
      return;
    }
    if (!mounted) return;
    String? codigoAtual;
    for (final p in planos) {
      if (p['nome'] == _planoAtual) codigoAtual = p['codigo'] as String?;
    }
    String? escolhido = sugerido ?? codigoAtual;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, definir) => AlertDialog(
          title: const Text('Trocar de plano'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final p in planos)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(escolhido == p['codigo'] ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: escolhido == p['codigo'] ? Cores.indigo500 : Cores.neutro),
                  title: Text.rich(TextSpan(text: '${p['nome']} · ${_moeda(p['valor_mensal'])}/mês', children: [
                    if (p['codigo'] == codigoAtual)
                      const TextSpan(text: '  (plano atual)', style: TextStyle(color: Cores.indigo700, fontWeight: FontWeight.w700)),
                  ])),
                  subtitle: Text('${_usuarios(p['usuarios_incluidos'])}, ${p['minutos_incluidos']} minutos de IA e '
                      '${p['mensagens_incluidas']} mensagens. Usuário a mais: ${_moeda(p['valor_usuario_extra'])}/mês.'),
                  onTap: () => definir(() => escolhido = p['codigo'] as String),
                ),
              const SizedBox(height: 8),
              const Text('Vale a partir da próxima mensalidade. A que já foi gerada não muda, e os dados continuam todos aqui.',
                  style: TextStyle(color: Cores.neutro)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
            FilledButton(
                onPressed: escolhido == null || escolhido == codigoAtual ? null : () => Navigator.of(ctx).pop(true),
                child: const Text('Trocar')),
          ],
        ),
      ),
    );
    if (ok != true || escolhido == null) return;
    await _acao(() async {
      final r = await Supabase.instance.client.rpc('plano_trocar', params: {'p_codigo': escolhido});
      final m = Map<String, dynamic>.from(r as Map);
      if (mounted) {
        _avisar(m['mudou'] == true
            ? 'Plano trocado para ${m['plano']}. Vale a partir da próxima mensalidade.'
            : 'Você já está no plano ${m['plano']}.');
      }
      if (mounted) _recarregar();
    });
  }

  /// Guia 89: muda para o anual (a fatura sai na hora) ou volta para o mensal.
  Future<void> _periodicidade(Map<String, dynamic> anual, String para) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(para == 'anual' ? 'Pagar por ano?' : 'Voltar para o mensal?'),
        content: SizedBox(
          width: 480,
          child: Text(para == 'anual'
              ? 'Plano por ${_moeda(anual['valor_anual'])} à vista: paga ${anual['meses_pagos']} meses e usa 12 '
                  '(economia de ${_moeda(anual['economia'])}). Começa em ${_data(anual['comeca_em'])}.\n\n'
                  '• A fatura anual sai agora. Se não for paga até o início, você continua no mensal, sem multa.\n'
                  '• Usuários a mais e o módulo de notas continuam na mensalidade.\n'
                  '• O plano fica o mesmo até a renovação, que é automática (a fatura sai 7 dias antes do fim).\n'
                  '• Até ${anual['arrependimento_dias']} dias depois de pagar, dá para desistir com devolução integral. '
                  'Depois disso, não há devolução: o plano vale até o fim do período.'
              : 'A fatura anual em aberto é cancelada. O que já está pago continua valendo até o fim do período; '
                  'depois, a cobrança volta a ser mensal.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(para == 'anual' ? 'Gerar a fatura anual' : 'Voltar para o mensal')),
        ],
      ),
    );
    if (ok != true) return;
    await _acao(() async {
      final r = await Supabase.instance.client.rpc('assinatura_periodicidade', params: {'p_periodicidade': para});
      final m = r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
      final aberta = m['aberta'] is Map ? Map<String, dynamic>.from(m['aberta'] as Map) : null;
      if (mounted) {
        _avisar(para == 'anual'
            ? (aberta != null
                ? 'Fatura anual nº ${aberta['numero']} gerada: ${_moeda(aberta['valor_total'])}, vence em ${_data(aberta['vencimento'])}.'
                : 'Pagamento anual ligado: a renovação sai 7 dias antes do fim do período.')
            : 'Pronto: a cobrança volta a ser mensal.');
      }
      if (mounted) _recarregar();
    });
  }

  /// Guia 89: arrependimento do anual (até 7 dias depois de pagar), com devolução pelo Mercado Pago.
  Future<void> _desistirAnual(Map<String, dynamic> vigente) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desistir do pagamento anual?'),
        content: SizedBox(
          width: 460,
          child: Text('Devolvemos ${_moeda(vigente['valor_pago'])} pelo Mercado Pago, na mesma forma do pagamento '
              '(no cartão, o crédito aparece na fatura do cartão). A conta volta ao pagamento mensal'
              '${DateTime.tryParse('${vigente['inicio']}')?.isAfter(DateTime.now()) == false ? ' e a mensalidade deste ciclo é gerada' : ''}.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Cores.erro),
              onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Desistir e devolver')),
        ],
      ),
    );
    if (ok != true) return;
    await _acao(() async {
      await chamarFuncao('cobranca', {'acao': 'estornar', 'fatura_id': vigente['fatura_id']});
      if (mounted) _avisar('Pronto: o valor foi devolvido no Mercado Pago e a conta voltou ao mensal.');
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
          // Pacotes em destaque; com 80% ou mais de consumo, sobem para logo abaixo do plano.
          final c = d['consumo'] is Map ? Map<String, dynamic>.from(d['consumo'] as Map) : <String, dynamic>{};
          num pct(String usado, String total) => _n(c[total]) > 0 ? _n(c[usado]) * 100 / _n(c[total]) : 0;
          final minutosPct = pct('minutos_usados', 'minutos_incluidos');
          final mensagensPct = pct('mensagens_usadas', 'mensagens_incluidas');
          final urgente = minutosPct >= 80 || mensagensPct >= 80;
          // Guia 81: o pacote de notas só aparece para quem contratou a emissão de notas.
          final notas = d['notas'] is Map ? Map<String, dynamic>.from(d['notas'] as Map) : <String, dynamic>{};
          final listaPacotes =
              lista(d['pacotes']).where((k) => k['tipo'] != 'notas' || _n(notas['empresas']) > 0).toList();
          final pacotes = _Pacotes(listaPacotes, cupom: d['cupom'] as Map<String, dynamic>?,
              aoComprar: _ocupado ? null : _comprar, minutosPct: minutosPct, mensagensPct: mensagensPct);
          return ListView(padding: const EdgeInsets.all(24), children: [
            Row(children: [
              Expanded(child: Text('Plano e consumo', style: Theme.of(context).textTheme.headlineSmall)),
              if (financeiro) TextButton.icon(onPressed: _ocupado ? null : () => _trocarPlano(), icon: const Icon(Icons.swap_horiz), label: const Text('Trocar de plano')),
              if (financeiro) TextButton.icon(onPressed: _cupom, icon: const Icon(Icons.local_offer_outlined), label: const Text('Tenho um cupom')),
              IconButton(onPressed: _recarregar, icon: const Icon(Icons.refresh), tooltip: 'Atualizar'),
            ]),
            const SizedBox(height: 12),
            _Situacao(d),
            if (d['anual'] is Map && (d['anual'] as Map)['disponivel'] == true)
              _Anual(Map<String, dynamic>.from(d['anual'] as Map),
                  aoMudar: financeiro && !_ocupado ? _periodicidade : null,
                  aoPagar: _ocupado ? null : _pagar,
                  aoDesistir: financeiro && !_ocupado ? _desistirAnual : null),
            if (d['sugestao'] is Map)
              _Sugestao(Map<String, dynamic>.from(d['sugestao'] as Map),
                  aoTrocar: financeiro && !_ocupado ? (codigo) => _trocarPlano(codigo) : null),
            if (urgente) pacotes,
            _Consumo(d),
            _Notas(notas),
            if (!urgente) pacotes,
            _Usuarios(d),
            _Faturas(lista(d['faturas']), aoPagar: _ocupado ? null : _pagar, aoConferir: _ocupado ? null : _conferir),
            if (d['indicacao'] is Map) _Indicacao(Map<String, dynamic>.from(d['indicacao'] as Map)),
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
/// Valor depois do cupom (o mesmo cálculo da fatura). [tipo]: mensalidade ou pacote.
num _comCupom(dynamic valor, Map<String, dynamic>? cupom, String tipo) {
  final v = _n(valor);
  if (cupom == null || cupom['vale_$tipo'] != true || v <= 0) return v;
  // Guia 89: na mensalidade vale a fração do próximo mês (1 = mês grátis).
  if (tipo == 'mensalidade' && cupom['fracao_proximo_mes'] != null) {
    return v - (v * _n(cupom['fracao_proximo_mes']) * 100).round() / 100;
  }
  final desconto = cupom['tipo'] == 'percentual'
      ? (v * _n(cupom['valor'])).round() / 100
      : _n(cupom['valor']);
  return v - (desconto > v ? v : desconto);
}

String _usuarios(dynamic v) => _n(v) == 1 ? '1 usuário' : '${_n(v)} usuários';

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
    final cupom = d['cupom'] as Map<String, dynamic>?;
    // Guia 89: no mês pago pelo anual o plano não entra (nem o cupom); o mês grátis de indicação tira o plano.
    final comPlano = est['plano_incluido'] != false;
    final comCupom = comPlano ? _comCupom(est['valor'], cupom, 'mensalidade') : _n(est['valor']);
    final fracao = comPlano && cupom?['vale_mensalidade'] == true ? _n(cupom?['fracao_proximo_mes']) : 0;
    final credito = comPlano && _n(d['creditos_disponiveis']) > 0 ? _n(est['valor_plano']) * (1 - fracao) : 0;
    final estimado = comCupom - credito < 0 ? 0 : comCupom - credito;
    final restantes = cupom?['mensalidades_restantes'];
    final gratis = _n(cupom?['gratis_restantes']);
    final anual = d['anual'] is Map ? Map<String, dynamic>.from(d['anual'] as Map) : const <String, dynamic>{};
    final vigente = anual['vigente'] is Map ? Map<String, dynamic>.from(anual['vigente'] as Map) : null;
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
        Text('${_moeda(p['valor_mensal'])}/mês com ${_usuarios(p['usuarios_incluidos'])}, ${p['minutos_incluidos']} minutos de IA '
            'e ${p['mensagens_incluidas']} mensagens de WhatsApp. Usuário a mais: ${_moeda(p['valor_usuario_extra'])}/mês, '
            'com +${p['minutos_por_usuario_extra']} minutos e +${p['mensagens_por_usuario_extra']} mensagens.'
            '${_n(p['desconto_pct']) > 0 ? ' Desconto de ${_n(p['desconto_pct'])}%.' : ''}'),
        const SizedBox(height: 4),
        Text('Ciclo atual: ${_data(c['ciclo_inicio'])} a ${_data(c['ciclo_fim'])}.'
            '${vigente != null ? ' Plano pago no anual até ${_data(vigente['fim'])}.' : ''}',
            style: const TextStyle(color: Cores.neutro)),
        if (cupom != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.local_offer, size: 18, color: Cores.sucesso),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Cupom ${cupom['codigo']}: ${cupom['resumo']}'
                  '${gratis > 0 ? ' (${gratis == 1 ? 'falta 1 mês grátis' : 'faltam $gratis meses grátis'})' : restantes != null && cupom['aplica_em'] != 'pacote' ? ' (falta(m) ${_n(restantes)} mês(es) com desconto)' : ''}.',
                  style: const TextStyle(color: Cores.sucesso, fontWeight: FontWeight.w600)),
            ),
          ]),
        ],
        if (d['cobrar'] != false && d['situacao'] != 'cancelada') ...[
          const SizedBox(height: 8),
          Text('Próxima mensalidade estimada: ${_moeda(estimado)}'
              '${comCupom < _n(est['valor']) ? ' (${_moeda(est['valor'])} menos o cupom ${cupom?['codigo']})' : ''}'
              '${credito > 0 ? ', com 1 mês do plano grátis por indicação' : ''}'
              '${comPlano ? '' : ' (o plano está pago no anual; aqui só usuários a mais e notas)'} · '
              '${est['usuarios_cobrados']} usuário(s) contando a regra dos ${_n(d['dias_minimos'])} dias, se nada mudar.',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }
}

/// Guia 49: outro plano sai mais em conta para os usuários de agora.
class _Sugestao extends StatelessWidget {
  const _Sugestao(this.s, {required this.aoTrocar});

  final Map<String, dynamic> s;
  final void Function(String codigo)? aoTrocar;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        color: Cores.indigo100,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.savings_outlined, color: Cores.indigo700),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Com ${_usuarios(s['usuarios'])}, o plano ${s['nome']} sai por ${_moeda(s['valor_sugerido'])}/mês, '
                  '${_moeda(s['economia'])} a menos que no ${s['plano_atual']} (${_moeda(s['valor_atual'])}), '
                  'com ${s['minutos']} minutos de IA e ${s['mensagens']} mensagens.'),
            ),
            if (aoTrocar != null) ...[
              const SizedBox(width: 12),
              FilledButton(onPressed: () => aoTrocar!(s['codigo'] as String), child: Text('Mudar para o ${s['nome']}')),
            ],
          ]),
        ),
      );
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
            '${_n(c['minutos_usados']) >= _n(c['minutos_incluidos']) && _n(c['minutos_incluidos']) > 0
                ? 'Passou de 100%: há uma tolerância de 20%. Depois disso, os áudios esperam um pacote (dá para digitar).'
                : 'Se passar de 100%, há uma tolerância de 20%; depois, os áudios esperam um pacote (dá para digitar).'}'),
        _barra('Mensagens automáticas de WhatsApp', _n(c['mensagens_usadas']), _n(c['mensagens_incluidas']),
            'As mensagens que o técnico envia pelo próprio WhatsApp não contam.'),
      ]),
    );
  }
}

/// Pacotes extras em destaque (é venda): cartões grandes com preço e "Comprar agora".
/// Com o consumo a partir de 80%, a moldura fica coral e o pacote que falta ganha "Recomendado".
class _Pacotes extends StatelessWidget {
  const _Pacotes(this.pacotes, {required this.aoComprar, this.minutosPct = 0, this.mensagensPct = 0, this.cupom});

  final List<Map<String, dynamic>> pacotes;
  final Map<String, dynamic>? cupom;
  final void Function(Map<String, dynamic>)? aoComprar;
  final num minutosPct;
  final num mensagensPct;

  bool _recomendado(Map<String, dynamic> k) =>
      (k['tipo'] == 'minutos' && minutosPct >= 80) || (k['tipo'] == 'mensagens' && mensagensPct >= 80);

  @override
  Widget build(BuildContext context) {
    if (pacotes.isEmpty) return const SizedBox.shrink();
    final urgente = minutosPct >= 80 || mensagensPct >= 80;
    final tema = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: urgente ? Cores.coral500 : Cores.indigo500, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.bolt, color: urgente ? Cores.coral500 : Cores.indigo500, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(urgente ? 'Seu consumo passou de 80%: garanta mais antes de acabar' : 'Precisa de mais? Compre um pacote extra',
                  style: tema.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 4),
          const Text('Libera na hora, com Pix, boleto ou cartão. Vale até o fim do ciclo; comprado na última semana, vale também o próximo.',
              style: TextStyle(color: Cores.neutro)),
          const SizedBox(height: 16),
          // Lado a lado com a mesma altura (botões alinhados); na tela estreita, um embaixo do outro.
          LayoutBuilder(builder: (context, limites) {
            const largura = 300.0, espaco = 16.0;
            final cartoes = [
              for (final k in pacotes)
                _CartaoPacote(k, recomendado: _recomendado(k), aoComprar: aoComprar,
                    valorFinal: _comCupom(k['valor'], cupom, 'pacote')),
            ];
            if (limites.maxWidth < pacotes.length * largura + (pacotes.length - 1) * espaco) {
              return Column(children: [
                for (final c in cartoes) Padding(padding: const EdgeInsets.only(bottom: espaco), child: c),
              ]);
            }
            return IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < cartoes.length; i++) ...[
                  if (i > 0) const SizedBox(width: espaco),
                  SizedBox(width: largura, child: cartoes[i]),
                ],
              ]),
            );
          }),
        ]),
      ),
    );
  }
}

class _CartaoPacote extends StatelessWidget {
  const _CartaoPacote(this.k, {required this.recomendado, required this.aoComprar, required this.valorFinal});

  final Map<String, dynamic> k;
  final num valorFinal;
  final bool recomendado;
  final void Function(Map<String, dynamic>)? aoComprar;

  @override
  Widget build(BuildContext context) {
    final minutos = k['tipo'] == 'minutos';
    final qtd = _n(k['quantidade']);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: recomendado ? const Color(0xFFFFF1EC) : Cores.indigo100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: recomendado ? Cores.coral500 : Cores.linha, width: recomendado ? 2 : 1),
      ),
      // Em cima: ícone, nome e descrição; embaixo: preço e botão (alinhados entre os cartões).
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Icon(minutos ? Icons.mic : (k['tipo'] == 'notas' ? Icons.request_quote_outlined : Icons.chat_outlined),
                color: minutos ? Cores.coral500 : Cores.indigo500, size: 28),
          ),
          const Spacer(),
          if (recomendado)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Cores.coral500, borderRadius: BorderRadius.circular(999)),
              child: const Text('RECOMENDADO', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
        ]),
        const SizedBox(height: 14),
        Text('${k['nome']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(minutos
                ? 'Uns ${(qtd / 2).round()} relatos por áudio a mais.'
                : k['tipo'] == 'notas'
                    ? 'Notas fiscais além das incluídas no mês.'
                    : 'Para meses de muito atendimento.',
            style: const TextStyle(color: Cores.neutro)),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 14),
        if (valorFinal < _n(k['valor']))
          Text(_moeda(k['valor']),
              style: const TextStyle(color: Cores.neutro, decoration: TextDecoration.lineThrough, fontSize: 14)),
        Text(_moeda(valorFinal),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Cores.indigo700, height: 1)),
        Text(valorFinal < _n(k['valor']) ? 'com o seu cupom' : 'pagamento único',
            style: const TextStyle(color: Cores.neutro, fontSize: 12)),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Cores.coral500, padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: aoComprar == null ? null : () => aoComprar!(k),
            icon: const Icon(Icons.shopping_cart_outlined),
            label: const Text('Comprar agora', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        ]),
      ]),
    );
  }
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
                    title: Text('Nº ${f['numero']} · ${{'mensalidade': 'Mensalidade', 'anual': 'Plano anual', 'pacote': 'Pacote extra', 'avulsa': 'Cobrança'}[f['tipo']] ?? ''}'
                        '${f['periodo_inicio'] != null ? ' · ${_data(f['periodo_inicio'])} a ${_data(f['periodo_fim'])}' : ''}'),
                    subtitle: Text(f['situacao'] == 'estornada'
                        ? 'Devolvida em ${_data(f['estornada_em'])} · ${_moeda(f['valor_total'])}'
                        : f['situacao'] == 'paga'
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

/// Guia 86: "50, 200 ou 1000" a partir das faixas do módulo.
String _faixasTexto(Map<String, dynamic> n) {
  final f = ((n['faixas'] as List?) ?? const []).map((e) => _n((e as Map)['notas'])).toList();
  if (f.isEmpty) return '${_n(n['notas_por_empresa'])}';
  if (f.length == 1) return '${f.first}';
  return '${f.sublist(0, f.length - 1).join(', ')} ou ${f.last}';
}

/// Guia 81: notas fiscais no ciclo (ou o convite para contratar).
class _Notas extends StatelessWidget {
  const _Notas(this.n);

  final Map<String, dynamic> n;

  @override
  Widget build(BuildContext context) {
    if (n.isEmpty) return const SizedBox.shrink();
    final contratado = _n(n['empresas']) > 0;
    if (!contratado) {
      return _Cartao(
        titulo: 'Notas fiscais',
        child: Row(children: [
          Expanded(
            child: Text('NFS-e dos serviços e NF-e das peças direto das OS, uma a uma ou o mês inteiro. '
                'A partir de ${_moeda(n['valor_modulo'])} por mês com ${_n(n['notas_por_empresa'])} notas '
                '(faixas de até ${_faixasTexto(n)} notas); nota além da faixa ${_moeda(n['valor_extra'])}.'),
          ),
          const SizedBox(width: 12),
          OutlinedButton(onPressed: () => context.go('/notas/configuracao'), child: const Text('Conhecer')),
        ]),
      );
    }
    final usadas = _n(n['usadas']);
    final incluidas = _n(n['incluidas']);
    final pct = incluidas > 0 ? (usadas / incluidas).clamp(0, 1).toDouble() : 0.0;
    return _Cartao(
      titulo: 'Notas fiscais',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('$usadas de $incluidas notas neste ciclo')),
          TextButton(onPressed: () => context.go('/notas'), child: const Text('Ver as notas')),
        ]),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: pct, minHeight: 8, borderRadius: BorderRadius.circular(8)),
        const SizedBox(height: 6),
        Text(
            _n(n['excedente']) > 0
                ? '${_n(n['excedente'])} notas além das incluídas: ${_moeda(_n(n['excedente']) * _n(n['valor_extra']))} na próxima mensalidade.'
                : 'Módulo: ${_moeda(n['valor_modulo_total'] ?? _n(n['valor_modulo']) * _n(n['empresas']))} por mês. '
                    'Troque a faixa em Notas fiscais › Configuração. As notas de teste não contam.',
            style: const TextStyle(color: Cores.neutro)),
      ]),
    );
  }
}

/// Guia 89: pagamento anual (paga 10, usa 12). Oferta, fatura em aberto, período pago e desistência.
class _Anual extends StatelessWidget {
  const _Anual(this.a, {required this.aoMudar, required this.aoPagar, required this.aoDesistir});

  final Map<String, dynamic> a;
  final void Function(Map<String, dynamic> anual, String para)? aoMudar;
  final void Function(String faturaId)? aoPagar;
  final void Function(Map<String, dynamic> vigente)? aoDesistir;

  @override
  Widget build(BuildContext context) {
    final vigente = a['vigente'] is Map ? Map<String, dynamic>.from(a['vigente'] as Map) : null;
    final aberta = a['aberta'] is Map ? Map<String, dynamic>.from(a['aberta'] as Map) : null;
    final renova = a['periodicidade'] == 'anual';
    final linhas = <Widget>[];
    if (vigente != null) {
      linhas.add(Text('Plano pago de ${_data(vigente['inicio'])} a ${_data(vigente['fim'])} '
          '(${_moeda(vigente['valor_pago'])}, pago em ${_data(vigente['pago_em'])}).',
          style: const TextStyle(fontWeight: FontWeight.w600)));
      linhas.add(Text(renova
          ? 'Renova sozinho: a fatura do próximo ano sai em ${_data(vigente['renovacao_em'])}.'
          : 'Não renova: depois de ${_data(vigente['fim'])}, a cobrança volta a ser mensal.',
          style: const TextStyle(color: Cores.neutro)));
    }
    if (aberta != null) {
      linhas.add(Text('Fatura anual nº ${aberta['numero']} de ${_moeda(aberta['valor_total'])} aguardando pagamento, '
          'para ${_data(aberta['inicio'])} a ${_data(aberta['fim'])}. Vence em ${_data(aberta['vencimento'])}; '
          'se não for paga até o início, você continua no mensal.'));
    }
    if (vigente == null && aberta == null) {
      linhas.add(Text('Pague por ano e ganhe ${a['meses_gratis']} meses: ${_moeda(a['valor_anual'])} à vista '
          '(equivale a ${_moeda(_n(a['valor_anual']) / 12)} por mês, economia de ${_moeda(a['economia'])}). '
          'Começa em ${_data(a['comeca_em'])}.'));
    }
    final botoes = <Widget>[
      if (aberta != null && aoPagar != null)
        FilledButton(onPressed: () => aoPagar!(aberta['fatura_id'] as String), child: const Text('Pagar a anual')),
      if (aoMudar != null && (aberta != null || (vigente != null && renova)))
        TextButton(onPressed: () => aoMudar!(a, 'mensal'),
            child: Text(vigente != null ? 'Voltar para o mensal no fim do período' : 'Continuar no mensal')),
      if (aoMudar != null && aberta == null && !renova)
        FilledButton.icon(onPressed: () => aoMudar!(a, 'anual'), icon: const Icon(Icons.savings_outlined),
            label: Text(vigente != null ? 'Renovar no anual' : 'Mudar para o anual')),
      if (vigente != null && vigente['pode_desistir'] == true && aoDesistir != null)
        TextButton(onPressed: () => aoDesistir!(vigente),
            style: TextButton.styleFrom(foregroundColor: Cores.erro),
            child: Text('Desistir do anual (devolução até ${_data(vigente['desistir_ate'])})')),
    ];
    return _Cartao(
      titulo: 'Pagamento anual',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final l in linhas) Padding(padding: const EdgeInsets.only(bottom: 6), child: l),
        if (botoes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: botoes),
        ],
      ]),
    );
  }
}

/// Guia 89: indique o ServPilot e ganhe 1 mês do plano por indicado que pagar.
class _Indicacao extends StatelessWidget {
  const _Indicacao(this.i);

  final Map<String, dynamic> i;

  String _situacao(Map<String, dynamic> x) => switch (x['situacao']) {
        'valida' => 'valeu 1 mês grátis',
        'recusada' => 'não valeu${x['motivo'] != null ? ' (${x['motivo']})' : ''}',
        _ when x['cancelada'] == true => 'cancelou',
        _ when x['em_teste'] == true => 'em teste grátis',
        _ => 'aguardando o 1º pagamento',
      };

  @override
  Widget build(BuildContext context) {
    final link = '${i['link']}';
    final disponiveis = _n(i['creditos_disponiveis']);
    final indicacoes = lista(i['indicacoes']);
    final texto = 'Uso o ServPilot para organizar as OS, o PMOC e a equipe. Teste 14 dias grátis pelo meu link: $link';
    return _Cartao(
      titulo: 'Indique o ServPilot e ganhe',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Para cada empresa que assinar pelo seu link e pagar a 1ª mensalidade, você ganha 1 mês do plano grátis. '
            'O desconto entra sozinho na sua próxima mensalidade.'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Cores.indigo100, borderRadius: BorderRadius.circular(8)),
          child: SelectableText(link, style: const TextStyle(fontWeight: FontWeight.w700, color: Cores.indigo700)),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copiar o link'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copiado.')));
              }
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Mandar pelo WhatsApp'),
            onPressed: () => abrirEmNovaAba('https://wa.me/?text=${Uri.encodeComponent(texto)}'),
          ),
        ]),
        const SizedBox(height: 12),
        Text(disponiveis > 0
            ? '${disponiveis == 1 ? '1 mês grátis' : '$disponiveis meses grátis'} para usar nas próximas mensalidades.'
            : 'Nenhum mês grátis para usar agora.',
            style: TextStyle(fontWeight: FontWeight.w600, color: disponiveis > 0 ? Cores.sucesso : Cores.neutro)),
        if (indicacoes.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final x in indicacoes)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(x['situacao'] == 'valida' ? Icons.check_circle : Icons.schedule,
                  color: x['situacao'] == 'valida' ? Cores.sucesso : Cores.neutro),
              title: Text('${x['nome']}'),
              subtitle: Text('Desde ${_data(x['criado_em'])} · ${_situacao(x)}'),
            ),
        ],
      ]),
    );
  }
}
