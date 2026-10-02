import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cadastros/campos.dart';
import '../cadastros/definicoes.dart';
import '../servicos/etiquetas_pdf.dart';
import '../widgets/margem.dart';

/// Etiquetas QR dos equipamentos em PDF A4, para papel adesivo.
/// O QR leva o qr_token do equipamento; o app lê e acha o equipamento na hora.
class EtiquetasTela extends StatefulWidget {
  const EtiquetasTela({super.key});

  @override
  State<EtiquetasTela> createState() => _EtiquetasTelaState();
}

class _EtiquetasTelaState extends State<EtiquetasTela> {
  static const _campoCliente = CampoDef('cliente_id', 'Cliente',
      tipo: TipoCampo.lookup, lookup: Lookup(tabela: 'clientes'));
  static const _campoLocal = CampoDef('local_id', 'Local',
      tipo: TipoCampo.lookup,
      lookup: Lookup(
          tabela: 'locais',
          colunaDetalhe: 'cidade',
          colunaFiltro: 'cliente_id',
          campoPai: 'cliente_id'));

  final _pular = TextEditingController(text: '0');
  String? _clienteId;
  String? _localId;
  ModeloEtiqueta _modelo = modelosEtiqueta.first;
  bool _contorno = false;
  bool _gerando = false;
  int? _quantidade;

  @override
  void initState() {
    super.initState();
    _contar();
  }

  @override
  void dispose() {
    _pular.dispose();
    super.dispose();
  }

  PostgrestFilterBuilder<PostgrestList> _consulta(String colunas) {
    var q = Supabase.instance.client
        .from('equipamentos')
        .select(colunas)
        .isFilter('excluido_em', null)
        .eq('situacao', 'ativo');
    if (_clienteId != null) q = q.eq('cliente_id', _clienteId!);
    if (_localId != null) q = q.eq('local_id', _localId!);
    return q;
  }

  Future<void> _contar() async {
    setState(() => _quantidade = null);
    try {
      final r = await _consulta('id').limit(1).count(CountOption.exact);
      if (mounted) setState(() => _quantidade = r.count);
    } catch (_) {
      if (mounted) setState(() => _quantidade = -1);
    }
  }

  Future<String> _rodape() async {
    final id = Sessao.atual?.empresaId;
    if (id == null) return '';
    final e = await Supabase.instance.client
        .from('empresas')
        .select('razao_social, nome_fantasia, telefone')
        .eq('id', id)
        .single();
    final nome = (e['nome_fantasia'] ?? e['razao_social'] ?? '') as String;
    final tel = formatarValor(e['telefone'], TipoCampo.telefone);
    return tel.isEmpty ? 'Manutenção: $nome' : 'Manutenção: $nome · $tel';
  }

  /// [baixar] = true salva o arquivo; false abre a impressão do navegador.
  Future<void> _gerar({required bool baixar}) async {
    setState(() => _gerando = true);
    try {
      final linhas = await _consulta('codigo, descricao, qr_token, clientes(nome), locais(nome)')
          .order('codigo', ascending: true)
          .limit(3000);
      if (linhas.isEmpty) {
        _avisar('Nenhum equipamento ativo com esses filtros.', erro: true);
        return;
      }
      final etiquetas = [
        for (final l in linhas)
          Etiqueta(
            codigo: (l['codigo'] ?? '') as String,
            qrToken: (l['qr_token'] ?? '') as String,
            descricao: l['descricao'] as String?,
            cliente: (l['clientes'] as Map?)?['nome'] as String?,
            local: (l['locais'] as Map?)?['nome'] as String?,
          ),
      ];
      final bytes = await gerarPdfEtiquetas(
        etiquetas: etiquetas,
        modelo: _modelo,
        rodape: await _rodape(),
        pular: int.tryParse(_pular.text.trim()) ?? 0,
        contorno: _contorno,
      );
      if (baixar) {
        await Printing.sharePdf(bytes: bytes, filename: 'etiquetas-qr.pdf');
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'etiquetas-qr');
      }
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  void _avisar(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: erro ? Cores.erro : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final folhas = (_quantidade == null || _quantidade! <= 0)
        ? null
        : ((_quantidade! + (int.tryParse(_pular.text) ?? 0)) / _modelo.porFolha).ceil();
    return SingleChildScrollView(
      padding: margemDaTela(context),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                IconButton(
                  onPressed: () => context.canPop() ? context.pop() : context.go('/c/equipamentos'),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 4),
                Text('Etiquetas QR',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              const Text(
                'Gera um PDF A4 para papel adesivo com o QR, o código, a descrição, o cliente e o '
                'local de cada equipamento ativo. Use etiqueta resistente (poliéster ou vinil) '
                'em equipamentos externos.',
                style: TextStyle(color: Cores.neutro),
              ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CampoLookup(
                        campo: _campoCliente,
                        valor: _clienteId,
                        valorPai: null,
                        rotuloPai: null,
                        habilitado: !_gerando,
                        aoMudar: (v) {
                          setState(() {
                            _clienteId = v;
                            _localId = null;
                          });
                          _contar();
                        },
                      ),
                      const SizedBox(height: 12),
                      CampoLookup(
                        campo: _campoLocal,
                        valor: _localId,
                        valorPai: _clienteId,
                        rotuloPai: 'Cliente',
                        habilitado: !_gerando,
                        aoMudar: (v) {
                          setState(() => _localId = v);
                          _contar();
                        },
                      ),
                      const SizedBox(height: 4),
                      const Text('Sem cliente escolhido, saem todos os equipamentos ativos.',
                          style: TextStyle(color: Cores.neutro, fontSize: 12)),
                      const SizedBox(height: 16),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Papel',
                          helperText: 'Confira as medidas na embalagem das etiquetas',
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<ModeloEtiqueta>(
                            value: _modelo,
                            isDense: true,
                            isExpanded: true,
                            items: [
                              for (final m in modelosEtiqueta)
                                DropdownMenuItem(value: m, child: Text(m.nome)),
                            ],
                            onChanged: _gerando
                                ? null
                                : (m) => setState(() => _modelo = m ?? _modelo),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 260,
                        child: TextField(
                          controller: _pular,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Pular etiquetas já usadas',
                            helperText: 'Para aproveitar uma folha começada',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _contorno,
                        onChanged: _gerando ? null : (v) => setState(() => _contorno = v ?? false),
                        title: const Text('Desenhar contorno'),
                        subtitle: const Text('Para testar em folha comum antes de usar o papel adesivo'),
                      ),
                      const Divider(height: 24),
                      Text(
                        _quantidade == null
                            ? 'Contando…'
                            : _quantidade! < 0
                                ? 'Não foi possível contar os equipamentos.'
                                : '$_quantidade equipamento(s)${folhas == null ? '' : ' · $folhas folha(s)'}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _gerando ? null : () => _gerar(baixar: true),
                            icon: const Icon(Icons.download),
                            label: const Text('Baixar PDF'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _gerando ? null : () => _gerar(baixar: false),
                            icon: _gerando
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.print),
                            label: const Text('Imprimir'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
