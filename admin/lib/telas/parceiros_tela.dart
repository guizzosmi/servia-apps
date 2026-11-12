import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:servia_comum/servia_comum.dart';

import '../api.dart';
import '../widgets/comuns.dart';

/// Parceiros que indicam clientes (guia 89): código próprio, comissão, link da página
/// do parceiro e o "Paguei" das comissões liberadas (o Pix você faz no banco).
class ParceirosTela extends StatefulWidget {
  const ParceirosTela({super.key});

  @override
  State<ParceirosTela> createState() => _ParceirosTelaState();
}

class _ParceirosTelaState extends State<ParceirosTela> {
  late Future<List<Map<String, dynamic>>> _dados = rpcLista('admin_parceiros');

  void _recarregar() => setState(() => _dados = rpcLista('admin_parceiros'));

  Future<void> _editar([Map<String, dynamic>? p]) async {
    final salvou = await showDialog<bool>(context: context, builder: (_) => _DialogoParceiro(parceiro: p));
    if (salvou == true) _recarregar();
  }

  Future<void> _copiar(String texto, String aviso) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (mounted) avisar(context, aviso);
  }

  Future<void> _pagar(Map<String, dynamic> p) async {
    final data = TextEditingController(text: dataBr(DateTime.now().toIso8601String()));
    final obs = TextEditingController();
    final ok = await dialogoForm(context, titulo: 'Paguei ${moeda(p['a_pagar'])} a ${p['nome']}?', confirmar: 'Marcar como pago', campos: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: Text('Chave Pix: ${p['chave_pix'] ?? '(sem chave cadastrada)'}')),
          if (p['chave_pix'] != null)
            IconButton(
              tooltip: 'Copiar a chave',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () => Clipboard.setData(ClipboardData(text: '${p['chave_pix']}')),
            ),
        ]),
      ),
      campoTexto(data, 'Pago em (dd/mm/aaaa)'),
      campoTexto(obs, 'Observação (ex.: id do Pix)'),
    ]);
    if (!ok) return;
    try {
      final r = await rpcMapa('admin_comissoes_pagar', {
        'p': {'parceiro_id': p['id'], 'pago_em': dataIso(data.text), 'obs': obs.text.trim()}
      });
      if (mounted) avisar(context, '${r['itens']} comissão(ões) marcada(s) como paga(s): ${moeda(r['total'])}.');
      if (mounted) _recarregar();
    } catch (e) {
      if (mounted) avisarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Carregar<List<Map<String, dynamic>>>(
        futuro: _dados,
        recarregar: _recarregar,
        construir: (parceiros) => ListView(padding: const EdgeInsets.all(24), children: [
          Row(children: [
            Expanded(child: Text('Parceiros', style: Theme.of(context).textTheme.headlineSmall)),
            FilledButton.icon(onPressed: () => _editar(), icon: const Icon(Icons.add), label: const Text('Novo parceiro')),
          ]),
          const SizedBox(height: 4),
          const Text('Distribuidores, engenheiros que assinam PMOC e outros que indicam clientes. A comissão é calculada '
              'sozinha sobre o que o cliente indicado paga de mensalidade, nos meses combinados. A do pagamento anual '
              'só libera depois do prazo de arrependimento.',
              style: TextStyle(color: Cores.neutro)),
          const SizedBox(height: 16),
          if (parceiros.isEmpty) const Text('Nenhum parceiro ainda.'),
          for (final p in parceiros)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Text('${p['nome']} · ${p['codigo'] ?? ''}',
                          style: TextStyle(fontWeight: FontWeight.w700, color: p['ativo'] == true ? Cores.tinta : Cores.neutro)),
                    ),
                    ChipSituacao(p['ativo'] == true ? 'ativa' : 'cancelada'),
                    IconButton(onPressed: () => _editar(p), icon: const Icon(Icons.edit_outlined), tooltip: 'Editar'),
                  ]),
                  Text('${numero(p['comissao_pct'])}% por ${p['comissao_meses']} meses · ${p['indicados']} indicado(s), '
                      '${p['clientes']} pagante(s)${p['chave_pix'] != null ? ' · Pix ${p['chave_pix']}' : ''}',
                      style: const TextStyle(color: Cores.neutro)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 16, runSpacing: 4, children: [
                    Text('A pagar: ${moeda(p['a_pagar'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('A liberar: ${moeda(p['a_liberar'])}'),
                    Text('Já pago: ${moeda(p['pago'])}'),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.link),
                      label: const Text('Copiar link de indicação'),
                      onPressed: () => _copiar('${p['link_indicacao']}', 'Link de indicação copiado.'),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.badge_outlined),
                      label: const Text('Copiar página do parceiro'),
                      onPressed: () => _copiar('${p['link_pagina']}',
                          'Página do parceiro copiada. É privada: mande só para ele.'),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Paguei'),
                      onPressed: numero(p['a_pagar']) > 0 ? () => _pagar(p) : null,
                    ),
                  ]),
                ]),
              ),
            ),
        ]),
      );
}

class _DialogoParceiro extends StatefulWidget {
  const _DialogoParceiro({required this.parceiro});

  final Map<String, dynamic>? parceiro;

  @override
  State<_DialogoParceiro> createState() => _DialogoParceiroState();
}

class _DialogoParceiroState extends State<_DialogoParceiro> {
  late final p = widget.parceiro ?? const <String, dynamic>{};
  late final _nome = TextEditingController(text: '${p['nome'] ?? ''}');
  late final _documento = TextEditingController(text: '${p['documento'] ?? ''}');
  late final _email = TextEditingController(text: '${p['email'] ?? ''}');
  late final _telefone = TextEditingController(text: '${p['telefone'] ?? ''}');
  late final _pix = TextEditingController(text: '${p['chave_pix'] ?? ''}');
  late final _codigo = TextEditingController(text: '${p['codigo'] ?? ''}');
  late final _pct = TextEditingController(text: p['comissao_pct'] == null ? '10' : '${numero(p['comissao_pct'])}');
  late final _meses = TextEditingController(text: '${p['comissao_meses'] ?? 12}');
  late final _obs = TextEditingController(text: '${p['observacao'] ?? ''}');
  late bool _ativo = p['ativo'] != false;
  bool _salvando = false;

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      await rpcLista('admin_parceiro_salvar', {
        'p': {
          'id': p['id'],
          'nome': _nome.text.trim(),
          'documento': _documento.text.trim(),
          'email': _email.text.trim(),
          'telefone': _telefone.text.trim(),
          'chave_pix': _pix.text.trim(),
          'codigo': _codigo.text.trim(),
          'comissao_pct': numero(_pct.text),
          'comissao_meses': numero(_meses.text).toInt(),
          'observacao': _obs.text.trim(),
          'ativo': _ativo,
        }
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) avisarErro(context, e);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.parceiro == null ? 'Novo parceiro' : '${p['nome']}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              campoTexto(_nome, 'Nome (pessoa ou empresa)'),
              campoTexto(_documento, 'CPF ou CNPJ', ajuda: 'Indicação de quem tem o mesmo documento não vale.'),
              campoTexto(_email, 'E-mail'),
              campoTexto(_telefone, 'WhatsApp'),
              campoTexto(_pix, 'Chave Pix (para pagar a comissão)'),
              campoTexto(_codigo, 'Código de indicação',
                  ajuda: 'Ex.: REFRIPECAS (4 a 30 letras, números ou hífen). Vazio = o sistema cria um.'),
              Row(children: [
                Expanded(child: campoTexto(_pct, 'Comissão (%)', teclado: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: campoTexto(_meses, 'Durante quantos meses', teclado: TextInputType.number)),
              ]),
              campoTexto(_obs, 'Observação'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _ativo,
                onChanged: (v) => setState(() => _ativo = v),
                title: const Text('Ativo'),
                subtitle: const Text('Desligado: o código para de valer para clientes novos. '
                    'As comissões de quem já indicou continuam.'),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: _salvando ? null : _salvar, child: const Text('Salvar')),
        ],
      );
}
