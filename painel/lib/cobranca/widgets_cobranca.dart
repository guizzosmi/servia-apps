import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';

import '../servicos/arquivo_web.dart' show abrirEmNovaAba;
import '../servicos/cobranca.dart' show lerValor;
import '../servicos/comercial.dart' show reais;
import '../servicos/status.dart' show dataBr, dataHoraBr, dataIso;
import 'servico_cobranca.dart';

/// Cobrança parametrizável (guia 100): peças usadas no A cobrar, no Caixa e na tela de títulos.

void _avisar(BuildContext context, String t, {bool erro = false}) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Cores.erro : null));

Future<void> _copiar(BuildContext context, String texto, String oQue) async {
  await Clipboard.setData(ClipboardData(text: texto));
  if (context.mounted) _avisar(context, '$oQue copiado.');
}

/// Botão "Boleto/Pix" de uma cobrança do A cobrar (e do Caixa › A receber). No modo manual não aparece:
/// o fluxo de sempre não muda. Com título, mostra a 2ª via; sem, oferece emitir.
class BotaoTitulo extends StatelessWidget {
  const BotaoTitulo({super.key, required this.cobrancaId, this.aoMudar});

  final String cobrancaId;
  final VoidCallback? aoMudar;

  Future<void> _abrir(BuildContext context) async {
    try {
      final r = await listaTitulos({'origem': 'cobranca', 'origem_id': cobrancaId});
      final lista = ((r['titulos'] as List?) ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
      final vivo = lista.where((t) => !const {'cancelado', 'baixado'}.contains(t['situacao'])).toList();
      if (!context.mounted) return;
      if (vivo.isNotEmpty) {
        await mostrarSegundaVia(context, '${vivo.first['id']}');
      } else {
        final emitiu = await showDialog<bool>(context: context, builder: (_) => _EmitirDaCobranca(cobrancaId: cobrancaId));
        if (emitiu == true) aoMudar?.call();
      }
    } catch (e) {
      if (context.mounted) _avisar(context, mensagemDeErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: ModoCobranca.atual(),
      builder: (context, snap) {
        final modo = snap.data ?? 'manual';
        if (modo == 'manual') return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: OutlinedButton.icon(
            onPressed: () => _abrir(context),
            icon: const Icon(Icons.receipt_outlined),
            label: Text(modo == 'pix' ? 'Pix' : 'Boleto'),
          ),
        );
      },
    );
  }
}

class _EmitirDaCobranca extends StatefulWidget {
  const _EmitirDaCobranca({required this.cobrancaId});

  final String cobrancaId;

  @override
  State<_EmitirDaCobranca> createState() => _EmitirDaCobrancaState();
}

class _EmitirDaCobrancaState extends State<_EmitirDaCobranca> {
  DateTime? _vencimento;
  bool _salvando = false;
  String? _erro;

  Future<void> _emitir() async {
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final r = await acaoCobranca({
        'acao': 'emitir_cobranca',
        'cobranca_id': widget.cobrancaId,
        if (_vencimento != null) 'vencimento': dataIso(_vencimento!),
      });
      final t = Map<String, dynamic>.from((r['titulo'] as Map?) ?? const {});
      if (t['via'] == 'api' && t['situacao'] == 'a_registrar') {
        try {
          await funcaoCobranca({'acao': 'processar', 'titulo_id': r['titulo_id']});
        } catch (_) {
          // a rotina registra em alguns minutos
        }
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      _avisar(context, 'Título ${r['codigo']} emitido.');
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Emitir boleto/Pix desta cobrança'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('O título sai no modo da empresa (Configurações › Cobrança), com o valor da cobrança. '
              'Quando o cliente pagar, a baixa cai sozinha no Caixa.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_outlined),
            label: Text(_vencimento == null ? 'Vencimento padrão da empresa' : 'Vence em ${dataBr(dataIso(_vencimento!))}'),
            onPressed: () async {
              final hoje = DateTime.now();
              final d = await showDatePicker(
                  context: context,
                  initialDate: _vencimento ?? hoje.add(const Duration(days: 5)),
                  firstDate: hoje,
                  lastDate: hoje.add(const Duration(days: 365)));
              if (d != null && mounted) setState(() => _vencimento = d);
            },
          ),
          if (_erro != null)
            Padding(
                padding: const EdgeInsets.only(top: 8), child: Text(_erro!, style: const TextStyle(color: Cores.erro))),
        ]),
      ),
      actions: [
        TextButton(onPressed: _salvando ? null : () => Navigator.pop(context), child: const Text('Voltar')),
        FilledButton(onPressed: _salvando ? null : _emitir, child: const Text('Emitir')),
      ],
    );
  }
}

/// Segunda via: linha digitável, Pix, link, situação e a história do título.
Future<void> mostrarSegundaVia(BuildContext context, String tituloId) async {
  Map<String, dynamic> r;
  try {
    r = await verTitulo(tituloId);
  } catch (e) {
    if (context.mounted) _avisar(context, mensagemDeErro(e), erro: true);
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (_) => _SegundaVia(dados: r));
}

class _SegundaVia extends StatelessWidget {
  const _SegundaVia({required this.dados});

  final Map<String, dynamic> dados;

  @override
  Widget build(BuildContext context) {
    final t = Map<String, dynamic>.from((dados['titulo'] as Map?) ?? const {});
    final eventos = ((dados['eventos'] as List?) ?? const []).cast<Map>();
    final linha = '${t['linha_digitavel'] ?? ''}';
    final pix = '${t['pix_copia_cola'] ?? ''}';
    final url = '${t['url'] ?? ''}';
    return AlertDialog(
      title: Row(children: [
        Expanded(child: Text('${t['codigo']} · ${reais(t['valor'])}')),
        SeloTitulo('${t['situacao']}', vencido: t['vencido'] == true),
      ]),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t['cliente'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
                [
                  'vence ${dataBr(t['vencimento'])}',
                  rotuloViaTitulo[t['via']] ?? '${t['via']}',
                  if (t['banco'] != null) nomesBancos[t['banco']] ?? '${t['banco']}',
                  if ((t['nosso_numero'] ?? '') != '') 'nosso número ${t['nosso_numero']}',
                  if ((t['documento'] ?? '') != '') '${t['documento']}',
                ].join(' · '),
                style: const TextStyle(color: Cores.neutro)),
            if (t['situacao'] == 'pago')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Pago ${reais(t['valor_pago'])} em ${dataBr(t['pago_em'])}',
                    style: const TextStyle(color: Cores.sucesso, fontWeight: FontWeight.w600)),
              ),
            if (t['situacao'] == 'a_registrar')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    switch ('${t['via']}') {
                      'cnab' => 'Entra na próxima remessa CNAB: a linha digitável sai quando você gerar a remessa (Títulos).',
                      'erp' => 'Aguardando o ERP emitir o título.',
                      _ => 'Indo para o banco: a linha digitável e o Pix aparecem aqui em instantes.',
                    },
                    style: const TextStyle(color: Cores.info)),
              ),
            if ((t['erro'] ?? '') != '')
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${t['erro']}', style: const TextStyle(color: Cores.erro))),
            if (linha.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Linha digitável', style: TextStyle(fontWeight: FontWeight.w600)),
              SelectableText(linha, style: const TextStyle(fontFamily: 'monospace')),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: () => _copiar(context, linha.replaceAll(RegExp(r'\D'), ''), 'Linha digitável'),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar linha')),
              ),
            ],
            if (pix.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Pix copia e cola', style: TextStyle(fontWeight: FontWeight.w600)),
              SelectableText(pix, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: () => _copiar(context, pix, 'Pix'),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar Pix')),
              ),
            ],
            if (url.isNotEmpty)
              TextButton.icon(
                  onPressed: () => abrirEmNovaAba(url),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir o boleto do banco')),
            if (eventos.isNotEmpty) ...[
              const Divider(height: 24),
              const Text('História', style: TextStyle(fontWeight: FontWeight.w600)),
              for (final e in eventos)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${dataHoraBr(e['criado_em'])} · ${e['descricao'] ?? e['tipo']}'
                      '${e['quem'] != null ? ' · ${e['quem']}' : ''}'),
                ),
            ],
          ]),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}

/// Dar baixa (recebido por fora do banco): valor, data, forma e observação.
class DialogoBaixarTitulo extends StatefulWidget {
  const DialogoBaixarTitulo({super.key, required this.titulo});

  final Map<String, dynamic> titulo;

  @override
  State<DialogoBaixarTitulo> createState() => _DialogoBaixarTituloState();
}

class _DialogoBaixarTituloState extends State<DialogoBaixarTitulo> {
  late final _valor =
      TextEditingController(text: (num.tryParse('${widget.titulo['valor']}') ?? 0).toStringAsFixed(2).replaceAll('.', ','));
  final _obs = TextEditingController();
  DateTime _data = DateTime.now();
  String _forma = 'pix';

  @override
  void dispose() {
    _valor.dispose();
    _obs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valor = lerValor(_valor.text);
    return AlertDialog(
      title: Text('Dar baixa · ${widget.titulo['codigo']}'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Recebido por fora do banco (dinheiro, transferência, Pix direto). A entrada vai para o Caixa e, se o '
              'título está no banco, a baixa é pedida lá para o cliente não pagar duas vezes.',
              style: TextStyle(color: Cores.neutro)),
          const SizedBox(height: 12),
          TextField(
            controller: _valor,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor recebido (R\$)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _forma,
            decoration: const InputDecoration(labelText: 'Forma'),
            items: [
              for (final e in rotuloFormaRecebimento.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _forma = v ?? 'pix'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_outlined),
            label: Text('Recebido em ${dataBr(dataIso(_data))}'),
            onPressed: () async {
              final d = await showDatePicker(
                  context: context,
                  initialDate: _data,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now());
              if (d != null && mounted) setState(() => _data = d);
            },
          ),
          const SizedBox(height: 8),
          TextField(controller: _obs, decoration: const InputDecoration(labelText: 'Observação (opcional)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
        FilledButton(
          onPressed: valor == null || valor <= 0
              ? null
              : () => Navigator.pop(context, <String, dynamic>{
                    'valor': valor,
                    'data': dataIso(_data),
                    'forma': _forma,
                    if (_obs.text.trim().isNotEmpty) 'observacao': _obs.text.trim(),
                  }),
          child: const Text('Dar baixa'),
        ),
      ],
    );
  }
}

/// Configurações › Cobrança (no meio das configurações da empresa).
class CartaoCobranca extends StatelessWidget {
  const CartaoCobranca({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: const Icon(Icons.account_balance_outlined, color: Cores.indigo700),
        title: const Text('Cobrança (boleto e Pix registrado, CNAB)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        subtitle: const Text('Como a empresa cobra: manual, Pix, boleto/Pix registrado pela API do banco, arquivo CNAB ou '
            'pelo ERP. Multa, juros, desconto, vencimento, protesto e as contas de cobrança.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go('/titulos/configuracao'),
      ),
    );
  }
}
