// O painel é só web: aqui é o lugar das APIs do navegador.
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:servia_comum/servia_comum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

/// Cobrança parametrizável (guia 100): o que as telas de títulos e da configuração usam em comum.
/// As regras ficam no banco (cobranca_bancaria_acao, cobranca_titulos_lista...) e a conversa com os bancos
/// (API e CNAB) na função "cobranca-bancaria".

const rotuloSituacaoTitulo = {
  'rascunho': 'Rascunho',
  'a_registrar': 'Indo para o banco',
  'registrado': 'Em aberto',
  'pago': 'Pago',
  'baixado': 'Baixado',
  'cancelado': 'Cancelado',
  'erro': 'Com erro',
};

const corSituacaoTitulo = {
  'rascunho': Cores.neutro,
  'a_registrar': Cores.info,
  'registrado': Cores.andamento,
  'pago': Cores.sucesso,
  'baixado': Cores.neutro,
  'cancelado': Cores.neutro,
  'erro': Cores.erro,
};

const rotuloModoCobranca = {
  'manual': 'Manual (como hoje)',
  'pix': 'Pix da empresa',
  'api': 'Boleto/Pix registrado por API do banco',
  'cnab': 'CNAB (arquivo de remessa e retorno)',
  'erp': 'Pelo ERP (Protheus)',
};

const rotuloViaTitulo = {
  'manual': 'Manual',
  'pix': 'Pix da empresa',
  'api': 'Banco (API)',
  'cnab': 'CNAB',
  'erp': 'ERP',
};

const rotuloOrigemTitulo = {
  'os': 'OS',
  'cobranca': 'A cobrar',
  'medicao': 'Medição',
  'locacao': 'Locação',
  'avulso': 'Avulso',
};

const nomesBancos = {
  '001': 'Banco do Brasil',
  '237': 'Bradesco',
  '033': 'Santander',
  '748': 'Sicredi',
  '208': 'BTG Pactual',
  '341': 'Itaú',
};

const rotuloFormaRecebimento = {
  'pix': 'Pix',
  'transferencia': 'Transferência',
  'dinheiro': 'Dinheiro',
  'boleto': 'Boleto',
  'cartao': 'Cartão',
  'outro': 'Outro',
};

Future<Map<String, dynamic>> _rpc(String funcao, [Map<String, dynamic>? p]) async {
  final r = await Supabase.instance.client.rpc(funcao, params: p == null ? null : {'p': p});
  return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
}

/// Configuração, contas de cobrança e bancos.
Future<Map<String, dynamic>> configCobranca() => _rpc('cobranca_config_ver');

/// Lista de títulos com os totais.
Future<Map<String, dynamic>> listaTitulos(Map<String, dynamic> filtros) => _rpc('cobranca_titulos_lista', filtros);

/// Título com a história (eventos) e a fila do banco.
Future<Map<String, dynamic>> verTitulo(String id) => _rpc('cobranca_titulo_ver', {'titulo_id': id});

/// Ações do banco de dados (emitir, cancelar, baixar, configurar...).
Future<Map<String, dynamic>> acaoCobranca(Map<String, dynamic> p) => _rpc('cobranca_bancaria_acao', p);

/// Chama a função "cobranca-bancaria" (registrar agora, remessa, retorno, credenciais, testar conexão).
Future<Map<String, dynamic>> funcaoCobranca(Map<String, dynamic> corpo) async {
  final r = await Supabase.instance.client.functions.invoke('cobranca-bancaria', body: corpo);
  final d = r.data;
  return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
}

/// Modo da empresa (guardado enquanto o painel está aberto; a tela de configuração renova).
class ModoCobranca {
  ModoCobranca._();

  static Future<String>? _modo;

  static Future<String> atual() => _modo ??= configCobranca().then((r) => '${(r['config'] as Map?)?['modo'] ?? 'manual'}');

  static void renovar() => _modo = null;
}

/// Baixa um arquivo de texto (remessa CNAB) no navegador.
void baixarArquivoTexto(String nome, String conteudo) {
  final bytes = latin1.encode(conteudo.replaceAll(RegExp(r'[^\x00-\xFF]'), ' '));
  final blob = web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: 'text/plain'));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = nome;
  a.click();
  web.URL.revokeObjectURL(url);
}

/// Selo colorido da situação do título.
class SeloTitulo extends StatelessWidget {
  const SeloTitulo(this.situacao, {super.key, this.vencido = false});

  final String situacao;
  final bool vencido;

  @override
  Widget build(BuildContext context) {
    final cor = vencido ? Cores.alerta : (corSituacaoTitulo[situacao] ?? Cores.neutro);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(vencido ? 'Vencido' : (rotuloSituacaoTitulo[situacao] ?? situacao),
          style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}
