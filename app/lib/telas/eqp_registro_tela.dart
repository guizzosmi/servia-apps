import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_eqp.dart';
import '../core/acoes_orcamento.dart';
import '../core/arquivos.dart';
import '../core/eqp_dados.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import '../core/posicao.dart';
import '../core/resumo.dart';
import '../widgets/status_chip.dart';
import 'assinatura_tela.dart';

/// Registro de um evento do equipamento pelo app (guia 104): saída/entrega,
/// chegada, transferência, recolher, retorno, mover ou iniciar manutenção.
///
/// Na entrega (e na retirada e no retorno): o ponto exato pelo GPS, com o
/// mapa para conferir; fotos obrigatórias; horímetro; checklist do modelo;
/// conferência do conjunto; divergências (avaria, falta, sujeira, uso acima)
/// e a assinatura de quem recebe. Tudo fica no aparelho e sobe pela fila.
class EqpRegistroTela extends StatefulWidget {
  const EqpRegistroTela({super.key, required this.equipamentoId, required this.evento});

  final String equipamentoId;
  final String evento;

  @override
  State<EqpRegistroTela> createState() => _EqpRegistroTelaState();
}

class _Resposta {
  bool? ok;
  final numero = TextEditingController();
  final texto = TextEditingController();
  final obs = TextEditingController();
  final List<FotoEqp> fotos = [];

  void dispose() {
    numero.dispose();
    texto.dispose();
    obs.dispose();
  }
}

class _Apontamento {
  _Apontamento(this.tipo);
  final String id = AcoesEqp.novoId();
  String tipo;
  final descricao = TextEditingController();
  final valor = TextEditingController();
  final List<FotoEqp> fotos = [];

  void dispose() {
    descricao.dispose();
    valor.dispose();
  }
}

class _EqpRegistroTelaState extends State<EqpRegistroTela> {
  late final Map<String, dynamic> _ficha;
  late final EqpParametros _param;
  Map<String, dynamic>? _ativa;
  List<Map<String, dynamic>> _reservadas = const [];

  String? _reservaId;
  bool _direto = true;
  bool _emTransito = false;
  String? _localId;

  Posicao? _posicao;
  LeituraPosicao? _falhaGps;
  bool _lendoGps = false;
  final _semGps = TextEditingController();

  final List<FotoEqp> _fotos = [];
  bool _tirando = false;
  final _leitura = TextEditingController();

  Map<String, dynamic>? _checklist;
  final Map<String, _Resposta> _respostas = {};

  final Map<String, bool> _presente = {};
  final Map<String, TextEditingController> _conferida = {};

  final List<_Apontamento> _apontamentos = [];
  final _obs = TextEditingController();
  bool _gravando = false;

  String get _ev => widget.evento;
  bool get _entrega => const ['saida', 'chegada', 'transferencia', 'recolher', 'retorno'].contains(_ev);
  bool get _temMedidor => _ficha['medidor'] != null && _ficha['medidor'] != 'nenhum';
  List<Map> get _conjunto => ((_ficha['conjunto'] as List?) ?? const []).cast<Map>();

  /// Troca de mãos: quem recebe (ou devolve) assina.
  bool get _trocaDeMaos => switch (_ev) {
        'saida' => _direto,
        'chegada' || 'recolher' => true,
        'transferencia' => !_emTransito,
        'retorno' => _ficha['status'] == 'em_uso',
        _ => false,
      };

  String? get _tipoChecklist => switch (_ev) {
        'saida' || 'chegada' || 'transferencia' => 'saida',
        'recolher' || 'retorno' => 'retorno',
        'iniciar_manutencao' => 'manutencao',
        _ => null,
      };

  bool get _checklistObrigatorio =>
      _checklist != null &&
      _param.checklistObrigatorio &&
      (_ev == 'saida' || _ev == 'recolher' || (_ev == 'retorno' && _ficha['status'] != 'em_transito'));

  bool get _mostraChecklist => _checklist != null && (_checklistObrigatorio || _ev == 'iniciar_manutencao');

  /// A conferência do conjunto vira apontamento de falta no recolher e no retorno (se não houve recolher).
  bool get _conferenciaConta =>
      _conjunto.isNotEmpty && (_ev == 'recolher' || (_ev == 'retorno' && _ficha['status'] != 'em_transito'));
  bool get _mostraConjunto => _conjunto.isNotEmpty && (_ev == 'saida' || _conferenciaConta);
  bool get _apontaDivergencia => const ['chegada', 'recolher', 'retorno'].contains(_ev);

  @override
  void initState() {
    super.initState();
    final banco = EstadoApp.instancia.banco!;
    _ficha = Map<String, dynamic>.from(banco.eqpFicha(widget.equipamentoId) ?? const {});
    _param = EqpParametros.de(banco);
    final reservas = banco.eqpReservas(widget.equipamentoId);
    _ativa = reservas.where((r) => r['situacao'] == 'ativa').firstOrNull;
    _reservadas = reservas.where((r) => r['situacao'] == 'reservada').toList();
    if (_ev == 'saida') _reservaId = _reservadas.firstOrNull?['id'] as String?;
    if (_ev == 'retorno' || _ev == 'recolher') _localId = _ficha['local_base_id'] as String?;
    if (_ev == 'mover') {
      _localId = banco.eqpLocaisEmpresa.where((l) => l['id'] != _ficha['local_atual_id']).firstOrNull?['id'] as String?;
    }
    final tipo = _tipoChecklist;
    if (tipo != null && _ficha.isNotEmpty) _checklist = banco.eqpChecklist(_ficha, tipo);
    for (final i in ((_checklist?['itens'] as List?) ?? const []).cast<Map>()) {
      _respostas['${i['id']}'] = _Resposta();
    }
    for (final c in _conjunto) {
      _presente['${c['chave']}'] = true;
      if (c['tipo'] == 'quantidade') {
        _conferida['${c['chave']}'] = TextEditingController(text: numeroBr(c['quantidade']));
      }
    }
  }

  @override
  void dispose() {
    _semGps.dispose();
    _leitura.dispose();
    _obs.dispose();
    for (final r in _respostas.values) {
      r.dispose();
    }
    for (final c in _conferida.values) {
      c.dispose();
    }
    for (final a in _apontamentos) {
      a.dispose();
    }
    super.dispose();
  }

  void _aviso(String texto, {bool erro = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));

  // ------------------------------------------------------------------
  // GPS e fotos
  // ------------------------------------------------------------------

  Future<void> _marcarPonto() async {
    setState(() => _lendoGps = true);
    final leitura = await Gps.ler();
    if (!mounted) return;
    setState(() {
      _lendoGps = false;
      if (leitura.ok) {
        _posicao = leitura.posicao;
        _falhaGps = null;
      } else {
        _falhaGps = leitura;
      }
    });
  }

  Future<void> _tirarFoto(List<FotoEqp> destino) async {
    setState(() => _tirando = true);
    try {
      final f = await AcoesEqp.tirarFoto();
      if (f != null && mounted) setState(() => destino.add(f));
    } catch (e) {
      if (mounted) _aviso('Não foi possível tirar a foto: $e', erro: true);
    } finally {
      if (mounted) setState(() => _tirando = false);
    }
  }

  Future<void> _lerComponente() async {
    final lido = await context.push<String>('/ler-codigo');
    if (lido == null || !mounted) return;
    final v = lido.trim().toLowerCase();
    final c = _conjunto
        .where((c) => '${c['qr_token'] ?? ''}'.toLowerCase() == v || '${c['codigo'] ?? ''}'.toLowerCase() == v)
        .firstOrNull;
    if (c == null) {
      _aviso('Esta etiqueta não é de um componente deste conjunto.', erro: true);
      return;
    }
    setState(() => _presente['${c['chave']}'] = true);
    _aviso('Conferido: ${c['codigo'] ?? c['descricao']}');
  }

  // ------------------------------------------------------------------
  // Registrar
  // ------------------------------------------------------------------

  num? _num(String t) => num.tryParse(t.trim().replaceAll('.', '').replaceAll(',', '.'));
  num? _numSimples(String t) => num.tryParse(t.trim().replaceAll(',', '.'));

  /// O que falta (null = pode registrar). Mesmas regras da plataforma.
  String? _falta() {
    if (_ev == 'saida' && _reservaId == null) return 'Escolha a reserva da saída.';
    if ((_ev == 'retorno' || _ev == 'recolher' || _ev == 'mover') && _localId == null) {
      return 'Escolha o local da empresa para onde ele vai.';
    }
    if (_entrega && _param.gpsObrigatorio && _posicao == null && _semGps.text.trim().isEmpty) {
      return 'Marque o ponto pelo GPS (ou diga por que não deu).';
    }
    if (_entrega && _fotos.length < _param.fotosMinimas) {
      return 'Tire ao menos ${_param.fotosMinimas} foto(s) do equipamento.';
    }
    if (_temMedidor && _leitura.text.trim().isNotEmpty && _numSimples(_leitura.text) == null) {
      return 'Leitura inválida.';
    }
    if (_mostraChecklist) {
      for (final i in ((_checklist!['itens'] as List?) ?? const []).cast<Map>()) {
        final r = _respostas['${i['id']}']!;
        final respondido = switch ('${i['resposta']}') {
          'numero' => _numSimples(r.numero.text) != null,
          'texto' => r.texto.text.trim().isNotEmpty,
          _ => r.ok != null,
        };
        if (i['obrigatorio'] != false && !respondido && _checklistObrigatorio) return 'Checklist: falta "${i['texto']}".';
        if (i['foto_obrigatoria'] == true && respondido && r.fotos.isEmpty) return 'Checklist: "${i['texto']}" pede foto.';
      }
    }
    for (final a in _apontamentos) {
      if (a.descricao.text.trim().isEmpty) return 'Descreva cada divergência.';
      if (a.valor.text.trim().isNotEmpty && _num(a.valor.text) == null) return 'Valor sugerido inválido.';
    }
    return null;
  }

  Map<String, dynamic>? _reservaEscolhida() =>
      _reservaId == null ? null : EstadoApp.instancia.banco!.um('eqp_reservas', _reservaId);

  /// O que quem recebe vê e assina (o mesmo conteúdo vai no PDF guardado).
  ConteudoResumo _conteudo() {
    final devolucao = _ev == 'recolher' || _ev == 'retorno';
    final r = _ev == 'saida' ? _reservaEscolhida() : _ativa;
    final itens = ((_checklist?['itens'] as List?) ?? const []).cast<Map>();
    final checklist = [
      for (final i in itens)
        if (_respostas['${i['id']}'] case final _Resposta resp)
          '${i['texto']}: ${switch ('${i['resposta']}') {
            'numero' => resp.numero.text.trim(),
            'texto' => resp.texto.text.trim(),
            _ => resp.ok == null ? '—' : (resp.ok! ? 'OK' : 'NÃO OK'),
          }}${resp.obs.text.trim().isEmpty ? '' : ' (${resp.obs.text.trim()})'}',
    ].join('\n');
    final faltas = [
      for (final c in _conjunto)
        if (_presente['${c['chave']}'] == false) 'Faltou: ${[c['codigo'], c['descricao']].where((x) => x != null).join(' · ')}',
    ].join('\n');
    final divergencias = [
      for (final a in _apontamentos)
        '${tiposApontamento[a.tipo]}: ${a.descricao.text.trim()}'
            '${_num(a.valor.text) == null ? '' : ' · valor sugerido ${dinheiro(_num(a.valor.text))}'}',
    ].join('\n');
    return ConteudoResumo(
      titulo: devolucao ? 'DEVOLUÇÃO DE EQUIPAMENTO' : 'ENTREGA DE EQUIPAMENTO',
      subtitulo: '${_ficha['codigo']} · ${dataHoraBr(DateTime.now().toIso8601String())}',
      empresa: AcoesOrcamento.empresa,
      campos: [
        ('Equipamento', '${_ficha['codigo']} ${_ficha['descricao'] ?? ''}'.trim()),
        if (_ficha['patrimonio'] != null) ('Patrimônio', '${_ficha['patrimonio']}'),
        if (r?['com'] != null) (devolucao ? 'Devolvido por' : 'Para', '${r!['com']}'),
        if (r?['locacao'] != null) ('Contrato', '${r!['locacao']}'),
        if (r?['local'] != null) ('Local', [r!['local'], r['endereco']].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
        if (_temMedidor && _leitura.text.trim().isNotEmpty) ('Leitura', leituraEqp(_numSimples(_leitura.text), _ficha['medidor'])),
        if (_posicao != null) ('Ponto (GPS)', '${_posicao!.texto} ${_posicao!.precisaoTexto}'),
        ('Fotos', '${_fotos.length}'),
      ],
      blocos: [
        if (checklist.isNotEmpty) ('Checklist', checklist),
        if (faltas.isNotEmpty) ('Conjunto', faltas),
        if (divergencias.isNotEmpty) ('Divergências', divergencias),
        if (_obs.text.trim().isNotEmpty) ('Observação', _obs.text.trim()),
      ],
      termo: devolucao
          ? 'Declaro que devolvi o equipamento descrito acima. As divergências foram apontadas na minha presença; '
              'os valores são sugeridos e serão confirmados pela empresa.'
          : 'Declaro que recebi o equipamento descrito acima, nas condições registradas (checklist e fotos), e me '
              'responsabilizo por ele até a devolução.',
      recibo: true,
    );
  }

  /// Assinatura de quem recebe: (decisão, motivo sem assinatura). null = voltou.
  Future<(Decisao?, String?)?> _colherAceite() async {
    final escolha = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            title: Text('Assinatura de quem recebe', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('A pessoa confere o resumo e assina na tela.'),
          ),
          ListTile(
            leading: const Icon(Icons.draw_outlined),
            title: const Text('Colher a assinatura'),
            onTap: () => Navigator.of(ctx).pop('assinar'),
          ),
          ListTile(
            leading: const Icon(Icons.do_not_touch_outlined),
            title: const Text('Seguir sem assinatura'),
            onTap: () => Navigator.of(ctx).pop('sem'),
          ),
        ]),
      ),
    );
    if (escolha == null || !mounted) return null;
    if (escolha == 'assinar') {
      final r = _ev == 'saida' ? _reservaEscolhida() : _ativa;
      final d = await AssinaturaTela.abrir(
        context,
        AssinaturaTela(
          conteudo: _conteudo(),
          nomeInicial: r?['contato'] as String?,
          decisaoAoAssinar: 'ciente',
          botaoAssinar: 'Assinar',
        ),
      );
      if (d == null || !mounted) return null;
      return (d, null);
    }
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sem assinatura'),
        content: TextField(
          controller: motivo,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Por quê? (ex.: ninguém no local)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Seguir')),
        ],
      ),
    );
    // Sem dispose: o diálogo ainda anima a saída usando o campo.
    if (ok != true || !mounted) return null;
    if (_param.aceiteObrigatorio && motivo.text.trim().isEmpty) {
      _aviso('Informe por que ficou sem assinatura.', erro: true);
      return null;
    }
    return (null, motivo.text.trim().isEmpty ? 'Sem assinatura' : motivo.text.trim());
  }

  Future<void> _registrar() async {
    FocusScope.of(context).unfocus();
    final falta = _falta();
    if (falta != null) {
      _aviso(falta, erro: true);
      return;
    }
    Decisao? decisao;
    String? semAceite;
    if (_trocaDeMaos) {
      final r = await _colherAceite();
      if (r == null || !mounted) return;
      (decisao, semAceite) = r;
    }
    setState(() => _gravando = true);
    try {
      final anexos = <Map<String, dynamic>>[for (final f in _fotos) f.anexo];
      final itens = ((_checklist?['itens'] as List?) ?? const []).cast<Map>();
      final faltando = [
        for (final c in _conjunto)
          if (_presente['${c['chave']}'] == false) [c['codigo'], c['descricao']].where((x) => x != null).join(' · '),
      ];
      final obs = [
        _obs.text.trim(),
        // Na saída, o que não foi não vira cobrança: fica anotado.
        if (_ev == 'saida' && faltando.isNotEmpty) 'Saiu sem: ${faltando.join('; ')}',
      ].where((x) => x.isNotEmpty).join('\n');
      final dados = <String, dynamic>{
        if (_ev == 'saida') ...{'alocacao_id': _reservaId, 'direto': _direto},
        if (_ev == 'transferencia') ...{
          if (_reservaId != null) 'alocacao_id': _reservaId,
          if (_reservaId == null && _localId != null) 'local_id': _localId,
          'em_transito': _emTransito,
        },
        if (_ev == 'retorno' || _ev == 'recolher' || _ev == 'mover') 'local_id': _localId,
        if (_temMedidor && _numSimples(_leitura.text) != null) 'leitura': _numSimples(_leitura.text),
        if (_posicao != null) 'gps': _posicao!.paraEnvio(),
        if (_posicao == null && _semGps.text.trim().isNotEmpty) 'sem_gps_motivo': _semGps.text.trim(),
        'fotos': [for (final f in _fotos) f.caminho],
        if (_mostraChecklist)
          'checklist': {
            'id': AcoesEqp.novoId(),
            'modelo_id': _checklist!['id'],
            'respostas': [
              for (final i in itens)
                if (_respostas['${i['id']}'] case final _Resposta r)
                  {
                    'item_id': i['id'],
                    'texto': i['texto'],
                    if (r.ok != null) 'ok': r.ok,
                    if (_numSimples(r.numero.text) != null) 'numero': _numSimples(r.numero.text),
                    if (r.texto.text.trim().isNotEmpty) 'valor_texto': r.texto.text.trim(),
                    if (r.obs.text.trim().isNotEmpty) 'observacao': r.obs.text.trim(),
                    'fotos': [for (final f in r.fotos) f.caminho],
                  },
            ],
          },
        if (_conferenciaConta)
          'conjunto': [
            for (final c in _conjunto)
              {
                'chave': c['chave'],
                'presente': _presente['${c['chave']}'] != false,
                if (c['tipo'] == 'quantidade')
                  'quantidade_conferida': _presente['${c['chave']}'] == false
                      ? 0
                      : (_numSimples(_conferida['${c['chave']}']?.text ?? '') ?? c['quantidade']),
              },
          ],
        if (_apontamentos.isNotEmpty)
          'apontamentos': [
            for (final a in _apontamentos)
              {
                'id': a.id,
                'tipo': a.tipo,
                'descricao': a.descricao.text.trim(),
                if (_num(a.valor.text) != null) 'valor_sugerido': _num(a.valor.text),
                'fotos': [for (final f in a.fotos) f.caminho],
              },
          ],
        if (obs.isNotEmpty) 'observacao': obs,
        if (semAceite != null) 'sem_aceite_motivo': semAceite,
      };
      for (final r in _respostas.values) {
        anexos.addAll(r.fotos.map((f) => f.anexo));
      }
      for (final a in _apontamentos) {
        anexos.addAll(a.fotos.map((f) => f.anexo));
      }
      if (decisao != null) {
        final (aceite, arquivos) = await AcoesEqp.aceite(_conteudo(), decisao);
        dados['aceite'] = aceite;
        anexos.addAll(arquivos);
      }
      await AcoesEqp.registrar(ficha: _ficha, evento: _ev, dados: dados, anexos: anexos);
      if (!mounted) return;
      _aviso('${eventosEqp[_ev]} registrada. Sobe para a plataforma assim que houver internet.');
      context.pop();
    } catch (e) {
      if (mounted) _aviso('Não foi possível registrar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  // ------------------------------------------------------------------
  // Tela
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_ficha.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Registrar')),
        body: const Center(child: Text('Equipamento não encontrado no aparelho.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(eventosEqp[_ev] ?? _ev, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('${_ficha['codigo']} · ${_ficha['descricao'] ?? ''}',
              style: const TextStyle(fontSize: 13, color: Cores.neutro), overflow: TextOverflow.ellipsis),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
        _Secao(
          titulo: 'Agora',
          child: Row(children: [
            StatusChip('${_ficha['status']}', statusEqp),
            const SizedBox(width: 8),
            Expanded(child: Text('${_ficha['local_atual'] ?? ''}${_ficha['com'] != null ? ' · ${_ficha['com']}' : ''}')),
          ]),
        ),
        ..._destino(),
        if (_entrega) _secaoGps(),
        _Secao(
          titulo: _entrega ? 'Fotos do equipamento (mínimo ${_param.fotosMinimas})' : 'Fotos (opcional)',
          child: _Fotos(fotos: _fotos, ocupado: _tirando, aoTirar: () => _tirarFoto(_fotos), aoTirarDe: setState),
        ),
        if (_temMedidor)
          _Secao(
            titulo: switch ('${_ficha['medidor']}') { 'km' => 'Odômetro', 'ciclos' => 'Ciclos', _ => 'Horímetro' },
            child: TextField(
              controller: _leitura,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Leitura agora',
                helperText: 'Última: ${leituraEqp(_ficha['leitura_atual'], _ficha['medidor'])}',
              ),
            ),
          ),
        if (_mostraChecklist) _secaoChecklist(),
        if (_mostraConjunto) _secaoConjunto(),
        if (_apontaDivergencia) _secaoDivergencias(),
        _Secao(
          titulo: 'Observação',
          child: TextField(
            controller: _obs,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Opcional'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: _gravando ? null : _registrar,
            icon: _gravando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(_trocaDeMaos ? 'Registrar e colher assinatura' : 'Registrar'),
          ),
        ),
      ]),
    );
  }

  List<Widget> _destino() {
    final locaisEmpresa = EstadoApp.instancia.banco!.eqpLocaisEmpresa;
    switch (_ev) {
      case 'saida':
        return [
          _Secao(
            titulo: 'Reserva',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_reservadas.isEmpty)
                const Text('Sem reserva no aparelho: o escritório reserva pelo painel.', style: TextStyle(color: Cores.alerta)),
              for (final r in _reservadas)
                _Opcao(
                  selecionada: _reservaId == r['id'],
                  titulo: '${r['com'] ?? destinosEqp[r['destino']] ?? ''}${r['locacao'] != null ? ' · ${r['locacao']}' : ''}',
                  subtitulo: [
                    '${dataBr(r['inicio'])}${r['fim_previsto'] != null ? ' a ${dataBr(r['fim_previsto'])}' : ''}',
                    [r['local'], r['endereco']].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                  ].where((x) => x.isNotEmpty).join('\n'),
                  aoTocar: () => setState(() => _reservaId = r['id'] as String?),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _direto,
                onChanged: (v) => setState(() => _direto = v),
                title: const Text('Entregue aqui, agora'),
                subtitle: Text(_direto
                    ? 'Quem recebe está presente e assina.'
                    : 'Vai em trânsito: a entrega (com o ponto e a assinatura) é registrada na chegada.'),
              ),
            ]),
          ),
        ];
      case 'transferencia':
        final mesmoCliente = _ativa == null
            ? const <Map<String, dynamic>>[]
            : EstadoApp.instancia.banco!
                .todos('locais')
                .where((l) => l['cliente_id'] == _ativa!['cliente_id'] && l['id'] != _ativa!['local_id'])
                .toList();
        return [
          _Secao(
            titulo: 'Para onde',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final r in _reservadas)
                _Opcao(
                  selecionada: _reservaId == r['id'],
                  titulo: 'Outro destino: ${r['com'] ?? destinosEqp[r['destino']] ?? ''}',
                  subtitulo: [r['local'], r['endereco']].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                  aoTocar: () => setState(() {
                    _reservaId = r['id'] as String?;
                    _localId = null;
                  }),
                ),
              for (final l in mesmoCliente)
                _Opcao(
                  selecionada: _reservaId == null && _localId == l['id'],
                  titulo: 'Mesmo cliente: ${l['nome']}',
                  subtitulo: [l['logradouro'], l['numero'], l['cidade']].where((x) => x != null && '$x'.isNotEmpty).join(', '),
                  aoTocar: () => setState(() {
                    _localId = l['id'] as String?;
                    _reservaId = null;
                  }),
                ),
              if (_reservadas.isEmpty && mesmoCliente.isEmpty)
                const Text('Nenhum outro destino no aparelho: o escritório reserva pelo painel.',
                    style: TextStyle(color: Cores.alerta)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _emTransito,
                onChanged: (v) => setState(() => _emTransito = v),
                title: const Text('Vai em trânsito'),
                subtitle: const Text('Desligado: já está no novo local.'),
              ),
            ]),
          ),
        ];
      case 'retorno' || 'recolher' || 'mover':
        return [
          _Secao(
            titulo: _ev == 'mover' ? 'Para qual local da empresa' : 'Volta para',
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final l in locaisEmpresa)
                ChoiceChip(
                  label: Text('${l['nome']}'),
                  selected: _localId == l['id'],
                  onSelected: (_) => setState(() => _localId = l['id'] as String?),
                ),
              if (locaisEmpresa.isEmpty)
                const Text('Sem locais da empresa no aparelho (sincronize).', style: TextStyle(color: Cores.alerta)),
            ]),
          ),
        ];
      default:
        return const [];
    }
  }

  Widget _secaoGps() {
    final p = _posicao;
    final boa = p != null && p.precisaoM <= _param.precisaoBoaM;
    return _Secao(
      titulo: 'Ponto exato (GPS)',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Marque no lugar onde o equipamento fica. A localização é lida só agora, com o app aberto.',
            style: TextStyle(color: Cores.neutro, fontSize: 13)),
        const SizedBox(height: 8),
        if (p != null) ...[
          Row(children: [
            Icon(boa ? Icons.gps_fixed : Icons.gps_not_fixed, color: boa ? Cores.sucesso : Cores.alerta),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${p.texto}\n${p.precisaoTexto} · ${horaDe(p.em.toIso8601String())}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
          if (!boa)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Precisão baixa: se puder, vá para um lugar aberto e marque de novo.',
                  style: TextStyle(color: Cores.alerta)),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final abriu = await p.abrirNoMapa();
                  if (!abriu && mounted) _aviso('Não foi possível abrir o mapa.', erro: true);
                },
                icon: const Icon(Icons.map_outlined),
                label: const Text('Conferir no mapa'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _lendoGps ? null : _marcarPonto,
                icon: const Icon(Icons.my_location),
                label: const Text('Marcar de novo'),
              ),
            ),
          ]),
        ] else ...[
          SizedBox(
            height: 52,
            child: FilledButton.tonalIcon(
              onPressed: _lendoGps ? null : _marcarPonto,
              icon: _lendoGps
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
              label: Text(_lendoGps ? 'Lendo o GPS...' : 'Marcar o ponto agora'),
            ),
          ),
          if (_falhaGps != null) ...[
            const SizedBox(height: 8),
            Text(_falhaGps!.motivo ?? '', style: const TextStyle(color: Cores.erro, fontWeight: FontWeight.w600)),
            if (_falhaGps!.abrirConfiguracoes)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Gps.abrirConfiguracoes(doApp: !_falhaGps!.servicoDesligado),
                  child: const Text('Abrir as configurações'),
                ),
              ),
            TextField(
              controller: _semGps,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Seguir sem o ponto: por quê?', hintText: 'Ex.: sem sinal no subsolo'),
            ),
          ],
        ],
      ]),
    );
  }

  Widget _secaoChecklist() {
    final itens = ((_checklist!['itens'] as List?) ?? const []).cast<Map>();
    return _Secao(
      titulo: 'Checklist · ${_checklist!['nome']}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final i in itens) _itemChecklist(i, _respostas['${i['id']}']!),
      ]),
    );
  }

  Widget _itemChecklist(Map i, _Resposta r) {
    final tipo = '${i['resposta']}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: '${i['texto']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (i['obrigatorio'] != false) const TextSpan(text: ' *', style: TextStyle(color: Cores.erro)),
          if (i['foto_obrigatoria'] == true) const TextSpan(text: '  (com foto)', style: TextStyle(color: Cores.neutro)),
        ])),
        const SizedBox(height: 6),
        if (tipo == 'numero')
          TextField(
            controller: r.numero,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(isDense: true, suffixText: i['unidade'] as String?),
            onChanged: (_) => setState(() {}),
          )
        else if (tipo == 'texto')
          TextField(
            controller: r.texto,
            decoration: const InputDecoration(isDense: true),
            onChanged: (_) => setState(() {}),
          )
        else
          Row(children: [
            ChoiceChip(
              label: const Text('OK'),
              selected: r.ok == true,
              selectedColor: Cores.sucesso.withValues(alpha: .2),
              onSelected: (_) => setState(() => r.ok = true),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Não OK'),
              selected: r.ok == false,
              selectedColor: Cores.erro.withValues(alpha: .2),
              onSelected: (_) => setState(() => r.ok = false),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Foto do item',
              onPressed: _tirando ? null : () => _tirarFoto(r.fotos),
              icon: Badge(
                isLabelVisible: r.fotos.isNotEmpty,
                label: Text('${r.fotos.length}'),
                child: const Icon(Icons.photo_camera_outlined),
              ),
            ),
          ]),
        if (r.ok == false)
          TextField(
            controller: r.obs,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(isDense: true, labelText: 'O que está errado?'),
          ),
      ]),
    );
  }

  Widget _secaoConjunto() {
    return _Secao(
      titulo: 'Conjunto',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          _conferenciaConta
              ? 'Confira cada componente. O que faltar vira um apontamento de falta, com o valor de reposição.'
              : 'Confira o que sai junto. O que não for fica anotado na saída.',
          style: const TextStyle(color: Cores.neutro, fontSize: 13),
        ),
        for (final c in _conjunto)
          Row(children: [
            Expanded(
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _presente['${c['chave']}'] != false,
                onChanged: (v) => setState(() => _presente['${c['chave']}'] = v ?? false),
                title: Text([c['codigo'], c['descricao']].where((x) => x != null).join(' · ')),
                subtitle: Text([
                  if (c['tipo'] == 'quantidade') 'Quantidade ${numeroBr(c['quantidade'])}',
                  if (_conferenciaConta && c['valor_reposicao'] != null) 'reposição ${dinheiro(c['valor_reposicao'])}',
                ].join(' · ')),
              ),
            ),
            if (c['tipo'] == 'quantidade' && _presente['${c['chave']}'] != false)
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _conferida['${c['chave']}'],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(isDense: true, labelText: 'Veio'),
                ),
              ),
          ]),
        if (_conjunto.any((c) => c['tipo'] == 'serializado'))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _lerComponente,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Ler a etiqueta de um componente'),
            ),
          ),
      ]),
    );
  }

  Widget _secaoDivergencias() {
    return _Secao(
      titulo: 'Divergências',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_apontamentos.isEmpty)
          const Text('Nada fora do normal? Siga. Se houver avaria, falta, sujeira ou uso acima, aponte aqui com foto.',
              style: TextStyle(color: Cores.neutro, fontSize: 13)),
        for (final a in _apontamentos)
          Card(
            color: Cores.fundo,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final t in tiposApontamento.entries)
                        ChoiceChip(
                          label: Text(t.value),
                          selected: a.tipo == t.key,
                          onSelected: (_) => setState(() => a.tipo = t.key),
                        ),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Tirar este apontamento',
                    onPressed: () => setState(() {
                      _apontamentos.remove(a);
                      a.dispose();
                    }),
                    icon: const Icon(Icons.delete_outline, color: Cores.erro),
                  ),
                ]),
                TextField(
                  controller: a.descricao,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'O que houve'),
                ),
                TextField(
                  controller: a.valor,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Valor sugerido (R\$, opcional)'),
                ),
                const SizedBox(height: 6),
                _Fotos(fotos: a.fotos, ocupado: _tirando, aoTirar: () => _tirarFoto(a.fotos), aoTirarDe: setState),
              ]),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _apontamentos.add(_Apontamento('avaria'))),
            icon: const Icon(Icons.add),
            label: const Text('Apontar divergência'),
          ),
        ),
      ]),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.child});
  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(titulo.toUpperCase(),
                style: const TextStyle(fontSize: 12, letterSpacing: .6, fontWeight: FontWeight.w800, color: Cores.indigo700)),
            const SizedBox(height: 8),
            child,
          ]),
        ),
      );
}

class _Opcao extends StatelessWidget {
  const _Opcao({required this.selecionada, required this.titulo, required this.subtitulo, required this.aoTocar});
  final bool selecionada;
  final String titulo;
  final String subtitulo;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: aoTocar,
        leading: Icon(selecionada ? Icons.check_circle : Icons.circle_outlined,
            color: selecionada ? Cores.indigo500 : Cores.neutro),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: subtitulo.isEmpty ? null : Text(subtitulo),
      );
}

/// Miniaturas das fotos tiradas, com o botão de tirar e o de tirar da lista.
class _Fotos extends StatelessWidget {
  const _Fotos({required this.fotos, required this.ocupado, required this.aoTirar, required this.aoTirarDe});
  final List<FotoEqp> fotos;
  final bool ocupado;
  final VoidCallback aoTirar;
  final void Function(VoidCallback) aoTirarDe;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
        for (final f in fotos)
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(fit: StackFit.expand, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Arquivos.equipamento(f.local)?.existsSync() ?? false
                    ? Image.file(Arquivos.equipamento(f.local)!, fit: BoxFit.cover, cacheWidth: 200)
                    : const ColoredBox(color: Cores.indigo100),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  tooltip: 'Tirar esta foto',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => aoTirarDe(() => fotos.remove(f)),
                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                ),
              ),
            ]),
          ),
        SizedBox(
          width: 84,
          height: 84,
          child: OutlinedButton(
            onPressed: ocupado ? null : aoTirar,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            child: const Icon(Icons.add_a_photo_outlined),
          ),
        ),
      ]);
}
