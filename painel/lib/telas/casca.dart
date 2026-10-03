import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cadastros/catalogo.dart';
import '../servicos/parametros.dart';

/// Moldura do painel: menu lateral + barra superior com a empresa e "Sair".
/// Em telas estreitas o menu vira uma gaveta (ícone ☰).
class Casca extends StatelessWidget {
  const Casca({super.key, required this.local, required this.child});

  final String local;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Parâmetros da empresa (menu, Início, planos): a gaveta fechada não é desenhada.
    ParametrosEmpresa.instancia.garantir();
    final largura = MediaQuery.sizeOf(context).width;
    final largo = largura >= 1000;
    final celular = largura < 600;
    final menu = _Menu(local: local, fecharAoEscolher: !largo);
    return Scaffold(
      appBar: AppBar(
        // No celular, só o símbolo: o nome da empresa precisa do espaço.
        title: celular ? const Marca(altura: 30, layout: MarcaLayout.simbolo) : Marca(altura: largo ? 30 : 26),
        titleSpacing: celular ? 0 : null,
        automaticallyImplyLeading: !largo,
        shape: const Border(bottom: BorderSide(color: Cores.linha)),
        actions: const [_EmpresaAtual(), SizedBox(width: 8)],
      ),
      drawer: largo ? null : Drawer(child: menu),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (largo)
            Container(
              width: 250,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(right: BorderSide(color: Cores.linha)),
              ),
              child: menu,
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.local, required this.fecharAoEscolher});

  final String local;
  final bool fecharAoEscolher;

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icone, String rotulo, String destino) {
      final selecionado =
          destino == '/' ? local == '/' : local.startsWith(destino);
      return ListTile(
        dense: true,
        leading: Icon(icone, size: 20),
        title: Text(rotulo),
        selected: selecionado,
        selectedColor: Cores.indigo700,
        selectedTileColor: Cores.indigo100,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onTap: () {
          if (fecharAoEscolher) Navigator.of(context).pop();
          context.go(destino);
        },
      );
    }

    Widget grupo(String titulo) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
          child: Text(titulo.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w700,
                  color: Cores.neutro)),
        );

    final param = ParametrosEmpresa.instancia..garantir();
    return ListenableBuilder(
      listenable: param,
      builder: (context, _) => ListView(
      padding: const EdgeInsets.all(8),
      children: [
        item(Icons.home_outlined, 'Início', '/'),
        grupo('Operação'),
        item(Icons.view_kanban_outlined, 'Quadro do dia', '/quadro'),
        item(Icons.inbox_outlined, 'Fila de pendentes', '/fila'),
        item(Icons.assignment_outlined, 'Ordens de serviço', '/os'),
        item(Icons.request_quote_outlined, 'Orçamentos', '/orcamentos'),
        // Só para quem usa (Configurações > Preventivas).
        if (param.usaPreventivas) item(Icons.event_repeat_outlined, param.nomePlanos, '/planos'),
        grupo('Financeiro'),
        item(Icons.handshake_outlined, 'Contratos', '/contratos'),
        grupo('Cadastros'),
        for (final def in cadastrosDoMenu)
          item(def.icone, def.titulo, '/c/${def.chave}'),
        if (Sessao.atual?.tem(Papel.admin) ?? false) ...[
          grupo('Administração'),
          item(Icons.manage_accounts_outlined, 'Usuários', '/usuarios'),
          item(Icons.smartphone_outlined, 'Aparelhos', '/aparelhos'),
          item(Icons.tune_outlined, 'Configurações', '/configuracoes'),
        ],
        grupo('Em breve'),
        const ListTile(
          dense: true,
          enabled: false,
          leading: Icon(Icons.payments_outlined, size: 20),
          title: Text('Faturamento'),
        ),
      ],
      ),
    );
  }
}

/// Nome da empresa ativa + menu com "Trocar empresa" e "Sair".
class _EmpresaAtual extends StatefulWidget {
  const _EmpresaAtual();

  @override
  State<_EmpresaAtual> createState() => _EmpresaAtualState();
}

class _EmpresaAtualState extends State<_EmpresaAtual> {
  String? _empresaId;
  Future<String>? _nome;

  Future<String> _buscarNome(String id) async {
    final e = await Supabase.instance.client
        .from('empresas')
        .select('razao_social, nome_fantasia')
        .eq('id', id)
        .single();
    return (e['nome_fantasia'] ?? e['razao_social'] ?? '') as String;
  }

  @override
  Widget build(BuildContext context) {
    final sessao = Sessao.atual;
    if (sessao?.empresaId != _empresaId) {
      _empresaId = sessao?.empresaId;
      _nome = _empresaId == null ? null : _buscarNome(_empresaId!);
    }
    return FutureBuilder<String>(
      future: _nome,
      builder: (context, snap) {
        return PopupMenuButton<String>(
          tooltip: 'Empresa e usuário',
          onSelected: (op) {
            if (op == 'trocar') context.go('/empresa');
            if (op == 'sair') Sessao.sair();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              enabled: false,
              child: Text(sessao?.email ?? '',
                  style: const TextStyle(color: Cores.neutro)),
            ),
            const PopupMenuItem(
              value: 'trocar',
              child: ListTile(
                leading: Icon(Icons.swap_horiz),
                title: Text('Trocar empresa'),
              ),
            ),
            const PopupMenuItem(
              value: 'sair',
              child: ListTile(leading: Icon(Icons.logout), title: Text('Sair')),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.business, size: 18, color: Cores.indigo500),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width < 600 ? 150 : 220),
                  child: Text(
                    snap.data ?? '…',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        );
      },
    );
  }
}
