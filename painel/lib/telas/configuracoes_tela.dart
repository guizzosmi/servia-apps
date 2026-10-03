import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/parametros.dart';
import '../widgets/margem.dart';

/// Configurações da empresa (só o admin altera): preventivas, orçamento no
/// app, assinatura do cliente e mensagens. Os valores ficam em empresa_config.parametros.
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

const _itensAvulsos = {
  'desligado': 'Não: só itens do catálogo',
  'gestor': 'Sim, mas o orçamento vem para o gestor revisar antes do cliente',
  'liberado': 'Sim: o técnico digita descrição e preço e já colhe a assinatura',
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
  String _avulsos = 'desligado';
  final _desconto = TextEditingController();
  final _validade = TextEditingController();
  final _termo = TextEditingController();
  // Modelos das mensagens do WhatsApp (o padrão vem do pacote comum).
  final _modelos = {for (final m in modelosMensagem) m.chave: TextEditingController()};
  // Preventivas: menu, PMOC e os números da geração e dos cards.
  bool _usaPrev = true;
  bool _pmoc = false;
  final _antecedencia = TextEditingController();
  final _tolerancia = TextEditingController();
  bool _fotoObrigatoria = true;
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
    _antecedencia.dispose();
    _tolerancia.dispose();
    for (final c in _modelos.values) {
      c.dispose();
    }
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
        _avulsos = _itensAvulsos.containsKey(orc['itens_avulsos_app']) ? orc['itens_avulsos_app'] as String : 'desligado';
        _conclusao = _aceiteConclusao.containsKey(p['aceite_conclusao']) ? p['aceite_conclusao'] as String : 'opcional';
        _desconto.text = _numero(orc['desconto_max_app_pct'] ?? 10);
        _validade.text = _numero(orc['validade_dias'] ?? 15);
        _termo.text = '${orc['termo_aceite'] ?? ''}';
        for (final m in modelosMensagem) {
          _modelos[m.chave]!.text = textoDoModelo(m.chave, p['mensagens'] as Map?);
        }
        final prev = Map<String, dynamic>.from((p['preventivas'] as Map?) ?? const {});
        _usaPrev = prev['usa'] != false;
        _pmoc = prev['pmoc'] == true;
        _antecedencia.text = _numero(p['antecedencia_preventivas_dias'] ?? 15);
        _tolerancia.text = _numero(prev['tolerancia_dias'] ?? 15);
        _fotoObrigatoria = prev['foto_obrigatoria'] != false;
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
    final antecedencia = int.tryParse(_antecedencia.text.trim());
    final tolerancia = int.tryParse(_tolerancia.text.trim());
    if (antecedencia == null || antecedencia < 0 || antecedencia > 90) {
      _avisar('Antecedência das preventivas: de 0 a 90 dias.', erro: true);
      return;
    }
    if (tolerancia == null || tolerancia < 0 || tolerancia > 90) {
      _avisar('Tolerância: de 0 a 90 dias.', erro: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      final prev = Map<String, dynamic>.from((_parametros['preventivas'] as Map?) ?? const {})
        ..['usa'] = _usaPrev
        ..['pmoc'] = _usaPrev && _pmoc
        ..['tolerancia_dias'] = tolerancia
        ..['foto_obrigatoria'] = _fotoObrigatoria;
      // Muda só estas chaves: o resto dos parâmetros continua como está.
      final orc = Map<String, dynamic>.from((_parametros['orcamento'] as Map?) ?? const {})
        ..['quem_monta'] = _quem
        ..['itens_avulsos_app'] = _avulsos
        ..['desconto_max_app_pct'] = desconto
        ..['validade_dias'] = validade;
      final termo = _termo.text.trim();
      if (termo.isEmpty) {
        orc.remove('termo_aceite');
      } else {
        orc['termo_aceite'] = termo;
      }
      // Mensagens: guarda só o que ficou diferente do padrão.
      final mensagens = <String, String>{
        for (final m in modelosMensagem)
          if (_modelos[m.chave]!.text.trim().isNotEmpty && _modelos[m.chave]!.text.trim() != m.padrao.trim())
            m.chave: _modelos[m.chave]!.text.trim(),
      };
      final novos = {
        ..._parametros,
        'orcamento': orc,
        'aceite_conclusao': _conclusao,
        'mensagens': mensagens,
        'preventivas': prev,
        'antecedencia_preventivas_dias': antecedencia,
      };
      await _db
          .from('empresa_config')
          .update({'parametros': novos})
          .eq('empresa_id', Sessao.atual!.empresaId!);
      _avisar('Configurações salvas. O app recebe na próxima sincronização.');
      await ParametrosEmpresa.instancia.recarregar(); // o menu acompanha
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
    return ListView(padding: margemDaTela(context), children: [
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
                const Text('Preventivas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('O menu mostra só o que a empresa usa.', style: TextStyle(color: Cores.neutro)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Usa planos de preventiva'),
                  subtitle: const Text('Serviços recorrentes (manutenção preventiva, contratos): menu, OS automáticas '
                      'e os cards de prazo na Início'),
                  value: _usaPrev,
                  onChanged: admin ? (v) => setState(() {
                        _usaPrev = v;
                        _sujo = true;
                      }) : null,
                ),
                if (_usaPrev) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Atende PMOC (climatização)'),
                    subtitle: const Text('Plano do tipo PMOC, responsável técnico e as atividades padrão da '
                        'Portaria GM/MS 3.523/98'),
                    value: _pmoc,
                    onChanged: admin ? (v) => setState(() {
                          _pmoc = v;
                          _sujo = true;
                        }) : null,
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 16, runSpacing: 12, children: [
                    SizedBox(
                      width: 210,
                      child: TextField(
                        controller: _antecedencia,
                        enabled: admin,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Gerar o lote com antecedência',
                          suffixText: 'dias',
                          helperText: 'O lote do mês seguinte nasce isso antes (o plano pode ter a sua)',
                          helperMaxLines: 2,
                        ),
                        onChanged: (_) => _mudou(),
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: TextField(
                        controller: _tolerancia,
                        enabled: admin,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Tolerância',
                          suffixText: 'dias',
                          helperText: 'Janela antes do vencimento de cada aparelho (o plano pode ter a sua)',
                          helperMaxLines: 2,
                        ),
                        onChanged: (_) => _mudou(),
                      ),
                    ),
                  ]),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Foto obrigatória nos itens que pedem foto'),
                    subtitle: const Text('No app, a câmera abre ao marcar o item; sem a foto, ele não é marcado. '
                        'Desligado, dá para marcar sem a foto'),
                    value: _fotoObrigatoria,
                    onChanged: admin ? (v) => setState(() {
                          _fotoObrigatoria = v;
                          _sujo = true;
                        }) : null,
                  ),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                const Text('Itens fora do catálogo no orçamento do app'),
                const SizedBox(height: 4),
                for (final e in _itensAvulsos.entries)
                  _Opcao(
                    texto: e.value,
                    marcada: _avulsos == e.key,
                    aoEscolher: admin ? () => setState(() {
                          _avulsos = e.key;
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
                        helperText: 'Por item, sobre o preço (vale também para itens fora do catálogo)',
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
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Mensagens do WhatsApp', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text(
                    'O app e o painel abrem o WhatsApp com a mensagem pronta; quem manda confere e envia. '
                    'Os campos entre chaves viram os dados do serviço. Uma linha com um campo vazio some '
                    '(ex.: sem link, a linha do link não aparece).',
                    style: TextStyle(color: Cores.neutro)),
                for (final m in modelosMensagem) ...[
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(m.onde, style: const TextStyle(color: Cores.neutro, fontSize: 12)),
                      ]),
                    ),
                    if (admin && _modelos[m.chave]!.text.trim() != m.padrao.trim())
                      TextButton(
                        onPressed: () => setState(() {
                          _modelos[m.chave]!.text = m.padrao;
                          _sujo = true;
                        }),
                        child: const Text('Voltar ao padrão'),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _modelos[m.chave],
                    enabled: admin,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: 1000,
                    decoration: InputDecoration(
                      alignLabelWithHint: true,
                      helperText: 'Campos: ${m.campos.map((c) => '{$c}').join(' ')}',
                      helperMaxLines: 3,
                    ),
                    onChanged: (_) => _mudou(),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  for (final e in camposMensagem.entries)
                    Text('{${e.key}} ${e.value}', style: const TextStyle(fontSize: 12, color: Cores.neutro)),
                ]),
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
