import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/arquivo_web.dart';
import '../servicos/notas.dart';
import '../servicos/status.dart' show dataBr;
import '../widgets/itens_os.dart' show dinheiro;
import '../widgets/margem.dart';

/// Configuração fiscal (guia 81): contratar a emissão de notas, os dados
/// fiscais da empresa (com a busca na Receita pelo CNPJ), o certificado
/// digital A1 (vai direto para a Focus NFe, não fica guardado aqui) e o
/// ambiente (teste ou produção). Só o gestor altera; o financeiro vê.
class FiscalTela extends StatefulWidget {
  const FiscalTela({super.key});

  @override
  State<FiscalTela> createState() => _FiscalTelaState();
}

const _regimes = {
  1: 'Simples Nacional',
  2: 'Simples Nacional (excesso de sublimite)',
  3: 'Lucro Presumido ou Real',
  4: 'MEI',
};

const _pecas = {
  'nfe': 'NF-e separada (modelo 55)',
  'nfse': 'Junto na NFS-e',
  'nenhuma': 'Não emitir nota das peças',
};

class _FiscalTelaState extends State<FiscalTela> {
  Map<String, dynamic>? _r;
  bool _carregando = true;
  bool _salvando = false;
  String? _erro;
  int? _regime;
  String _nfsePadrao = 'nacional';
  String _pecasNaNota = 'nfe';
  bool _issRetido = false;
  bool _enviarEmail = true;
  bool _avancado = false;
  final _c = <String, TextEditingController>{};

  SupabaseClient get _db => Supabase.instance.client;

  static const _campos = [
    'inscricao_municipal', 'inscricao_estadual', 'codigo_municipio', 'cnae', 'servico_codigo_nacional',
    'servico_codigo_municipal', 'servico_nbs', 'iss_aliquota', 'descricao_padrao', 'ibs_cbs_cst',
    'ibs_cbs_classificacao', 'nfe_natureza', 'nfe_cfop_dentro', 'nfe_cfop_fora', 'nfe_icms_situacao',
    'nfe_icms_aliquota', 'nfe_pis_cofins_situacao',
  ];

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

  void _avisar(String t, {bool erro = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Cores.erro : null));

  void _preencher(Map<String, dynamic> r) {
    final cfg = r['config'] is Map ? Map<String, dynamic>.from(r['config'] as Map) : <String, dynamic>{};
    for (final k in _campos) {
      final v = cfg[k];
      _t(k).text = v == null ? '' : '$v'.replaceAll('.', k.contains('aliquota') ? ',' : '.');
    }
    _regime = (cfg['regime_tributario'] as num?)?.toInt();
    _nfsePadrao = '${cfg['nfse_padrao'] ?? 'nacional'}';
    _pecasNaNota = '${cfg['pecas_na_nota'] ?? 'nfe'}';
    _issRetido = cfg['iss_retido_padrao'] == true;
    _enviarEmail = cfg['enviar_email_tomador'] != false;
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('fiscal_config') as Map);
      if (mounted) {
        setState(() {
          _r = r;
          _preencher(r);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Map<String, dynamic> get _config => _r?['config'] is Map ? Map<String, dynamic>.from(_r!['config'] as Map) : {};

  // ---------- Contratar (com a faixa), trocar a faixa ou cancelar (guia 86) ----------
  Map<String, dynamic> get _precos => Map<String, dynamic>.from((_r?['precos'] as Map?) ?? const {});

  List<Map<String, dynamic>> get _faixas =>
      ((_precos['faixas'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  int get _faixaAtual => (_r?['faixa'] as num?)?.toInt() ?? 1;

  String get _faixaContratada {
    for (final f in _faixas) {
      if ((f['faixa'] as num).toInt() == _faixaAtual) return _textoFaixa(f);
    }
    return 'faixa $_faixaAtual';
  }

  String _textoFaixa(Map<String, dynamic> f) => 'Até ${f['notas']} notas por mês · ${dinheiro(f['valor'])} por mês';

  Future<int?> _escolherFaixa(String titulo, String botao, int atual) => showDialog<int>(
        context: context,
        builder: (_) {
          var escolha = atual;
          return StatefulBuilder(
            builder: (context, setD) => AlertDialog(
              title: Text(titulo),
              content: SizedBox(
                width: 480,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final f in _faixas)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      selected: (f['faixa'] as num).toInt() == escolha,
                      leading: Icon((f['faixa'] as num).toInt() == escolha
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked),
                      title: Text(_textoFaixa(f)),
                      onTap: () => setD(() => escolha = (f['faixa'] as num).toInt()),
                    ),
                  const SizedBox(height: 8),
                  Text(
                      'NFS-e e NF-e somadas, por empresa (CNPJ) que emite. Nota além da faixa: '
                      '${dinheiro(_precos['valor_extra'])} cada, na mensalidade seguinte. As notas de teste '
                      '(homologação) não contam. O valor do módulo entra na próxima mensalidade.',
                      style: const TextStyle(color: Cores.neutro)),
                ]),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
                FilledButton(onPressed: () => Navigator.pop(context, escolha), child: Text(botao)),
              ],
            ),
          );
        },
      );

  Future<void> _chamarModulo(Map<String, dynamic> p, String aviso) async {
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('notas_modulo', params: {'p': p}) as Map);
      if (!mounted) return;
      setState(() {
        _r = r;
        _preencher(r);
      });
      _avisar(aviso);
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  Future<void> _trocarFaixa() async {
    final atual = _faixaAtual;
    final f = await _escolherFaixa('Trocar a faixa de notas', 'Trocar', atual);
    if (f == null || f == atual) return;
    await _chamarModulo({'acao': 'faixa', 'faixa': f}, 'Faixa trocada. O novo valor entra na próxima mensalidade.');
  }

  Future<void> _modulo(String acao) async {
    if (acao == 'contratar') {
      final f = await _escolherFaixa('Contratar a emissão de notas', 'Contratar', 1);
      if (f == null) return;
      await _chamarModulo({'acao': 'contratar', 'faixa': f}, 'Emissão de notas contratada. Agora configure abaixo.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar a emissão de notas'),
        content: const Text('As notas já emitidas continuam valendo e aparecendo aqui. Não dá mais para emitir novas até '
            'contratar de novo. O módulo sai da próxima mensalidade.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancelar o módulo')),
        ],
      ),
    );
    if (ok != true) return;
    await _chamarModulo({'acao': 'cancelar'}, 'Módulo cancelado.');
  }

  // ---------- Receita (CNPJ) e CEP ----------
  Future<void> _buscarReceita() async {
    try {
      final r = await funcaoNotas({'acao': 'cnpj'});
      final end = Map<String, dynamic>.from((r['endereco'] as Map?) ?? const {});
      setState(() {
        if (r['regime_sugerido'] is num) _regime = (r['regime_sugerido'] as num).toInt();
        if ((r['cnae'] ?? '') != '') _t('cnae').text = '${r['cnae']}';
        if ((end['codigo_ibge'] ?? '') != '') _t('codigo_municipio').text = '${end['codigo_ibge']}';
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Dados da Receita'),
          content: Text([
            '${r['razao_social'] ?? ''}',
            if ((r['nome_fantasia'] ?? '') != '') 'Fantasia: ${r['nome_fantasia']}',
            'Situação: ${r['situacao_cadastral'] ?? '-'}',
            'Regime: ${_regimes[r['regime_sugerido']] ?? '-'}',
            'CNAE principal: ${r['cnae'] ?? '-'}',
            'Município: ${end['cidade'] ?? '-'}/${end['uf'] ?? ''} (IBGE ${end['codigo_ibge'] ?? '-'})',
            '',
            'Preenchi o regime, o CNAE e o município. Confira com o seu contador. '
                'A inscrição estadual e a municipal não vêm da Receita: digite.',
          ].join('\n')),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendi'))],
        ),
      );
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  // ---------- Salvar ----------
  Map<String, dynamic> _dados() => {
        for (final k in _campos) k: _t(k).text.trim(),
        'regime_tributario': _regime,
        'nfse_padrao': _nfsePadrao,
        'pecas_na_nota': _pecasNaNota,
        'iss_retido_padrao': _issRetido,
        'enviar_email_tomador': _enviarEmail,
      };

  Future<void> _salvar() async {
    if (_regime == null) {
      _avisar('Escolha o regime tributário.', erro: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      var r = Map<String, dynamic>.from(await _db.rpc('fiscal_salvar', params: {'p': _dados()}) as Map);
      // Já cadastrada na Focus: manda as mudanças para lá também.
      if (r['config'] is Map && (r['config'] as Map)['focus_empresa_id'] != null) {
        await funcaoNotas({'acao': 'empresa'});
        r = Map<String, dynamic>.from(await _db.rpc('fiscal_config') as Map);
        _avisar('Configuração salva e enviada para a Focus.');
      } else {
        _avisar('Configuração salva. Agora envie o certificado digital.');
      }
      setState(() {
        _r = r;
        _preencher(r);
      });
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
      _carregar();
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  // ---------- Certificado ----------
  Future<void> _enviarCertificado() async {
    final arq = await escolherArquivo(aceitar: '.pfx,.p12,application/x-pkcs12');
    if (arq == null || !mounted) return;
    final senha = await showDialog<String>(context: context, builder: (_) => _SenhaCertificado(nome: arq.nome));
    if (senha == null || senha.isEmpty) return;
    setState(() => _salvando = true);
    try {
      // Antes, grava o que está na tela (o cadastro na Focus usa esses dados).
      await _db.rpc('fiscal_salvar', params: {'p': _dados()});
      final r = await funcaoNotas({'acao': 'empresa', 'certificado_base64': base64Encode(arq.bytes), 'senha': senha});
      _avisar('Certificado aceito, válido até ${dataBr(r['certificado_valido_ate'])}.');
      await _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
      _carregar();
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _ambiente(String amb) async {
    if (amb == 'producao') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Passar para produção?'),
          content: const Text('Daqui em diante as notas emitidas valem de verdade (vão para a prefeitura e a SEFAZ) '
              'e contam no plano. Faça antes ao menos uma nota de teste de cada tipo.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Passar para produção')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('fiscal_salvar', params: {
        'p': {'ambiente': amb}
      }) as Map);
      setState(() {
        _r = r;
        _preencher(r);
      });
      _avisar(amb == 'producao' ? 'Emissão em produção.' : 'Emissão em teste (homologação).');
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  // ---------- Tela ----------
  Widget _texto(String k, String rotulo, {String? ajuda, double largura = 260, int linhas = 1}) => SizedBox(
        width: largura,
        child: TextField(
          controller: _t(k),
          maxLines: linhas,
          decoration: InputDecoration(labelText: rotulo, helperText: ajuda, helperMaxLines: 3),
        ),
      );

  Widget _escolha<T>(String rotulo, Map<T, String> opcoes, T? atual, void Function(T) mudar) =>
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

  Widget _contratar() {
    return _secao('Emissão de notas fiscais', [
      const Text('NFS-e dos serviços e NF-e das peças direto das OS: uma a uma ou o mês inteiro de uma vez, '
          'juntando as OS de cada cliente. O cliente recebe a nota por e-mail.'),
      const SizedBox(height: 8),
      for (final f in _faixas) Text('• ${_textoFaixa(f)}'),
      const SizedBox(height: 4),
      Text('Nota além da faixa: ${dinheiro(_precos['valor_extra'])} cada.', style: const TextStyle(color: Cores.neutro)),
      const SizedBox(height: 12),
      FilledButton.icon(
          onPressed: () => _modulo('contratar'),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Contratar')),
    ]);
  }

  Widget _situacao() {
    final cfg = _config;
    final focus = '${cfg['focus_situacao'] ?? 'pendente'}';
    final validoAte = DateTime.tryParse('${cfg['certificado_valido_ate'] ?? ''}');
    final vencendo = validoAte != null && validoAte.isBefore(DateTime.now().add(const Duration(days: 30)));
    final pronta = _r?['pronta'] == true;
    final consumo = Map<String, dynamic>.from((_r?['consumo'] as Map?) ?? const {});
    final producao = cfg['ambiente'] == 'producao';
    return _secao('Situação', [
      Wrap(spacing: 24, runSpacing: 8, children: [
        _linha(Icons.verified_outlined, pronta ? 'Pronta para emitir' : 'Falta configurar',
            pronta ? Cores.sucesso : Cores.alerta),
        _linha(Icons.badge_outlined,
            validoAte == null ? 'Sem certificado' : 'Certificado até ${dataBr(cfg['certificado_valido_ate'])}',
            validoAte == null ? Cores.alerta : (vencendo ? Cores.erro : Cores.sucesso)),
        _linha(Icons.cloud_done_outlined,
            focus == 'ok' ? 'Cadastro na Focus em dia' : (focus == 'erro' ? 'Focus recusou' : 'Cadastro na Focus pendente'),
            focus == 'ok' ? Cores.sucesso : (focus == 'erro' ? Cores.erro : Cores.alerta)),
        if (consumo.isNotEmpty)
          _linha(Icons.receipt_outlined, '${consumo['usadas']} de ${consumo['incluidas']} notas neste ciclo', Cores.indigo500),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Faixa: $_faixaContratada', style: const TextStyle(fontWeight: FontWeight.w600)),
        TextButton(onPressed: _trocarFaixa, child: const Text('Trocar a faixa')),
      ]),
      if (focus == 'erro' && (cfg['focus_erro'] ?? '') != '') ...[
        const SizedBox(height: 8),
        Text('${cfg['focus_erro']}', style: const TextStyle(color: Cores.erro)),
      ],
      if (vencendo) ...[
        const SizedBox(height: 8),
        const Text('O certificado vence em menos de 30 dias: renove e envie o novo arquivo.',
            style: TextStyle(color: Cores.erro)),
      ],
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Ambiente:', style: TextStyle(fontWeight: FontWeight.w600)),
        ChoiceChip(label: const Text('Teste (homologação)'), selected: !producao, onSelected: (_) => _ambiente('homologacao')),
        ChoiceChip(label: const Text('Produção'), selected: producao, onSelected: (_) => _ambiente('producao')),
      ]),
    ]);
  }

  Widget _linha(IconData i, String t, Color cor) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 18, color: cor),
        const SizedBox(width: 6),
        Text(t, style: TextStyle(color: cor, fontWeight: FontWeight.w600)),
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
    final contratado = _r?['contratado'] == true;
    final empresa = Map<String, dynamic>.from((_r?['empresa'] as Map?) ?? const {});
    return SingleChildScrollView(
      padding: margemDaTela(context),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text('Configuração fiscal',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (contratado)
                TextButton.icon(
                    onPressed: () => context.go('/notas'),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Notas fiscais')),
            ]),
            Text('${empresa['razao_social'] ?? ''} · CNPJ ${empresa['documento'] ?? 'não preenchido'}',
                style: const TextStyle(color: Cores.neutro)),
            const SizedBox(height: 12),
            if (!contratado) _contratar(),
            if (contratado) ...[
              _situacao(),
              const SizedBox(height: 12),
              _secao('Empresa', sub: 'Confira com o seu contador.', [
                OutlinedButton.icon(
                    onPressed: _buscarReceita,
                    icon: const Icon(Icons.travel_explore),
                    label: const Text('Buscar dados na Receita pelo CNPJ')),
                const SizedBox(height: 12),
                _escolha<int>('Regime tributário', _regimes, _regime, (v) => _regime = v),
                const SizedBox(height: 12),
                Wrap(spacing: 16, runSpacing: 8, children: [
                  _texto('inscricao_municipal', 'Inscrição municipal'),
                  _texto('inscricao_estadual', 'Inscrição estadual', ajuda: 'Só para emitir NF-e das peças.'),
                  _texto('codigo_municipio', 'Município (código IBGE)', ajuda: '7 dígitos. Ex.: Cascavel/PR = 4104808.'),
                  _texto('cnae', 'CNAE principal'),
                ]),
              ]),
              const SizedBox(height: 12),
              _secao('Nota de serviço (NFS-e)', [
                _escolha<String>('Padrão da nota', {'nacional': 'NFS-e Nacional', 'municipal': 'Da prefeitura'},
                    _nfsePadrao, (v) => _nfsePadrao = v),
                const SizedBox(height: 4),
                const Text('MEI e Simples Nacional usam a NFS-e Nacional. "Da prefeitura" só se a sua cidade ainda exigir.',
                    style: TextStyle(color: Cores.neutro, fontSize: 12)),
                const SizedBox(height: 12),
                Wrap(spacing: 16, runSpacing: 8, children: [
                  _texto('servico_codigo_nacional', 'Código de tributação nacional',
                      ajuda: '6 dígitos. Manutenção de ar-condicionado costuma ser 14.01.01 (confira com o contador).'),
                  _texto('servico_codigo_municipal', 'Código do serviço na prefeitura', ajuda: 'Se a prefeitura pedir.'),
                  _texto('servico_nbs', 'NBS', ajuda: '9 dígitos.'),
                  _texto('iss_aliquota', 'Alíquota do ISS (%)', ajuda: 'Simples: deixe em branco (vai pelo DAS).', largura: 200),
                ]),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('ISS retido pelo cliente (padrão)'),
                  subtitle: const Text('Prefeituras e empresas grandes costumam reter. Dá para mudar em cada nota.'),
                  value: _issRetido,
                  onChanged: (v) => setState(() => _issRetido = v),
                ),
                _texto('descricao_padrao', 'Descrição padrão do serviço',
                    ajuda: '{os} vira o número das OS. Ex.: "Manutenção de ar-condicionado conforme {os}."',
                    largura: 760, linhas: 2),
              ]),
              const SizedBox(height: 12),
              _secao('Peças', [
                _escolha<String>('Nota das peças usadas nas OS', _pecas, _pecasNaNota, (v) => _pecasNaNota = v),
                const SizedBox(height: 4),
                const Text('NF-e precisa da inscrição estadual da empresa e do NCM em cada produto (Catálogo).',
                    style: TextStyle(color: Cores.neutro, fontSize: 12)),
              ]),
              const SizedBox(height: 12),
              _secao('Entrega', [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mandar a nota por e-mail para o cliente'),
                  subtitle: const Text('Usa o "E-mail para nota" do cliente (ou o e-mail dele).'),
                  value: _enviarEmail,
                  onChanged: (v) => setState(() => _enviarEmail = v),
                ),
              ]),
              const SizedBox(height: 12),
              ExpansionTile(
                title: const Text('Avançado (impostos da NF-e e reforma tributária)'),
                initiallyExpanded: _avancado,
                onExpansionChanged: (v) => _avancado = v,
                childrenPadding: const EdgeInsets.all(16),
                children: [
                  Wrap(spacing: 16, runSpacing: 8, children: [
                    _texto('nfe_natureza', 'Natureza da operação (NF-e)'),
                    _texto('nfe_cfop_dentro', 'CFOP dentro do estado', largura: 200),
                    _texto('nfe_cfop_fora', 'CFOP fora do estado', largura: 200),
                    _texto('nfe_icms_situacao', 'CSOSN / CST do ICMS', ajuda: 'Simples: 102. Normal: 00.', largura: 200),
                    _texto('nfe_icms_aliquota', 'Alíquota do ICMS (%)', largura: 200),
                    _texto('nfe_pis_cofins_situacao', 'CST do PIS/COFINS', largura: 200),
                    _texto('ibs_cbs_cst', 'CST do IBS/CBS', largura: 200),
                    _texto('ibs_cbs_classificacao', 'Classificação do IBS/CBS', largura: 200),
                  ]),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 8, children: [
                FilledButton.icon(
                    onPressed: _salvando ? null : _salvar,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Salvar')),
                OutlinedButton.icon(
                    onPressed: _salvando ? null : _enviarCertificado,
                    icon: const Icon(Icons.badge_outlined),
                    label: Text(_config['certificado_valido_ate'] == null
                        ? 'Enviar o certificado digital (A1)'
                        : 'Trocar o certificado digital')),
                if (_salvando) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              const SizedBox(height: 8),
              const Text(
                  'O certificado (.pfx) e a senha vão direto para a Focus NFe, que assina as notas. O ServPilot não guarda o arquivo.',
                  style: TextStyle(color: Cores.neutro, fontSize: 12)),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                    onPressed: () => _modulo('cancelar'),
                    child: const Text('Cancelar a emissão de notas', style: TextStyle(color: Cores.erro))),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _SenhaCertificado extends StatefulWidget {
  const _SenhaCertificado({required this.nome});
  final String nome;

  @override
  State<_SenhaCertificado> createState() => _SenhaCertificadoState();
}

class _SenhaCertificadoState extends State<_SenhaCertificado> {
  final _senha = TextEditingController();
  bool _ver = false;

  @override
  void dispose() {
    _senha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Senha do certificado'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Arquivo: ${widget.nome}', style: const TextStyle(color: Cores.neutro)),
          const SizedBox(height: 12),
          TextField(
            controller: _senha,
            obscureText: !_ver,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Senha',
              suffixIcon: IconButton(
                icon: Icon(_ver ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _ver = !_ver),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _senha.text), child: const Text('Enviar')),
      ],
    );
  }
}
