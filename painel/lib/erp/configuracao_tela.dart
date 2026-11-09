import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/status.dart' show dataHoraBr;
import '../widgets/margem.dart';
import 'servico.dart';

/// Administração › ERP (Protheus) (guia 105): ligar a integração, o endereço
/// do REST do Protheus, Basic ou OAuth2, empresa e filial (tenantId), o
/// usuário e a senha (cifrados, nunca voltam para a tela), quem é o dono do
/// cadastro dos equipamentos (decisão 7), o que integrar, o de-para (produto
/// e TES da locação, condição de pagamento...) e "importar agora".
class ErpConfiguracaoTela extends StatefulWidget {
  const ErpConfiguracaoTela({super.key});

  @override
  State<ErpConfiguracaoTela> createState() => _ErpConfiguracaoTelaState();
}

/// De-para: chave, rótulo e ajuda.
const _dePara = [
  ('produto_locacao', 'Produto da locação (B1_COD)', 'Item do pedido de venda da locação.'),
  ('tes_locacao', 'TES da locação', 'Saída sem ISS (locação de bem móvel).'),
  ('produto_avaria', 'Produto da avaria (B1_COD)', 'Vazio = o da locação.'),
  ('tes_avaria', 'TES da avaria', 'Vazio = a da locação.'),
  ('produto_cobranca', 'Produto da cobrança (B1_COD)', 'Cobrança "Pelo ERP" como pedido. Vazio = o da locação.'),
  ('tes_cobranca', 'TES da cobrança', ''),
  ('condicao_pagamento', 'Condição de pagamento (E4_CODIGO)', ''),
  ('natureza', 'Natureza financeira (ED_CODIGO)', ''),
  ('produto_compra', 'Produto genérico de compras', 'Item da solicitação sem produto importado.'),
  ('centro_custo_padrao', 'Centro de custo padrão (CTT)', 'Quando o equipamento não tem.'),
  ('armazem', 'Armazém das compras', 'Ex.: 01'),
  ('prefixo_titulo', 'Prefixo do título', 'Cobrança como título. Ex.: SPL'),
  ('tipo_titulo', 'Tipo do título', 'Padrão: DP'),
];

const _naturezas = {
  'outros': 'Outros',
  'reparo': 'Reparo',
  'corretiva': 'Corretiva',
  'preventiva': 'Preventiva',
  'preparacao': 'Preparação',
  'retrofit': 'Retrofit',
  'frete': 'Frete',
};

class _ErpConfiguracaoTelaState extends State<ErpConfiguracaoTela> {
  Map<String, dynamic>? _r;
  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;
  final _c = <String, TextEditingController>{};
  String _autenticacao = 'oauth2';
  String _leitura = 'servpilot';
  String _origem = 'atf';
  String _dono = 'servpilot';
  String _cobrancaComo = 'pedido';
  String _naturezaCusto = 'outros';
  String? _localBase;
  bool _importarDiario = true;
  bool _custoDiario = true;
  final _operacoes = <String, bool>{};

  TextEditingController _t(String k) => _c.putIfAbsent(k, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _config =>
      _r?['config'] is Map ? Map<String, dynamic>.from(_r!['config'] as Map) : <String, dynamic>{};

  Map<String, dynamic> get _parametros =>
      _config['parametros'] is Map ? Map<String, dynamic>.from(_config['parametros'] as Map) : <String, dynamic>{};

  bool get _temEquipamentos => _r?['equipamentos'] == true;

  void _avisar(String t, {bool erro = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Cores.erro : null));

  void _preencher(Map<String, dynamic> r) {
    _r = r;
    final cfg = _config;
    final par = _parametros;
    _t('url_base').text = '${cfg['url_base'] ?? ''}';
    _t('grupo').text = '${cfg['grupo'] ?? ''}';
    _t('filial').text = '${cfg['filial'] ?? ''}';
    _t('prefixo').text = '${cfg['prefixo'] ?? '/servpilot/v1'}';
    _t('timeout_s').text = '${cfg['timeout_s'] ?? 30}';
    for (final d in _dePara) {
      _t(d.$1).text = '${par[d.$1] ?? ''}';
    }
    _autenticacao = '${cfg['autenticacao'] ?? 'oauth2'}';
    _leitura = '${cfg['leitura'] ?? 'servpilot'}';
    _origem = '${cfg['origem_equipamentos'] ?? 'atf'}';
    _dono = '${r['dono_cadastro'] ?? 'servpilot'}';
    _cobrancaComo = '${par['cobranca_como'] ?? 'pedido'}';
    _naturezaCusto = _naturezas.containsKey(par['natureza_custo']) ? '${par['natureza_custo']}' : 'outros';
    _localBase = par['local_base_id'] == null ? null : '${par['local_base_id']}';
    _importarDiario = par['importar_diario'] != false;
    _custoDiario = par['custo_diario'] != false;
    final ops = r['operacoes'] is Map ? Map<String, dynamic>.from(r['operacoes'] as Map) : <String, dynamic>{};
    _operacoes
      ..clear()
      ..addAll({for (final k in operacoesErp.keys) k: ops[k] == true});
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await erpRpc('erp_config');
      if (mounted) setState(() => _preencher(r));
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar(Map<String, dynamic> p, String aviso) async {
    setState(() => _ocupado = true);
    try {
      final r = await erpRpc('erp_config_salvar', p);
      if (!mounted) return;
      setState(() => _preencher(r));
      _avisar(aviso);
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Map<String, dynamic> _dados() {
    final locais = _r?['locais_base'] is List ? _r!['locais_base'] as List : const [];
    final localOk = _localBase != null && locais.any((l) => (l as Map)['id'] == _localBase);
    return {
      'url_base': _t('url_base').text.trim(),
      'autenticacao': _autenticacao,
      'grupo': _t('grupo').text.trim(),
      'filial': _t('filial').text.trim(),
      'leitura': _leitura,
      'prefixo': _t('prefixo').text.trim().isEmpty ? '/servpilot/v1' : _t('prefixo').text.trim(),
      'timeout_s': int.tryParse(_t('timeout_s').text.trim()) ?? 30,
      'operacoes': Map<String, bool>.from(_operacoes),
      'parametros': {
        for (final d in _dePara) d.$1: _t(d.$1).text.trim(),
        'cobranca_como': _cobrancaComo,
        'natureza_custo': _naturezaCusto,
        'importar_diario': _importarDiario,
        'custo_diario': _custoDiario,
        if (_temEquipamentos) 'local_base_id': localOk ? _localBase : null,
      },
      if (_temEquipamentos) 'origem_equipamentos': _origem,
      if (_temEquipamentos) 'dono_cadastro': _dono,
    };
  }

  Future<void> _ligar(bool v) => _salvar({'ativo': v}, v ? 'Integração ligada.' : 'Integração desligada.');

  Future<void> _testar() async {
    setState(() => _ocupado = true);
    try {
      final r = await funcaoErp({'acao': 'testar'});
      if (!mounted) return;
      _avisar('${r['mensagem'] ?? (r['ok'] == true ? 'Conectado.' : 'Falhou.')}', erro: r['ok'] != true);
      await _carregar();
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _credenciais() async {
    final r = await showDialog<(String, String)>(context: context, builder: (_) => const _CredenciaisDialogo());
    if (r == null || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await funcaoErp({'acao': 'credenciais', 'usuario': r.$1, 'senha': r.$2});
      if (!mounted) return;
      _avisar('Usuário e senha gravados (cifrados). Agora teste a conexão.');
      await _carregar();
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _apagarCredenciais() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar usuário e senha?'),
        content: const Text('A integração é desligada até gravar de novo. A fila fica esperando.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await funcaoErp({'acao': 'apagar_credenciais'});
      if (!mounted) return;
      _avisar('Credenciais apagadas.');
      await _carregar();
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _importar(String tipo) async {
    setState(() => _ocupado = true);
    try {
      await erpRpc('erp_importar', {'tipo': tipo});
      final r = await funcaoErp({'acao': 'processar'});
      if (!mounted) return;
      _avisar('Pedido ao Protheus: ${resumoProcessamento(r)} Detalhes na fila.');
      await _carregar();
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ---------- Tela ----------
  Widget _texto(String k, String rotulo, {String? ajuda, double largura = 260, bool numero = false}) => SizedBox(
        width: largura,
        child: TextField(
          controller: _t(k),
          keyboardType: numero ? TextInputType.number : null,
          decoration: InputDecoration(labelText: rotulo, helperText: (ajuda ?? '').isEmpty ? null : ajuda, helperMaxLines: 3),
        ),
      );

  Widget _escolha(String rotulo, Map<String, String> opcoes, String atual, void Function(String) mudar) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(rotulo, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final e in opcoes.entries)
            ChoiceChip(label: Text(e.value), selected: atual == e.key, onSelected: (_) => setState(() => mudar(e.key))),
        ]),
      ]);

  Widget _secao(String titulo, List<Widget> filhos, {String? sub}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (sub != null) Text(sub, style: const TextStyle(color: Cores.neutro)),
            const SizedBox(height: 12),
            ...filhos,
          ]),
        ),
      );

  Widget _linha(IconData i, String t, Color cor) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 18, color: cor),
        const SizedBox(width: 6),
        Flexible(child: Text(t, style: TextStyle(color: cor, fontWeight: FontWeight.w600))),
      ]);

  Widget _situacao() {
    final cfg = _config;
    final ativo = cfg['ativo'] == true;
    final sit = '${cfg['situacao'] ?? 'pendente'}';
    final fila = _r?['fila'] is Map ? Map<String, dynamic>.from(_r!['fila'] as Map) : <String, dynamic>{};
    final cred = _r?['credenciais'] is Map ? Map<String, dynamic>.from(_r!['credenciais'] as Map) : null;
    final cor = sit == 'ok' ? Cores.sucesso : (sit == 'erro' ? Cores.erro : Cores.alerta);
    return _secao('Situação', [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Integração ligada'),
        subtitle: const Text('Desligada, nada é enviado nem importado; o ServPilot funciona igual, sem ERP.'),
        value: ativo,
        onChanged: _ocupado ? null : _ligar,
      ),
      Wrap(spacing: 24, runSpacing: 8, children: [
        _linha(Icons.cable_outlined,
            sit == 'ok' ? 'Conexão testada' : (sit == 'erro' ? 'A conexão falhou' : 'Conexão não testada'), cor),
        _linha(Icons.key_outlined, cred == null ? 'Sem usuário e senha' : 'Usuário ${cred['usuario'] ?? ''} gravado',
            cred == null ? Cores.alerta : Cores.sucesso),
        _linha(Icons.schedule_outlined, '${fila['pendente'] ?? 0} na fila', Cores.indigo500),
        _linha(Icons.error_outline, '${fila['erro'] ?? 0} com erro', (fila['erro'] ?? 0) == 0 ? Cores.neutro : Cores.erro),
      ]),
      if ((cfg['situacao_mensagem'] ?? '') != '') ...[
        const SizedBox(height: 8),
        Text('${cfg['situacao_mensagem']}${cfg['situacao_em'] == null ? '' : ' (${dataHoraBr(cfg['situacao_em'])})'}',
            style: TextStyle(color: sit == 'erro' ? Cores.erro : Cores.neutro)),
      ],
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
            onPressed: _ocupado ? null : _testar, icon: const Icon(Icons.wifi_tethering), label: const Text('Testar a conexão')),
        OutlinedButton.icon(
            onPressed: _ocupado ? null : _credenciais,
            icon: const Icon(Icons.password_outlined),
            label: Text(cred == null ? 'Gravar usuário e senha' : 'Trocar usuário e senha')),
        if (cred != null)
          TextButton(
              onPressed: _ocupado ? null : _apagarCredenciais,
              child: const Text('Apagar credenciais', style: TextStyle(color: Cores.erro))),
        if (_ocupado) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
    ]);
  }

  Widget _conexao() {
    final tenant = _r?['tenant'] is Map ? Map<String, dynamic>.from(_r!['tenant'] as Map) : <String, dynamic>{};
    final http = _t('url_base').text.trim().startsWith('http://');
    return _secao('Conexão com o REST do Protheus', sub: 'O endereço que a TI do cliente liberou (veja o guia 105).', [
      _texto('url_base', 'URL base do REST', largura: 560, ajuda: 'Ex.: https://minhaempresa.protheus.cloudtotvs.com.br:4050/rest'),
      if (http)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Sem HTTPS o usuário e a senha trafegam abertos: só para teste.', style: TextStyle(color: Cores.erro)),
        ),
      const SizedBox(height: 12),
      _escolha('Autenticação', const {'oauth2': 'Token OAuth2 do Protheus', 'basic': 'Basic (usuário e senha)'}, _autenticacao,
          (v) => _autenticacao = v),
      const SizedBox(height: 12),
      Wrap(spacing: 16, runSpacing: 8, children: [
        _texto('grupo', 'Grupo de empresas', largura: 180, ajuda: 'Vazio = o de Integrações (API): ${tenant['grupo'] ?? '-'}'),
        _texto('filial', 'Filial', largura: 180, ajuda: 'Vazio = o de Integrações (API): ${tenant['filial'] ?? '-'}'),
        _texto('prefixo', 'Prefixo dos endpoints do ServPilot', largura: 260, ajuda: 'Padrão: /servpilot/v1'),
        _texto('timeout_s', 'Tempo de espera (s)', largura: 160, numero: true),
      ]),
      const SizedBox(height: 12),
      _escolha('Leitura dos cadastros',
          const {'servpilot': 'Endpoints do ServPilot (TLPP)', 'generic_query': 'API padrão genericQuery'}, _leitura, (v) => _leitura = v),
      const SizedBox(height: 4),
      const Text('Envios (compras, pedidos, títulos), custo realizado e baixas sempre usam os endpoints do ServPilot.',
          style: TextStyle(color: Cores.neutro, fontSize: 12)),
    ]);
  }

  Widget _equipamentos() {
    final locais = (_r?['locais_base'] is List ? _r!['locais_base'] as List : const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final atual = locais.any((l) => l['id'] == _localBase) ? _localBase : null;
    return _secao('Equipamentos', [
      _escolha('Dono do cadastro do equipamento', const {'servpilot': 'ServPilot (envia ao Protheus)', 'erp': 'Protheus (importa)'},
          _dono, (v) => _dono = v),
      const SizedBox(height: 4),
      Text(
          _dono == 'erp'
              ? 'Os bens vêm do Protheus. Descrição, patrimônio, série, marca, modelo, centro de custo e aquisição ficam '
                  'travados aqui; preços, medidor, depósito e observações continuam livres.'
              : 'O cadastro nasce no ServPilot e cada inclusão ou alteração vai para o Protheus. A importação só liga o de-para '
                  '(não sobrescreve).',
          style: const TextStyle(color: Cores.neutro, fontSize: 12)),
      const SizedBox(height: 12),
      _escolha('Onde estão os bens no Protheus', const {'atf': 'Ativo Fixo (SN1)', 'mnt': 'Manutenção de Ativos (ST9)'}, _origem,
          (v) => _origem = v),
      const SizedBox(height: 12),
      SizedBox(
        width: 360,
        child: DropdownButtonFormField<String?>(
          key: ValueKey('local-base-$atual'),
          initialValue: atual,
          decoration: const InputDecoration(labelText: 'Depósito dos importados', helperText: 'Vazio = o primeiro depósito.'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('(o primeiro depósito)')),
            for (final l in locais) DropdownMenuItem<String?>(value: '${l['id']}', child: Text('${l['nome']}')),
          ],
          onChanged: (v) => setState(() => _localBase = v),
        ),
      ),
      const SizedBox(height: 12),
      _escolha('Natureza do custo vindo do ERP (quando a nota não diz)', _naturezas, _naturezaCusto, (v) => _naturezaCusto = v),
    ]);
  }

  Widget _oQueIntegrar() {
    final cobrancaOk = _r?['cobranca_disponivel'] == true;
    return _secao('O que integrar', [
      for (final e in operacoesErp.entries)
        if (_temEquipamentos || !const {'importar_equipamentos', 'enviar_equipamentos', 'pedido_locacao', 'pedido_avaria'}.contains(e.key))
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(e.value.$1),
            subtitle: Text(e.key == 'cobranca' && !cobrancaOk
                ? '${e.value.$2} (a cobrança parametrizável ainda não está nesta versão)'
                : e.value.$2),
            value: _operacoes[e.key] == true,
            onChanged: (v) => setState(() => _operacoes[e.key] = v),
          ),
      const Divider(),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Importar os cadastros todo dia'),
        subtitle: const Text('Clientes, produtos e (com o Protheus dono) equipamentos, só o que mudou.'),
        value: _importarDiario,
        onChanged: (v) => setState(() => _importarDiario = v),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Ler o custo realizado todo dia'),
        subtitle: const Text('Do mês passado até hoje: nota que chega atrasada entra; a mesma nota nunca entra duas vezes.'),
        value: _custoDiario,
        onChanged: (v) => setState(() => _custoDiario = v),
      ),
    ]);
  }

  Widget _secaoDePara() => _secao('De-para do Faturamento e do Compras', sub: 'Códigos do Protheus. Confira com o consultor.', [
        Wrap(spacing: 16, runSpacing: 8, children: [
          for (final d in _dePara) _texto(d.$1, d.$2, ajuda: d.$3),
        ]),
        const SizedBox(height: 12),
        _escolha('Cobrança pelo ERP vira', const {'pedido': 'Pedido de venda', 'titulo': 'Título a receber'}, _cobrancaComo,
            (v) => _cobrancaComo = v),
      ]);

  Widget _importarAgora() => _secao('Importar agora', sub: 'Vai para a fila e roda na hora; o resultado fica na fila.', [
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
              onPressed: _ocupado ? null : () => _importar('clientes'),
              icon: const Icon(Icons.people_outline),
              label: const Text('Clientes')),
          OutlinedButton.icon(
              onPressed: _ocupado ? null : () => _importar('produtos'),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Produtos')),
          if (_temEquipamentos)
            OutlinedButton.icon(
                onPressed: _ocupado ? null : () => _importar('equipamentos'),
                icon: const Icon(Icons.construction_outlined),
                label: const Text('Equipamentos')),
          if (_temEquipamentos)
            OutlinedButton.icon(
                onPressed: _ocupado ? null : () => _importar('custos'),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Custo realizado')),
          if (_operacoes['cobranca'] == true)
            OutlinedButton.icon(
                onPressed: _ocupado ? null : () => _importar('baixas'),
                icon: const Icon(Icons.price_check_outlined),
                label: const Text('Baixas da cobrança')),
        ]),
      ]);

  @override
  Widget build(BuildContext context) {
    if (_carregando && _r == null) return const Center(child: CircularProgressIndicator());
    if (_erro != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_erro!, style: const TextStyle(color: Cores.erro)),
          TextButton(onPressed: _carregar, child: const Text('Tentar de novo')),
        ]),
      );
    }
    final ativo = _config['ativo'] == true;
    return SingleChildScrollView(
      padding: margemDaTela(context),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text('ERP (Protheus)',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                  onPressed: () => context.go('/erp/fila'), icon: const Icon(Icons.sync_alt), label: const Text('Fila do ERP')),
            ]),
            const Text('O ServPilot opera o campo e o depósito; o Protheus segue dono de compras, custos e faturamento. '
                'Tudo passa por uma fila: com o Protheus fora do ar, a operação continua e a fila espera.',
                style: TextStyle(color: Cores.neutro)),
            const SizedBox(height: 12),
            _situacao(),
            const SizedBox(height: 12),
            _conexao(),
            if (_temEquipamentos) ...[
              const SizedBox(height: 12),
              _equipamentos(),
            ],
            const SizedBox(height: 12),
            _oQueIntegrar(),
            const SizedBox(height: 12),
            _secaoDePara(),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 8, children: [
              FilledButton.icon(
                  onPressed: _ocupado ? null : () => _salvar(_dados(), 'Configuração salva.'),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Salvar')),
              if (_ocupado) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            if (ativo) ...[
              const SizedBox(height: 16),
              _importarAgora(),
            ],
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}

class _CredenciaisDialogo extends StatefulWidget {
  const _CredenciaisDialogo();

  @override
  State<_CredenciaisDialogo> createState() => _CredenciaisDialogoState();
}

class _CredenciaisDialogoState extends State<_CredenciaisDialogo> {
  final _usuario = TextEditingController();
  final _senha = TextEditingController();
  bool _ver = false;

  @override
  void dispose() {
    _usuario.dispose();
    _senha.dispose();
    super.dispose();
  }

  void _gravar() {
    if (_usuario.text.trim().isEmpty || _senha.text.isEmpty) return;
    Navigator.pop(context, (_usuario.text.trim(), _senha.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Usuário do REST do Protheus'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Use um usuário só da integração, com acesso apenas às rotinas do guia 105. A senha é cifrada e '
              'nunca volta para a tela.', style: TextStyle(color: Cores.neutro)),
          const SizedBox(height: 12),
          TextField(controller: _usuario, autofocus: true, decoration: const InputDecoration(labelText: 'Usuário')),
          const SizedBox(height: 8),
          TextField(
            controller: _senha,
            obscureText: !_ver,
            decoration: InputDecoration(
              labelText: 'Senha',
              suffixIcon: IconButton(
                icon: Icon(_ver ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _ver = !_ver),
              ),
            ),
            onSubmitted: (_) => _gravar(),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _gravar, child: const Text('Gravar')),
      ],
    );
  }
}
