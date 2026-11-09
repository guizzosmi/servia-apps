import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/comercial.dart';

/// Anotar rápido (guia 97): o contato novo entra no funil com poucos campos e a próxima tarefa
/// já marcada. Antes de gravar mostra quem já existe com o mesmo WhatsApp, e-mail ou nome
/// (cliente, contato ou oportunidade) para não duplicar. Devolve o id da oportunidade (nova ou a
/// que já existia) ou null se desistiu.
Future<String?> anotarOportunidade(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _DialogoCaptura());

class _DialogoCaptura extends StatefulWidget {
  const _DialogoCaptura();

  @override
  State<_DialogoCaptura> createState() => _DialogoCapturaState();
}

class _DialogoCapturaState extends State<_DialogoCaptura> {
  final _nome = TextEditingController();
  final _empresa = TextEditingController();
  final _telefone = TextEditingController();
  final _email = TextEditingController();
  final _titulo = TextEditingController();
  final _valor = TextEditingController();
  final _mensal = TextEditingController();
  String _origem = 'whatsapp';
  bool _salvando = false;
  String? _erro;
  Map<String, dynamic>? _parecidos;

  @override
  void dispose() {
    for (final c in [_nome, _empresa, _telefone, _email, _titulo, _valor, _mensal]) {
      c.dispose();
    }
    super.dispose();
  }

  num _numero(TextEditingController c) => num.tryParse(c.text.trim().replaceAll('.', '').replaceAll(',', '.')) ?? 0;

  /// Procura quem já existe (ao sair do WhatsApp, do e-mail ou da empresa).
  Future<void> _procurar() async {
    final tel = _telefone.text.replaceAll(RegExp(r'\D'), '');
    final email = _email.text.trim();
    final nome = _empresa.text.trim().isNotEmpty ? _empresa.text.trim() : _nome.text.trim();
    if (tel.length < 8 && !email.contains('@') && nome.length < 4) return;
    try {
      final r = await Supabase.instance.client.rpc('comercial_duplicados', params: {
        'p': {
          'telefone': tel.length >= 8 ? tel : null,
          'email': email.contains('@') ? email : null,
          'nome': nome.length >= 4 ? nome : null,
        }
      });
      if (!mounted || r is! Map) return;
      final m = Map<String, dynamic>.from(r);
      final vazio = ['clientes', 'contatos', 'oportunidades'].every((k) => (m[k] as List? ?? const []).isEmpty);
      setState(() => _parecidos = vazio ? null : m);
    } catch (_) {
      // a busca é só um aviso: sem ela, o banco ainda evita duplicar pelo telefone
    }
  }

  Future<void> _salvar({bool forcar = false}) async {
    if (_nome.text.trim().isEmpty && _empresa.text.trim().isEmpty) {
      setState(() => _erro = 'Diga o nome da pessoa ou da empresa.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final r = await acaoComercial({
        'acao': 'captura_rapida',
        'nome': _nome.text.trim(),
        'empresa': _empresa.text.trim(),
        'telefone': _telefone.text.trim(),
        'email': _email.text.trim(),
        'titulo': _titulo.text.trim(),
        'valor': _numero(_valor),
        'valor_mensal': _numero(_mensal),
        'origem': _origem,
        'forcar': forcar,
      });
      if (!mounted) return;
      final aviso = r['duplicada'] == true
          ? '${r['aviso']}'
          : (r['cliente_existente'] == true
              ? '${r['codigo']} criada e ligada ao cliente que já existia. Próxima tarefa: amanhã às 9h.'
              : '${r['codigo']} criada. Próxima tarefa: amanhã às 9h.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(aviso)));
      Navigator.of(context).pop(r['oportunidade_id'] as String?);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _campo(TextEditingController c, String rotulo, {TextInputType? teclado, bool procurar = false, String? dica}) => Focus(
        onFocusChange: procurar
            ? (f) {
                if (!f) _procurar();
              }
            : null,
        child: TextField(
          controller: c,
          keyboardType: teclado,
          decoration: InputDecoration(labelText: rotulo, hintText: dica),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = _parecidos;
    return AlertDialog(
      title: const Text('Anotar oportunidade'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Só o essencial: o resto você completa depois. A próxima tarefa já fica marcada.',
                style: TextStyle(color: Cores.neutro)),
            Row(children: [
              Expanded(child: _campo(_nome, 'Pessoa')),
              const SizedBox(width: 12),
              Expanded(child: _campo(_empresa, 'Empresa', procurar: true)),
            ]),
            Row(children: [
              Expanded(child: _campo(_telefone, 'WhatsApp', teclado: TextInputType.phone, procurar: true)),
              const SizedBox(width: 12),
              Expanded(child: _campo(_email, 'E-mail', teclado: TextInputType.emailAddress, procurar: true)),
            ]),
            _campo(_titulo, 'O que precisa', dica: 'Ex.: PMOC de 3 splits'),
            Row(children: [
              Expanded(child: _campo(_valor, 'Valor (R\$)', teclado: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: _campo(_mensal, 'Mensal (R\$)', teclado: TextInputType.number)),
            ]),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('origem-$_origem'),
              initialValue: _origem,
              decoration: const InputDecoration(labelText: 'Origem'),
              items: [for (final e in origensComercial.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _origem = v ?? 'outro'),
            ),
            if (p != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Cores.alerta.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Cores.alerta.withValues(alpha: .4)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Já existe parecido:', style: TextStyle(fontWeight: FontWeight.w700, color: Cores.alerta)),
                  for (final c in listaDeMapas(p['clientes'])) Text('Cliente: ${c['nome']}${c['telefone'] != null ? ' · ${c['telefone']}' : ''}'),
                  for (final c in listaDeMapas(p['contatos'])) Text('Contato: ${c['nome']} (${c['cliente']})'),
                  for (final o in listaDeMapas(p['oportunidades']))
                    Text('Oportunidade: ${o['codigo']} · ${o['titulo']} (${o['situacao']})'),
                  const SizedBox(height: 4),
                  const Text('Mesmo WhatsApp ou e-mail com oportunidade aberta: o contato é registrado nela. '
                      'Cliente que já existe: a oportunidade é ligada a ele.',
                      style: TextStyle(fontSize: 12, color: Cores.neutro)),
                ]),
              ),
            ],
            if (_erro != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_erro!, style: const TextStyle(color: Cores.erro))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _salvando ? null : () => Navigator.of(context).pop(), child: const Text('Voltar')),
        if (p != null && listaDeMapas(p['oportunidades']).any((o) => o['situacao'] == 'aberta'))
          TextButton(onPressed: _salvando ? null : () => _salvar(forcar: true), child: const Text('Criar outra mesmo assim')),
        FilledButton(onPressed: _salvando ? null : _salvar, child: const Text('Anotar')),
      ],
    );
  }
}
