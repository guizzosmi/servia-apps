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
import '../widgets/busca_aparelhos.dart';
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
  const NovaOsTela(
      {super.key, this.clienteId, this.localId, this.equipamentoId, this.audioId, this.falarAoAbrir = false});

  final String? clienteId;
  final String? localId;

  /// Guia 108: "Abrir OS para este aparelho" (etiqueta lida fora da OS): já vem marcado.
  final String? equipamentoId;
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

  /// Pelo que ele falou (guias 17d e 80): futuro ("amanhã vou na..."), indo
  /// ("estou indo na..."), agora ("estou na...") ou feito ("fui na..., troquei").
  /// Decide o que acontece depois que a OS entra na parte.
  String _momento = 'futuro';

  /// "feito": o horário falado (ou escolhido aqui). Sem ele, o app pergunta.
  TimeOfDay? _inicio;
  TimeOfDay? _fim;

  /// Guia 95: o dia da OS que não é "atender agora" (aaaa-mm-dd; null = hoje).
  /// Ela entra na agenda da equipe dele nesse dia.
  String? _dia;

  /// Guia 80: as OS em aberto do cliente e a escolhida para usar (null = OS
  /// nova). [_decidiuNova]: ele tocou "Abrir uma OS nova".
  List<OsAberta> _abertas = const [];
  OsAberta? _usar;
  bool _decidiuNova = false;

  bool _propostaAplicada = false;
  List<String> _dicas = const [];
  // Guia 59: retorno de outra OS citado no áudio (sugerido ou candidatos) e o que o técnico confirmou.
  List<Map> _retornoCandidatos = const [];
  Map? _retornoSugerido;
  String? _retornoOsId;
  List<Map> _clientesSugeridos = const [];
  /// Nome do cliente falado que a IA não achou no cadastro: o técnico pode cadastrá-lo com um toque.
  String _clienteFalado = '';
  String _lNomeFalado = '';

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
      final eq = banco.um('equipamentos', widget.equipamentoId);
      if (eq != null && eq['local_id'] == _local?['id']) _equipamentos.add('${eq['id']}');
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
      _esquecerAbertas();
      _contatoId = null;
      _contatoNovo = null;
      if (escolha.cliente != null) {
        _cliente = escolha.cliente;
        _clienteNovo = false;
        _escolherLocalPadrao();
      } else {
        _cadastrarNovo(escolha.nomeDigitado);
      }
    });
  }

  /// Passa o formulário para "Cliente novo" (com o nome já preenchido, se houver) e um local novo.
  /// Chamar dentro de setState.
  void _cadastrarNovo(String nome, {String local = ''}) {
    _limparEquipamentos();
    _esquecerAbertas();
    _contatoId = null;
    _contatoNovo = null;
    _cliente = null;
    _clienteNovo = true;
    _cNome.text = nome;
    _local = null;
    _localNovo = true;
    if (local.isNotEmpty) _lNome.text = local;
    _clientesSugeridos = const [];
    _clienteFalado = '';
    _dicas = _dicas
        .where((d) => !d.startsWith('Qual cliente') && !d.startsWith('Não deu para saber o cliente'))
        .toList();
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
      _clienteFalado = '';
      _esquecerAbertas();
    });
  }

  /// "Retorno da OS-000123 (02/10, limpeza do split)": confirmar, trocar ou nenhuma.
  Widget _cartaoRetorno() {
    String rotulo(Map c) {
      final d = '${c['data'] ?? ''}';
      final data = d.length >= 10 ? '${d.substring(8, 10)}/${d.substring(5, 7)}' : d;
      return [c['codigo'], data, c['resumo']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
    }

    final todos = <Map>[if (_retornoSugerido != null) _retornoSugerido!, ..._retornoCandidatos];
    final escolhido = todos.where((c) => c['os_id'] == _retornoOsId).firstOrNull;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: Cores.indigo100,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              escolhido != null
                  ? 'Retorno da ${rotulo(escolhido)}'
                  : _retornoSugerido != null
                      ? 'Parece retorno da ${rotulo(_retornoSugerido!)}'
                      : 'Retorno de qual serviço?',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (escolhido == null && _retornoSugerido != null)
              FilledButton.tonal(
                onPressed: () => setState(() => _retornoOsId = '${_retornoSugerido!['os_id']}'),
                child: const Text('Confirmar'),
              ),
            if (escolhido == null)
              for (final c in _retornoCandidatos.where((c) => c['os_id'] != _retornoSugerido?['os_id']))
                ActionChip(label: Text(rotulo(c)), onPressed: () => setState(() => _retornoOsId = '${c['os_id']}')),
            TextButton(
              onPressed: () => setState(() {
                _retornoOsId = null;
                _retornoSugerido = null;
                _retornoCandidatos = const [];
              }),
              child: Text(escolhido == null ? 'Não é retorno' : 'Desfazer'),
            ),
          ]),
        ]),
      ),
    );
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
      _clienteFalado = '';
      _lNomeFalado = '';
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
          dicas.add('Cliente novo: "$falado" não está no cadastro. Confira o nome e complete o telefone abaixo, '
              'ou toque em "Escolher da lista" se ele já existir com outro nome.');
        } else {
          sugeridos = [
            for (final x in (cli['candidatos'] is List ? cli['candidatos'] as List : const []).whereType<Map>())
              if (banco.um('clientes', x['cliente_id']) != null) x,
          ];
          dicas.add(falado.isEmpty
              ? 'Não deu para saber o cliente: escolha ou cadastre.'
              : 'Qual cliente é "$falado"? Escolha abaixo ou cadastre como cliente novo.');
          _clienteFalado = falado;
          _lNomeFalado = '${loc['falado'] ?? ''}'.trim();
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
      final ret = ab['retorno'] is Map ? ab['retorno'] as Map : const {};
      _retornoSugerido = ret['tipo'] == 'sugerido' ? ret : null;
      _retornoCandidatos = (ret['tipo'] == 'escolher' || ret['tipo'] == 'sugerido') && ret['candidatos'] is List
          ? (ret['candidatos'] as List).whereType<Map>().toList()
          : const [];
      _retornoOsId = null;
      _comoRelato = ab['tem_relato'] == true;
      final momento = '${ab['momento'] ?? ''}';
      _momento = _momentos.containsKey(momento) ? momento : 'agora';
      final horario = ab['horario'] is Map ? ab['horario'] as Map : const {};
      _inicio = _hora(horario['inicio']);
      _fim = _hora(horario['fim']);
      // Guia 96: o dia falado ("amanhã às 9h") vira o dia do serviço, se ele ainda não trocou.
      final diaFalado = _diaFalado(ab['data_prevista']);
      if (diaFalado != null && _dia == null) _dia = diaFalado;
      // Guia 80: as OS em aberto deste cliente (a que combina com o falado vem primeiro).
      final abertas = ab['os_aberta'] is Map ? ab['os_aberta'] as Map : const {};
      final clienteId = _cliente?['id'];
      _abertas = clienteId != null && clienteId == cli['cliente_id'] && abertas['candidatos'] is List
          ? [for (final c in (abertas['candidatos'] as List).whereType<Map>()) OsAberta(c, clienteId: '$clienteId')]
          : const [];
      // Aberta de dentro de um serviço ("outra OS neste cliente"): a OS nova continua sendo o padrão.
      final outraOs = widget.clienteId != null;
      _usar = abertas['tipo'] == 'identificada' && _abertas.isNotEmpty && !outraOs ? _abertas.first : null;
      _decidiuNova = _abertas.isNotEmpty && outraOs;
      _dicas = dicas;
      _clientesSugeridos = sugeridos;
    });
  }

  /// 'HH:MM' -> horário (null se não veio).
  static TimeOfDay? _hora(Object? v) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch('${v ?? ''}'.trim());
    if (m == null) return null;
    final h = int.parse(m[1]!), min = int.parse(m[2]!);
    return h < 24 && min < 60 ? TimeOfDay(hour: h, minute: min) : null;
  }

  /// 'aaaa-mm-dd' de hoje até 120 dias (o limite de "Trocar dia"); senão null.
  static String? _diaFalado(Object? v) {
    final s = '${v ?? ''}'.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) || DateTime.tryParse(s) == null) return null;
    final hoje = EstadoApp.instancia.sync!.hoje;
    return s.compareTo(hoje) >= 0 && s.compareTo(somarDias(hoje, 120)) <= 0 ? s : null;
  }

  static String _hhmm(TimeOfDay? t) =>
      t == null ? '--:--' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<TimeOfDay?> _perguntarHora({required bool inicio}) => showTimePicker(
        context: context,
        initialTime: (inicio ? _inicio : _fim) ?? TimeOfDay.now(),
        helpText: inicio ? 'Que horas você começou?' : 'Que horas você terminou?',
      );

  Future<void> _escolherHora({required bool inicio}) async {
    final t = await _perguntarHora(inicio: inicio);
    if (t == null || !mounted) return;
    setState(() {
      if (inicio) {
        _inicio = t;
      } else {
        _fim = t;
      }
    });
  }

  /// "Já fiz": das que horas às que horas (o falado ou o escolhido no quadro).
  /// O que faltar, pergunta. null = desistiu ou o horário não fecha.
  Future<(DateTime, DateTime)?> _periodoFeito() async {
    final inicio = _inicio ?? await _perguntarHora(inicio: true);
    if (inicio == null || !mounted) return null;
    final fim = _fim ?? await _perguntarHora(inicio: false);
    if (fim == null || !mounted) return null;
    setState(() {
      _inicio = inicio;
      _fim = fim;
    });
    final dia = DateTime.parse(EstadoApp.instancia.sync!.hoje);
    final de = DateTime(dia.year, dia.month, dia.day, inicio.hour, inicio.minute);
    final ate = DateTime(dia.year, dia.month, dia.day, fim.hour, fim.minute);
    final erro = !ate.isAfter(de)
        ? 'O fim precisa ser depois do início.'
        : ate.isAfter(DateTime.now())
            ? 'O fim não pode ser depois de agora.'
            : null;
    if (erro == null) return (de, ate);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$erro Confira o horário em "Já fiz".')));
    return null;
  }

  /// Outro cliente (ou sem o áudio): as OS em aberto da proposta não valem mais.
  void _esquecerAbertas() {
    _abertas = const [];
    _usar = null;
    _decidiuNova = false;
  }

  void _abrirNova() => setState(() {
        _usar = null;
        _decidiuNova = true;
      });

  /// Guia 80: o cliente já tem OS em aberto. A que combina com o que ele falou
  /// vem marcada; dá para escolher outra ou abrir uma nova.
  Widget _cartaoOsAberta() {
    Widget opcao(bool marcada, String titulo, String sub, VoidCallback aoTocar, {String? alerta}) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(marcada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: marcada ? Cores.indigo500 : Cores.neutro),
          title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sub),
            if (alerta != null) Text(alerta, style: const TextStyle(color: Cores.erro)),
          ]),
          onTap: aoTocar,
        );

    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: Cores.indigo100,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_abertas.length == 1 ? 'Este cliente já tem uma OS aberta' : 'Este cliente tem ${_abertas.length} OS abertas',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (_usar == null && !_decidiuNova)
            const Text('Escolha a OS deste serviço ou abra uma nova.', style: TextStyle(color: Cores.alerta)),
          for (final o in _abertas)
            opcao(
              _usar?.osId == o.osId,
              [o.codigo, o.problema].where((x) => x.isNotEmpty).join(' · '),
              o.ondeEsta,
              () => setState(() {
                _usar = o;
                _decidiuNova = false;
              }),
              // (no futuro não traz para a parte: só liga o áudio)
              alerta: _momento == 'futuro' ? null : o.impedimento,
            ),
          opcao(_usar == null && _decidiuNova, 'Abrir uma OS nova', 'É outro serviço neste cliente.', _abrirNova),
        ]),
      ),
    );
  }

  /// Troca o cliente: o local, os equipamentos e o contato eram do outro.
  void _trocarCliente(Map<String, dynamic> c) {
    _limparEquipamentos();
    _esquecerAbertas();
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
              // (usando a OS que já existe, as dicas e o retorno eram para a OS nova)
              if (_usar == null)
                for (final d in _dicas)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $d', style: const TextStyle(color: Cores.alerta)),
                  ),
              if (_abertas.isNotEmpty) _cartaoOsAberta(),
              if (_usar == null && (_retornoSugerido != null || _retornoCandidatos.isNotEmpty || _retornoOsId != null))
                _cartaoRetorno(),
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
                          _clienteFalado = '';
                          _dicas = _dicas
                              .where((d) => !d.startsWith('Qual cliente') && !d.startsWith('Não deu para saber o cliente'))
                              .toList();
                          // Com um local só, ele já fica; com vários, o técnico escolhe na lista.
                          if (_local == null && !_localNovo) _dicas = [..._dicas, 'Escolha o local abaixo.'];
                        });
                      },
                    ),
                ]),
              if (_clienteFalado.isNotEmpty && _cliente == null && !_clienteNovo)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _cadastrarNovo(_clienteFalado, local: _lNomeFalado)),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: Text('Cadastrar "$_clienteFalado" como cliente novo'),
                    ),
                  ),
                ),
              if ((r?.transcricao ?? '').trim().isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('O que foi falado'),
                  children: [Text(r!.transcricao!, style: const TextStyle(fontStyle: FontStyle.italic))],
                ),
              const SizedBox(height: 8),
              const Text('Quando é o serviço?', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final m in _momentos.entries)
                  ChoiceChip(
                    label: Text(m.value.$1),
                    selected: _momento == m.key,
                    onSelected: (_) => setState(() => _momento = m.key),
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_momentos[_momento]!.$2, style: const TextStyle(fontSize: 12, color: Cores.neutro)),
              ),
              if (_momento == 'feito')
                Row(children: [
                  const Text('Das'),
                  TextButton(onPressed: () => _escolherHora(inicio: true), child: Text(_hhmm(_inicio))),
                  const Text('às'),
                  TextButton(onPressed: () => _escolherHora(inicio: false), child: Text(_hhmm(_fim))),
                  if (_inicio == null || _fim == null)
                    const Expanded(
                      child: Text('Sem horário no áudio: toque para escolher.',
                          style: TextStyle(fontSize: 12, color: Cores.neutro)),
                    ),
                ]),
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
  // Guia 95: o dia da agenda

  String get _diaEscolhido {
    final hoje = EstadoApp.instancia.sync!.hoje;
    final d = _dia;
    return d == null || d.compareTo(hoje) < 0 ? hoje : d;
  }

  /// 'sábado, 07/11 (hoje)'
  String _textoDia(String dia) {
    final hoje = EstadoApp.instancia.sync!.hoje;
    final quando = dia == hoje ? ' (hoje)' : dia == somarDias(hoje, 1) ? ' (amanhã)' : '';
    return '${dataComDia(dia)}$quando';
  }

  /// 'hoje', 'amanhã' ou 'sexta, 14/11'
  String _quando(String dia) {
    final hoje = EstadoApp.instancia.sync!.hoje;
    return dia == hoje ? 'hoje' : dia == somarDias(hoje, 1) ? 'amanhã' : dataComDia(dia);
  }

  Future<void> _escolherDia() async {
    final hoje = DateTime.parse(EstadoApp.instancia.sync!.hoje);
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_diaEscolhido),
      firstDate: hoje,
      lastDate: hoje.add(const Duration(days: 120)),
      helpText: 'Para que dia é o serviço?',
    );
    if (d == null || !mounted) return;
    setState(() => _dia = dataIso(d));
  }

  /// O que acontece com a OS que não é "atender agora" (embaixo do botão).
  String _dicaAgenda() {
    if (!AcoesOs.tenhoEquipe) return 'Você não está em nenhuma equipe: a OS vai para a fila do escritório.';
    final parte = AcoesOs.minhaParteNoDia(_diaEscolhido);
    final banco = EstadoApp.instancia.banco!;
    if (parte == null) return 'Entra na agenda da sua equipe nesse dia. O escritório vê no quadro e pode mudar.';
    if (parte['status'] == 'rascunho') {
      return 'Entra na parte da ${banco.nomeEquipe(parte['equipe_id'])}, que o escritório ainda vai publicar.';
    }
    return 'Entra no fim da parte da ${banco.nomeEquipe(parte['equipe_id'])}. O escritório vê no quadro e pode mudar.';
  }

  /// O aviso depois de salvar a OS que não é "atender agora".
  String _avisoAgenda(String dia, {required bool tinhaParte}) {
    final quando = _quando(dia);
    if (!AcoesOs.tenhoEquipe) {
      return 'OS registrada. Você não está em nenhuma equipe: ela vai para a fila do escritório (sobe quando houver internet).';
    }
    if (tinhaParte) return 'OS na sua agenda de $quando. O escritório vê no quadro e pode mudar.';
    final hoje = EstadoApp.instancia.sync!.hoje;
    if (dia.compareTo(somarDias(hoje, 2)) > 0) {
      return 'OS registrada para $quando, na agenda da sua equipe. Ela aparece na tela Hoje 2 dias antes.';
    }
    return 'OS registrada para $quando: entra na agenda da sua equipe assim que subir para a plataforma.';
  }

  Future<void> _salvar({required bool agora}) async {
    if (_salvando) return;
    if (_abertas.isNotEmpty && _usar == null && !_decidiuNova) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Este cliente já tem OS aberta: escolha uma delas ou toque em "Abrir uma OS nova".')));
      return;
    }
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
    (DateTime, DateTime)? periodo;
    if (agora) {
      final partes = await _partesAgora();
      if (partes == null || !mounted) return;
      parte = partes.length == 1 ? partes.first : await _escolherParte(partes);
      if (parte == null || !mounted) return;
      // Já fez: o horário antes de abrir (se desistir, nada é registrado).
      if (_audioId != null && _momento == 'feito') {
        periodo = await _periodoFeito();
        if (periodo == null || !mounted) return;
      }
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
        retornoDeOsId: _retornoOsId,
      );
      final dia = _diaEscolhido;
      final tinhaParte = !agora && AcoesOs.minhaParteNoDia(dia) != null;
      final itemId = await AcoesOs.abrir(pedido,
          parte: parte, dia: agora ? null : dia, audioId: _audioUsavel(), audioComoRelato: _comoRelato);
      if (!mounted) return;
      final aviso = ScaffoldMessenger.of(context);
      if (itemId != null && _audioId != null) {
        // OS falada: segue pelo que ele falou (a caminho, no serviço ou o que já fez).
        if (_momento == 'indo') {
          final item = EstadoApp.instancia.banco!.um('partes_itens', itemId);
          if (item != null) await AcoesAtendimento.mudarStatus(item, 'em_deslocamento');
          if (!mounted) return;
        }
        await _seguir(itemId, 'OS aberta e incluída na sua parte', periodo);
      } else if (itemId != null) {
        aviso.showSnackBar(const SnackBar(content: Text('OS aberta e incluída na sua parte. Faça o check-in quando começar.')));
        context.pushReplacement('/servico/$itemId');
      } else {
        aviso.showSnackBar(SnackBar(content: Text(_avisoAgenda(dia, tinhaParte: tinhaParte))));
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não deu para registrar: $e'), backgroundColor: Cores.erro));
    }
  }

  /// A OS falada, se o áudio ainda pode ir para uma OS (recusado porque o
  /// arquivo sumiu, já usado ou descartado: a OS vai sem ele).
  String? _audioUsavel() {
    final audio = _audioId == null ? null : AcoesRelato.um(_audioId!);
    return audio == null || const ['recusado', 'revisado', 'descartado'].contains(audio.status) ? null : audio.id;
  }

  /// Depois que a OS (nova ou a que já existia) entrou na parte: segue pelo
  /// que ele falou. [quem]: o começo do aviso ("OS aberta e incluída na sua parte").
  Future<void> _seguir(String itemId, String quem, (DateTime, DateTime)? periodo) async {
    final banco = EstadoApp.instancia.banco!;
    final aviso = ScaffoldMessenger.of(context);
    final item = banco.um('partes_itens', itemId);
    if (item == null || _momento == 'futuro') {
      aviso.showSnackBar(SnackBar(content: Text('$quem. Faça o check-in quando começar.')));
      context.pushReplacement('/servico/$itemId');
      return;
    }
    if (_momento == 'indo') {
      // A caminho: oferece o aviso ao cliente, como no "Estou a caminho".
      final avisou = await avisarACaminho(context, Map<String, dynamic>.from(item));
      if (!mounted) return;
      if (!avisou) aviso.showSnackBar(SnackBar(content: Text('$quem: você está a caminho.')));
      context.pushReplacement('/servico/$itemId');
      return;
    }
    // Está no local ou já fez: entra no serviço (quem está junto, se for o líder).
    await entrarNoServico(context, Map<String, dynamic>.from(item),
        abrir: false, inicio: periodo?.$1, fim: periodo?.$2);
    if (!mounted) return;
    final atdId = AcoesAtendimento.idAtendimento(itemId);
    if (periodo != null && banco.um('atendimentos', atdId) != null) {
      final de = _hhmm(TimeOfDay.fromDateTime(periodo.$1)), ate = _hhmm(TimeOfDay.fromDateTime(periodo.$2));
      aviso.showSnackBar(
          SnackBar(content: Text('$quem: serviço das $de às $ate registrado. Revise o relato e conclua.')));
      context.pushReplacement('/atendimento/$atdId');
    } else if (AcoesAtendimento.meuCheckin()?['atendimento_id'] == atdId) {
      aviso.showSnackBar(SnackBar(content: Text('$quem: você já está no serviço.')));
      context.pushReplacement('/atendimento/$atdId');
    } else {
      aviso.showSnackBar(SnackBar(content: Text('$quem. Faça o check-in quando começar.')));
      context.pushReplacement('/servico/$itemId');
    }
  }

  /// Guia 80: usar a OS que já existe. "Ainda vou": só liga o áudio a ela.
  /// Nos outros momentos, traz o serviço para a parte de hoje (os_puxar) e
  /// segue como na OS nova.
  Future<void> _usarExistente() async {
    final os = _usar;
    if (os == null || _salvando) return;
    final audio = _audioUsavel();
    if (_momento == 'futuro') {
      setState(() => _salvando = true);
      if (audio != null) await AcoesRelato.vincular(audio, os.osId, comoRelato: _comoRelato);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Nenhuma OS nova: o áudio ficou na ${os.codigo}.')));
      context.pop();
      return;
    }
    // Já fez: o horário antes de tudo (se desistir, nada é registrado).
    final periodo = _momento == 'feito' ? await _periodoFeito() : null;
    if (!mounted || (_momento == 'feito' && periodo == null)) return;
    final item = AcoesOs.servicoNaMinhaParte(os);
    Map<String, dynamic>? parte;
    var confirmado = false;
    if (item == null) {
      final partes = await _partesAgora();
      if (partes == null || !mounted) return;
      parte = partes.length == 1 ? partes.first : await _escolherParte(partes);
      if (parte == null || !mounted) return;
      if (os.comOutraEquipe) {
        confirmado = await _confirmarTrazer(os);
        if (!confirmado || !mounted) return;
      }
    }

    setState(() => _salvando = true);
    try {
      final String itemId;
      if (item != null) {
        // Já está na minha parte: é o mesmo serviço.
        itemId = '${item['id']}';
        if (_momento == 'indo' && item['status'] == 'programado') {
          await AcoesAtendimento.mudarStatus(item, 'em_deslocamento');
        }
      } else {
        itemId = await AcoesOs.puxar(os, parte: parte!, confirmado: confirmado, aCaminho: _momento == 'indo');
      }
      if (audio != null) await AcoesRelato.vincular(audio, os.osId, comoRelato: _comoRelato);
      if (!mounted) return;
      await _seguir(itemId, '${os.codigo} na sua parte', periodo);
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não deu para registrar: $e'), backgroundColor: Cores.erro));
    }
  }

  /// As partes para atender agora (guia 113: no modo simples, sem parte hoje,
  /// abre o dia do técnico). null = não deu (o motivo já apareceu).
  Future<List<Map<String, dynamic>>?> _partesAgora() async {
    final messenger = ScaffoldMessenger.of(context);
    if (AcoesOs.partesParaAtender().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Abrindo o seu dia de hoje...')));
    }
    try {
      final partes = await AcoesOs.partesParaAtenderAgora();
      messenger.hideCurrentSnackBar();
      return partes.isEmpty ? null : partes;
    } on FalhaMeuDia catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.motivo), backgroundColor: Cores.erro));
      return null;
    }
  }

  /// Guia 80: a OS está com outra equipe (ou em outro dia): trazer só confirmando.
  Future<bool> _confirmarTrazer(OsAberta os) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Trazer a ${os.codigo} para você?'),
        content: Text('${os.ondeEsta}. Ela sai de lá e entra no fim da sua parte de hoje. O escritório é avisado.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Trazer para mim')),
        ],
      ),
    );
    return ok == true;
  }

  /// O que acontece ao usar a OS que já existe (embaixo do botão).
  String _dicaUsar(OsAberta os, List<Map<String, dynamic>> partes) {
    if (_momento == 'futuro') return 'Nenhuma OS nova: o áudio fica nesta OS.';
    if (os.impedimento case final motivo?) return motivo;
    if (partes.isEmpty) return AcoesOs.semParteHoje ?? AcoesOs.abreMeuDia;
    if (os.naMinhaParte) return 'Ela já está na sua parte de hoje.';
    if (os.comOutraEquipe) return 'Ela sai de onde está e entra no fim da sua parte (o escritório é avisado).';
    return partes.length == 1
        ? 'Entra no fim da parte da ${EstadoApp.instancia.banco!.nomeEquipe(partes.first['equipe_id'])}.'
        : 'Entra no fim da parte da sua equipe.';
  }

  Widget _botoesUsar(OsAberta os, List<Map<String, dynamic>> partes) {
    final bloqueado = _momento != 'futuro' && (os.impedimento != null || !AcoesOs.possoAtenderAgora);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: _salvando || bloqueado ? null : _usarExistente,
          icon: const Icon(Icons.task_alt),
          label: Text(switch (_momento) {
            'agora' => 'Usar a ${os.codigo} e entrar no serviço',
            'feito' => 'Usar a ${os.codigo} e registrar o serviço',
            'indo' => 'Usar a ${os.codigo}: estou a caminho',
            _ => 'Usar a ${os.codigo} (já aberta)',
          }),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(_dicaUsar(os, partes),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: bloqueado ? Cores.erro : Cores.neutro)),
      ),
      SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: _salvando ? null : _abrirNova,
          icon: const Icon(Icons.add),
          label: const Text('Abrir uma OS nova'),
        ),
      ),
    ]);
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
    final usar = _usar;

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
              // Guia 80: usando a OS que já existe, o formulário da OS nova não aparece.
              if (usar == null) ...[
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
                    Row(children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: _escolherCliente,
                            icon: const Icon(Icons.search),
                            label: const Text('Escolher cliente'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: () => setState(() => _cadastrarNovo('')),
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('Cliente novo'),
                          ),
                        ),
                      ),
                    ]),
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
                            labelText: 'Nome do local', hintText: 'Ex.: Matriz, Loja Centro (vazio: Principal)'),
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
                    // Guia 108: com muitos aparelhos, a busca (e a etiqueta) no topo, por ambiente.
                    BuscaAparelhos(
                      key: ValueKey('aparelhos-${_local?['id']}'),
                      aparelhos: equipamentos,
                      aoAcharPorEtiqueta: (e, _) async {
                        setState(() => _equipamentos.add('${e['id']}'));
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('Marcado: ${rotuloAparelho(e)}')));
                      },
                      item: (e) => CheckboxListTile(
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
              ],
              // Botões no fim do formulário: rolam junto e nunca ficam atrás do teclado.
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: usar != null
                    ? _botoesUsar(usar, partes)
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _salvando || !AcoesOs.possoAtenderAgora ? null : () => _salvar(agora: true),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(_audioId == null
                              ? 'Atender agora'
                              : switch (_momento) {
                                  'agora' => 'Atender agora e entrar no serviço',
                                  'feito' => 'Atender agora e registrar o serviço',
                                  'indo' => 'Atender agora: estou a caminho',
                                  _ => 'Atender agora',
                                }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          partes.isEmpty
                              ? AcoesOs.semParteHoje ?? AcoesOs.abreMeuDia
                              : partes.length == 1
                                  ? 'Entra no fim da parte da ${banco.nomeEquipe(partes.first['equipe_id'])}.'
                                  : 'Entra no fim da parte da sua equipe.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Cores.neutro),
                        ),
                      ),
                      // Guia 95: sem "atender agora", a OS vai para a agenda da equipe no dia escolhido.
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.event_outlined, size: 20, color: Cores.neutro),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Dia do serviço: ${_textoDia(_diaEscolhido)}',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        TextButton(onPressed: _salvando ? null : _escolherDia, child: const Text('Trocar dia')),
                      ]),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _salvando ? null : () => _salvar(agora: false),
                          icon: Icon(AcoesOs.tenhoEquipe ? Icons.event_available_outlined : Icons.send_outlined),
                          label: Text(AcoesOs.tenhoEquipe ? 'Pôr na minha agenda' : 'Mandar para o escritório'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_dicaAgenda(),
                            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Cores.neutro)),
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

/// Quando é o serviço (o "momento" da OS falada): o rótulo e o que acontece.
const _momentos = {
  'futuro': ('Ainda vou', 'Só deixa a OS pronta: o check-in fica para depois.'),
  'indo': ('Estou indo', 'O serviço já fica "a caminho" (e dá para avisar o cliente).'),
  'agora': ('Estou no local', 'Já faz o check-in no serviço.'),
  'feito': ('Já fiz', 'Registra o serviço no horário em que você fez.'),
};

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
