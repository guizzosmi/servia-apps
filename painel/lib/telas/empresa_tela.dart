import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


/// Escolha (ou troca) da empresa em que o usuário vai trabalhar.
/// Mostra todas as empresas em que ele tem vínculo ativo.
class EmpresaTela extends StatefulWidget {
  const EmpresaTela({super.key});

  @override
  State<EmpresaTela> createState() => _EmpresaTelaState();
}

class _Vinculo {
  _Vinculo(this.empresaId, this.nome, this.papeis);
  final String empresaId;
  final String nome;
  final List<String> papeis;

  bool get acessaPainel =>
      papeis.contains(Papel.admin) ||
      papeis.contains(Papel.gestor) ||
      papeis.contains(Papel.financeiro);
}

class _EmpresaTelaState extends State<EmpresaTela> {
  late Future<List<_Vinculo>> _carga = _carregar();
  String? _trocando;
  String? _erro;

  Future<List<_Vinculo>> _carregar() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return [];
    final linhas = await Supabase.instance.client
        .from('usuario_empresas')
        .select('empresa_id, papeis, empresas(razao_social, nome_fantasia, ativa, excluido_em)')
        .eq('usuario_id', uid)
        .eq('ativo', true);
    final lista = <_Vinculo>[];
    for (final l in linhas) {
      final e = l['empresas'] as Map<String, dynamic>?;
      if (e == null || e['ativa'] != true || e['excluido_em'] != null) continue;
      lista.add(_Vinculo(
        l['empresa_id'] as String,
        (e['nome_fantasia'] ?? e['razao_social'] ?? '') as String,
        ((l['papeis'] as List?) ?? const []).map((p) => p.toString()).toList(),
      ));
    }
    lista.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return lista;
  }

  Future<void> _escolher(_Vinculo v) async {
    setState(() {
      _trocando = v.empresaId;
      _erro = null;
    });
    try {
      final atual = Sessao.atual;
      if (atual?.empresaId != v.empresaId) {
        await Sessao.trocarEmpresa(v.empresaId);
      }
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _trocando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessao = Sessao.atual;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: FutureBuilder<List<_Vinculo>>(
                  future: _carga,
                  builder: (context, snap) {
                    final filhos = <Widget>[
                      const Marca(altura: 30),
                      const SizedBox(height: 8),
                      Text('Escolha a empresa',
                          style: Theme.of(context).textTheme.titleMedium),
                      if (sessao != null)
                        Text(sessao.email,
                            style: const TextStyle(color: Cores.neutro)),
                      const SizedBox(height: 16),
                    ];
                    if (snap.connectionState != ConnectionState.done) {
                      filhos.add(const Center(child: CircularProgressIndicator()));
                    } else if (snap.hasError) {
                      filhos.add(Text(mensagemDeErro(snap.error!),
                          style: const TextStyle(color: Cores.erro)));
                      filhos.add(TextButton(
                        onPressed: () => setState(() => _carga = _carregar()),
                        child: const Text('Tentar de novo'),
                      ));
                    } else if (snap.data!.isEmpty) {
                      filhos.add(const Text(
                          'Seu usuário não tem acesso ativo a nenhuma empresa. '
                          'Fale com o administrador da sua conta.'));
                    } else {
                      for (final v in snap.data!) {
                        final ativa = v.empresaId == sessao?.empresaId;
                        filhos.add(ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.business,
                              color: ativa ? Cores.indigo500 : Cores.neutro),
                          title: Text(v.nome),
                          subtitle: Text(v.acessaPainel
                              ? v.papeis.join(', ')
                              : 'Sem acesso ao painel (${v.papeis.join(', ')}) · use o app'),
                          enabled: v.acessaPainel && _trocando == null,
                          trailing: _trocando == v.empresaId
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : (ativa ? const Chip(label: Text('atual')) : null),
                          onTap: () => _escolher(v),
                        ));
                      }
                    }
                    if (_erro != null) {
                      filhos.add(Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_erro!, style: const TextStyle(color: Cores.erro)),
                      ));
                    }
                    filhos.add(const SizedBox(height: 16));
                    filhos.add(Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: Sessao.sair,
                        icon: const Icon(Icons.logout),
                        label: const Text('Sair'),
                      ),
                    ));
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: filhos,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
