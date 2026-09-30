import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../cadastros/campos.dart';
import '../cadastros/definicoes.dart';
import '../servicos/status.dart';
import '../widgets/campos_data_hora.dart';
import '../widgets/escolha_equipamentos.dart';

/// Abertura de OS. A OS nasce "aberta", com um agendamento na fila.
class OsNovaTela extends StatefulWidget {
  const OsNovaTela({super.key});

  @override
  State<OsNovaTela> createState() => _OsNovaTelaState();
}

class _OsNovaTelaState extends State<OsNovaTela> {
  static const _campoCliente = CampoDef('cliente_id', 'Cliente',
      tipo: TipoCampo.lookup, obrigatorio: true, lookup: Lookup(tabela: 'clientes'));
  static const _campoLocal = CampoDef('local_id', 'Local',
      tipo: TipoCampo.lookup,
      obrigatorio: true,
      lookup: Lookup(tabela: 'locais', colunaDetalhe: 'cidade', colunaFiltro: 'cliente_id', campoPai: 'cliente_id'));
  static const _campoSolicitante = CampoDef('solicitante_contato_id', 'Quem pediu (contato)',
      tipo: TipoCampo.lookup,
      lookup: Lookup(tabela: 'contatos', colunaDetalhe: 'cargo', colunaFiltro: 'cliente_id', campoPai: 'cliente_id'));

  final _form = GlobalKey<FormState>();
  final _problema = TextEditingController();
  final _obsInterna = TextEditingController();
  final _orientacoes = TextEditingController();
  final _duracao = TextEditingController();

  String _tipo = 'corretiva';
  String _prioridade = 'media';
  String? _clienteId;
  String? _localId;
  String? _solicitanteId;
  bool _requerOrcamento = false;
  DateTime? _prevista;
  String _tipoAgendamento = 'visita_tecnica';
  DateTime? _dataAgendamento;
  TimeOfDay? _janelaInicio;
  TimeOfDay? _janelaFim;

  /// Equipamentos escolhidos: id -> "código · descrição".
  final Map<String, String> _equipamentos = {};
  bool _salvando = false;

  @override
  void dispose() {
    for (final c in [_problema, _obsInterna, _orientacoes, _duracao]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Trocou cliente ou local: a escolha de equipamentos recomeça.
  void _limparEquipamentos() => setState(_equipamentos.clear);

  Future<void> _escolherEquipamentos() async {
    if (_localId == null || _clienteId == null) return;
    final r = await escolherEquipamentos(context,
        clienteId: _clienteId!, localId: _localId!, atuais: _equipamentos.keys.toSet());
    if (r != null && mounted) {
      setState(() {
        _equipamentos
          ..clear()
          ..addAll(r);
      });
    }
  }

  void _avisar(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _salvando = true);
    try {
      final r = await acaoOs({
        'acao': 'abrir',
        'tipo': _tipo,
        'prioridade': _prioridade,
        'cliente_id': _clienteId,
        'local_id': _localId,
        'solicitante_contato_id': _solicitanteId,
        'problema_relatado': _problema.text.trim(),
        'observacao_interna': _obsInterna.text.trim(),
        'requer_orcamento': _requerOrcamento,
        'prevista_para': _prevista == null ? null : dataIso(_prevista!),
        'equipamentos': _equipamentos.keys.toList(),
        'agendamento': {
          'tipo': _tipoAgendamento,
          'data_prevista': _dataAgendamento == null ? null : dataIso(_dataAgendamento!),
          'janela_inicio': horaParaBanco(_janelaInicio),
          'janela_fim': horaParaBanco(_janelaFim),
          'duracao_estimada_min': int.tryParse(_duracao.text.trim()),
          'orientacoes': _orientacoes.text.trim(),
        },
      });
      final osId = r['os_id'] as String;
      final aviso = r['aviso'] as Map<String, dynamic>?;
      if (aviso != null && aviso['tipo'] == 'garantia_possivel' && mounted) {
        await _perguntarGarantia(osId, aviso);
      }
      if (!mounted) return;
      _avisar('${r['codigo']} aberta. O agendamento já está na fila.');
      // Volta para quem abriu (lista ou fila) levando o id; ela abre a OS nova.
      if (context.canPop()) {
        context.pop(osId);
      } else {
        context.go('/os/$osId');
      }
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _perguntarGarantia(String osId, Map<String, dynamic> aviso) async {
    final decisao = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.verified_user_outlined, color: Cores.alerta),
        title: const Text('Possível retorno em garantia'),
        content: Text('${aviso['mensagem']}\n\n'
            'Confirmando, esta OS fica ligada à ${aviso['codigo']} e não será cobrada. '
            'Se não souber agora, dá para decidir depois na própria OS.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Decidir depois')),
          OutlinedButton(onPressed: () => Navigator.of(ctx).pop('descartar'), child: const Text('Não é garantia')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop('confirmar'), child: const Text('Confirmar garantia')),
        ],
      ),
    );
    if (decisao == null) return;
    try {
      await acaoOs({'acao': 'garantia', 'os_id': osId, 'decisao': decisao});
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    }
  }

  /// Cartão de seção. [filhos] recebe a largura cheia, a de meia e a de um quarto,
  /// para os campos se ajustarem à tela (duas colunas em tela larga).
  Widget _secao(String titulo, List<Widget> Function(double cheio, double metade, double quarto) filhos) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: LayoutBuilder(builder: (context, box) {
            final cheio = box.maxWidth;
            final metade = cheio >= 640 ? (cheio - 16) / 2 : cheio;
            final quarto = cheio >= 640 ? (cheio - 48) / 4 : metade;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(titulo,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Wrap(spacing: 16, runSpacing: 16, children: filhos(cheio, metade, quarto)),
              ],
            );
          }),
        ),
      );


  Widget _dropdown(String rotulo, String valor, Map<String, String> opcoes, ValueChanged<String> aoMudar,
      {required double largura}) {
    return SizedBox(
      width: largura,
      child: InputDecorator(
        decoration: InputDecoration(labelText: rotulo),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: valor,
            isDense: true,
            isExpanded: true,
            items: [
              for (final e in opcoes.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => aoMudar(v ?? valor),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  IconButton(
                    onPressed: () => context.canPop() ? context.pop() : context.go('/os'),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 4),
                  Text('Nova OS',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 16),
                _secao('Onde e o quê', (cheio, metade, quarto) => [
                  _dropdown('Tipo', _tipo, tiposOs, (v) => setState(() {
                        _tipo = v;
                        _tipoAgendamento = v == 'preventiva' ? 'preventiva' : 'visita_tecnica';
                      }), largura: quarto),
                  _dropdown('Prioridade', _prioridade, {for (final e in prioridades.entries) e.key: e.value.texto},
                      (v) => setState(() => _prioridade = v), largura: quarto),
                  SizedBox(
                    width: metade,
                    child: CampoLookup(
                      campo: _campoCliente,
                      valor: _clienteId,
                      valorPai: null,
                      rotuloPai: null,
                      habilitado: !_salvando,
                      aoMudar: (v) {
                        setState(() {
                          _clienteId = v;
                          _localId = null;
                          _solicitanteId = null;
                        });
                        _limparEquipamentos();
                      },
                    ),
                  ),
                  SizedBox(
                    width: metade,
                    child: CampoLookup(
                      campo: _campoLocal,
                      valor: _localId,
                      valorPai: _clienteId,
                      rotuloPai: 'Cliente',
                      habilitado: !_salvando,
                      aoMudar: (v) {
                        setState(() => _localId = v);
                        _limparEquipamentos();
                      },
                    ),
                  ),
                  SizedBox(
                    width: metade,
                    child: CampoLookup(
                      campo: _campoSolicitante,
                      valor: _solicitanteId,
                      valorPai: _clienteId,
                      rotuloPai: 'Cliente',
                      habilitado: !_salvando,
                      aoMudar: (v) => setState(() => _solicitanteId = v),
                    ),
                  ),
                  SizedBox(
                    width: quarto,
                    child: CampoData(
                      rotulo: 'Prevista para',
                      valor: _prevista,
                      aoMudar: (d) => setState(() => _prevista = d),
                    ),
                  ),
                  SizedBox(
                    width: cheio,
                    child: TextFormField(
                      controller: _problema,
                      minLines: 2,
                      maxLines: 6,
                      decoration: const InputDecoration(labelText: 'Problema relatado *'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Descreva o problema ou o serviço' : null,
                    ),
                  ),
                  SizedBox(
                    width: cheio,
                    child: TextFormField(
                      controller: _obsInterna,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Observação interna (o cliente não vê)'),
                    ),
                  ),
                  SizedBox(
                    width: metade,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _requerOrcamento,
                      onChanged: (v) => setState(() => _requerOrcamento = v),
                      title: const Text('Precisa de orçamento antes de executar'),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _secao('Equipamentos', (cheio, metade, quarto) => [
                  if (_localId == null)
                    const Text('Escolha o local para ver os equipamentos.', style: TextStyle(color: Cores.neutro))
                  else
                    SizedBox(
                      width: cheio,
                      child: ResumoEquipamentos(
                        escolhidos: _equipamentos,
                        habilitado: !_salvando,
                        aoEscolher: _escolherEquipamentos,
                        aoRemover: (id) => setState(() => _equipamentos.remove(id)),
                      ),
                    ),
                ]),
                const SizedBox(height: 16),
                _secao('Primeira visita (vai para a fila)', (cheio, metade, quarto) => [
                  _dropdown('Tipo de visita', _tipoAgendamento, tiposAgendamento,
                      (v) => setState(() => _tipoAgendamento = v), largura: quarto),
                  SizedBox(
                    width: quarto,
                    child: CampoData(
                      rotulo: 'Data desejada',
                      valor: _dataAgendamento,
                      aoMudar: (d) => setState(() => _dataAgendamento = d),
                    ),
                  ),
                  SizedBox(
                    width: quarto,
                    child: CampoHora(
                      rotulo: 'Janela: das',
                      valor: _janelaInicio,
                      aoMudar: (t) => setState(() => _janelaInicio = t),
                    ),
                  ),
                  SizedBox(
                    width: quarto,
                    child: CampoHora(
                      rotulo: 'até',
                      valor: _janelaFim,
                      aoMudar: (t) => setState(() => _janelaFim = t),
                    ),
                  ),
                  SizedBox(
                    width: quarto,
                    child: TextFormField(
                      controller: _duracao,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Duração (min)'),
                      validator: (v) => (v ?? '').trim().isEmpty || int.tryParse(v!.trim()) != null
                          ? null
                          : 'Só números',
                    ),
                  ),
                  SizedBox(
                    width: cheio,
                    child: TextFormField(
                      controller: _orientacoes,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Orientações para a equipe'),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  OutlinedButton(
                    onPressed: () => context.canPop() ? context.pop() : context.go('/os'),
                    child: const Text('Voltar'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _salvando ? null : _salvar,
                    icon: _salvando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: const Text('Abrir OS'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
