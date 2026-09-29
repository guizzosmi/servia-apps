import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cadastros/servico.dart';
import '../servicos/funcoes.dart';

/// Lista dos usuários da conta (só o admin). A leitura vem direto do banco:
/// o RLS mostra ao admin os usuários com vínculo em alguma empresa da conta.
class UsuariosTela extends StatefulWidget {
  const UsuariosTela({super.key});

  @override
  State<UsuariosTela> createState() => _UsuariosTelaState();
}

class _UsuariosTelaState extends State<UsuariosTela> {
  final _busca = TextEditingController();
  Timer? _espera;
  List<Map<String, dynamic>>? _itens;
  String? _erro;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      var q = Supabase.instance.client.from('usuarios').select(
          'id, nome, email, telefone, ativo, ultimo_acesso, '
          'usuario_empresas(empresa_id, papeis, matricula, ativo)');
      final b = CadastroServico.limparBusca(_busca.text);
      if (b.isNotEmpty) q = q.or('nome.ilike."*$b*",email.ilike."*$b*"');
      final dados = await q.order('nome', ascending: true).limit(200);
      if (mounted) setState(() => _itens = dados);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _abrir(String destino) async {
    await context.push(destino);
    if (mounted) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final empresaAtiva = Sessao.atual?.empresaId;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Usuários',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _busca,
                  decoration: const InputDecoration(
                      hintText: 'Buscar', prefixIcon: Icon(Icons.search, size: 20)),
                  onChanged: (_) {
                    _espera?.cancel();
                    _espera = Timer(const Duration(milliseconds: 350), _carregar);
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _abrir('/usuarios/novo'),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Novo usuário'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Quem entra no painel usa e-mail e senha. O técnico pode entrar no app '
            'com matrícula e PIN de 6 números.',
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
                    child: Text(_erro!, style: const TextStyle(color: Cores.erro)),
                  )
                : (_itens == null)
                    ? const SizedBox(height: 80)
                    : _itens!.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Nenhum usuário encontrado.'),
                          )
                        : Column(
                            children: [
                              for (final u in _itens!) ...[
                                _LinhaUsuario(
                                  u: u,
                                  empresaAtiva: empresaAtiva,
                                  aoTocar: () => _abrir('/usuarios/${u['id']}'),
                                ),
                                if (u != _itens!.last) const Divider(height: 1),
                              ],
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}

String _inicial(String nome) =>
    nome.trim().isEmpty ? '?' : nome.trim().characters.first.toUpperCase();

class _LinhaUsuario extends StatelessWidget {
  const _LinhaUsuario({required this.u, required this.empresaAtiva, required this.aoTocar});

  final Map<String, dynamic> u;
  final String? empresaAtiva;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final email = (u['email'] ?? '') as String;
    final vinculos = ((u['usuario_empresas'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final aqui = vinculos.where((v) => v['empresa_id'] == empresaAtiva).firstOrNull;
    final papeis = aqui == null || aqui['ativo'] != true
        ? 'sem acesso nesta empresa'
        : ((aqui['papeis'] as List?) ?? const [])
            .map((p) => rotulosPapeis[p] ?? p.toString())
            .join(', ');
    final login = ehLoginPorPin(email) ? 'Matrícula ${matriculaDoEmail(email)} · PIN' : email;
    final ativo = u['ativo'] == true;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: ativo ? Cores.indigo100 : Cores.linha,
        foregroundColor: Cores.indigo700,
        child: Text(_inicial((u['nome'] ?? '') as String)),
      ),
      title: Text((u['nome'] ?? '') as String),
      subtitle: Text('$login\n$papeis'),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!ativo)
            const Chip(
              label: Text('Desativado'),
              visualDensity: VisualDensity.compact,
            ),
          if (vinculos.length > 1)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Tooltip(
                message: '${vinculos.length} empresas',
                child: const Icon(Icons.business, size: 18, color: Cores.neutro),
              ),
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: aoTocar,
    );
  }
}
