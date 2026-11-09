import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/arquivo_web.dart' show escolherArquivo;
import '../servicos/cobranca.dart' show lerValor;
import '../servicos/status.dart' show dataBr, dataHoraBr;
import '../widgets/margem.dart';
import 'servico_cobranca.dart';

/// Configurações › Cobrança (guia 100): como a empresa cobra (manual, Pix, banco por API, CNAB, ERP), as regras
/// (multa, juros, desconto, vencimento, protesto, baixa, espécie) e as contas de cobrança com as credenciais
/// (cifradas; nunca voltam para a tela), o "Testar conexão" e o ambiente (homologação ou produção).
class CobrancaConfigTela extends StatefulWidget {
  const CobrancaConfigTela({super.key});

  @override
  State<CobrancaConfigTela> createState() => _CobrancaConfigTelaState();
}

const _especies = {'DS': 'Duplicata de serviço', 'DM': 'Duplicata mercantil', 'RC': 'Recibo', 'FAT': 'Fatura', 'OU': 'Outros'};

/// Campo de texto com o rótulo e o valor inicial (o controlador é da tela).
TextField _campo(TextEditingController c, String rotulo, {String? ajuda, bool numero = false, ValueChanged<String>? mudou}) =>
    TextField(
      controller: c,
      keyboardType: numero ? const TextInputType.numberWithOptions(decimal: true) : null,
      decoration: InputDecoration(labelText: rotulo, helperText: ajuda),
      onChanged: mudou,
    );

class _CobrancaConfigTelaState extends State<CobrancaConfigTela> {
  Map<String, dynamic>? _dados;
  Map<String, Map<String, dynamic>> _bancos = {};
  bool _carregando = true;
  bool _salvando = false;
  bool _sujo = false;
  String? _erro;

  String _modo = 'manual';
  bool _emitirAoRegistrar = false;
  bool _comPix = true;
  String _especie = 'DS';
  String _docLocacao = 'fatura';
  final _vencDias = TextEditingController();
  final _multa = TextEditingController();
  final _juros = TextEditingController();
  final _desconto = TextEditingController();
  final _descontoDias = TextEditingController();
  final _protesto = TextEditingController();
  final _baixa = TextEditingController();
  final _instrucoes = TextEditingController();

  bool get _gestor => Sessao.atual?.tem(Papel.gestor) ?? false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in [_vencDias, _multa, _juros, _desconto, _descontoDias, _protesto, _baixa, _instrucoes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _avisar(String t, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Cores.erro : null));
  }

  String _num(Object? v) {
    final n = num.tryParse('${v ?? ''}');
    if (n == null) return '';
    return (n == n.roundToDouble() ? n.toInt().toString() : n.toString()).replaceAll('.', ',');
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final d = await configCobranca();
      Map<String, Map<String, dynamic>> bancos = {};
      try {
        final b = await funcaoCobranca({'acao': 'bancos'});
        bancos = {
          for (final x in ((b['bancos'] as List?) ?? const []).cast<Map>()) '${x['codigo']}': Map<String, dynamic>.from(x),
        };
      } catch (_) {
        // sem a função publicada a tela funciona; só não mostra o que cada banco pede
      }
      final c = Map<String, dynamic>.from((d['config'] as Map?) ?? const {});
      if (!mounted) return;
      setState(() {
        _dados = d;
        _bancos = bancos;
        _modo = '${c['modo'] ?? 'manual'}';
        _emitirAoRegistrar = c['emitir_ao_registrar'] == true;
        _comPix = c['com_pix'] != false;
        _especie = _especies.containsKey(c['especie']) ? '${c['especie']}' : 'DS';
        _docLocacao = c['documento_locacao'] == 'recibo' ? 'recibo' : 'fatura';
        _vencDias.text = _num(c['vencimento_dias']);
        _multa.text = _num(c['multa_percentual']);
        _juros.text = _num(c['juros_mes_percentual']);
        _desconto.text = _num(c['desconto_percentual']);
        _descontoDias.text = _num(c['desconto_dias']);
        _protesto.text = _num(c['protesto_dias']);
        _baixa.text = _num(c['baixa_dias']);
        _instrucoes.text = '${c['instrucoes'] ?? ''}';
        _sujo = false;
      });
      ModoCobranca.renovar();
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      await acaoCobranca({
        'acao': 'config_salvar',
        'modo': _modo,
        'emitir_ao_registrar': _emitirAoRegistrar,
        'com_pix': _comPix,
        'especie': _especie,
        'documento_locacao': _docLocacao,
        'vencimento_dias': int.tryParse(_vencDias.text.trim()) ?? 5,
        'multa_percentual': lerValor(_multa.text) ?? 0,
        'juros_mes_percentual': lerValor(_juros.text) ?? 0,
        'desconto_percentual': lerValor(_desconto.text) ?? 0,
        'desconto_dias': int.tryParse(_descontoDias.text.trim()) ?? 0,
        'protesto_dias': int.tryParse(_protesto.text.trim()) ?? 0,
        'baixa_dias': int.tryParse(_baixa.text.trim()) ?? 60,
        'instrucoes': _instrucoes.text.trim(),
      });
      _avisar('Configuração da cobrança salva.');
      await _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _editarConta([Map<String, dynamic>? conta]) async {
    final p = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => _DialogoConta(conta: conta, bancos: _bancos));
    if (p == null) return;
    try {
      await acaoCobranca({'acao': 'conta_salvar', if (conta != null) 'conta_bancaria_id': conta['id'], ...p});
      _avisar(conta == null ? 'Conta de cobrança cadastrada. Agora informe as credenciais.' : 'Conta salva.');
      await _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _credenciais(Map<String, dynamic> conta) async {
    final ok = await showDialog<bool>(
        context: context, builder: (_) => _DialogoCredenciais(conta: conta, banco: _bancos['${conta['banco']}']));
    if (ok == true) {
      _avisar('Credenciais gravadas (cifradas). Use "Testar conexão".');
      await _carregar();
    }
  }

  Future<void> _testar(Map<String, dynamic> conta) async {
    setState(() => _salvando = true);
    try {
      final r = await funcaoCobranca({'acao': 'testar_conexao', 'conta_bancaria_id': conta['id'], 'configurar_aviso': true});
      _avisar('${r['mensagem'] ?? (r['ok'] == true ? 'Conexão funcionando.' : 'O banco recusou.')}', erro: r['ok'] != true);
      await _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _inativar(Map<String, dynamic> conta) async {
    final sim = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Desativar ${conta['nome']}?'),
        content: const Text('Os títulos já emitidos continuam. Se for a conta padrão, a empresa volta ao modo manual.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Desativar')),
        ],
      ),
    );
    if (sim != true) return;
    try {
      await acaoCobranca({'acao': 'conta_inativar', 'conta_bancaria_id': conta['id']});
      await _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  Widget _secao(String titulo, List<Widget> filhos, {String? ajuda}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (ajuda != null) ...[
              const SizedBox(height: 4),
              Text(ajuda, style: const TextStyle(color: Cores.neutro)),
            ],
            const SizedBox(height: 8),
            ...filhos,
          ]),
        ),
      );

  Widget _opcaoModo(String modo) {
    final marcada = _modo == modo;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      enabled: _gestor,
      leading: Icon(marcada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: marcada ? Cores.indigo700 : Cores.neutro),
      title: Text(rotuloModoCobranca[modo] ?? modo),
      subtitle: Text(switch (modo) {
        'manual' => 'O ServPilot calcula, a empresa cobra por fora e marca o recebido (como hoje).',
        'pix' => 'Copia e cola com a chave Pix da empresa (Configurações › Pix). A baixa continua no "Recebi".',
        'api' => 'O ServPilot registra o boleto/Pix no banco e dá baixa sozinho quando o banco avisa o pagamento.',
        'cnab' => 'Gera a remessa (CNAB 240 ou 400) para enviar ao banco e lê o retorno com as baixas.',
        _ => 'Com o Protheus: o ERP emite o título e manda a baixa (integração do ERP).',
      }),
      onTap: _gestor
          ? () => setState(() {
                _modo = modo;
                _sujo = true;
              })
          : null,
    );
  }

  Widget _cartaoConta(Map<String, dynamic> c) {
    final banco = _bancos['${c['banco']}'];
    final campos = ((c['credenciais_campos'] as List?) ?? const []).map((x) => '$x').toList();
    final caminho = '${c['webhook_caminho'] ?? ''}';
    final ok = c['conexao_ok_em'] != null;
    return Card(
      color: c['ativa'] == true ? null : Cores.fundo,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${c['nome']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${nomesBancos[c['banco']] ?? c['banco']} · ag. ${c['agencia']} · conta ${c['conta']}${c['conta_dv'] != null ? '-${c['conta_dv']}' : ''}'),
            Text(c['ambiente'] == 'producao' ? 'PRODUÇÃO' : 'homologação (teste)',
                style: TextStyle(color: c['ambiente'] == 'producao' ? Cores.sucesso : Cores.alerta, fontWeight: FontWeight.w600)),
            if (c['ativa'] != true) const Text('desativada', style: TextStyle(color: Cores.neutro)),
            if ((_dados?['config'] as Map?)?['conta_padrao_id'] == c['id'])
              const Text('padrão', style: TextStyle(color: Cores.indigo700, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          Text(
              [
                'CNAB ${c['cnab_layout']}',
                if (c['nosso_numero_proximo'] != null)
                  'nosso número: próximo ${c['nosso_numero_proximo']}${c['nosso_numero_livres'] != null ? ' (${c['nosso_numero_livres']} livres)' : ''}'
                else
                  'nosso número pelo banco',
                campos.isEmpty ? 'sem credenciais' : 'credenciais: ${campos.join(', ')}',
                if (c['certificado_valido_ate'] != null) 'certificado até ${dataBr(c['certificado_valido_ate'])}',
                if (banco != null && banco['api_pronta'] != true) 'API deste banco em breve (use CNAB)',
              ].join(' · '),
              style: const TextStyle(color: Cores.neutro, fontSize: 13)),
          Text(
              ok
                  ? 'Conexão testada em ${dataHoraBr(c['conexao_ok_em'])}'
                  : (c['conexao_erro'] ?? '') != ''
                      ? 'Último teste: ${c['conexao_erro']}'
                      : 'Conexão ainda não testada',
              style: TextStyle(color: ok ? Cores.sucesso : ((c['conexao_erro'] ?? '') != '' ? Cores.erro : Cores.neutro), fontSize: 13)),
          if ((banco?['requisitos'] as Map?)?['observacao'] != null)
            Text('${(banco!['requisitos'] as Map)['observacao']}', style: const TextStyle(color: Cores.neutro, fontSize: 12)),
          const SizedBox(height: 4),
          if (_gestor && c['ativa'] == true)
            Wrap(spacing: 8, runSpacing: 4, children: [
              OutlinedButton.icon(onPressed: () => _editarConta(c), icon: const Icon(Icons.edit_outlined), label: const Text('Editar')),
              OutlinedButton.icon(
                  onPressed: () => _credenciais(c), icon: const Icon(Icons.key_outlined), label: const Text('Credenciais')),
              OutlinedButton.icon(
                  onPressed: _salvando ? null : () => _testar(c),
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Testar conexão')),
              if (caminho.isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: '${Config.supabaseUrl}$caminho'));
                    _avisar('Endereço do aviso de pagamento copiado (cadastre no portal do banco, se ele pedir).');
                  },
                  icon: const Icon(Icons.link),
                  label: const Text('Copiar endereço do aviso'),
                ),
              TextButton(onPressed: () => _inativar(c), child: const Text('Desativar')),
            ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null) return Center(child: Text(_erro!, style: const TextStyle(color: Cores.erro)));
    final contas = ((_dados?['contas'] as List?) ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final ValueChanged<String>? mudou = _gestor ? (_) => setState(() => _sujo = true) : null;
    return ListView(padding: margemDaTela(context), children: [
      Row(children: [
        IconButton(tooltip: 'Títulos', onPressed: () => context.go('/titulos'), icon: const Icon(Icons.arrow_back)),
        Expanded(
          child: Text('Cobrança', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        if (_gestor)
          FilledButton(onPressed: _salvando || !_sujo ? null : _salvar, child: Text(_salvando ? 'Salvando…' : 'Salvar')),
      ]),
      const SizedBox(height: 4),
      Text(
          _gestor
              ? 'Vale para a Refrigeração e para os Equipamentos: o A cobrar e a locação só geram o título; o resto é daqui.'
              : 'Só o gestor muda a configuração da cobrança.',
          style: const TextStyle(color: Cores.neutro)),
      const SizedBox(height: 12),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _secao('Como a empresa cobra', [
            for (final m in rotuloModoCobranca.keys) _opcaoModo(m),
            if (_modo == 'pix' && _dados?['tem_pix'] != true)
              const Text('Cadastre antes a chave Pix em Configurações › Pix para receber.', style: TextStyle(color: Cores.erro)),
            if ((_modo == 'api' || _modo == 'cnab') && contas.isEmpty)
              const Text('Cadastre antes a conta de cobrança (abaixo).', style: TextStyle(color: Cores.erro)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Emitir o título junto com a cobrança do A cobrar'),
              subtitle: const Text('Desligado: o botão "Boleto" de cada cobrança emite quando você quiser.'),
              value: _emitirAoRegistrar,
              onChanged: _gestor
                  ? (v) => setState(() {
                        _emitirAoRegistrar = v;
                        _sujo = true;
                      })
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Boleto com QR Pix (híbrido), quando o banco permite'),
              value: _comPix,
              onChanged: _gestor
                  ? (v) => setState(() {
                        _comPix = v;
                        _sujo = true;
                      })
                  : null,
            ),
          ]),
          const SizedBox(height: 12),
          _secao('Regras do título', ajuda: 'Valem para os títulos emitidos daqui para a frente.', [
            Wrap(spacing: 12, runSpacing: 4, children: [
              SizedBox(width: 220, child: _campo(_vencDias, 'Vencimento (dias após emitir)', mudou: mudou)),
              SizedBox(width: 220, child: _campo(_multa, 'Multa (%)', ajuda: 'Consumidor: até 2%', numero: true, mudou: mudou)),
              SizedBox(width: 220, child: _campo(_juros, 'Juros ao mês (%)', ajuda: 'Cobrado por dia de atraso', numero: true, mudou: mudou)),
              SizedBox(width: 220, child: _campo(_desconto, 'Desconto pontualidade (%)', numero: true, mudou: mudou)),
              SizedBox(width: 220, child: _campo(_descontoDias, 'Desconto até (dias antes)', mudou: mudou)),
              SizedBox(width: 220, child: _campo(_protesto, 'Protestar após (dias)', ajuda: '0 = não protestar', mudou: mudou)),
              SizedBox(width: 220, child: _campo(_baixa, 'Baixa no banco após (dias)', mudou: mudou)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 8, children: [
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  initialValue: _especie,
                  decoration: const InputDecoration(labelText: 'Espécie do título'),
                  items: [for (final e in _especies.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: _gestor
                      ? (v) => setState(() {
                            _especie = v ?? 'DS';
                            _sujo = true;
                          })
                      : null,
                ),
              ),
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  initialValue: _docLocacao,
                  decoration: const InputDecoration(labelText: 'Documento da locação'),
                  items: const [
                    DropdownMenuItem(value: 'fatura', child: Text('Fatura de locação')),
                    DropdownMenuItem(value: 'recibo', child: Text('Recibo de locação')),
                  ],
                  onChanged: _gestor
                      ? (v) => setState(() {
                            _docLocacao = v ?? 'fatura';
                            _sujo = true;
                          })
                      : null,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            _campo(_instrucoes, 'Instruções no boleto (opcional)', ajuda: 'Até 200 caracteres', mudou: mudou),
          ]),
          const SizedBox(height: 12),
          _secao('Contas de cobrança',
              ajuda: 'Banco, agência, conta, convênio e carteira (o banco informa ao liberar a cobrança). As credenciais e o '
                  'certificado A1 ficam cifrados e nunca voltam para a tela. Teste sempre em homologação antes de produção.',
              [
                for (final c in contas) _cartaoConta(c),
                if (contas.isEmpty) const Text('Nenhuma conta ainda.', style: TextStyle(color: Cores.neutro)),
                if (_gestor)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                        onPressed: () => _editarConta(), icon: const Icon(Icons.add), label: const Text('Nova conta de cobrança')),
                  ),
              ]),
        ]),
      ),
    ]);
  }
}

// ---------- Conta de cobrança ----------
class _DialogoConta extends StatefulWidget {
  const _DialogoConta({required this.conta, required this.bancos});

  final Map<String, dynamic>? conta;
  final Map<String, Map<String, dynamic>> bancos;

  @override
  State<_DialogoConta> createState() => _DialogoContaState();
}

class _DialogoContaState extends State<_DialogoConta> {
  late String _banco = '${widget.conta?['banco'] ?? '748'}';
  late String _ambiente = '${widget.conta?['ambiente'] ?? 'homologacao'}';
  late String _layout = '${widget.conta?['cnab_layout'] ?? '400'}';
  final Map<String, TextEditingController> _c = {};
  final Map<String, TextEditingController> _extras = {};

  static const _rotulos = {
    'nome': 'Apelido (ex.: Sicredi principal)',
    'agencia': 'Agência',
    'agencia_dv': 'Dígito da agência',
    'conta': 'Conta',
    'conta_dv': 'Dígito da conta',
    'convenio': 'Convênio',
    'carteira': 'Carteira',
    'variacao_carteira': 'Variação da carteira (BB)',
    'codigo_beneficiario': 'Código do beneficiário',
    'posto': 'Posto (Sicredi)',
    'cooperativa': 'Cooperativa (Sicredi)',
    'codigo_transmissao': 'Código de transmissão (Santander, CNAB)',
    'chave_pix': 'Chave Pix da conta (boleto com Pix)',
    'nosso_numero_proximo': 'Nosso número: próximo da faixa',
    'nosso_numero_fim': 'Nosso número: fim da faixa',
  };

  TextEditingController _ctl(String k) => _c.putIfAbsent(k, () => TextEditingController(text: '${widget.conta?[k] ?? ''}'));

  @override
  void dispose() {
    for (final c in [..._c.values, ..._extras.values]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _obrigatorios =>
      (((widget.bancos[_banco]?['requisitos'] as Map?)?['conta'] as List?) ?? const []).map((x) => '$x').toList();

  List<Map> get _extrasDoBanco => (((widget.bancos[_banco]?['requisitos'] as Map?)?['extras'] as List?) ?? const [])
      .cast<Map>()
      .where((e) => e['onde'] == 'conta')
      .toList();

  List<String> get _layouts {
    final l = ((widget.bancos[_banco]?['cnab'] as List?) ?? const []).map((x) => '$x').toList();
    if (l.isNotEmpty) return l;
    return _banco == '208' ? ['240'] : _banco == '341' ? ['400'] : ['240', '400'];
  }

  @override
  Widget build(BuildContext context) {
    final obrig = _obrigatorios;
    final nn = (widget.bancos[_banco]?['requisitos'] as Map?)?['nosso_numero'] as Map?;
    final layouts = _layouts;
    if (!layouts.contains(_layout)) _layout = layouts.first;
    Widget campo(String k) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: TextField(
            controller: _ctl(k),
            decoration: InputDecoration(labelText: '${_rotulos[k] ?? k}${obrig.contains(k) ? ' *' : ''}'),
          ),
        );
    return AlertDialog(
      title: Text(widget.conta == null ? 'Nova conta de cobrança' : 'Conta de cobrança'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            campo('nome'),
            DropdownButtonFormField<String>(
              initialValue: _banco,
              decoration: const InputDecoration(labelText: 'Banco'),
              items: [for (final e in nomesBancos.entries) DropdownMenuItem(value: e.key, child: Text('${e.key} · ${e.value}'))],
              onChanged: widget.conta == null ? (v) => setState(() => _banco = v ?? '748') : null,
            ),
            if (widget.bancos[_banco] != null && widget.bancos[_banco]!['api_pronta'] != true)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('A integração por API deste banco ainda não está pronta: use o CNAB por enquanto.',
                    style: TextStyle(color: Cores.alerta)),
              ),
            Row(children: [Expanded(child: campo('agencia')), const SizedBox(width: 8), SizedBox(width: 120, child: campo('agencia_dv'))]),
            Row(children: [Expanded(child: campo('conta')), const SizedBox(width: 8), SizedBox(width: 120, child: campo('conta_dv'))]),
            if (_banco == '001') ...[campo('convenio'), campo('carteira'), campo('variacao_carteira')],
            if (_banco == '237' || _banco == '208' || _banco == '341') ...[campo('carteira'), campo('codigo_beneficiario')],
            if (_banco == '208') campo('convenio'),
            if (_banco == '033') ...[campo('codigo_beneficiario'), campo('carteira'), campo('codigo_transmissao')],
            if (_banco == '748') ...[campo('cooperativa'), campo('posto'), campo('codigo_beneficiario')],
            campo('chave_pix'),
            for (final e in _extrasDoBanco)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: TextField(
                  controller: _extras.putIfAbsent('${e['chave']}',
                      () => TextEditingController(text: '${(widget.conta?['extras'] as Map?)?[e['chave']] ?? ''}')),
                  decoration: InputDecoration(labelText: '${e['rotulo']}${e['obrigatorio'] == true ? ' *' : ''}'),
                ),
              ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _ambiente,
              decoration: const InputDecoration(labelText: 'Ambiente'),
              items: const [
                DropdownMenuItem(value: 'homologacao', child: Text('Homologação (teste do banco)')),
                DropdownMenuItem(value: 'producao', child: Text('Produção (boletos valendo)')),
              ],
              onChanged: (v) => setState(() => _ambiente = v ?? 'homologacao'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _layout,
              decoration: const InputDecoration(labelText: 'Layout CNAB'),
              items: [for (final l in layouts) DropdownMenuItem(value: l, child: Text('CNAB $l'))],
              onChanged: (v) => setState(() => _layout = v ?? layouts.first),
            ),
            const SizedBox(height: 8),
            Text(
                nn?['quem'] == 'banco'
                    ? 'Neste banco o nosso número é gerado pelo banco na API (a faixa só vale para o CNAB).'
                    : 'Faixa do nosso número que o banco liberou (obrigatória no CNAB${nn?['quem'] == 'empresa' ? ' e na API deste banco' : ''}).',
                style: const TextStyle(color: Cores.neutro, fontSize: 12)),
            Row(children: [
              Expanded(child: campo('nosso_numero_proximo')),
              const SizedBox(width: 8),
              Expanded(child: campo('nosso_numero_fim')),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
        FilledButton(
          onPressed: () {
            final p = <String, dynamic>{'banco': _banco, 'ambiente': _ambiente, 'cnab_layout': _layout};
            for (final e in _c.entries) {
              p[e.key] = e.value.text.trim();
            }
            if (_extras.isNotEmpty) p['extras'] = {for (final e in _extras.entries) e.key: e.value.text.trim()};
            Navigator.pop(context, p);
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

// ---------- Credenciais (cifradas; nunca voltam para a tela) ----------
class _DialogoCredenciais extends StatefulWidget {
  const _DialogoCredenciais({required this.conta, required this.banco});

  final Map<String, dynamic> conta;
  final Map<String, dynamic>? banco;

  @override
  State<_DialogoCredenciais> createState() => _DialogoCredenciaisState();
}

class _DialogoCredenciaisState extends State<_DialogoCredenciais> {
  final _clientId = TextEditingController();
  final _segredo = TextEditingController();
  final _chaveApp = TextEditingController();
  final _senhaCert = TextEditingController();
  final Map<String, TextEditingController> _extras = {};
  String? _pfxNome;
  String? _pfxBase64;
  bool _salvando = false;
  String? _erro;

  List<String> get _ja => ((widget.conta['credenciais_campos'] as List?) ?? const []).map((x) => '$x').toList();
  List<String> get _pede => (((widget.banco?['requisitos'] as Map?)?['credenciais'] as List?) ?? const []).map((x) => '$x').toList();

  @override
  void dispose() {
    for (final c in [_clientId, _segredo, _chaveApp, _senhaCert, ..._extras.values]) {
      c.dispose();
    }
    super.dispose();
  }

  String _rotulo(String campo, String nome) =>
      '$nome${_pede.contains(campo) ? ' *' : ''}${_ja.contains(campo) ? ' (já informado: deixe em branco para manter)' : ''}';

  Future<void> _escolherPfx() async {
    final a = await escolherArquivo(aceitar: '.pfx,.p12');
    if (a == null || !mounted) return;
    setState(() {
      _pfxNome = a.nome;
      _pfxBase64 = base64Encode(a.bytes);
    });
  }

  Future<void> _salvar() async {
    final corpo = <String, dynamic>{'acao': 'salvar_credenciais', 'conta_bancaria_id': widget.conta['id']};
    if (_clientId.text.trim().isNotEmpty) corpo['client_id'] = _clientId.text.trim();
    if (_segredo.text.trim().isNotEmpty) corpo['client_secret'] = _segredo.text.trim();
    if (_chaveApp.text.trim().isNotEmpty) corpo['chave_aplicacao'] = _chaveApp.text.trim();
    if (_pfxBase64 != null) {
      corpo['certificado_pfx_base64'] = _pfxBase64;
      corpo['certificado_senha'] = _senhaCert.text;
    }
    final extras = {for (final e in _extras.entries) if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim()};
    if (extras.isNotEmpty) corpo['extras'] = extras;
    if (corpo.length <= 2) {
      setState(() => _erro = 'Preencha ao menos um campo.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await funcaoCobranca(corpo);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final extrasCred = (((widget.banco?['requisitos'] as Map?)?['extras'] as List?) ?? const [])
        .cast<Map>()
        .where((e) => e['onde'] == 'credenciais')
        .toList();
    return AlertDialog(
      title: Text('Credenciais · ${widget.conta['nome']}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Do portal do desenvolvedor do banco (aplicação de cobrança). Ficam cifradas no ServPilot: ninguém vê '
                'de novo, nem nós. Para trocar, informe o novo valor.',
                style: TextStyle(color: Cores.neutro)),
            const SizedBox(height: 8),
            TextField(controller: _clientId, decoration: InputDecoration(labelText: _rotulo('client_id', 'Client ID'))),
            TextField(
                controller: _segredo,
                obscureText: true,
                decoration: InputDecoration(labelText: _rotulo('client_secret', 'Client secret'))),
            if (widget.conta['banco'] == '001' || _pede.contains('chave_aplicacao'))
              TextField(
                  controller: _chaveApp,
                  obscureText: true,
                  decoration: InputDecoration(labelText: _rotulo('chave_aplicacao', 'Chave da aplicação (gw-dev-app-key)'))),
            for (final e in extrasCred)
              TextField(
                controller: _extras.putIfAbsent('${e['chave']}', TextEditingController.new),
                obscureText: true,
                decoration: InputDecoration(labelText: '${e['rotulo']}${e['obrigatorio'] == true ? ' *' : ''}'),
              ),
            const SizedBox(height: 12),
            Text(
                'Certificado digital A1 (.pfx)${_pede.contains('certificado_pem') ? ' *' : ''}'
                '${_ja.contains('certificado_pem') ? ' · já informado${widget.conta['certificado_valido_ate'] != null ? ', vale até ${dataBr(widget.conta['certificado_valido_ate'])}' : ''}' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Row(children: [
              OutlinedButton.icon(
                  onPressed: _escolherPfx, icon: const Icon(Icons.upload_file), label: Text(_pfxNome ?? 'Escolher arquivo')),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                    controller: _senhaCert, obscureText: true, decoration: const InputDecoration(labelText: 'Senha do certificado')),
              ),
            ]),
            const Text('O arquivo e a senha não são guardados: viram a chave do mTLS, cifrada.',
                style: TextStyle(color: Cores.neutro, fontSize: 12)),
            if (_erro != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(_erro!, style: const TextStyle(color: Cores.erro))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _salvando ? null : () => Navigator.pop(context), child: const Text('Voltar')),
        FilledButton(onPressed: _salvando ? null : _salvar, child: Text(_salvando ? 'Gravando…' : 'Gravar')),
      ],
    );
  }
}
