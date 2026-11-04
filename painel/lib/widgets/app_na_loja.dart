import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Guia 50: o app do técnico na Play Store. Enquanto está em teste, só instala quem está na lista
/// de testadores; o admin da empresa informa aqui o Gmail do celular de cada um.
class AppNaLoja extends StatefulWidget {
  const AppNaLoja({super.key});

  @override
  State<AppNaLoja> createState() => _AppNaLojaState();
}

class _AppNaLojaState extends State<AppNaLoja> {
  final _email = TextEditingController();
  final _nome = TextEditingController();
  Map<String, dynamic>? _d;
  String? _erro;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    // Depois do primeiro quadro (setState não pode rodar dentro do initState).
    Future.microtask(() => _rodar(() => Supabase.instance.client.rpc('app_testadores_lista')));
  }

  @override
  void dispose() {
    _email.dispose();
    _nome.dispose();
    super.dispose();
  }

  Future<void> _rodar(Future<dynamic> Function() f, {bool limpar = false}) async {
    if (!mounted) return;
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      final r = await f();
      if (!mounted) return;
      setState(() {
        if (r is Map) _d = Map<String, dynamic>.from(r);
        if (limpar) {
          _email.clear();
          _nome.clear();
        }
      });
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _adicionar() => _rodar(
      () => Supabase.instance.client.rpc('app_testador_adicionar', params: {'p_email': _email.text, 'p_nome': _nome.text}),
      limpar: true);

  void _remover(dynamic id) =>
      _rodar(() => Supabase.instance.client.rpc('app_testador_remover', params: {'p_id': id}));

  Future<void> _copiar(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copiado.')));
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final titulo = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    if (d == null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _erro != null
              ? Text(_erro!, style: const TextStyle(color: Cores.erro))
              : const LinearProgressIndicator(minHeight: 2),
        ),
      );
    }
    final publicado = d['situacao'] == 'publicado';
    final itens = d['itens'] is List
        ? (d['itens'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
    final linkTeste = d['link_teste'] as String?;
    final linkLoja = '${d['link_loja'] ?? ''}';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.android, color: Cores.sucesso),
            const SizedBox(width: 8),
            Expanded(child: Text('App do técnico na Play Store', style: titulo)),
          ]),
          const SizedBox(height: 8),
          if (publicado) ...[
            const Text('O app está na Play Store para todo mundo. Mande o link para a equipe instalar e entrar com '
                'matrícula e PIN (ou e-mail e senha).'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: () => _copiar(linkLoja), icon: const Icon(Icons.link), label: const Text('Copiar o link da loja')),
              OutlinedButton.icon(onPressed: () => abrirLink(linkLoja), icon: const Icon(Icons.open_in_new), label: const Text('Abrir')),
            ]),
          ] else ...[
            const Text('O app ainda está em teste na Play Store: só instala quem está na lista de testadores. Informe aqui o '
                'e-mail da conta Google do celular de cada pessoa (o que aparece na Play Store, normalmente um Gmail). '
                'Liberamos em até 1 dia útil.'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Gmail do celular', isDense: true),
                  onSubmitted: (_) {
                    if (!_ocupado) _adicionar();
                  },
                ),
              ),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _nome,
                  decoration: const InputDecoration(labelText: 'Nome (opcional)', isDense: true),
                  onSubmitted: (_) {
                    if (!_ocupado) _adicionar();
                  },
                ),
              ),
              FilledButton.icon(
                  onPressed: _ocupado ? null : _adicionar, icon: const Icon(Icons.add), label: const Text('Adicionar')),
            ]),
            if (_erro != null) ...[
              const SizedBox(height: 8),
              Text(_erro!, style: const TextStyle(color: Cores.erro)),
            ],
            if (itens.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final t in itens)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(t['incluido'] == true ? Icons.check_circle : Icons.schedule,
                      color: t['incluido'] == true ? Cores.sucesso : Cores.alerta),
                  title: Text('${t['email']}${t['nome'] != null ? ' · ${t['nome']}' : ''}'),
                  subtitle: Text(t['incluido'] == true ? 'Liberado: já pode instalar pelo link abaixo' : 'Aguardando liberação'),
                  trailing: t['incluido'] == true
                      ? null
                      : IconButton(
                          tooltip: 'Tirar da lista',
                          onPressed: _ocupado ? null : () => _remover(t['id']),
                          icon: const Icon(Icons.close)),
                ),
            ],
            if (linkTeste != null) ...[
              const SizedBox(height: 8),
              const Text('Para instalar: no celular, abra o link no Chrome com a mesma conta Google, toque em '
                  '"Aceitar convite" e depois em "Baixar no Google Play".',
                  style: TextStyle(color: Cores.neutro)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                FilledButton.icon(
                    onPressed: () => _copiar(linkTeste), icon: const Icon(Icons.link), label: const Text('Copiar o link para instalar')),
              ]),
            ],
          ],
        ]),
      ),
    );
  }
}
