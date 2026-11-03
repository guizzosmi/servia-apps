import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:servia_comum/servia_comum.dart';

import '../api.dart';
import '../widgets/comuns.dart';

/// Guia 50: Gmails que os clientes informaram para instalar o app enquanto ele está em teste na
/// Play Store. Copie os pendentes, cole na lista de testadores da Play Console e marque como incluídos.
class TestadoresTela extends StatefulWidget {
  const TestadoresTela({super.key});

  @override
  State<TestadoresTela> createState() => _TestadoresTelaState();
}

class _TestadoresTelaState extends State<TestadoresTela> {
  late Future<Map<String, dynamic>> _dados = rpcMapa('admin_testadores');
  bool _ocupado = false;

  void _recarregar() => setState(() => _dados = rpcMapa('admin_testadores'));

  void _avisar(String texto, {bool erro = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));

  Future<void> _acao(Map<String, dynamic> p, String ok) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await rpcMapa('admin_testadores_acao', {'p': p});
      if (mounted) _avisar(ok);
      if (mounted) _recarregar();
    } catch (e) {
      if (mounted) _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _copiar(List<Map<String, dynamic>> pendentes) async {
    await Clipboard.setData(ClipboardData(text: pendentes.map((t) => t['email']).join(', ')));
    if (mounted) _avisar('${pendentes.length} e-mail(s) copiado(s). Cole na lista de testadores da Play Console e salve.');
  }

  Future<void> _editarPlay(Map<String, dynamic> play) async {
    final teste = TextEditingController(text: '${play['link_teste'] ?? ''}');
    final loja = TextEditingController(text: '${play['link_loja'] ?? ''}');
    var publicado = play['situacao'] == 'publicado';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, definir) => AlertDialog(
          title: const Text('App na Play Store'),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Publicado para todo mundo'),
                subtitle: const Text('Ligado: o painel dos clientes mostra o link da loja e para de pedir Gmails.'),
                value: publicado,
                onChanged: (v) => definir(() => publicado = v),
              ),
              campoTexto(teste, 'Link do teste (Play Console > Teste fechado ou interno > Copiar link)'),
              campoTexto(loja, 'Link da loja'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _acao({'acao': 'play', 'situacao': publicado ? 'publicado' : 'teste', 'link_teste': teste.text, 'link_loja': loja.text},
          'Salvo.');
    }
  }

  @override
  Widget build(BuildContext context) => Carregar<Map<String, dynamic>>(
        futuro: _dados,
        recarregar: _recarregar,
        construir: (d) {
          final play = mapa(d['play']);
          final itens = lista(d['itens']);
          final pendentes = itens.where((t) => t['incluido_em'] == null).toList();
          final incluidos = itens.where((t) => t['incluido_em'] != null).toList();
          return ListView(padding: const EdgeInsets.all(24), children: [
            Row(children: [
              Expanded(child: Text('Testadores do app', style: Theme.of(context).textTheme.headlineSmall)),
              OutlinedButton.icon(
                  onPressed: () => _editarPlay(play), icon: const Icon(Icons.settings_outlined), label: const Text('Links e situação')),
            ]),
            const SizedBox(height: 4),
            Text(
                play['situacao'] == 'publicado'
                    ? 'O app está publicado: o painel dos clientes mostra o link da loja.'
                    : 'O app está em teste. Os clientes informam os Gmails no painel (Usuários). Copie os pendentes, cole na lista '
                        'de testadores da Play Console (Teste fechado > Testadores), salve lá e marque aqui como incluídos. '
                        'A Google pede 12 pessoas no teste fechado por 14 dias seguidos para liberar a produção.',
                style: const TextStyle(color: Cores.neutro)),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, children: [
              Indicador(rotulo: 'Incluídos', valor: '${d['incluidos'] ?? 0}'),
              Indicador(rotulo: 'Pendentes', valor: '${d['pendentes'] ?? 0}'),
              Indicador(rotulo: 'Link do teste', valor: (play['link_teste'] ?? '') == '' ? 'não informado' : 'informado'),
            ]),
            const SizedBox(height: 16),
            Secao(
              titulo: 'Pendentes (${pendentes.length})',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (pendentes.isEmpty) const Text('Nenhum pendente.'),
                for (final t in pendentes)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${t['email']}${t['nome'] != null ? ' · ${t['nome']}' : ''}'),
                    subtitle: Text('${t['conta']} · pedido em ${dataBr(t['criado_em'], hora: true)}'),
                    trailing: IconButton(
                        tooltip: 'Remover',
                        onPressed: _ocupado ? null : () => _acao({'acao': 'remover', 'ids': [t['id']]}, 'Removido.'),
                        icon: const Icon(Icons.delete_outline)),
                  ),
                if (pendentes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                        onPressed: () => _copiar(pendentes), icon: const Icon(Icons.copy), label: const Text('Copiar os e-mails pendentes')),
                    FilledButton.icon(
                        onPressed: _ocupado
                            ? null
                            : () => _acao({'acao': 'incluir', 'ids': [for (final t in pendentes) t['id']]},
                                'Marcados como incluídos. O link aparece no painel deles.'),
                        icon: const Icon(Icons.done_all),
                        label: const Text('Já incluí na Play Console')),
                  ]),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            Secao(
              titulo: 'Incluídos (${incluidos.length})',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (incluidos.isEmpty) const Text('Ninguém ainda.'),
                for (final t in incluidos)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${t['email']}${t['nome'] != null ? ' · ${t['nome']}' : ''}'),
                    subtitle: Text('${t['conta']} · incluído em ${dataBr(t['incluido_em'])}'),
                    trailing: TextButton(
                        onPressed: _ocupado ? null : () => _acao({'acao': 'pendente', 'ids': [t['id']]}, 'Voltou para pendente.'),
                        child: const Text('Voltar para pendente')),
                  ),
              ]),
            ),
          ]);
        },
      );
}
