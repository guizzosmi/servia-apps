import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/status.dart';
import '../servicos/whatsapp.dart';

/// Portal do cliente (guia 72): o link em que o cliente acompanha as visitas,
/// o que está em andamento e o que foi feito, e pede um serviço. Na tela do
/// cliente. O banco guarda só o hash: o link aparece inteiro só ao gerar.
class PortalDoCliente extends StatefulWidget {
  const PortalDoCliente({super.key, required this.clienteId, required this.clienteNome});

  final String clienteId;
  final String clienteNome;

  @override
  State<PortalDoCliente> createState() => _PortalDoClienteState();
}

class _PortalDoClienteState extends State<PortalDoCliente> {
  Map<String, dynamic>? _info;
  String? _link;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _chamar('ver');
  }

  Future<void> _chamar(String acao) async {
    setState(() => _ocupado = true);
    try {
      final r = Map<String, dynamic>.from(await Supabase.instance.client.rpc('portal_link', params: {
        'p': {'cliente_id': widget.clienteId, 'acao': acao}
      }) as Map);
      if (!mounted) return;
      setState(() {
        if (acao == 'gerar') {
          _link = '${Config.linkAceite}/p/${r['token']}';
          _info = {'ativo': true, 'expira_em': r['expira_em'], 'acessos': 0};
        } else if (acao == 'revogar') {
          _link = null;
          _info = {'ativo': false};
        } else {
          _info = r;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagemDeErro(e)), backgroundColor: Cores.erro));
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _gerar() async {
    if (_info?['ativo'] == true) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Gerar outro link?'),
          content: const Text('O link anterior para de funcionar. Mande o novo para o cliente.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Gerar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _chamar('gerar');
  }

  Future<void> _revogar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Desligar o portal?'),
        content: const Text('O link do cliente para de funcionar na hora.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Cores.erro),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Desligar')),
        ],
      ),
    );
    if (ok == true) await _chamar('revogar');
  }

  @override
  Widget build(BuildContext context) {
    final i = _info;
    final ativo = i?['ativo'] == true;
    final link = _link;
    final acessos = num.tryParse('${i?['acessos'] ?? 0}') ?? 0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.public, color: Cores.indigo700),
            SizedBox(width: 8),
            Text('Portal do cliente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          const Text(
              'Um link para o cliente ver as próximas visitas, o que está em andamento e o que foi feito, e pedir um '
              'serviço (o pedido cai em Pedidos do WhatsApp). Vale 1 ano.',
              style: TextStyle(color: Cores.neutro)),
          const SizedBox(height: 10),
          if (i == null)
            const LinearProgressIndicator()
          else if (ativo)
            Text(
              'Link ativo até ${dataBr(i['expira_em'])} · '
              '${acessos == 0 ? 'ainda não aberto' : '$acessos acesso(s), o último em ${dataHoraBr(i['ultimo_acesso_em'])}'}',
              style: const TextStyle(color: Cores.sucesso, fontWeight: FontWeight.w600),
            )
          else
            const Text('Sem link ativo.', style: TextStyle(color: Cores.neutro)),
          if (link != null) ...[
            const SizedBox(height: 10),
            SelectableText(link, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            const SizedBox(height: 4),
            const Text('Guarde ou mande agora: por segurança, o link inteiro só aparece ao gerar.',
                style: TextStyle(color: Cores.alerta, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (link != null) ...[
              FilledButton.icon(
                onPressed: () => mandarWhatsAppSemOs(context,
                    modelo: 'portal_cliente',
                    titulo: 'Mandar o portal',
                    clienteId: widget.clienteId,
                    valores: {'cliente': widget.clienteNome, 'link': link}),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Mandar no WhatsApp'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copiado.')));
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copiar'),
              ),
            ],
            if (i != null)
              OutlinedButton.icon(
                onPressed: _ocupado ? null : _gerar,
                icon: const Icon(Icons.link),
                label: Text(ativo ? 'Gerar outro link' : 'Gerar o link'),
              ),
            if (ativo)
              TextButton.icon(
                onPressed: _ocupado ? null : _revogar,
                style: TextButton.styleFrom(foregroundColor: Cores.erro),
                icon: const Icon(Icons.link_off),
                label: const Text('Desligar'),
              ),
          ]),
        ]),
      ),
    );
  }
}
