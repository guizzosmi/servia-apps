import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/oauth.dart';

/// Tela de consentimento do conector (guia 91): "o Claude quer acessar o ServPilot".
/// Mostra quem pede, para onde volta, a empresa e o que ele poderá fazer (Configurações › Conector).
class OauthConsentimentoTela extends StatefulWidget {
  const OauthConsentimentoTela({super.key, required this.authorizationId});

  final String? authorizationId;

  @override
  State<OauthConsentimentoTela> createState() => _OauthConsentimentoTelaState();
}

class _OauthConsentimentoTelaState extends State<OauthConsentimentoTela> {
  Map<String, dynamic>? _pedido;
  String? _empresa;
  Map<String, dynamic> _conector = const {};
  bool _comercial = false;
  String? _erro;
  bool _ocupado = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final id = widget.authorizationId;
    if (id == null || id.isEmpty) {
      setState(() {
        _erro = 'Pedido de acesso sem identificação. Comece de novo pelo Claude.';
        _ocupado = false;
      });
      return;
    }
    try {
      final p = await detalhesDoPedido(id);
      // Já aprovado antes: volta direto.
      if (!p.containsKey('authorization_id') && (p['redirect_url'] ?? p['redirect_uri']) is String) {
        voltarPara((p['redirect_url'] ?? p['redirect_uri']) as String);
        return;
      }
      final db = Supabase.instance.client;
      final emp = Sessao.atual?.empresaId;
      if (emp != null) {
        final e = await db.from('empresas').select('razao_social, nome_fantasia').eq('id', emp).maybeSingle();
        _empresa = (e?['nome_fantasia'] ?? e?['razao_social']) as String?;
        final c = await db.from('empresa_config').select('parametros').eq('empresa_id', emp).maybeSingle();
        final par = Map<String, dynamic>.from((c?['parametros'] as Map?) ?? const {});
        _conector = Map<String, dynamic>.from((par['conector'] as Map?) ?? const {});
        _comercial = (par['comercial'] as Map?)?['usa'] == true;
      }
      if (mounted) setState(() => _pedido = p);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _responder(bool aprovar) async {
    setState(() => _ocupado = true);
    try {
      voltarPara(await responderPedido(widget.authorizationId!, aprovar: aprovar));
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = mensagemDeErro(e);
          _ocupado = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _pedido;
    final cliente = Map<String, dynamic>.from((p?['client'] as Map?) ?? const {});
    final nome = '${cliente['client_name'] ?? cliente['name'] ?? 'Um aplicativo'}';
    final volta = Uri.tryParse('${p?['redirect_uri'] ?? ''}')?.host ?? '';
    final pode = <String>[
      'Consultar clientes, OS, agenda, orçamentos, contratos, financeiro e indicadores',
      if (_comercial && _conector['comercial'] != false) 'Criar e atualizar oportunidades, tarefas e anotações do Comercial',
      if (_conector['cadastros'] == true) 'Cadastrar e alterar clientes, endereços e equipamentos',
      if (_conector['operacao'] == true) 'Cuidar das OS, dos orçamentos e dos pedidos recebidos',
      if (_conector['financeiro'] == true) 'Registrar cobranças, Pix, recebimentos e lançamentos no caixa',
    ];
    return Scaffold(
      backgroundColor: Cores.fundo,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _ocupado && p == null
                    ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                    : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const Icon(Icons.hub_outlined, size: 40, color: Cores.indigo700),
                        const SizedBox(height: 12),
                        if (p == null)
                          Text(_erro ?? 'Pedido de acesso não encontrado.', textAlign: TextAlign.center, style: const TextStyle(color: Cores.erro))
                        else ...[
                          Text('$nome quer acessar o ServPilot', textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text('Empresa: ${_empresa ?? '-'} · ${Sessao.atual?.email ?? ''}', textAlign: TextAlign.center,
                              style: const TextStyle(color: Cores.neutro)),
                          if (volta.isNotEmpty)
                            Text('Depois de responder, você volta para: $volta', textAlign: TextAlign.center,
                                style: const TextStyle(color: Cores.neutro, fontSize: 12)),
                          if (volta == 'localhost' || volta == '127.0.0.1')
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('Atenção: o retorno é para um programa neste computador. Só aprove se foi você que '
                                  'acabou de conectar (ex.: Claude Code).', textAlign: TextAlign.center, style: TextStyle(color: Cores.alerta)),
                            ),
                          const SizedBox(height: 16),
                          const Text('Com o seu login, ele vai poder:', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          for (final x in pode)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Icon(Icons.check, size: 18, color: Cores.sucesso),
                                const SizedBox(width: 6),
                                Expanded(child: Text(x)),
                              ]),
                            ),
                          const SizedBox(height: 8),
                          const Text('Ele vê só esta empresa e só o que o seu usuário pode ver. O administrador muda o que ele pode '
                              'fazer em Configurações › Conector do Claude. Tudo o que ele grava fica registrado.',
                              style: TextStyle(color: Cores.neutro, fontSize: 12)),
                          if (_erro != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_erro!, style: const TextStyle(color: Cores.erro))),
                          const SizedBox(height: 20),
                          Row(children: [
                            Expanded(
                              child: OutlinedButton(onPressed: _ocupado ? null : () => _responder(false), child: const Text('Recusar')),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(onPressed: _ocupado ? null : () => _responder(true), child: const Text('Permitir')),
                            ),
                          ]),
                        ],
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
