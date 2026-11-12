import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/arquivo_web.dart';
import '../servicos/notas.dart';

/// Guia 114: Configurações › Dados da empresa. O nome, o contato, o endereço e a
/// logo que saem no cabeçalho dos PDFs (OS, orçamento, PMOC), no portal do
/// cliente e nas mensagens. Só o gestor (ou admin) muda; o CNPJ não muda aqui.
class CartaoDadosEmpresa extends StatefulWidget {
  const CartaoDadosEmpresa({super.key});

  @override
  State<CartaoDadosEmpresa> createState() => _CartaoDadosEmpresaState();
}

class _CartaoDadosEmpresaState extends State<CartaoDadosEmpresa> {
  static const _campos = [
    'nome_fantasia', 'razao_social', 'telefone', 'email', 'cep', 'logradouro', 'numero', 'complemento', 'bairro',
    'cidade', 'uf',
  ];

  final _c = <String, TextEditingController>{};
  Map<String, dynamic>? _d;
  String? _erro;
  bool _aberto = false;
  bool _salvando = false;
  bool _sujo = false;
  bool _buscandoCep = false;
  Uint8List? _logo;

  SupabaseClient get _db => Supabase.instance.client;
  bool get _gestor => Sessao.atual?.tem(Papel.gestor) ?? false;

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

  Future<void> _carregar() async {
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('empresa_dados') as Map);
      _preencher(r);
      await _baixarLogo(r['logo_caminho']);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    }
  }

  void _preencher(Map<String, dynamic> r) {
    if (!mounted) return;
    setState(() {
      _d = r;
      _erro = null;
      _sujo = false;
      for (final k in _campos) {
        _t(k).text = '${r[k] ?? ''}';
      }
    });
  }

  Future<void> _baixarLogo(Object? caminho) async {
    Uint8List? bytes;
    if (caminho is String && caminho.isNotEmpty) {
      try {
        bytes = await _db.storage.from('logos').download(caminho);
      } catch (_) {
        bytes = null;
      }
    }
    if (mounted) setState(() => _logo = bytes);
  }

  void _avisar(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));
  }

  /// Grava (só os campos ou a logo) e, se a empresa emite nota pela Focus, manda os dados novos para lá.
  Future<Map<String, dynamic>> _gravar(Map<String, dynamic> p) async {
    final r = Map<String, dynamic>.from(await _db.rpc('empresa_salvar', params: {'p': p}) as Map);
    final antiga = r['logo_antiga'];
    if (antiga is String && antiga.isNotEmpty) {
      try {
        await _db.storage.from('logos').remove([antiga]);
      } catch (_) {
        // O arquivo antigo fica sem uso; não atrapalha.
      }
    }
    if (r['mudou'] == true && r['notas_na_focus'] == true && !p.containsKey('logo_caminho')) {
      try {
        await funcaoNotas({'acao': 'empresa'});
      } catch (e) {
        _avisar('Salvo aqui, mas não deu para atualizar na Focus agora: ${mensagemDeErro(e)}', erro: true);
      }
    }
    return r;
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      final r = await _gravar({for (final k in _campos) k: _t(k).text.trim()});
      _preencher(r);
      _avisar(r['mudou'] == true ? 'Dados da empresa salvos. Os próximos PDFs já saem assim.' : 'Nada mudou.');
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _trocarLogo() async {
    final arq = await escolherArquivo(aceitar: 'image/png,image/jpeg');
    if (arq == null || !mounted) return;
    if (arq.tipo != 'image/png' && arq.tipo != 'image/jpeg') {
      _avisar('Escolha uma imagem PNG ou JPG.', erro: true);
      return;
    }
    if (arq.bytes.length > 10 * 1024 * 1024) {
      _avisar('Imagem grande demais (mais de 10 MB).', erro: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      final png = await reduzirImagem(arq.bytes, arq.tipo);
      if (png == null) {
        _avisar('Não deu para abrir esta imagem. Tente outra (PNG ou JPG).', erro: true);
        return;
      }
      if (png.length > 1024 * 1024) {
        _avisar('A logo ficou com mais de 1 MB mesmo reduzida. Tente uma imagem mais simples.', erro: true);
        return;
      }
      final s = Sessao.atual!;
      final caminho = '${s.contaId}/${s.empresaId}/logo/logo-${novoUuid().substring(0, 8)}.png';
      await _db.storage
          .from('logos')
          .uploadBinary(caminho, png, fileOptions: const FileOptions(contentType: 'image/png'));
      final r = await _gravar({'logo_caminho': caminho});
      if (!mounted) return;
      setState(() {
        _d = r;
        _logo = png;
      });
      _avisar('Logo salva. Ela sai no cabeçalho dos próximos PDFs.');
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _tirarLogo() async {
    setState(() => _salvando = true);
    try {
      final r = await _gravar({'logo_caminho': ''});
      if (!mounted) return;
      setState(() {
        _d = r;
        _logo = null;
      });
      _avisar('Logo retirada dos PDFs.');
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _buscarCep() async {
    final cep = _t('cep').text.replaceAll(RegExp(r'\D'), '');
    if (cep.length != 8) {
      _avisar('Digite o CEP com 8 números.', erro: true);
      return;
    }
    setState(() => _buscandoCep = true);
    try {
      final r = await funcaoNotas({'acao': 'cep', 'cep': cep});
      if (!mounted) return;
      setState(() {
        for (final k in ['logradouro', 'bairro', 'cidade', 'uf']) {
          if ((r[k] ?? '') != '') _t(k).text = '${r[k]}';
        }
        _sujo = true;
      });
    } catch (e) {
      _avisar('Não achei o CEP (${mensagemDeErro(e)}). Preencha o endereço à mão.', erro: true);
    } finally {
      if (mounted) setState(() => _buscandoCep = false);
    }
  }

  Widget _campo(String k, String rotulo, {double largura = 320, TextInputType? teclado, Widget? sufixo}) => SizedBox(
        width: largura,
        child: TextField(
          controller: _t(k),
          enabled: _gestor && !_salvando,
          keyboardType: teclado,
          onChanged: (_) {
            if (!_sujo) setState(() => _sujo = true);
          },
          decoration: InputDecoration(labelText: rotulo, isDense: true, suffixIcon: sufixo),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => setState(() => _aberto = !_aberto),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Dados da empresa', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    d == null
                        ? (_erro ?? 'Carregando...')
                        : [d['nome_fantasia'] ?? d['razao_social'], d['endereco']]
                            .where((x) => x != null && '$x'.isNotEmpty)
                            .join(' · '),
                    style: TextStyle(color: _erro != null && d == null ? Cores.erro : Cores.neutro),
                  ),
                ]),
              ),
              Icon(_aberto ? Icons.expand_less : Icons.expand_more),
            ]),
          ),
          if (_aberto && d != null) ...[
            const SizedBox(height: 8),
            const Text('Saem no cabeçalho dos PDFs (OS, orçamento, PMOC), no portal do cliente e nas mensagens.',
                style: TextStyle(color: Cores.neutro)),
            const SizedBox(height: 16),
            // ---------- Logo
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                width: 140,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(border: Border.all(color: Cores.linha), borderRadius: BorderRadius.circular(8)),
                child: _logo == null
                    ? const Text('Sem logo', style: TextStyle(color: Cores.neutro))
                    : Padding(padding: const EdgeInsets.all(6), child: Image.memory(_logo!, fit: BoxFit.contain)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: _gestor && !_salvando ? _trocarLogo : null,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(_logo == null ? 'Enviar a logo' : 'Trocar a logo'),
                  ),
                  if (_logo != null)
                    TextButton(onPressed: _gestor && !_salvando ? _tirarLogo : null, child: const Text('Tirar a logo')),
                  const Text('PNG (de preferência com fundo transparente) ou JPG. O painel reduz o tamanho sozinho.',
                      style: TextStyle(color: Cores.neutro, fontSize: 12)),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            // ---------- Nome e contato
            Wrap(spacing: 12, runSpacing: 12, children: [
              _campo('nome_fantasia', 'Nome fantasia (o nome grande no PDF)'),
              _campo('razao_social', 'Razão social'),
              SizedBox(
                width: 200,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'CNPJ/CPF', isDense: true, enabled: false),
                  child: Text('${d['documento'] ?? '(não informado)'}'),
                ),
              ),
              _campo('telefone', 'Telefone (com DDD)', largura: 200, teclado: TextInputType.phone),
              _campo('email', 'E-mail', teclado: TextInputType.emailAddress),
            ]),
            const SizedBox(height: 16),
            // ---------- Endereço
            Wrap(spacing: 12, runSpacing: 12, children: [
              _campo('cep', 'CEP',
                  largura: 160,
                  teclado: TextInputType.number,
                  sufixo: _buscandoCep
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(
                          tooltip: 'Buscar o endereço pelo CEP',
                          icon: const Icon(Icons.search),
                          onPressed: _gestor && !_salvando ? _buscarCep : null,
                        )),
              _campo('logradouro', 'Rua', largura: 360),
              _campo('numero', 'Número', largura: 100),
              _campo('complemento', 'Complemento', largura: 200),
              _campo('bairro', 'Bairro', largura: 240),
              _campo('cidade', 'Cidade', largura: 240),
              _campo('uf', 'UF', largura: 70),
            ]),
            const SizedBox(height: 8),
            const Text('O CNPJ não muda por aqui: ele vale nas notas fiscais. Para trocar, fale com o suporte.',
                style: TextStyle(color: Cores.neutro, fontSize: 12)),
            const SizedBox(height: 16),
            if (_gestor)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _sujo && !_salvando ? _salvar : null,
                  child: Text(_salvando ? 'Salvando...' : 'Salvar dados da empresa'),
                ),
              )
            else
              const Text('Só o gestor muda os dados da empresa.', style: TextStyle(color: Cores.neutro)),
          ],
        ]),
      ),
    );
  }
}
