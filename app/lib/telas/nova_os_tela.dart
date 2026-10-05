import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_atendimento.dart';
import '../core/acoes_cadastro.dart';
import '../core/acoes_os.dart';
import '../core/acoes_relato.dart';
import '../core/consultas.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import '../widgets/cadastros_rapidos.dart';
import '../widgets/entrar_no_servico.dart';
import '../widgets/relato_audio.dart';
import '../widgets/status_chip.dart';

/// Abrir uma OS no celular (quem tem a permissão). Funciona sem internet:
/// a OS aparece na hora como "OS nova" e ganha o número quando sincronizar.
/// [clienteId] e [localId] já vêm preenchidos quando ela é aberta de dentro
/// de um serviço ("outra OS neste cliente"). [audioId]: uma OS falada
/// (guia 17b), que preenche a tela com o que a IA entendeu.
class NovaOsTela extends StatefulWidget {
  const NovaOsTela({super.key, this.clienteId, this.localId, this.audioId, this.falarAoAbrir = false});

  final String? clienteId;
  final String? localId;
  final String? audioId;

  /// Abre já gravando ("Falar a OS" da tela Hoje).
  final bool falarAoAbrir;

  @override
  State<NovaOsTela> createState() => _NovaOsTelaState();
}

class _NovaOsTelaState extends State<NovaOsTela> {
  final _form = GlobalKey<FormState>();

  Map<String, dynamic>? _cliente;
  bool _clienteNovo = false;
  final _cNome = TextEditingController();
  final _cTelefone = TextEditingController();
  final _cDocumento = TextEditingController();

  Map<String, dynamic>? _local;
  bool _localNovo = false;
  final _lNome = TextEditingController();
  final _lRua = TextEditingController();
  final _lNumero = TextEditingController();
  final _lBairro = TextEditingController();
  final _lCidade = TextEditingController();
  final _lUf = TextEditingController();
  final _lAcesso = TextEditingController();

  String _tipo = 'corretiva';
  String _prioridade = 'media';
  final _problema = TextEditingController();
  final Set<String> _equipamentos = {};
  final List<EquipamentoNovo> _novos = []; // cadastrados aqui
  String? _contatoId;
  ContatoNovo? _contatoNovo;
  bool _salvando = false;

  // OS falada: o áudio, se ele também é o relato e o que a IA não resolveu.
  String? _audioId;
  bool _comoRelato = false;

  /// Pelo que ele falou ("estou na...", "fui na..."), já está no local:
  /// "Atender agora" também faz o check-in. ("amanhã vou na..." = não.)
  bool _jaNoLocal = false;
  bool _propostaAplicada = false;
  List<String> _dicas = const [];
  List<Map> _clientesSugeridos = const [];

  @override
  void initState() {
    super.initState();
    _audioId = widget.audioId;
    if (widget.falarAoAbrir && _audioId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _falar();
      });
    }
    final banco = EstadoApp.instancia.banco!;
    _cliente = banco.um('clientes', widget.clienteId);
    if (_cliente != null) {
      _local = banco.um('locais', widget.localId);
      if (_local == null) _escolherLocalPadrao();
    }
  }

  @override
  void dispose() {
    for (final c in [_cNome, _cTelefone, _cDocumento, _lNome, _lRua, _lNumero, _lBairro, _lCidade, _lUf, _lAcesso, _problema]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _preencheuAlgo =>
      _audioId != null ||
      _cliente != null ||
      _clienteNovo ||
      _problema.text.trim().isNotEmpty ||
      _equipamentos.isNotEmpty ||
      _novos.isNotEmpty;

  /// Trocou o local: os equipamentos (escolhidos e cadastrados) eram do outro.
  void _limparEquipamentos() {
    _equipamentos.clear();
    _novos.clear();
  }

  Future<void> _novoEquipamento() async {
    final usados = <String, String>{
      if (!_clienteNovo) ...AcoesCadastro.codigosDoCliente(_cliente?['id']),
      for (final n in _novos)
        if (n.codigo.trim().isNotEmpty) n.codigo.trim().toLowerCase(): n.rotulo,
    };
    final e = await cadastrarEquipamento(
      context,
      localId: _localNovo ? null : _local?['id'] as String?,
      codigosUsados: usados,
      pendentes: List.of(_novos),
    );
    if (e != null && mounted) setState(() => _novos.add(e));
  }

  /// Tira um equipamento novo da lista (se outro novo não depender do
  /// ambiente ou do tipo que ele criou).
  void _tirarNovo(EquipamentoNovo e) {
    final usado = _novos.any((o) =>
        o != e &&
        ((e.ambienteNovo != null && o.ambienteId == e.ambienteNovoId) ||
            (e.tipoNovo != null && o.tipoId == e.tipoNovoId)));
    if (usado) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Outro equipamento novo usa o ambiente ou o tipo criado neste. Tire aquele antes.')));
      return;
    }
    setState(() => _novos.remove(e));
  }

  Future<void> _novoContato() async {
    final c = await cadastrarContato(context);
    if (c == null || !mounted) return;
    // Mesmo celular de um contato que já existe: usa o cadastrado.
    final ja = _clienteNovo ? null : AcoesCadastro.contatoComTelefone(_cliente?['id'], c.telefone);
    setState(() {
      if (ja != null) {
        _contatoNovo = null;
        _contatoId = '${ja['id']}';
      } else {
        _contatoNovo = c;
        _contatoId = null;
      }
    });
    if (ja != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Esse celular já é de ${ja['nome']}: escolhido da lista.')));
    }
  }

  /// Cliente com um local só: já fica escolhido. Sem nenhum: cadastra.
  void _escolherLocalPadrao() {
    final locais = AcoesOs.locaisDo(_cliente?['id']);
    _local = locais.length == 1 ? locais.first : null;
    _localNovo = locais.isEmpty;
  }

  Future<void> _escolherCliente() async {
    final escolha = await showModalBottomSheet<_EscolhaCliente>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _BuscaCliente(),
    );
    if (escolha == null || !mounted) return;
    setState(() {
      _limparEquipamentos();
      _contatoId = null;
      _contatoNovo = null;
      if (escolha.cliente != null) {
        _cliente = escolha.cliente;
        _clienteNovo = false;
        _escolherLocalPadrao();
      } else {
        _cliente = null;
        _clienteNovo = true;
        _cNome.text = escolha.nomeDigitado;
        _local = null;
        _localNovo = true;
      }
    });
  }

  // ------------------------------------------------------------------
  // OS falada

  Future<void> _falar() async {
    final gravado = await Navigator.of(context).push<(String, Duration)>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const GravadorRelatoTela(abertura: true)),
    );
    if (gravado == null) return;
    final (arquivo, duracao) = gravado;
    final id = arquivo.split(RegExp(r'[/\\]')).last.replaceAll('.m4a', '');
    await AcoesRelato.registrarAbertura(audioId: id, arquivoLocal: arquivo, duracao: duracao);
    if (!mounted) return;
    setState(() {
      _audioId = id;
      _propostaAplicada = false;
    });
  }

  Future<void> _descartarAudio() async {
    final id = _audioId;
    if (id == null) return;
    final r = AcoesRelato.um(id);
    // Ainda no aparelho: sai da fila; já na plataforma: fica registrado como descartado.
    if (r?.opId != null) {
      await EstadoApp.instancia.sync!.descartar(r!.opId!);
      await EstadoApp.instancia.banco!.gravarMeta('relato_processar:$id', null);
    } else {
      await AcoesRelato.descartar(id);
    }
    if (!mounted) return;
    setState(() {
      _audioId = null;
      _dicas = const [];
      _clientesSugeridos = const [];
    });
  }

  /// Preenche a tela com a proposta da IA (uma vez). O que ela não resolveu
  /// vira dica para o técnico escolher.
  void _aplicarProposta(Map<String, dynamic> ab) {
    final banco = EstadoApp.instancia.banco!;
    final dicas = <String>[];
    var sugeridos = <Map>[];
    final cli = ab['cliente'] is Map ? ab['cliente'] as Map : const {};
    final loc = ab['local'] is Map ? ab['local'] as Map : const {};
    final eq = ab['equipamento'] is Map ? ab['equipamento'] as Map : const {};
    final falado = '${cli['falado'] ?? ''}'.trim();
    setState(() {
      _propostaAplicada = true;
      // O que o técnico já escolheu (ou veio preenchido) fica: a proposta só completa.
      final jaTinhaCliente = _cliente != null || _clienteNovo;
      if (!jaTinhaCliente) {
        final c = cli['tipo'] == 'identificado' ? banco.um('clientes', cli['cliente_id']) : null;
        if (c != null) {
          _trocarCliente(c);
        } else if (cli['tipo'] == 'cadastrar' && falado.isNotEmpty) {
          _cliente = null;
          _clienteNovo = true;
          _contatoId = null;
          _contatoNovo = null;
          _cNome.text = falado;
          _local = null;
          _localNovo = true;
          _lNome.text = '${loc['falado'] ?? ''}'.trim();
          dicas.add('Cliente "$falado" não está no cadastro: confira o nome (ou escolha da lista).');
        } else {
          sugeridos = [
            for (final x in (cli['candidatos'] is List ? cli['candidatos'] as List : const []).whereType<Map>())
              if (banco.um('clientes', x['cliente_id']) != null) x,
          ];
          dicas.add(falado.isEmpty ? 'Não deu para saber o cliente: escolha.' : 'Qual cliente é "$falado"? Escolha.');
        }
      } else if (_cliente != null && cli['cliente_id'] != null && cli['cliente_id'] != _cliente!['id']) {
        dicas.add('A IA entendeu outro cliente ("$falado"). Ficou o que já estava escolhido.');
      }
      // Local: o identificado, se for do cliente escolhido e o técnico ainda não escolheu.
      if (_cliente != null && _local == null && !_localNovo) {
        final l = loc['tipo'] == 'identificado' ? banco.um('locais', loc['local_id']) : null;
        if (l != null && l['cliente_id'] == _cliente!['id']) {
          _local = l;
        } else {
          _escolherLocalPadrao();
          if (_local == null && !_localNovo) {
            final f = '${loc['falado'] ?? ''}'.trim();
            dicas.add('${f.isEmpty ? 'O local não foi falado' : 'Não achei o local "$f"'}: escolha abaixo.');
          }
        }
      }
      final tipo = '${ab['tipo_servico'] ?? ''}';
      if (tiposOs.containsKey(tipo)) _tipo = tipo;
      final problema = '${ab['problema'] ?? ''}'.trim();
      if (problema.isNotEmpty && _problema.text.trim().isEmpty) _problema.text = problema;
      // O equipamento só se for do local escolhido.
      final e = eq['equipamento_id'] == null ? null : banco.um('equipamentos', eq['equipamento_id']);
      final doLocal = e != null && _local != null && e['local_id'] == _local!['id'];
      if ((eq['tipo'] == 'sugerido' || eq['tipo'] == 'confirmar') && doLocal) {
        _equipamentos.add('${e['id']}');
        if (eq['tipo'] == 'confirmar') dicas.add('Confira o equipamento: ${eq['texto'] ?? ''}.');
      } else if (eq['tipo'] != null && eq['texto'] != null) {
        dicas.add('Equipamento: ${eq['texto']}.');
      }
      _comoRelato = ab['tem_relato'] == true;
      _jaNoLocal = ab['momento'] != 'futuro';
      _dicas = dicas;
      _clientesSugeridos = sugeridos;
    });
  }

  /// Troca o cliente: o local, os equipamentos e o contato eram do outro.
  void _trocarCliente(Map<String, dynamic> c) {
    _limparEquipamentos();
    _contatoId = null;
    _contatoNovo = null;
    _cliente = c;
    _clienteNovo = false;
    _local = null;
    _escolherLocalPadrao();
  }

  Widget _osFalada() {
    final banco = EstadoApp.instancia.banco!;
    return ListenableBuilder(
      listenable: banco,
      builder: (context, _) {
        final id = _audioId;
        if (id == null) {
          if (!AcoesRelato.ligado) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _salvando ? null : _falar,
                icon: const Icon(Icons.mic, color: Cores.coral500),
                label: const Text('Falar a OS (a IA preenche)'),
              ),
            ),
          );
        }
        final r = AcoesRelato.um(id);
        final ab = r?.abertura ?? (r?.resultado?['abertura_proposta'] as Map?)?.cast<String, dynamic>();
        if (r != null && r.status == 'pronto' && ab != null && !_propostaAplicada) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_propostaAplicada) _aplicarProposta(ab);
          });
        }
        final status = r?.status ?? 'aguardando_envio';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.record_voice_over_outlined, color: Cores.coral500),
                const SizedBox(width: 8),
                const Expanded(child: Text('OS falada', style: TextStyle(fontWeight: FontWeight.w800))),
                TextButton(
                  onPressed: _descartarAudio,
                  child: const Text('Descartar o áudio', style: TextStyle(color: Cores.erro)),
                ),
              ]),
              switch (status) {
                'aguardando_envio' => const Text(
                    'Sem internet agora: a proposta chega quando conectar (fica também na tela Hoje). '
                    'Se quiser, preencha à mão.',
                    style: TextStyle(color: Cores.neutro)),
                'enviado' || 'processando' => const Row(children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Expanded(child: Text('A IA está organizando (uns segundos)...')),
                  ]),
                'erro' || 'recusado' => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r?.erro ?? 'Não deu para organizar o áudio.', style: const TextStyle(color: Cores.erro)),
                    if (status == 'erro')
                      TextButton.icon(
                        onPressed: () => AcoesRelato.processarDeNovo(id),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Tentar de novo'),
                      ),
                  ]),
                'revisado' || 'descartado' => const Text('Este áudio já foi usado ou descartado.',
                    style: TextStyle(color: Cores.neutro)),
                _ => _propostaAplicada
                    ? const Text('Preenchido com o que a IA entendeu. Confira antes de salvar.',
                        style: TextStyle(color: Cores.sucesso, fontWeight: FontWeight.w600))
                    : const Text('A IA não trouxe uma proposta. Preencha à mão.', style: TextStyle(color: Cores.neutro)),
              },
              for (final d in _dicas)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('• $d', style: const TextStyle(color: Cores.alerta)),
                ),
              if (_clientesSugeridos.isNotEmpty)
                Wrap(spacing: 6, children: [
                  for (final c in _clientesSugeridos)
                    ActionChip(
                      label: Text('${c['nome_fantasia'] ?? c['nome']}'),
                      onPressed: () {
                        final cliente = banco.um('clientes', c['cliente_id']);
                        if (cliente == null) return;
                        setState(() {
                          _trocarCliente(cliente);
                          _clientesSugeridos = const [];
                          _dicas = _dicas
                              .where((d) => !d.startsWith('Qual cliente') && !d.startsWith('Não deu para saber o cliente'))
                              .toList();
                          // Com um local só, ele já fica; com vários, o técnico escolhe na lista.
                          if (_local == null && !_localNovo) _dicas = [..._dicas, 'Escolha o local abaixo.'];
                        });
                      },
                    ),
                ]),
              if ((r?.transcricao ?? '').trim().isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('O que foi falado'),
                  children: [Text(r!.transcricao!, style: const TextStyle(fontStyle: FontStyle.italic))],
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _jaNoLocal,
                onChanged: (v) => setState(() => _jaNoLocal = v),
                title: const Text('Já estou no local'),
                subtitle: const Text('"Atender agora" já faz o check-in no serviço.'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _comoRelato,
                onChanged: (v) => setState(() => _comoRelato = v ?? false),
                title: const Text('Usar este áudio também como relato do serviço'),
                subtitle: const Text('Marque quando você já contou o que encontrou e o que fez. '
                    'A revisão fica no atendimento.'),
              ),
            ]),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------

  Future<void> _salvar({required bool agora}) async {
    if (_salvando) return;
    final valido = _form.currentState?.validate() ?? false;
    String? falta;
    if (!_clienteNovo && _cliente == null) {
      falta = 'Escolha o cliente (ou cadastre um novo).';
    } else if (!_localNovo && _local == null) {
      falta = 'Escolha o local do serviço.';
    }
    if (falta != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(falta)));
      return;
    }
    if (!valido) return;

    Map<String, dynamic>? parte;
    if (agora) {
      final partes = AcoesOs.partesParaAtender();
      if (partes.isEmpty) return;
      parte = partes.length == 1 ? partes.first : await _escolherParte(partes);
      if (parte == null || !mounted) return;
    }

    setState(() => _salvando = true);
    try {
      final pedido = PedidoOs(
        clienteId: _clienteNovo ? null : _cliente!['id'] as String,
        clienteNovo: _clienteNovo
            ? ClienteNovo(nome: _cNome.text, telefone: _cTelefone.text, documento: _cDocumento.text)
            : null,
        localId: _localNovo ? null : _local!['id'] as String,
        localNovo: _localNovo
            ? LocalNovo(
                nome: _lNome.text,
                logradouro: _lRua.text,
                numero: _lNumero.text,
                bairro: _lBairro.text,
                cidade: _lCidade.text,
                uf: _lUf.text,
                instrucoes: _lAcesso.text,
              )
            : null,
        tipo: _tipo,
        prioridade: _prioridade,
        problema: _problema.text,
        equipamentos: _equipamentos.toList(),
        equipamentosNovos: List.of(_novos),
        contatoId: _contatoNovo == null ? _contatoId : null,
        contatoNovo: _contatoNovo,
      );
      // A OS falada recusada (arquivo sumiu...) não liga: a OS vai sem ela.
      final audio = _audioId == null ? null : AcoesRelato.um(_audioId!);
      final itemId = await AcoesOs.abrir(pedido,
          parte: parte,
          audioId: audio == null || const ['recusado', 'revisado', 'descartado'].contains(audio.status) ? null : audio.id,
          audioComoRelato: _comoRelato);
      if (!mounted) return;
      final aviso = ScaffoldMessenger.of(context);
      if (itemId != null && _audioId != null && _jaNoLocal) {
        // Já está no local: entra no serviço agora (quem está junto, se for o líder).
        final item = EstadoApp.instancia.banco!.um('partes_itens', itemId);
        if (item != null) await entrarNoServico(context, Map<String, dynamic>.from(item), abrir: false);
        if (!mounted) return;
        final atdId = AcoesAtendimento.idAtendimento(itemId);
        if (AcoesAtendimento.meuCheckin()?['atendimento_id'] == atdId) {
          aviso.showSnackBar(const SnackBar(content: Text('OS aberta e você já está no serviço.')));
          context.pushReplacement('/atendimento/$atdId');
        } else {
          aviso.showSnackBar(const SnackBar(content: Text('OS aberta e incluída na sua parte. Faça o check-in quando começar.')));
          context.pushReplacement('/servico/$itemId');
        }
      } else if (itemId != null) {
        aviso.showSnackBar(const SnackBar(content: Text('OS aberta e incluída na sua parte. Faça o check-in quando começar.')));
        context.pushReplacement('/servico/$itemId');
      } else {
        aviso.showSnackBar(const SnackBar(
            content: Text('OS registrada. Ela vai para a fila do escritório (sobe quando houver internet).')));
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não deu para registrar: $e'), backgroundColor: Cores.erro));
    }
  }

  Future<Map<String, dynamic>?> _escolherParte(List<Map<String, dynamic>> partes) {
    final banco = EstadoApp.instancia.banco!;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Em qual equipe?'),
        children: [
          for (final p in partes)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(p),
              child: Text(banco.nomeEquipe(p['equipe_id'])),
            ),
        ],
      ),
    );
  }

  Future<bool> _confirmarSaida() async {
    final sair = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar esta OS?'),
        content: Text(_audioId == null
            ? 'O que você preencheu não será salvo.'
            : 'O que você preencheu não será salvo. O áudio fica na tela Hoje, em "OS faladas".'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Continuar preenchendo')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Descartar')),
        ],
      ),
    );
    return sair == true;
  }

  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final banco = EstadoApp.instancia.banco!;
    final partes = AcoesOs.partesParaAtender();
    final equipamentos = (_localNovo || _local == null) ? const <Map<String, dynamic>>[] : AcoesOs.equipamentosDo(_local!['id']);

    return PopScope(
      canPop: !_preencheuAlgo || _salvando,
      onPopInvokedWithResult: (saiu, _) async {
        if (saiu) return;
        if (await _confirmarSaida() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Nova OS')),
        body: Form(
          key: _form,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              _osFalada(),
              // ---------- cliente ----------
              _Secao(titulo: 'Cliente', filhos: [
                if (_clienteNovo) ...[
                  Row(children: [
                    const Expanded(child: Text('Cliente novo', style: TextStyle(fontWeight: FontWeight.w700))),
                    TextButton(onPressed: _escolherCliente, child: const Text('Escolher da lista')),
                  ]),
                  TextFormField(
                    controller: _cNome,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nome do cliente *'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o nome' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _cTelefone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Telefone (com DDD)'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _cDocumento,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9./-]'))],
                    decoration: const InputDecoration(labelText: 'CPF ou CNPJ (se souber)'),
                    validator: (v) {
                      final n = (v ?? '').replaceAll(RegExp(r'\D'), '');
                      return n.isEmpty || n.length == 11 || n.length == 14 ? null : 'CPF tem 11 números; CNPJ, 14';
                    },
                  ),
                  const SizedBox(height: 6),
                  const Text('O escritório completa o resto do cadastro depois.',
                      style: TextStyle(fontSize: 12, color: Cores.neutro)),
                ] else if (_cliente != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${_cliente!['nome']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                    subtitle: _cliente!['nome_fantasia'] == null ? null : Text('${_cliente!['nome_fantasia']}'),
                    trailing: TextButton(onPressed: _escolherCliente, child: const Text('Trocar')),
                  )
                else
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _escolherCliente,
                      icon: const Icon(Icons.search),
                      label: const Text('Escolher cliente'),
                    ),
                  ),
              ]),

              // ---------- local ----------
              if (_cliente != null || _clienteNovo)
                _Secao(titulo: 'Local do serviço', filhos: [
                  if (_localNovo) ...[
                    if (!_clienteNovo && AcoesOs.locaisDo(_cliente?['id']).isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => setState(() {
                            _localNovo = false;
                            _limparEquipamentos();
                            _escolherLocalPadrao();
                          }),
                          child: const Text('Escolher da lista'),
                        ),
                      ),
                    TextFormField(
                      controller: _lNome,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                          labelText: 'Nome do local', hintText: 'Ex.: Matriz, Unidade Cacic (vazio: Principal)'),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _lRua,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Rua / rodovia'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(controller: _lNumero, decoration: const InputDecoration(labelText: 'Nº')),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _lBairro,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Bairro / linha'),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _lCidade,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Cidade'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _lUf,
                          maxLength: 2,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(labelText: 'UF', counterText: ''),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _lAcesso,
                      decoration: const InputDecoration(labelText: 'Como chegar / acesso (opcional)'),
                    ),
                  ] else ...[
                    for (final l in AcoesOs.locaisDo(_cliente?['id']))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _local?['id'] == l['id'] ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: _local?['id'] == l['id'] ? Cores.indigo500 : Cores.neutro,
                        ),
                        onTap: () => setState(() {
                          _local = l;
                          _limparEquipamentos();
                        }),
                        title: Text('${l['nome']}'),
                        subtitle: _comEnvio(_endereco(l), l['id']),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() {
                          _localNovo = true;
                          _local = null;
                          _limparEquipamentos();
                        }),
                        icon: const Icon(Icons.add_location_alt_outlined),
                        label: const Text('Outro local (cadastrar)'),
                      ),
                    ),
                  ],
                ]),

              // ---------- o que fazer ----------
              _Secao(titulo: 'O que fazer', filhos: [
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final t in tiposOs.entries)
                    ChoiceChip(
                      label: Text(t.value),
                      selected: _tipo == t.key,
                      onSelected: (_) => setState(() => _tipo = t.key),
                    ),
                ]),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _problema,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'O que precisa ser feito *',
                    hintText: 'Ex.: trocar a torneira do bebedouro do refeitório',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Conte o que precisa ser feito' : null,
                ),
                const SizedBox(height: 10),
                const Text('Prioridade', style: TextStyle(color: Cores.neutro)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final p in const ['baixa', 'media', 'alta', 'urgente'])
                    ChoiceChip(
                      label: Text(prioridades[p]!.texto),
                      selected: _prioridade == p,
                      onSelected: (_) => setState(() => _prioridade = p),
                    ),
                ]),
              ]),

              // ---------- quem pediu ----------
              if (_cliente != null || _clienteNovo)
                _Secao(titulo: 'Quem pediu (opcional)', filhos: [
                  for (final c in _clienteNovo ? const <Map<String, dynamic>>[] : AcoesCadastro.contatosDo(_cliente?['id'], localId: _local?['id']))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _contatoNovo == null && _contatoId == c['id'] ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: _contatoNovo == null && _contatoId == c['id'] ? Cores.indigo500 : Cores.neutro,
                      ),
                      onTap: () => setState(() {
                        _contatoNovo = null;
                        _contatoId = _contatoId == c['id'] ? null : '${c['id']}';
                      }),
                      title: Text('${c['nome']}'),
                      subtitle: _comEnvio(
                          [c['cargo'], c['telefone']].where((x) => x != null && '$x'.isNotEmpty).join(' · '), c['id']),
                    ),
                  if (_contatoNovo != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.radio_button_checked, color: Cores.indigo500),
                      title: Text(_contatoNovo!.nome.trim()),
                      subtitle: Text(['Novo', _contatoNovo!.cargo.trim(), _contatoNovo!.telefone.trim()]
                          .where((x) => x.isNotEmpty)
                          .join(' · ')),
                      trailing: IconButton(
                        tooltip: 'Tirar',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _contatoNovo = null),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _novoContato,
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Cadastrar contato'),
                    ),
                  ),
                ]),

              // ---------- equipamentos ----------
              if (_local != null || _localNovo)
                _Secao(titulo: 'Equipamentos (opcional)', filhos: [
                  for (final e in equipamentos)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _equipamentos.contains(e['id']),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _equipamentos.add('${e['id']}');
                        } else {
                          _equipamentos.remove('${e['id']}');
                        }
                      }),
                      title: Text([e['codigo'], e['descricao']].where((x) => x != null).join(' · ')),
                      subtitle: _comEnvio(
                          [
                            banco.um('ambientes', e['ambiente_id'])?['nome'],
                            [e['marca'], e['modelo']].where((x) => x != null).join(' '),
                          ].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                          e['id']),
                    ),
                  for (final e in _novos)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_box, color: Cores.indigo500),
                      title: Text(e.rotulo),
                      subtitle: Text(['Novo', e.ambienteNovo ?? '', '${e.marca} ${e.modelo}'.trim()]
                          .where((x) => x.trim().isNotEmpty)
                          .join(' · ')),
                      trailing: IconButton(
                        tooltip: 'Tirar',
                        icon: const Icon(Icons.close),
                        onPressed: () => _tirarNovo(e),
                      ),
                    ),
                  if (equipamentos.isEmpty && _novos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Text('Nenhum equipamento cadastrado neste local.', style: TextStyle(color: Cores.neutro)),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _novoEquipamento,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Cadastrar equipamento'),
                    ),
                  ),
                ]),
              // Botões no fim do formulário: rolam junto e nunca ficam atrás do teclado.
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _salvando || partes.isEmpty ? null : () => _salvar(agora: true),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(_audioId != null && _jaNoLocal ? 'Atender agora e entrar no serviço' : 'Atender agora'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      partes.isEmpty
                          ? 'Para atender agora, você precisa estar numa parte publicada de hoje.'
                          : partes.length == 1
                              ? 'Entra no fim da parte da ${banco.nomeEquipe(partes.first['equipe_id'])}.'
                              : 'Entra no fim da parte da sua equipe.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Cores.neutro),
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _salvando ? null : () => _salvar(agora: false),
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Mandar para o escritório'),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Subtítulo com o "Aguardando envio" de quem foi cadastrado no aparelho.
  static Widget? _comEnvio(String texto, Object? id) {
    final envio = textoEnvio(id);
    final t = [texto, ?envio].where((x) => x.isNotEmpty).join(' · ');
    return t.isEmpty ? null : Text(t);
  }

  static String _endereco(Map<String, dynamic> l) => [
        [l['logradouro'], l['numero']].where((x) => x != null && '$x'.isNotEmpty).join(', '),
        l['bairro'],
        [l['cidade'], l['uf']].where((x) => x != null && '$x'.isNotEmpty).join('/'),
      ].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
}

/// Resultado da busca: um cliente da lista ou "cadastrar novo" (com o nome digitado).
class _EscolhaCliente {
  const _EscolhaCliente.lista(Map<String, dynamic> this.cliente) : nomeDigitado = '';
  const _EscolhaCliente.novo(this.nomeDigitado) : cliente = null;

  final Map<String, dynamic>? cliente;
  final String nomeDigitado;
}

class _BuscaCliente extends StatefulWidget {
  const _BuscaCliente();

  @override
  State<_BuscaCliente> createState() => _BuscaClienteState();
}

class _BuscaClienteState extends State<_BuscaCliente> {
  final _busca = TextEditingController();

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texto = _busca.text.trim();
    final lista = AcoesOs.clientes(texto);
    final mostrar = lista.take(100).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _busca,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  hintText: 'Nome do cliente ou cidade', prefixIcon: Icon(Icons.search)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_outlined, color: Cores.indigo500),
            title: Text(texto.isEmpty ? 'Cadastrar cliente novo' : 'Cadastrar cliente novo: "$texto"',
                style: const TextStyle(color: Cores.indigo500, fontWeight: FontWeight.w600)),
            onTap: () => Navigator.of(context).pop(_EscolhaCliente.novo(texto)),
          ),
          const Divider(height: 1),
          Expanded(
            child: lista.isEmpty
                ? const Center(
                    child: Text('Nenhum cliente encontrado.', style: TextStyle(color: Cores.neutro)),
                  )
                : ListView.builder(
                    itemCount: mostrar.length + (lista.length > mostrar.length ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == mostrar.length) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text('Mais ${lista.length - mostrar.length}: digite para filtrar.',
                              textAlign: TextAlign.center, style: const TextStyle(color: Cores.neutro)),
                        );
                      }
                      final c = mostrar[i];
                      final cidades = AcoesOs.locaisDo(c['id'])
                          .map((l) => l['cidade'])
                          .where((x) => x != null && '$x'.isNotEmpty)
                          .toSet()
                          .join(', ');
                      final envio = textoEnvio(c['id']);
                      final sub = [cidades, ?envio].where((x) => x.isNotEmpty).join(' · ');
                      return ListTile(
                        title: Text('${c['nome']}'),
                        subtitle: sub.isEmpty ? null : Text(sub),
                        onTap: () => Navigator.of(context).pop(_EscolhaCliente.lista(c)),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.filhos});

  final String titulo;
  final List<Widget> filhos;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(titulo.toUpperCase(),
                style: const TextStyle(fontSize: 12, letterSpacing: .6, fontWeight: FontWeight.w700, color: Cores.neutro)),
            const SizedBox(height: 6),
            ...filhos,
          ]),
        ),
      );
}
