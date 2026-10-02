import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../core/acoes_atendimento.dart';
import '../core/acoes_mensagens.dart';
import '../core/acoes_orcamento.dart';
import '../core/banco_local.dart';
import '../core/consultas.dart';
import '../core/conteudos.dart';
import '../core/estado.dart';
import '../core/formatos.dart';
import '../widgets/aba_orcamento.dart';
import '../widgets/abas_atendimento.dart';
import '../widgets/entrar_no_servico.dart';
import '../widgets/indicador_sync.dart';
import '../widgets/status_chip.dart';
import 'assinatura_tela.dart';

const _statusAtendimento = {
  'em_andamento': Rotulo('Em andamento', Cores.andamento),
  'pausado': Rotulo('Pausado', Cores.alerta),
  'concluido': Rotulo('Concluído', Cores.sucesso),
  'nao_realizado': Rotulo('Não realizado', Cores.erro),
  'cancelado': Rotulo('Cancelado', Cores.neutro),
};

const _camposRelato = {
  'problema_identificado': 'Problema identificado',
  'causa': 'Causa',
  'solucao': 'Solução',
  'observacoes': 'Observações',
};

/// O atendimento no local: quem está no serviço, relato, equipamentos,
/// medições, itens e fotos; no fim, concluir ou não realizado.
class AtendimentoTela extends StatefulWidget {
  const AtendimentoTela({super.key, required this.atendimentoId});

  final String atendimentoId;

  @override
  State<AtendimentoTela> createState() => _AtendimentoTelaState();
}

class _AtendimentoTelaState extends State<AtendimentoTela> {
  final _relato = {for (final c in _camposRelato.keys) c: TextEditingController()};
  bool _sujo = false;

  @override
  void dispose() {
    for (final c in _relato.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final atd = EstadoApp.instancia.banco?.um('atendimentos', widget.atendimentoId);
    if (atd != null) {
      for (final e in _relato.entries) {
        e.value.text = '${atd[e.key] ?? ''}';
      }
    }
  }

  /// Sem edição pendente, os campos acompanham o que chegou da plataforma
  /// (depois do quadro atual, para não mexer nos campos durante o desenho).
  void _sincronizarCampos(Map<String, dynamic> atd) {
    if (_sujo) return;
    final diferentes = _relato.entries.where((e) => e.value.text != '${atd[e.key] ?? ''}').toList();
    if (diferentes.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _sujo) return;
      for (final e in diferentes) {
        e.value.text = '${atd[e.key] ?? ''}';
      }
    });
  }

  Future<void> _salvarRelato({bool avisar = true}) async {
    if (!_sujo) return;
    final atd = EstadoApp.instancia.banco?.um('atendimentos', widget.atendimentoId);
    if (atd == null) return;
    final campos = <String, dynamic>{
      for (final e in _relato.entries)
        if (e.value.text.trim() != '${atd[e.key] ?? ''}') e.key: e.value.text.trim(),
    };
    _sujo = false;
    if (campos.isEmpty) return;
    await AcoesAtendimento.salvarRelato(widget.atendimentoId, campos);
    if (avisar && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Relato salvo.')));
    }
    if (mounted) setState(() {});
  }

  Future<void> _concluir(Map<String, dynamic> atd) async {
    var presente = true;
    final nome = TextEditingController(text: '${atd['contato_cliente_nome'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Concluir o atendimento?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('O cliente acompanhou'),
              value: presente,
              onChanged: (v) => setD(() => presente = v),
            ),
            if (presente)
              TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome de quem acompanhou')),
            const SizedBox(height: 8),
            const Text('Todos que estão no serviço saem agora.', style: TextStyle(color: Cores.neutro)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Concluir')),
          ],
        ),
      ),
    );
    // Sem dispose aqui: o diálogo ainda anima a saída usando o campo (o
    // controle sem ouvintes é liberado pelo coletor de lixo).
    final contato = nome.text;
    if (!mounted) return;
    if (ok != true) return;
    await _salvarRelato(avisar: false);
    if (!mounted) return;

    // Assinatura do cliente na conclusão (conforme a empresa).
    String? semAssinatura;
    var assinou = false;
    final modo = AcoesOrcamento.config.aceiteConclusao;
    try {
      if (presente && modo != 'desligado') {
        final atual = EstadoApp.instancia.banco?.um('atendimentos', atd['id']) ?? atd;
        final colher = modo == 'obrigatorio' ? true : await _perguntarAssinatura();
        if (!mounted) return;
        if (colher == null) return;
        if (colher) {
          // O mesmo conteúdo na tela e no PDF.
          final conteudo = Conteudos.conclusao(atual);
          final decisao = await AssinaturaTela.abrir(
            context,
            AssinaturaTela(
              conteudo: conteudo,
              nomeInicial: contato.trim().isEmpty ? null : contato.trim(),
              decisaoAoAssinar: 'ciente',
              botaoAssinar: 'Assinar',
            ),
          );
          if (!mounted) return;
          if (decisao != null) {
            await AcoesOrcamento.registrarConclusao(atd: atual, conteudo: conteudo, decisao: decisao);
            assinou = true;
          } else if (modo == 'obrigatorio') {
            semAssinatura = await _motivoSemAssinatura();
            if (semAssinatura == null) return;
          } else {
            return; // voltou da assinatura: o atendimento continua aberto
          }
        }
      }
      await AcoesAtendimento.concluir(atd,
          clientePresente: presente, contatoNome: presente ? contato : null, semAssinaturaMotivo: semAssinatura);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Não foi possível concluir: $e'), backgroundColor: Cores.erro));
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(assinou ? 'Atendimento concluído, com a assinatura do cliente.' : 'Atendimento concluído.')));
    await _avisarConclusao(atd);
    if (!mounted) return;
    context.go('/hoje');
  }

  /// Serviço concluído: oferece a mensagem ao cliente, com o link do relatório.
  Future<void> _avisarConclusao(Map<String, dynamic> atd) async {
    final banco = EstadoApp.instancia.banco!;
    final atual = banco.um('atendimentos', atd['id']) ?? atd;
    final os = banco.um('ordens_servico', atual['os_id']);
    if (os == null) return;
    final solucao = '${atual['solucao'] ?? ''}'.trim();
    await AcoesMensagens.mandar(
      context,
      modelo: 'concluido',
      titulo: 'Avisar o cliente',
      os: os,
      valores: {'resumo': solucao.length > 300 ? '${solucao.substring(0, 297)}...' : solucao},
      link: LinkPreparado.novo(entidade: 'os_relatorio', osId: '${os['id']}'),
      entidade: 'atendimento',
      entidadeId: '${atd['id']}',
    );
  }

  /// Assinatura opcional: colher agora? (null = voltar sem concluir)
  Future<bool?> _perguntarAssinatura() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Assinatura do cliente'),
          content: const Text('Quer que o cliente assine na tela o recebimento do serviço?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Voltar')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Concluir sem assinatura')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Colher assinatura')),
          ],
        ),
      );

  /// Assinatura obrigatória e o cliente não assinou: o motivo vai para o histórico.
  Future<String?> _motivoSemAssinatura() async {
    final motivo = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Concluir sem a assinatura?'),
        content: TextField(
          controller: motivo,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Por quê? (ex.: o cliente não quis assinar)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Voltar')),
          FilledButton(
            onPressed: () {
              if (motivo.text.trim().isNotEmpty) Navigator.of(ctx).pop(motivo.text.trim());
            },
            child: const Text('Concluir'),
          ),
        ],
      ),
    );
    // Sem dispose: o diálogo ainda anima a saída usando o campo.
    return r;
  }

  Future<void> _naoRealizado(Map<String, dynamic> atd) async {
    final obs = TextEditingController();
    final motivo = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const ListTile(title: Text('Por que não foi feito?', style: TextStyle(fontWeight: FontWeight.w800))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(controller: obs, decoration: const InputDecoration(labelText: 'Observação (opcional)')),
              ),
              for (final m in motivosNaoRealizado.entries)
                ListTile(title: Text(m.value), onTap: () => Navigator.of(ctx).pop(m.key)),
            ]),
          ),
        ),
      ),
    );
    // Sem dispose: a folha ainda anima a saída usando o campo.
    final observacao = obs.text;
    if (motivo == null) return;
    await _salvarRelato(avisar: false);
    await AcoesAtendimento.naoRealizado(atd, motivo: motivo, observacao: observacao);
    if (mounted) context.go('/hoje');
  }

  @override
  Widget build(BuildContext context) {
    final banco = EstadoApp.instancia.banco!;
    return ListenableBuilder(
      listenable: banco,
      builder: (context, _) {
        final atd = banco.um('atendimentos', widget.atendimentoId);
        if (atd == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Atendimento')),
            body: const Center(child: Text('Atendimento não encontrado neste aparelho.')),
          );
        }
        _sincronizarCampos(atd);
        final os = banco.um('ordens_servico', atd['os_id']) ?? const {};
        final cliente = banco.um('clientes', os['cliente_id']) ?? const {};
        final aberto = atd['status'] == 'em_andamento' || atd['status'] == 'pausado';

        return PopScope(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) _salvarRelato(avisar: false);
          },
          child: DefaultTabController(
            length: 6,
            child: Scaffold(
              appBar: AppBar(
                title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${os['codigo'] ?? 'Atendimento'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${cliente['nome'] ?? ''}', style: const TextStyle(fontSize: 13, color: Cores.neutro)),
                ]),
                actions: const [IndicadorSync()],
                bottom: const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Relato'),
                    Tab(text: 'Equipamentos'),
                    Tab(text: 'Medições'),
                    Tab(text: 'Itens'),
                    Tab(text: 'Fotos'),
                    Tab(text: 'Orçamento'),
                  ],
                ),
              ),
              body: Column(children: [
                _QuemEsta(banco: banco, atd: atd, aberto: aberto),
                Expanded(
                  child: TabBarView(children: [
                    _Relato(
                      controles: _relato,
                      habilitado: aberto,
                      sujo: _sujo,
                      aoMudar: () => setState(() => _sujo = true),
                      aoSalvar: _salvarRelato,
                    ),
                    AbaEquipamentos(atd: atd, habilitado: aberto),
                    AbaMedicoes(atd: atd, habilitado: aberto),
                    AbaItens(atd: atd, habilitado: aberto),
                    AbaFotos(atd: atd, habilitado: aberto),
                    AbaOrcamento(atd: atd, habilitado: aberto),
                  ]),
                ),
              ]),
              bottomNavigationBar: aberto
                  ? SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Row(children: [
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: OutlinedButton(
                                onPressed: () => _naoRealizado(atd),
                                child: const Text('Não realizado', style: TextStyle(color: Cores.erro)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 52,
                              child: FilledButton.icon(
                                onPressed: () => _concluir(atd),
                                icon: const Icon(Icons.check),
                                label: const Text('Concluir'),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    )
                  : null,
            ),
          ),
        );
      },
    );
  }
}

/// Faixa de cima: status e quem está no serviço agora, com entrar/sair
/// e, para o líder, incluir ou tirar pessoas da equipe.
class _QuemEsta extends StatelessWidget {
  const _QuemEsta({required this.banco, required this.atd, required this.aberto});

  final BancoLocal banco;
  final Map<String, dynamic> atd;
  final bool aberto;

  Future<void> _pessoas(BuildContext context, Map<String, dynamic> item, String parteId) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: banco,
        builder: (ctx, _) {
          final abertos = banco.participantes(atd['id'], soAbertos: true);
          return SafeArea(
            child: ListView(shrinkWrap: true, children: [
              const ListTile(title: Text('Pessoas neste serviço', style: TextStyle(fontWeight: FontWeight.w800))),
              for (final c in banco.presentes(parteId))
                Builder(builder: (_) {
                  final colab = c['colaborador_id'] as String;
                  final aqui = abertos.where((p) => p['colaborador_id'] == colab).firstOrNull;
                  final outro = aqui == null ? banco.checkinAberto(colab) : null;
                  return ListTile(
                    title: Text(banco.nomeColaborador(colab)),
                    subtitle: Text(aqui != null
                        ? 'No serviço desde ${horaDe(aqui['entrada_em'])}'
                        : outro != null
                            ? 'Em outro serviço'
                            : 'Livre'),
                    trailing: aqui != null
                        ? TextButton(onPressed: () => AcoesAtendimento.checkout(aqui), child: const Text('Tirar'))
                        : colab == AcoesAtendimento.eu
                            ? null
                            : TextButton(
                                onPressed: () => AcoesAtendimento.checkin(item, colaboradorId: colab),
                                child: const Text('Incluir'),
                              ),
                  );
                }),
            ]),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = banco.um('partes_itens', atd['parte_item_id']) ?? const {};
    final parte = banco.um('partes_diarias', item['parte_id']) ?? const {};
    final abertos = banco.participantes(atd['id'], soAbertos: true);
    final eu = AcoesAtendimento.eu;
    final meu = abertos.where((p) => p['colaborador_id'] == eu).firstOrNull;
    final souLider = parte['lider_colaborador_id'] == eu;

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(children: [
        StatusChip(atd['status'] as String?, _statusAtendimento),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            abertos.isEmpty
                ? 'Ninguém no serviço agora'
                : abertos.map((p) => '${banco.nomeColaborador(p['colaborador_id'])} ${horaDe(p['entrada_em'])}').join(', '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (aberto && souLider && item.isNotEmpty)
          IconButton(
            tooltip: 'Pessoas',
            onPressed: () => _pessoas(context, Map<String, dynamic>.from(item), '${parte['id']}'),
            icon: const Icon(Icons.group_outlined),
          ),
        if (aberto && meu != null)
          TextButton(onPressed: () => AcoesAtendimento.checkout(meu), child: const Text('Sair')),
        if (aberto && meu == null && item.isNotEmpty)
          TextButton(
            onPressed: () => entrarNoServico(context, Map<String, dynamic>.from(item), abrir: false),
            child: const Text('Entrar'),
          ),
      ]),
    );
  }
}

class _Relato extends StatelessWidget {
  const _Relato({
    required this.controles,
    required this.habilitado,
    required this.sujo,
    required this.aoMudar,
    required this.aoSalvar,
  });

  final Map<String, TextEditingController> controles;
  final bool habilitado;
  final bool sujo;
  final VoidCallback aoMudar;
  final Future<void> Function() aoSalvar;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final e in _camposRelato.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: controles[e.key],
            enabled: habilitado,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: e.value, alignLabelWithHint: true),
            onChanged: (_) => aoMudar(),
          ),
        ),
      if (habilitado)
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: sujo ? aoSalvar : null,
            icon: const Icon(Icons.save_outlined),
            label: Text(sujo ? 'Salvar relato' : 'Relato salvo'),
          ),
        ),
      const SizedBox(height: 8),
      const Text('O relato também é salvo ao concluir e ao sair desta tela.',
          style: TextStyle(color: Cores.neutro, fontSize: 12)),
    ]);
  }
}
