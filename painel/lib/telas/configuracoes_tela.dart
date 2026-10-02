import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Configurações da empresa (só o admin altera): orçamento no app e
/// assinatura do cliente. Os valores ficam em empresa_config.parametros.
class ConfiguracoesTela extends StatefulWidget {
  const ConfiguracoesTela({super.key});

  @override
  State<ConfiguracoesTela> createState() => _ConfiguracoesTelaState();
}

const _quemMonta = {
  'gestor': 'Só o gestor (pelo painel)',
  'gestor_lider': 'Gestor e o líder da equipe (no app)',
  'todos': 'Gestor e toda a equipe (no app)',
};

const _aceiteConclusao = {
  'desligado': 'Não pedir',
  'opcional': 'Oferecer (o técnico escolhe)',
  'obrigatorio': 'Obrigatória quando o cliente acompanhou',
};

class _ConfiguracoesTelaState extends State<ConfiguracoesTela> {
  SupabaseClient get _db => Supabase.instance.client;

  bool _carregando = true;
  bool _salvando = false;
  String? _erro;
  Map<String, dynamic> _parametros = {};

  String _quem = 'gestor_lider';
  String _conclusao = 'opcional';
  final _desconto = TextEditingController();
  final _validade = TextEditingController();
  final _termo = TextEditingController();
  bool _sujo = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _desconto.dispose();
    _validade.dispose();
    _termo.dispose();
    super.dispose();
  }

  static String _numero(Object? v) {
    final n = num.tryParse('${v ?? ''}');
    if (n == null) return '';
    return (n == n.roundToDouble() ? n.toInt().toString() : n.toString()).replaceAll('.', ',');
  }

  Future<void> _carregar() async {
    setState(() => _erro = null);
    try {
      final c = await _db
          .from('empresa_config')
          .select('parametros')
          .eq('empresa_id', Sessao.atual!.empresaId!)
          .single();
      final p = Map<String, dynamic>.from((c['parametros'] as Map?) ?? const {});
      final orc = Map<String, dynamic>.from((p['orcamento'] as Map?) ?? const {});
      if (!mounted) return;
      setState(() {
        _parametros = p;
        _quem = _quemMonta.containsKey(orc['quem_monta']) ? orc['quem_monta'] as String : 'gestor_lider';
        _conclusao = _aceiteConclusao.containsKey(p['aceite_conclusao']) ? p['aceite_conclusao'] as String : 'opcional';
        _desconto.text = _numero(orc['desconto_max_app_pct'] ?? 10);
        _validade.text = _numero(orc['validade_dias'] ?? 15);
        _termo.text = '${orc['termo_aceite'] ?? ''}';
        _sujo = false;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    final desconto = num.tryParse(_desconto.text.trim().replaceAll(',', '.'));
    final validade = int.tryParse(_validade.text.trim());
    if (desconto == null || desconto < 0 || desconto > 100) {
      _avisar('Desconto máximo: um número de 0 a 100.', erro: true);
      return;
    }
    if (validade == null || validade < 1 || validade > 365) {
      _avisar('Validade: de 1 a 365 dias.', erro: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      // Muda só estas chaves: o resto dos parâmetros continua como está.
      final orc = Map<String, dynamic>.from((_parametros['orcamento'] as Map?) ?? const {})
        ..['quem_monta'] = _quem
        ..['desconto_max_app_pct'] = desconto
        ..['validade_dias'] = validade;
      final termo = _termo.text.trim();
      if (termo.isEmpty) {
        orc.remove('termo_aceite');
      } else {
        orc['termo_aceite'] = termo;
      }
      final novos = {..._parametros, 'orcamento': orc, 'aceite_conclusao': _conclusao};
      await _db
          .from('empresa_config')
          .update({'parametros': novos})
          .eq('empresa_id', Sessao.atual!.empresaId!);
      _avisar('Configurações salvas. O app recebe na próxima sincronização.');
      await _carregar();
    } catch (e) {
      _avisar(mensagemDeErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _avisar(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto), backgroundColor: erro ? Cores.erro : null));
  }

  void _mudou() => setState(() => _sujo = true);

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null) {
      return Center(child: Text(_erro!, style: const TextStyle(color: Cores.erro)));
    }
    final admin = Sessao.atual?.tem(Papel.admin) ?? false;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('Configurações', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Valem para a empresa ativa. O app recebe as mudanças na próxima sincronização.',
          style: TextStyle(color: Cores.neutro)),
      const SizedBox(height: 16),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Orçamento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                const Text('Quem monta orçamento'),
                const SizedBox(height: 4),
                for (final e in _quemMonta.entries)
                  _Opcao(
                    texto: e.value,
                    marcada: _quem == e.key,
                    aoEscolher: admin ? () => setState(() {
                          _quem = e.key;
                          _sujo = true;
                        }) : null,
                  ),
                const SizedBox(height: 8),
                Wrap(spacing: 16, runSpacing: 12, children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _desconto,
                      enabled: admin,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Desconto máximo no app',
                        suffixText: '%',
                        helperText: 'Por item, sobre o preço do catálogo',
                      ),
                      onChanged: (_) => _mudou(),
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _validade,
                      enabled: admin,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Validade do orçamento', suffixText: 'dias'),
                      onChanged: (_) => _mudou(),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: _termo,
                  enabled: admin,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Termo de aceite (vazio = texto padrão)',
                    alignLabelWithHint: true,
                    helperText: 'Aparece no PDF, na página do link e na tela de assinatura do app',
                  ),
                  onChanged: (_) => _mudou(),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Assinatura do cliente na conclusão',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('No app, ao concluir o atendimento com o cliente presente.',
                    style: TextStyle(color: Cores.neutro)),
                for (final e in _aceiteConclusao.entries)
                  _Opcao(
                    texto: e.value,
                    marcada: _conclusao == e.key,
                    aoEscolher: admin ? () => setState(() {
                          _conclusao = e.key;
                          _sujo = true;
                        }) : null,
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          if (admin)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _sujo && !_salvando ? _salvar : null,
                icon: _salvando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(_sujo ? 'Salvar' : 'Tudo salvo'),
              ),
            )
          else
            const Text('Só o administrador da empresa altera as configurações.',
                style: TextStyle(color: Cores.neutro)),
        ]),
      ),
    ]);
  }
}

/// Uma opção de uma escolha só (marcador redondo + texto).
class _Opcao extends StatelessWidget {
  const _Opcao({required this.texto, required this.marcada, this.aoEscolher});

  final String texto;
  final bool marcada;
  final VoidCallback? aoEscolher;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        enabled: aoEscolher != null,
        leading: Icon(marcada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: marcada ? Cores.indigo700 : Cores.neutro),
        title: Text(texto),
        onTap: aoEscolher,
      );
}
