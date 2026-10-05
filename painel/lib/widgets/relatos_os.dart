import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/arquivo_web.dart';
import '../servicos/relatos.dart';
import '../servicos/status.dart';
import 'itens_os.dart' show dinheiro, numeroBr;
import 'status_chip.dart';

/// Relatos por áudio da OS (guia 15): o que a IA entendeu de cada um. No
/// painel dá para enviar um áudio de teste; no app, quem grava é o técnico, e
/// a revisão (aceitar e levar para a OS) é no app (guia 17).
class RelatosDaOs extends StatefulWidget {
  const RelatosDaOs({super.key, required this.osId, required this.podeEnviar, this.versao = 0});

  final String osId;
  final bool podeEnviar;
  final int versao;

  @override
  State<RelatosDaOs> createState() => _RelatosDaOsState();
}

class _RelatosDaOsState extends State<RelatosDaOs> {
  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;
  String? _etapa; // "Enviando..." / "Transcrevendo e organizando..."
  List<Map<String, dynamic>> _audios = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(RelatosDaOs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.versao != widget.versao) _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await Supabase.instance.client
          .from('audios')
          .select('id, caminho, status, erro, tentativas, duracao_s, gravado_em, transcricao, transcricao_provedor, '
              'organizacao_modelo, resultado, custo_estimado, ms_total, processado_em, revisao, revisado_em, '
              'colaboradores(nome)')
          .eq('os_id', widget.osId)
          .isFilter('excluido_em', null)
          .order('gravado_em', ascending: false);
      if (!mounted) return;
      setState(() {
        _audios = r;
        _erro = null;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _aviso(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));
  }

  Future<void> _enviar() async {
    final arquivo = await escolherArquivo(aceitar: 'audio/*,.m4a,.mp3,.wav,.ogg,.opus,.mp4');
    if (arquivo == null || !mounted) return;
    if (arquivo.bytes.length > 15 * 1024 * 1024) {
      _aviso('Arquivo grande demais (máximo 15 MB).', erro: true);
      return;
    }
    setState(() {
      _ocupado = true;
      _etapa = 'Enviando e processando (uns 10 segundos)...';
    });
    try {
      await enviarRelato(osId: widget.osId, arquivo: arquivo);
      _aviso('Relato processado.');
    } catch (e) {
      _aviso(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _ocupado = false;
          _etapa = null;
        });
      }
      await _carregar();
    }
  }

  Future<void> _processar(String id) async {
    setState(() {
      _ocupado = true;
      _etapa = 'Processando de novo...';
    });
    try {
      await processarRelato(id);
      _aviso('Relato processado.');
    } catch (e) {
      _aviso(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _ocupado = false;
          _etapa = null;
        });
      }
      await _carregar();
    }
  }

  Future<void> _ouvir(String caminho) async {
    try {
      abrirEmNovaAba(await linkDoAudio(caminho));
    } catch (e) {
      _aviso(mensagemDeErro(e), erro: true);
    }
  }

  Widget _rotulo(String r, String? v) => (v == null || v.trim().isEmpty)
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$r: ', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: v),
          ])),
        );

  Widget _resultado(Map<String, dynamic> a) {
    final r = (a['resultado'] as Map?)?.cast<String, dynamic>() ?? const {};
    // O que a IA devolveu pode vir torto (texto no lugar de objeto): não quebra a tela.
    Map mapa(Object? v) => v is Map ? v : const {};
    List lista(Object? v) => v is List ? v : const [];
    final campos = mapa(r['campos']);
    final itens = lista(r['itens']).whereType<Map>().toList();
    final eq = mapa(r['equipamento']);
    final mo = mapa(r['mao_de_obra']);
    final cobranca = mapa(r['cobranca']);
    final duvidas = lista(r['duvidas']).map((x) => '$x').where((x) => x.trim().isNotEmpty).toList();
    final meds = lista(r['medicoes']).whereType<Map>().toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _rotulo('Problema', campos['problema_identificado']?.toString()),
      _rotulo('Causa', campos['causa']?.toString()),
      _rotulo('Solução', campos['solucao']?.toString()),
      _rotulo('Observações', campos['observacoes']?.toString()),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Equipamento:', style: TextStyle(fontWeight: FontWeight.w700)),
        StatusChip(eq['tipo']?.toString(), decisoesEquipamento, compacto: true),
        Text('${eq['texto'] ?? ''}'),
      ]),
      if ((r['local'] ?? '').toString().isNotEmpty)
        Text('Local falado: ${r['local']}${(r['equipamento_falado'] ?? '').toString().isNotEmpty ? ' · ${r['equipamento_falado']}' : ''}',
            style: const TextStyle(color: Cores.neutro)),
      const SizedBox(height: 8),
      const Text('Peças', style: TextStyle(fontWeight: FontWeight.w700)),
      if (itens.isEmpty) const Text('Nenhuma peça falada.', style: TextStyle(color: Cores.neutro)),
      for (final i in itens)
        Builder(builder: (_) {
          final cands = lista(i['candidatos']).whereType<Map>().toList();
          return Text('• ${i['falado']} · ${numeroBr(i['quantidade'])} ${i['unidade'] ?? ''}  →  ${cands.isEmpty ? 'sem correspondente no catálogo' : cands.map((c) => '${c['codigo'] ?? ''} ${c['descricao']} (${((num.tryParse('${c['nota']}') ?? 0) * 100).round()}%)').join('; ')}');
        }),
      const SizedBox(height: 4),
      Text('Mão de obra: ${numeroBr(mo['quantidade'] ?? 0)}${(mo['motivo'] ?? '').toString().isNotEmpty ? ' (${mo['motivo']})' : ''}'
          '${cobranca['cobrar'] == false ? ' · sem cobrança' : ''}'
          '${cobranca['valor_falado'] != null ? ' · valor falado: ${dinheiro(cobranca['valor_falado'])}' : ''}'),
      if (meds.isNotEmpty)
        Text('Medições: ${meds.map((m) => '${m['nome']}: ${numeroBr(m['valor'])} ${m['unidade'] ?? ''}').join('; ')}'),
      if (r['fluido'] is Map)
        Text('Fluido: ${(r['fluido'] as Map)['tipo'] ?? ''} ${numeroBr((r['fluido'] as Map)['adicionado_kg'] ?? 0)} kg'),
      if (duvidas.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Dúvidas da IA: ${duvidas.join(' · ')}', style: const TextStyle(color: Cores.alerta)),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('O técnico grava o relato no app e a IA organiza. Aqui dá para ver o que ela entendeu.',
            style: TextStyle(color: Cores.neutro)),
        if (widget.podeEnviar)
          OutlinedButton.icon(
            onPressed: _ocupado ? null : _enviar,
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Enviar áudio de teste'),
          ),
      ]),
      if (_etapa != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(_etapa!),
          ]),
        ),
      if (_carregando) const LinearProgressIndicator(minHeight: 2),
      if (_erro != null) Text(_erro!, style: const TextStyle(color: Cores.erro)),
      if (!_carregando && _audios.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Nenhum relato por áudio.', style: TextStyle(color: Cores.neutro)),
        ),
      for (final a in _audios)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: a == _audios.first,
          title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(dataHoraBr(a['gravado_em'])),
            StatusChip(a['status'] as String?, statusRelato, compacto: true),
          ]),
          subtitle: Text([
            (a['colaboradores'] as Map?)?['nome'] ?? 'Painel',
            if (a['duracao_s'] != null) '${numeroBr(a['duracao_s'])} s de áudio',
            if (a['transcricao_provedor'] != null) '${a['transcricao_provedor']} + ${a['organizacao_modelo'] ?? ''}',
            if (a['ms_total'] != null) '${((a['ms_total'] as num) / 1000).toStringAsFixed(1)} s',
            if (a['custo_estimado'] != null) 'US\$ ${(num.tryParse('${a['custo_estimado']}') ?? 0).toStringAsFixed(4)}',
          ].join(' · ')),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (a['status'] == 'erro')
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${a['erro'] ?? 'Erro'} (tentativa ${a['tentativas']})', style: const TextStyle(color: Cores.erro)),
              ),
            Wrap(spacing: 8, children: [
              TextButton.icon(
                onPressed: () => _ouvir('${a['caminho']}'),
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: const Text('Ouvir'),
              ),
              if (widget.podeEnviar && (a['status'] == 'erro' || a['status'] == 'enviado' || a['status'] == 'processando'))
                TextButton.icon(
                  onPressed: _ocupado ? null : () => _processar('${a['id']}'),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Processar de novo'),
                ),
            ]),
            if ((a['transcricao'] ?? '').toString().isNotEmpty) ...[
              const Text('Transcrição', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('${a['transcricao']}', style: const TextStyle(fontStyle: FontStyle.italic)),
              const SizedBox(height: 8),
            ],
            if (a['revisao'] is Map)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Revisado no app em ${dataHoraBr(a['revisado_em'])}: '
                  '${(a['revisao'] as Map)['aceitos_sem_editar'] ?? 0} de ${(a['revisao'] as Map)['total'] ?? 0} '
                  'proposta(s) da IA aceita(s) sem mudar.',
                  style: const TextStyle(color: Cores.indigo700, fontWeight: FontWeight.w600),
                ),
              ),
            if (a['resultado'] is Map) _resultado(a),
          ],
        ),
    ]);
  }
}
