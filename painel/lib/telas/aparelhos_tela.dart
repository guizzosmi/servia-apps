import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/funcoes.dart';

/// Aparelhos (celulares) que já entraram no app nesta empresa (só o admin).
/// Revogar: o aparelho não sincroniza mais. Apagar: além disso, o app apaga
/// os dados locais na próxima vez que abrir e confirma.
class AparelhosTela extends StatefulWidget {
  const AparelhosTela({super.key});

  @override
  State<AparelhosTela> createState() => _AparelhosTelaState();
}

class _AparelhosTelaState extends State<AparelhosTela> {
  List<Map<String, dynamic>>? _itens;
  String? _erro;
  bool _carregando = true;
  String? _ocupado; // id do aparelho em ação

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final dados = await Supabase.instance.client
          .from('dispositivos')
          .select('id, plataforma, modelo, versao_app, status, motivo, revogado_em, '
              'apagado_confirmado_em, ultima_sincronizacao, criado_em, usuarios(nome, email)')
          .eq('empresa_id', Sessao.atual?.empresaId ?? '')
          .order('ultima_sincronizacao', ascending: false, nullsFirst: false);
      if (mounted) setState(() => _itens = dados);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _acao(Map<String, dynamic> d, String acao) async {
    String? motivo;
    if (acao != 'reativar') {
      final campo = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(acao == 'apagar' ? 'Revogar e apagar os dados?' : 'Revogar aparelho?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(acao == 'apagar'
                  ? 'O aparelho para de sincronizar e, na próxima vez que o app abrir, '
                      'apaga tudo o que tem guardado (inclusive o que ainda não foi enviado). '
                      'Use quando o celular foi perdido ou roubado.'
                  : 'O aparelho para de sincronizar. Os dados continuam nele até você '
                      'mandar apagar ou reativar.'),
              const SizedBox(height: 12),
              TextField(
                controller: campo,
                decoration: const InputDecoration(labelText: 'Motivo (ex.: celular perdido)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Cores.erro),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(acao == 'apagar' ? 'Revogar e apagar' : 'Revogar'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      motivo = campo.text.trim();
    }
    setState(() => _ocupado = d['id'] as String);
    try {
      await chamarFuncao('dispositivo-acao', {
        'acao': acao,
        'dispositivo_id': d['id'],
        if (motivo != null && motivo.isNotEmpty) 'motivo': motivo,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feito.')));
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(mensagemDeErro(e)), backgroundColor: Cores.erro));
    } finally {
      if (mounted) setState(() => _ocupado = null);
    }
  }

  static String _dataHora(Object? v) {
    final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
    if (d == null) return '—';
    String dd(int n) => n.toString().padLeft(2, '0');
    return '${dd(d.day)}/${dd(d.month)}/${d.year} ${dd(d.hour)}:${dd(d.minute)}';
  }

  Widget _status(Map<String, dynamic> d) {
    final s = d['status'] as String? ?? '';
    final (texto, cor) = switch (s) {
      'ativo' => ('Ativo', Cores.sucesso),
      'revogado' => ('Revogado', Cores.alerta),
      'apagar' => (d['apagado_confirmado_em'] != null ? 'Dados apagados' : 'Apagar pendente', Cores.erro),
      _ => (s, Cores.neutro),
    };
    return Chip(
      label: Text(texto, style: TextStyle(color: cor, fontWeight: FontWeight.w600)),
      side: BorderSide(color: cor),
      backgroundColor: Colors.white,
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text('Aparelhos',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _carregando ? null : _carregar,
              icon: const Icon(Icons.refresh),
            ),
          ]),
          const Text(
            'Cada celular aparece aqui no primeiro login do app. Para bloquear só um aparelho '
            '(perdido, trocado), revogue aqui; para tirar o acesso da pessoa, desative o usuário.',
            style: TextStyle(color: Cores.neutro),
          ),
          const SizedBox(height: 12),
          if (_carregando) const LinearProgressIndicator(minHeight: 2),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: _erro != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_erro!, style: const TextStyle(color: Cores.erro)))
                : (_itens == null)
                    ? const SizedBox(height: 80)
                    : _itens!.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Nenhum aparelho registrado ainda.'))
                        : Column(children: [
                            for (final d in _itens!) ...[
                              _linha(d),
                              if (d != _itens!.last) const Divider(height: 1),
                            ],
                          ]),
          ),
        ],
      ),
    );
  }

  Widget _linha(Map<String, dynamic> d) {
    final u = (d['usuarios'] as Map<String, dynamic>?) ?? const {};
    final status = d['status'] as String? ?? '';
    final modelo = [d['modelo'], d['plataforma'], if (d['versao_app'] != null) 'app ${d['versao_app']}']
        .where((x) => x != null && '$x'.isNotEmpty)
        .join(' · ');
    return ListTile(
      leading: const Icon(Icons.smartphone),
      title: Text('${u['nome'] ?? '?'} · ${modelo.isEmpty ? 'aparelho' : modelo}'),
      subtitle: Text([
        'Última sincronização: ${_dataHora(d['ultima_sincronizacao'])}',
        if (d['motivo'] != null) 'Motivo: ${d['motivo']}',
      ].join('\n')),
      isThreeLine: d['motivo'] != null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _status(d),
          if (_ocupado == d['id'])
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'Ações',
              onSelected: (a) => _acao(d, a),
              itemBuilder: (_) => [
                if (status == 'ativo')
                  const PopupMenuItem(value: 'revogar', child: Text('Revogar')),
                if (status != 'apagar')
                  const PopupMenuItem(value: 'apagar', child: Text('Revogar e apagar os dados')),
                if (status != 'ativo')
                  const PopupMenuItem(value: 'reativar', child: Text('Reativar')),
              ],
            ),
        ],
      ),
    );
  }
}
