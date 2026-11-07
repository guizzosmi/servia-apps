import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/parametros.dart';
import '../servicos/status.dart' show dataHoraBr;
import '../widgets/margem.dart';

/// Conector do Claude (guia 91): endereço do servidor MCP e o app "Claude AI" cadastrado no OAuth do Supabase
/// (cliente público, sem segredo).
const _conectorUrl = 'https://srtokvosnwtyewiempyw.supabase.co/functions/v1/mcp';
const _conectorClientId = 'b2fe06d9-a2a0-42c7-950f-44b3e7eba7f8';

/// Configurações da empresa (só o admin altera): preventivas, orçamento no
/// app, assinatura do cliente e mensagens. Os valores ficam em empresa_config.parametros.
class ConfiguracoesTela extends StatefulWidget {
  const ConfiguracoesTela({super.key});

  @override
  State<ConfiguracoesTela> createState() => _ConfiguracoesTelaState();
}

const _quemMonta = {
  'gestor': 'Só o gestor (pelo painel)',
  'gestor_lider': 'Gestor e o líder da equipe (no app)',
  'todos': 'Gestor e toda a equipe (no app)',
};

const _itensAvulsos = {
  'desligado': 'Não: só itens do catálogo',
  'gestor': 'Sim, mas o orçamento vem para o gestor revisar antes do cliente',
  'liberado': 'Sim: o técnico digita descrição e preço e já colhe a assinatura',
};

const _aceiteConclusao = {
  'desligado': 'Não pedir',
  'opcional': 'Oferecer (o técnico escolhe)',
  'obrigatorio': 'Obrigatória quando o cliente acompanhou',
};

// Guia 54: impressão da OS (recibo no app e PDF da OS).
const _osValores = {
  'perguntar': 'Perguntar na hora (o técnico escolhe no app)',
  'com': 'Sempre com os valores (preço de cada item e total)',
  'sem': 'Sempre sem os valores (só o serviço, as peças e as quantidades)',
};

const _osPapel = {
  'a4': 'Folha A4 (impressora comum ou PDF)',
  '80mm': 'Bobina de 80 mm (impressora térmica)',
  '58mm': 'Bobina de 58 mm (impressora térmica portátil)',
};

class _ConfiguracoesTelaState extends State<ConfiguracoesTela> {
  SupabaseClient get _db => Supabase.instance.client;

  bool _carregando = true;
  bool _salvando = false;
  String? _erro;
  Map<String, dynamic> _parametros = {};

  String _quem = 'gestor_lider';
  String _conclusao = 'opcional';
  String _valoresOs = 'perguntar';
  String _papelOs = 'a4';
  String _avulsos = 'desligado';
  final _desconto = TextEditingController();
  final _validade = TextEditingController();
  final _termo = TextEditingController();
  // Modelos das mensagens do WhatsApp (o padrão vem do pacote comum).
  final _modelos = {for (final m in modelosMensagem) m.chave: TextEditingController()};
  // Preventivas: menu, PMOC e os números da geração e dos cards.
  bool _usaPrev = true;
  bool _pmoc = false;
  bool _manutencaoPropria = false;
  bool _modoSimples = false;
  bool _usaEstoque = false;
  // Guia 90: módulo Comercial (incluído no plano ou com valor por mês).
  bool _usaComercial = false;
  Map<String, dynamic>? _precoComercial;
  // Guia 91: o que o Claude (conector) pode fazer nesta empresa. Consultar é sempre liberado.
  final Map<String, bool> _conector = {'comercial': true, 'cadastros': false, 'operacao': false, 'financeiro': false};
  // Guia 60: garantia padrão e numeração (próximo número da OS, orçamento e contrato).
  final _garantiaDias = TextEditingController();
  final _numeros = {for (final t in const ['os', 'orcamento', 'contrato']) t: TextEditingController()};
  Map<String, dynamic> _numerosAtuais = {};
  bool _gravandoNumeros = false;
  final _antecedencia = TextEditingController();
  // Guia 64: lembrete de limpeza.
  bool _lembUsa = false;
  bool _lembAuto = false;
  final _lembMeses = TextEditingController();
  final _lembAntec = TextEditingController();
  // Guia 65: WhatsApp oficial.
  final _waPhoneId = TextEditingController();
  final _waNumero = TextEditingController();
  final _waModelo = TextEditingController();
  bool _waResposta = true;
  bool _waAssistente = true; // Guia 78: o dono pergunta pelo WhatsApp.
  // Guia 73: Pix para receber.
  String _pixTipo = 'cpf_cnpj';
  final _pixChave = TextEditingController();
  final _pixNome = TextEditingController();
  final _pixCidade = TextEditingController();
  final _tolerancia = TextEditingController();
  // PMOC: o responsável técnico padrão (o assistente do plano já preenche).
  final _rtNome = TextEditingController();
  final _rtRegistro = TextEditingController();
  final _rtArt = TextEditingController();
  bool _fotoObrigatoria = true;
  // IA: relato por áudio e o texto de encerramento das OS.
  bool _relatoAudio = true;
  final _encerramento = TextEditingController();
  // Privacidade e retenção (guia 38): prazos e a última limpeza.
  final _audiosDias = TextEditingController();
  final _localDias = TextEditingController();
  final _mensagensDias = TextEditingController();
  Map<String, dynamic> _retencao = {};
  bool _sujo = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _desconto.dispose();
    _validade.dispose();
    _termo.dispose();
    _antecedencia.dispose();
    _lembMeses.dispose();
    _lembAntec.dispose();
    _waPhoneId.dispose();
    _waNumero.dispose();
    _waModelo.dispose();
    _pixChave.dispose();
    _pixNome.dispose();
    _pixCidade.dispose();
    _tolerancia.dispose();
    _garantiaDias.dispose();
    for (final c in _numeros.values) {
      c.dispose();
    }
    _rtNome.dispose();
    _rtRegistro.dispose();
    _rtArt.dispose();
    _encerramento.dispose();
    _audiosDias.dispose();
    _localDias.dispose();
    _mensagensDias.dispose();
    for (final c in _modelos.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _numero(Object? v) {
    final n = num.tryParse('${v ?? ''}');
    if (n == null) return '';
    return (n == n.roundToDouble() ? n.toInt().toString() : n.toString()).replaceAll('.', ',');
  }

  Future<void> _carregar() async {
    setState(() => _erro = null);
    try {
      final c = await _db
          .from('empresa_config')
          .select('parametros')
          .eq('empresa_id', Sessao.atual!.empresaId!)
          .single();
      final p = Map<String, dynamic>.from((c['parametros'] as Map?) ?? const {});
      final ret = Map<String, dynamic>.from((await _db.rpc('retencao_resumo')) as Map? ?? const {});
      final orc = Map<String, dynamic>.from((p['orcamento'] as Map?) ?? const {});
      var numeros = <String, dynamic>{};
      try {
        numeros = Map<String, dynamic>.from(await _db.rpc('numeracao') as Map);
      } catch (_) {}
      Map<String, dynamic>? precoComercial;
      try {
        precoComercial = Map<String, dynamic>.from(await _db.rpc('comercial_preco') as Map);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _parametros = p;
        _precoComercial = precoComercial;
        _quem = _quemMonta.containsKey(orc['quem_monta']) ? orc['quem_monta'] as String : 'gestor_lider';
        _avulsos = _itensAvulsos.containsKey(orc['itens_avulsos_app']) ? orc['itens_avulsos_app'] as String : 'desligado';
        _conclusao = _aceiteConclusao.containsKey(p['aceite_conclusao']) ? p['aceite_conclusao'] as String : 'opcional';
        final imp = Map<String, dynamic>.from((p['os_impressao'] as Map?) ?? const {});
        _valoresOs = _osValores.containsKey(imp['valores']) ? imp['valores'] as String : 'perguntar';
        _papelOs = _osPapel.containsKey(imp['papel']) ? imp['papel'] as String : 'a4';
        _desconto.text = _numero(orc['desconto_max_app_pct'] ?? 10);
        _validade.text = _numero(orc['validade_dias'] ?? 15);
        _termo.text = '${orc['termo_aceite'] ?? ''}';
        for (final m in modelosMensagem) {
          _modelos[m.chave]!.text = textoDoModelo(m.chave, p['mensagens'] as Map?);
        }
        final prev = Map<String, dynamic>.from((p['preventivas'] as Map?) ?? const {});
        _usaPrev = prev['usa'] != false;
        _pmoc = prev['pmoc'] == true;
        _manutencaoPropria = ParametrosEmpresa.instancia.manutencaoPropria;
        _modoSimples = p['modo_simples'] == true;
        _usaEstoque = (p['estoque'] as Map?)?['usa'] == true;
        _usaComercial = (p['comercial'] as Map?)?['usa'] == true;
        final con = Map<String, dynamic>.from((p['conector'] as Map?) ?? const {});
        _conector['comercial'] = con['comercial'] != false;
        for (final k in const ['cadastros', 'operacao', 'financeiro']) {
          _conector[k] = con[k] == true;
        }
        final lemb = Map<String, dynamic>.from((p['lembrete_limpeza'] as Map?) ?? const {});
        _lembUsa = lemb['usa'] == true;
        _lembAuto = lemb['automatico'] == true;
        _lembMeses.text = _numero(lemb['meses'] ?? 6);
        _lembAntec.text = _numero(lemb['antecedencia_dias'] ?? 7);
        final wa = Map<String, dynamic>.from((p['whatsapp'] as Map?) ?? const {});
        _waPhoneId.text = '${wa['phone_number_id'] ?? ''}';
        _waNumero.text = '${wa['numero'] ?? ''}';
        _waModelo.text = '${wa['template_lembrete'] ?? 'lembrete_limpeza'}';
        _waResposta = wa['resposta_automatica'] != false;
        _waAssistente = wa['assistente_dono'] != false;
        final pix = Map<String, dynamic>.from((p['pix'] as Map?) ?? const {});
        _pixTipo = '${pix['tipo'] ?? 'cpf_cnpj'}';
        _pixChave.text = '${pix['chave'] ?? ''}';
        _pixNome.text = '${pix['nome'] ?? ''}';
        _pixCidade.text = '${pix['cidade'] ?? ''}';
        final pmoc = Map<String, dynamic>.from((p['pmoc'] as Map?) ?? const {});
        _rtNome.text = '${pmoc['rt_nome'] ?? ''}';
        _rtRegistro.text = '${pmoc['rt_registro'] ?? ''}';
        _rtArt.text = '${pmoc['art_numero'] ?? ''}';
        _antecedencia.text = _numero(p['antecedencia_preventivas_dias'] ?? 15);
        _tolerancia.text = _numero(prev['tolerancia_dias'] ?? 15);
        _fotoObrigatoria = prev['foto_obrigatoria'] != false;
        final ia = Map<String, dynamic>.from((p['ia'] as Map?) ?? const {});
        _relatoAudio = ia['relato_audio'] != false;
        _encerramento.text = '${ia['texto_encerramento'] ?? 'Testes realizados, tudo de acordo com os parâmetros.'}';
        _retencao = ret;
        _audiosDias.text = _numero(ret['audios_dias'] ?? 30);
        _garantiaDias.text = _numero((p['garantia'] as Map?)?['dias'] ?? 90);
        _numerosAtuais = numeros;
        for (final e in _numeros.entries) {
          e.value.text = '${numeros[e.key] ?? ''}';
        }
        _localDias.text = _numero(ret['localizacao_dias'] ?? 90);
        _mensagensDias.text = _numero(ret['mensagens_dias'] ?? 365);
        _sujo = false;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    final desconto = num.tryParse(_desconto.text.trim().replaceAll(',', '.'));
    final validade = int.tryParse(_validade.text.trim());
    if (desconto == null || desconto < 0 || desconto > 100) {
      _avisar('Desconto máximo: um número de 0 a 100.', erro: true);
      return;
    }
    if (validade == null || validade < 1 || validade > 365) {
      _avisar('Validade: de 1 a 365 dias.', erro: true);
      return;
    }
    final antecedencia = int.tryParse(_antecedencia.text.trim());
    final tolerancia = int.tryParse(_tolerancia.text.trim());
    if (antecedencia == null || antecedencia < 0 || antecedencia > 90) {
      _avisar('Antecedência das preventivas: de 0 a 90 dias.', erro: true);
      return;
    }
    if (tolerancia == null || tolerancia < 0 || tolerancia > 90) {
      _avisar('Tolerância: de 0 a 90 dias.', erro: true);
      return;
    }
    final audiosDias = int.tryParse(_audiosDias.text.trim());
    final localDias = int.tryParse(_localDias.text.trim());
    final mensagensDias = int.tryParse(_mensagensDias.text.trim());
    if (audiosDias == null || audiosDias < 7 || audiosDias > 365) {
      _avisar('Áudios: de 7 a 365 dias.', erro: true);
      return;
    }
    if (localDias == null || localDias < 7 || localDias > 365) {
      _avisar('Localização: de 7 a 365 dias.', erro: true);
      return;
    }
    if (mensagensDias == null || mensagensDias < 30 || mensagensDias > 1825) {
      _avisar('Mensagens: de 30 a 1825 dias.', erro: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      final retencao = Map<String, dynamic>.from((_parametros['retencao'] as Map?) ?? const {})
        ..['audios_dias'] = audiosDias
        ..['localizacao_dias'] = localDias
        ..['mensagens_dias'] = mensagensDias;
      final prev = Map<String, dynamic>.from((_parametros['preventivas'] as Map?) ?? const {})
        ..['usa'] = _usaPrev
        ..['pmoc'] = _usaPrev && _pmoc
        ..['tolerancia_dias'] = tolerancia
        ..['foto_obrigatoria'] = _fotoObrigatoria;
      // Muda só estas chaves: o resto dos parâmetros continua como está.
      final orc = Map<String, dynamic>.from((_parametros['orcamento'] as Map?) ?? const {})
        ..['quem_monta'] = _quem
        ..['itens_avulsos_app'] = _avulsos
        ..['desconto_max_app_pct'] = desconto
        ..['validade_dias'] = validade;
      final termo = _termo.text.trim();
      if (termo.isEmpty) {
        orc.remove('termo_aceite');
      } else {
        orc['termo_aceite'] = termo;
      }
      // Mensagens: guarda só o que ficou diferente do padrão.
      final mensagens = <String, String>{
        for (final m in modelosMensagem)
          if (_modelos[m.chave]!.text.trim().isNotEmpty && _modelos[m.chave]!.text.trim() != m.padrao.trim())
            m.chave: _modelos[m.chave]!.text.trim(),
      };
      final ia = Map<String, dynamic>.from((_parametros['ia'] as Map?) ?? const {})
        ..['relato_audio'] = _relatoAudio
        // Vazio = o texto padrão (é o que a função de relato usa no lugar).
        ..['texto_encerramento'] = _encerramento.text.trim().isEmpty
            ? 'Testes realizados, tudo de acordo com os parâmetros.'
            : _encerramento.text.trim();
      final novos = {
        ..._parametros,
        'ia': ia,
        'orcamento': orc,
        'aceite_conclusao': _conclusao,
        'os_impressao': {'valores': _valoresOs, 'papel': _papelOs},
        'mensagens': mensagens,
        'preventivas': prev,
        'manutencao_propria': _manutencaoPropria,
        'modo_simples': _modoSimples,
        'whatsapp': {
          ...Map<String, dynamic>.from((_parametros['whatsapp'] as Map?) ?? const {}),
          'phone_number_id': _waPhoneId.text.trim(),
          'numero': _waNumero.text.trim(),
          'template_lembrete': _waModelo.text.trim().isEmpty ? 'lembrete_limpeza' : _waModelo.text.trim(),
          'resposta_automatica': _waResposta,
          'assistente_dono': _waAssistente,
        },
        'lembrete_limpeza': {
          ...Map<String, dynamic>.from((_parametros['lembrete_limpeza'] as Map?) ?? const {}),
          'usa': _lembUsa,
          'automatico': _lembAuto,
          'meses': (int.tryParse(_lembMeses.text.trim()) ?? 6).clamp(1, 36),
          'antecedencia_dias': (int.tryParse(_lembAntec.text.trim()) ?? 7).clamp(0, 60),
        },
        'estoque': {...Map<String, dynamic>.from((_parametros['estoque'] as Map?) ?? const {}), 'usa': _usaEstoque},
        'comercial': {...Map<String, dynamic>.from((_parametros['comercial'] as Map?) ?? const {}), 'usa': _usaComercial},
        'conector': {..._conector},
        'pix': {
          'tipo': _pixTipo,
          'chave': _pixChave.text.trim(),
          'nome': _pixNome.text.trim(),
          'cidade': _pixCidade.text.trim(),
        },
        'pmoc': {
          ...Map<String, dynamic>.from((_parametros['pmoc'] as Map?) ?? const {}),
          'rt_nome': _rtNome.text.trim(),
          'rt_registro': _rtRegistro.text.trim(),
          'art_numero': _rtArt.text.trim(),
        },
        'antecedencia_preventivas_dias': antecedencia,
        'retencao': retencao,
        'garantia': {
          ...Map<String, dynamic>.from((_parametros['garantia'] as Map?) ?? const {}),
          'dias': int.tryParse(_garantiaDias.text.trim()) ?? 90,
        },
      };
      await _db
          .from('empresa_config')
          .update({'parametros': novos})
          .eq('empresa_id', Sessao.atual!.empresaId!);
      _avisar('Configurações salvas. O app recebe na próxima sincronização.');
      await ParametrosEmpresa.instancia.recarregar(); // o menu acompanha
      await _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _avisar(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));
  }

  void _mudou() => setState(() => _sujo = true);

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null) {
      return Center(child: Text(_erro!, style: const TextStyle(color: Cores.erro)));
    }
    final admin = Sessao.atual?.tem(Papel.admin) ?? false;
    final lista = ListView(padding: margemDaTela(context), children: [
      Text('Configurações', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Valem para a empresa ativa. O app recebe as mudanças na próxima sincronização.',
          style: TextStyle(color: Cores.neutro)),
      const SizedBox(height: 16),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Guia 62: modo simples para a empresa pequena.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Modo simples', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                subtitle: const Text('Para quem tem poucos técnicos: a Agenda (uma lista do que agendar e dos próximos '
                    'dias) no lugar do quadro e da fila, sem "fechar o dia" (os dias passados se fecham sozinhos e o '
                    'que não foi feito volta para agendar). Desligue para usar o quadro com equipes e líder.'),
                value: _modoSimples,
                onChanged: admin ? (v) => setState(() {
                      _modoSimples = v;
                      _sujo = true;
                    }) : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Guia 73: Pix para receber (QR Code e copia e cola em Caixa > A receber).
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Pix para receber', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('A chave onde o cliente paga. Em Caixa > A receber, cada cobrança ganha o QR Code e o Pix '
                    'copia e cola com o valor dentro. O dinheiro cai direto nesta chave, sem taxa.',
                    style: TextStyle(color: Cores.neutro)),
                const SizedBox(height: 12),
                Wrap(spacing: 16, runSpacing: 12, children: [
                  SizedBox(
                    width: 200,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Tipo da chave'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _pixTipo,
                          isDense: true,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'cpf_cnpj', child: Text('CPF ou CNPJ')),
                            DropdownMenuItem(value: 'telefone', child: Text('Telefone')),
                            DropdownMenuItem(value: 'email', child: Text('E-mail')),
                            DropdownMenuItem(value: 'aleatoria', child: Text('Aleatória')),
                          ],
                          onChanged: admin ? (v) => setState(() {
                                _pixTipo = v ?? 'cpf_cnpj';
                                _sujo = true;
                              }) : null,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _pixChave,
                      enabled: admin,
                      decoration: const InputDecoration(labelText: 'Chave Pix'),
                      onChanged: (_) => _mudou(),
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _pixNome,
                      enabled: admin,
                      maxLength: 25,
                      decoration: const InputDecoration(labelText: 'Nome do recebedor', helperText: 'Vazio = razão social'),
                      onChanged: (_) => _mudou(),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _pixCidade,
                      enabled: admin,
                      maxLength: 15,
                      decoration: const InputDecoration(labelText: 'Cidade', helperText: 'Vazio = a da empresa'),
                      onChanged: (_) => _mudou(),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          // Guia 64: lembrete recorrente de limpeza.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Lembrete de limpeza', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  subtitle: const Text('Aparelho com a última limpeza há N meses vira um lembrete para mandar ao cliente '
                      'pelo WhatsApp (menu Lembretes). Aparelho em plano de preventiva fica de fora.'),
                  value: _lembUsa,
                  onChanged: admin ? (v) => setState(() {
                        _lembUsa = v;
                        _sujo = true;
                      }) : null,
                ),
                if (_lembUsa) ...[
                  Wrap(spacing: 16, runSpacing: 12, children: [
                    SizedBox(
                      width: 200,
                      child: TextField(
                        controller: _lembMeses,
                        enabled: admin,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Lembrar a cada', suffixText: 'meses'),
                        onChanged: (_) => _mudou(),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: TextField(
                        controller: _lembAntec,
                        enabled: admin,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Avisar antes', suffixText: 'dias'),
                        onChanged: (_) => _mudou(),
                      ),
                    ),
                  ]),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enviar sozinho pelo WhatsApp oficial'),
                    subtitle: const Text('Quando a empresa tiver o WhatsApp oficial conectado (guia 65), o lembrete sai '
                        'sem ninguém tocar. Sem ele, os lembretes ficam na lista para mandar com um toque.'),
                    value: _lembAuto,
                    onChanged: admin ? (v) => setState(() {
                          _lembAuto = v;
                          _sujo = true;
                        }) : null,
                  ),
                  const Text('O texto da mensagem fica em Mensagens do WhatsApp > Lembrete de limpeza.',
                      style: TextStyle(color: Cores.neutro, fontSize: 12)),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 12),
          // Guia 65: WhatsApp oficial (API da Meta).
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('WhatsApp oficial', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('O número da empresa no WhatsApp Business da Meta (guia 65). Conectado, o que o cliente '
                    'mandar vira pedido em "Pedidos do WhatsApp" e o lembrete de limpeza pode sair sozinho.',
                    style: TextStyle(color: Cores.neutro)),
                const SizedBox(height: 8),
                Wrap(spacing: 16, runSpacing: 12, children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _waPhoneId,
                      enabled: admin,
                      decoration: const InputDecoration(labelText: 'ID do número (phone_number_id)',
                          helperText: 'Meta > WhatsApp > Configuração da API'),
                      onChanged: (_) => _mudou(),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _waNumero,
                      enabled: admin,
                      decoration: const InputDecoration(labelText: 'Número', hintText: '(45) 3000-0000'),
                      onChanged: (_) => _mudou(),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _waModelo,
                      enabled: admin,
                      decoration: const InputDecoration(labelText: 'Modelo do lembrete na Meta',
                          helperText: 'Nome do modelo aprovado'),
                      onChanged: (_) => _mudou(),
                    ),
                  ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Responder o cliente na hora'),
                  subtitle: const Text('"Recebemos seu pedido... em breve entramos em contato."'),
                  value: _waResposta,
                  onChanged: admin ? (v) => setState(() {
                        _waResposta = v;
                        _sujo = true;
                      }) : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Assistente do dono pelo WhatsApp'),
                  subtitle: const Text('Mensagem (ou áudio) do celular de um gestor da empresa não vira pedido: é pergunta '
                      'para o assistente ("quem me deve?"), respondida na mesma conversa.'),
                  value: _waAssistente,
                  onChanged: admin ? (v) => setState(() {
                        _waAssistente = v;
                        _sujo = true;
                      }) : null,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          // Guia 63: estoque.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Controla estoque', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                subtitle: const Text('Menu Estoque (almoxarifado, carro de cada equipe e cilindros de gás). A peça usada '
                    'na OS sai sozinha do carro da equipe que atendeu e o gás, do cilindro do carro.'),
                value: _usaEstoque,
                onChanged: admin ? (v) => setState(() {
                      _usaEstoque = v;
                      _sujo = true;
                    }) : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Guia 90: módulo Comercial.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Comercial (funil de vendas)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                subtitle: Text('Menu Comercial: oportunidades da indicação ao contrato, tarefas de follow-up, metas e '
                    'indicadores. Orçamento aprovado ou contrato ativado ganham a oportunidade sozinhos. Só o admin e o '
                    'gestor veem.${_precoComercial == null ? '' : _precoComercial!['incluido'] == true ? ' Incluído no seu plano.' : ' No seu plano: R\$ ${(num.tryParse('${_precoComercial!['valor']}') ?? 0).toStringAsFixed(2).replaceAll('.', ',')} por mês, na mensalidade.'}'),
                value: _usaComercial,
                onChanged: admin ? (v) => setState(() {
                      _usaComercial = v;
                      _sujo = true;
                    }) : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Guia 91: conector do ServPilot para o Claude.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Conector do Claude', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('No Claude (claude.ai ou o app), em Configurações › Conectores › Adicionar conector personalizado, '
                    'cole o endereço abaixo e, em Configurações avançadas, o OAuth Client ID (segredo em branco). Depois entre '
                    'com o seu login do ServPilot. O Claude vê só esta empresa e só o que o usuário que conectou pode ver; '
                    'consultar é sempre liberado.', style: TextStyle(color: Cores.neutro)),
                const SizedBox(height: 8),
                for (final (rotulo, valor) in const [('Endereço', _conectorUrl), ('OAuth Client ID', _conectorClientId)])
                  Row(children: [
                    SizedBox(width: 130, child: Text(rotulo, style: const TextStyle(color: Cores.neutro))),
                    Expanded(
                      child: SelectableText(valor, style: const TextStyle(fontWeight: FontWeight.w700, color: Cores.indigo700)),
                    ),
                    IconButton(
                      tooltip: 'Copiar',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () => Clipboard.setData(ClipboardData(text: valor)),
                    ),
                  ]),
                for (final (chave, titulo, ajuda) in const [
                  ('comercial', 'Comercial', 'Criar e atualizar oportunidades, tarefas e anotações (com o módulo Comercial ligado).'),
                  ('cadastros', 'Cadastros', 'Cadastrar e alterar clientes.'),
                  ('operacao', 'Operação', 'Abrir OS.'),
                  ('financeiro', 'Financeiro', 'Registrar recebimentos (ex.: lendo o comprovante) e lançar no caixa.'),
                ])
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Pode mexer em: $titulo'),
                    subtitle: Text(ajuda),
                    value: _conector[chave] ?? false,
                    onChanged: admin ? (v) => setState(() {
                          _conector[chave] = v;
                          _sujo = true;
                        }) : null,
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Preventivas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('O menu mostra só o que a empresa usa.', style: TextStyle(color: Cores.neutro)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Usa planos de preventiva'),
                  subtitle: const Text('Serviços recorrentes (manutenção preventiva, contratos): menu, OS automáticas '
                      'e os cards de prazo na Início'),
                  value: _usaPrev,
                  onChanged: admin ? (v) => setState(() {
                        _usaPrev = v;
                        _sujo = true;
                      }) : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Faz manutenção própria'),
                  subtitle: const Text('Equipamentos da própria empresa: o cliente "interno" aparece nas buscas de '
                      'cliente (painel e app). Desligado, ele fica escondido.'),
                  value: _manutencaoPropria,
                  onChanged: admin ? (v) => setState(() {
                        _manutencaoPropria = v;
                        _sujo = true;
                      }) : null,
                ),
                if (_usaPrev) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Atende PMOC (climatização)'),
                    subtitle: const Text('Plano do tipo PMOC, responsável técnico e as atividades padrão da '
                        'Portaria GM/MS 3.523/98'),
                    value: _pmoc,
                    onChanged: admin ? (v) => setState(() {
                          _pmoc = v;
                          _sujo = true;
                        }) : null,
                  ),
                  if (_pmoc) ...[
                    const Text('Responsável técnico padrão do PMOC (o assistente do plano já preenche):',
                        style: TextStyle(color: Cores.neutro)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 16, runSpacing: 12, children: [
                      for (final (c, r, w) in [
                        (_rtNome, 'Nome do RT (engenheiro ou técnico)', 300.0),
                        (_rtRegistro, 'CREA / CFT', 160.0),
                        (_rtArt, 'ART / TRT', 160.0),
                      ])
                        SizedBox(
                          width: w,
                          child: TextField(
                            controller: c,
                            enabled: admin,
                            decoration: InputDecoration(labelText: r),
                            onChanged: (_) => _mudou(),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                  Wrap(spacing: 16, runSpacing: 12, children: [
                    SizedBox(
                      width: 210,
                      child: TextField(
                        controller: _antecedencia,
                        enabled: admin,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Gerar o lote com antecedência',
                          suffixText: 'dias',
                          helperText: 'O lote do mês seguinte nasce isso antes (o plano pode ter a sua)',
                          helperMaxLines: 2,
                        ),
                        onChanged: (_) => _mudou(),
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: TextField(
                        controller: _tolerancia,
                        enabled: admin,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Tolerância',
                          suffixText: 'dias',
                          helperText: 'Janela antes do vencimento de cada aparelho (o plano pode ter a sua)',
                          helperMaxLines: 2,
                        ),
                        onChanged: (_) => _mudou(),
                      ),
                    ),
                  ]),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Foto obrigatória nos itens que pedem foto'),
                    subtitle: const Text('No app, a câmera abre ao marcar o item; sem a foto, ele não é marcado. '
                        'Desligado, dá para marcar sem a foto'),
                    value: _fotoObrigatoria,
                    onChanged: admin ? (v) => setState(() {
                          _fotoObrigatoria = v;
                          _sujo = true;
                        }) : null,
                  ),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Relato por áudio (IA)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('O técnico fala o que fez e a IA escreve a OS: problema, causa, solução, peças, mão de obra e '
                    'o equipamento. Nada entra na OS sem ele revisar.', style: TextStyle(color: Cores.neutro)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Usar o relato por áudio'),
                  value: _relatoAudio,
                  onChanged: admin ? (v) => setState(() {
                        _relatoAudio = v;
                        _sujo = true;
                      }) : null,
                ),
                if (_relatoAudio)
                  TextField(
                    controller: _encerramento,
                    enabled: admin,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Texto de encerramento da OS',
                      helperText: 'Vai nas observações quando o serviço terminou sem pendência',
                    ),
                    onChanged: (_) => _mudou(),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Orçamento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                const Text('Quem monta orçamento'),
                const SizedBox(height: 4),
                for (final e in _quemMonta.entries)
                  _Opcao(
                    texto: e.value,
                    marcada: _quem == e.key,
                    aoEscolher: admin ? () => setState(() {
                          _quem = e.key;
                          _sujo = true;
                        }) : null,
                  ),
                const SizedBox(height: 12),
                const Text('Itens fora do catálogo no orçamento do app'),
                const SizedBox(height: 4),
                for (final e in _itensAvulsos.entries)
                  _Opcao(
                    texto: e.value,
                    marcada: _avulsos == e.key,
                    aoEscolher: admin ? () => setState(() {
                          _avulsos = e.key;
                          _sujo = true;
                        }) : null,
                  ),
                const SizedBox(height: 8),
                Wrap(spacing: 16, runSpacing: 12, children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _desconto,
                      enabled: admin,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Desconto máximo no app',
                        suffixText: '%',
                        helperText: 'Por item, sobre o preço (vale também para itens fora do catálogo)',
                      ),
                      onChanged: (_) => _mudou(),
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _validade,
                      enabled: admin,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Validade do orçamento', suffixText: 'dias'),
                      onChanged: (_) => _mudou(),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: _termo,
                  enabled: admin,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Termo de aceite (vazio = texto padrão)',
                    alignLabelWithHint: true,
                    helperText: 'Aparece no PDF, na página do link e na tela de assinatura do app',
                  ),
                  onChanged: (_) => _mudou(),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Assinatura do cliente na conclusão',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('No app, ao concluir o atendimento com o cliente presente.',
                    style: TextStyle(color: Cores.neutro)),
                for (final e in _aceiteConclusao.entries)
                  _Opcao(
                    texto: e.value,
                    marcada: _conclusao == e.key,
                    aoEscolher: admin ? () => setState(() {
                          _conclusao = e.key;
                          _sujo = true;
                        }) : null,
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Impressão da OS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text(
                    'No app, ao concluir com o cliente presente, o técnico pode imprimir o recibo (com a assinatura, se '
                    'colheu) ou mandar ao cliente. Imprime pela impressora Wi-Fi do celular ou pela térmica bluetooth '
                    '(pelo app dela, ex.: RawBT). Os valores valem também para o PDF da OS no painel e no link do cliente '
                    '(no painel dá para escolher na hora).',
                    style: TextStyle(color: Cores.neutro)),
                const SizedBox(height: 8),
                const Text('Valores no recibo e na OS', style: TextStyle(fontWeight: FontWeight.w600)),
                for (final e in _osValores.entries)
                  _Opcao(
                    texto: e.value,
                    marcada: _valoresOs == e.key,
                    aoEscolher: admin ? () => setState(() {
                          _valoresOs = e.key;
                          _sujo = true;
                        }) : null,
                  ),
                const SizedBox(height: 8),
                const Text('Papel da impressão no app', style: TextStyle(fontWeight: FontWeight.w600)),
                for (final e in _osPapel.entries)
                  _Opcao(
                    texto: e.value,
                    marcada: _papelOs == e.key,
                    aoEscolher: admin ? () => setState(() {
                          _papelOs = e.key;
                          _sujo = true;
                        }) : null,
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Mensagens do WhatsApp', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text(
                    'O app e o painel abrem o WhatsApp com a mensagem pronta; quem manda confere e envia. '
                    'Os campos entre chaves viram os dados do serviço. Uma linha com um campo vazio some '
                    '(ex.: sem link, a linha do link não aparece).',
                    style: TextStyle(color: Cores.neutro)),
                for (final m in modelosMensagem) ...[
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(m.onde, style: const TextStyle(color: Cores.neutro, fontSize: 12)),
                      ]),
                    ),
                    if (admin && _modelos[m.chave]!.text.trim() != m.padrao.trim())
                      TextButton(
                        onPressed: () => setState(() {
                          _modelos[m.chave]!.text = m.padrao;
                          _sujo = true;
                        }),
                        child: const Text('Voltar ao padrão'),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _modelos[m.chave],
                    enabled: admin,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: 1000,
                    decoration: InputDecoration(
                      alignLabelWithHint: true,
                      helperText: 'Campos: ${m.campos.map((c) => '{$c}').join(' ')}',
                      helperMaxLines: 3,
                    ),
                    onChanged: (_) => _mudou(),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  for (final e in camposMensagem.entries)
                    Text('{${e.key}} ${e.value}', style: const TextStyle(fontSize: 12, color: Cores.neutro)),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          _cartaoNumeracao(admin),
          const SizedBox(height: 16),
          _cartaoRetencao(admin),
          const SizedBox(height: 16),
          if (admin)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _sujo && !_salvando ? _salvar : null,
                icon: _salvando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(_sujo ? 'Salvar' : 'Tudo salvo'),
              ),
            )
          else
            const Text('Só o administrador da empresa altera as configurações.',
                style: TextStyle(color: Cores.neutro)),
          // Espaço para o botão flutuante não cobrir o último cartão.
          if (admin && _sujo) const SizedBox(height: 72),
        ]),
      ),
    ]);
    // A página é longa: com alteração pendente, o Salvar fica sempre à vista.
    return Stack(children: [
      lista,
      if (admin && _sujo)
        Positioned(
          right: 24,
          bottom: 24,
          child: FilledButton.icon(
            onPressed: _salvando ? null : _salvar,
            icon: _salvando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Salvar alterações'),
          ),
        ),
    ]);
  }

  Future<void> _gravarNumeros() async {
    setState(() => _gravandoNumeros = true);
    try {
      for (final e in _numeros.entries) {
        final novo = int.tryParse(e.value.text.trim());
        if (novo != null && novo != _numerosAtuais[e.key]) {
          await _db.rpc('numeracao_definir', params: {
            'p': {'tipo': e.key, 'proximo': novo}
          });
        }
      }
      _numerosAtuais = Map<String, dynamic>.from(await _db.rpc('numeracao') as Map);
      _avisar('Numeração gravada.');
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _gravandoNumeros = false);
    }
  }

  /// Guia 60: garantia padrão (salva com as configurações) e numeração (grava na hora).
  Widget _cartaoNumeracao(bool admin) {
    const nomes = {'os': 'Próxima OS', 'orcamento': 'Próximo orçamento', 'contrato': 'Próximo contrato'};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Garantia e numeração', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SizedBox(
            width: 260,
            child: TextField(
              controller: _garantiaDias,
              enabled: admin,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Garantia dos serviços',
                suffixText: 'dias',
                helperText: 'Conta da conclusão da OS (salva com as configurações)',
                helperMaxLines: 2,
              ),
              onChanged: (_) => _mudou(),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Veio de outro sistema? Continue a numeração de lá (só para a frente).',
              style: TextStyle(color: Cores.neutro)),
          const SizedBox(height: 8),
          Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
            for (final e in _numeros.entries)
              SizedBox(
                width: 170,
                child: TextField(
                  controller: e.value,
                  enabled: admin,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: nomes[e.key]),
                ),
              ),
            if (admin)
              OutlinedButton(
                onPressed: _gravandoNumeros ? null : _gravarNumeros,
                child: const Text('Gravar numeração'),
              ),
          ]),
        ]),
      ),
    );
  }
}

extension on _ConfiguracoesTelaState {
  /// Privacidade e retenção: o que é apagado e quando (a limpeza roda todo dia).
  Widget _cartaoRetencao(bool admin) {
    String quando(Object? v) => v == null ? 'ainda não rodou' : dataHoraBr(v);
    Widget prazo(TextEditingController c, String rotulo, String ajuda) => SizedBox(
          width: 200,
          child: TextField(
            controller: c,
            enabled: admin,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: rotulo, suffixText: 'dias', helperText: ajuda, helperMaxLines: 2),
            onChanged: (_) => _mudou(),
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Privacidade e retenção', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
              'Todo dia, de madrugada, o ServPilot apaga o que passou do prazo. O áudio do relato some, mas o texto '
              'do relato continua. Fotos e registros ficam 5 anos.',
              style: TextStyle(color: Cores.neutro)),
          const SizedBox(height: 12),
          Wrap(spacing: 16, runSpacing: 8, children: [
            prazo(_audiosDias, 'Áudios dos relatos', '7 a 365'),
            prazo(_localDias, 'Localização (check-in e fotos)', '7 a 365'),
            prazo(_mensagensDias, 'Texto das mensagens', '30 a 1825'),
          ]),
          const SizedBox(height: 12),
          Text('Áudios guardados: ${_retencao['audios_guardados'] ?? 0} · apagados pelo prazo: '
              '${_retencao['audios_apagados'] ?? 0}'),
          Text('Última limpeza do banco: ${quando(_retencao['ultima_dados'])} · dos arquivos: '
              '${quando(_retencao['ultima_arquivos'])}',
              style: const TextStyle(color: Cores.neutro)),
          if (_retencao['agendada'] == false)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('A limpeza dos arquivos ainda não foi ligada (guia 38, Parte 2).',
                  style: TextStyle(color: Cores.alerta, fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
    );
  }
}

/// Uma opção de uma escolha só (marcador redondo + texto).
class _Opcao extends StatelessWidget {
  const _Opcao({required this.texto, required this.marcada, this.aoEscolher});

  final String texto;
  final bool marcada;
  final VoidCallback? aoEscolher;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        enabled: aoEscolher != null,
        leading: Icon(marcada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: marcada ? Cores.indigo700 : Cores.neutro),
        title: Text(texto),
        onTap: aoEscolher,
      );
}
