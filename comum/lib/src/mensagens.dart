import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'tema.dart';

/// Um modelo de mensagem do WhatsApp (nível 1: o aparelho abre o WhatsApp
/// com o texto pronto e a pessoa só confere e envia).
class ModeloMensagem {
  const ModeloMensagem({
    required this.chave,
    required this.titulo,
    required this.onde,
    required this.campos,
    required this.padrao,
  });

  final String chave;
  final String titulo;

  /// Onde aparece (para o admin saber o que está editando).
  final String onde;

  /// Campos que este modelo conhece, sem as chaves: contato, os...
  final List<String> campos;

  /// Texto padrão (vale enquanto a empresa não mudar).
  final String padrao;
}

/// O que cada campo vira na mensagem (ajuda da tela de Configurações).
const camposMensagem = <String, String>{
  'contato': 'primeiro nome de quem recebe',
  'empresa': 'nome da empresa',
  'tecnico': 'quem está mandando (app)',
  'os': 'número da OS',
  'cliente': 'nome do cliente',
  'local': 'nome do local',
  'endereco': 'endereço do local',
  'data': 'data da visita',
  'horario': 'janela de horário da visita',
  'orcamento': 'número do orçamento',
  'total': 'valor do orçamento',
  'validade': 'validade do orçamento',
  'resumo': 'o que foi feito (solução)',
  'link': 'link para o cliente',
};

/// Os modelos. O texto padrão fica aqui; a empresa guarda só o que mudou
/// (empresa_config.parametros.mensagens.<chave>).
///
/// Regra do texto: uma linha com um campo vazio some inteira (ex.: sem
/// link, a linha do link não aparece).
const modelosMensagem = <ModeloMensagem>[
  ModeloMensagem(
    chave: 'a_caminho',
    titulo: 'Estou a caminho',
    onde: 'App: ao tocar em "Estou a caminho"',
    campos: ['contato', 'tecnico', 'empresa', 'os', 'cliente', 'local', 'endereco'],
    padrao: 'Olá, {contato}!\n'
        'Aqui é {tecnico}, da {empresa}. Estou a caminho para o atendimento da {os} em {local}.\n'
        'Até já!',
  ),
  ModeloMensagem(
    chave: 'visita_agendada',
    titulo: 'Visita agendada',
    onde: 'Painel: na OS, em cada agendamento',
    campos: ['contato', 'empresa', 'os', 'cliente', 'local', 'endereco', 'data', 'horario'],
    padrao: 'Olá, {contato}!\n'
        'A visita da {empresa} para a {os} em {local} está agendada para {data}.\n'
        'Horário: {horario}.\n'
        'Qualquer dúvida, é só responder esta mensagem.',
  ),
  ModeloMensagem(
    chave: 'orcamento_link',
    titulo: 'Link do orçamento',
    onde: 'Painel e app: orçamento enviado',
    campos: ['contato', 'empresa', 'tecnico', 'os', 'cliente', 'local', 'orcamento', 'total', 'validade', 'link'],
    padrao: 'Olá, {contato}!\n'
        'Segue o orçamento {orcamento} da {empresa} ({os}), no valor de {total}, válido até {validade}.\n'
        'Para ver os detalhes e aprovar: {link}',
  ),
  ModeloMensagem(
    chave: 'concluido',
    titulo: 'Serviço concluído',
    onde: 'App: ao concluir o atendimento',
    campos: ['contato', 'empresa', 'tecnico', 'os', 'cliente', 'local', 'resumo', 'link'],
    padrao: 'Olá, {contato}!\n'
        'O atendimento da {os} em {local} foi concluído.\n'
        'O que foi feito: {resumo}\n'
        'Relatório do serviço: {link}\n'
        'Obrigado, {empresa}.',
  ),
  ModeloMensagem(
    chave: 'os_relatorio',
    titulo: 'Relatório da OS (para imprimir)',
    onde: 'Painel: na OS, botão do relatório',
    campos: ['contato', 'empresa', 'os', 'cliente', 'local', 'link'],
    padrao: 'Olá, {contato}!\n'
        'Segue o relatório da {os} ({local}), da {empresa}, para consultar ou imprimir:\n'
        '{link}',
  ),
];

ModeloMensagem? modeloMensagem(String chave) {
  for (final m in modelosMensagem) {
    if (m.chave == chave) return m;
  }
  return null;
}

/// O texto do modelo: o da empresa (se ela mudou) ou o padrão.
String textoDoModelo(String chave, Map? daEmpresa) {
  final proprio = daEmpresa?[chave];
  if (proprio is String && proprio.trim().isNotEmpty) return proprio;
  return modeloMensagem(chave)?.padrao ?? '';
}

final _campo = RegExp(r'\{(\w+)\}');

/// Preenche os campos {nome} do modelo. Linha com um campo vazio some;
/// campo desconhecido fica como está (para quem editou perceber).
String montarMensagem(String modelo, Map<String, String?> valores) {
  final linhas = <String>[];
  for (final linha in modelo.split('\n')) {
    var vazia = false;
    final pronta = linha.replaceAllMapped(_campo, (m) {
      final chave = m.group(1)!;
      if (!valores.containsKey(chave)) return m.group(0)!;
      final v = (valores[chave] ?? '').trim();
      if (v.isEmpty) vazia = true;
      return v;
    });
    if (!vazia) linhas.add(pronta.trimRight());
  }
  return linhas.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

const _diasDaSemana = ['segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado', 'domingo'];

/// '2026-11-05' -> 'quinta-feira, 05/11/2026' (para a mensagem da visita).
String dataPorExtenso(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  String dd(int n) => n.toString().padLeft(2, '0');
  return '${_diasDaSemana[d.weekday - 1]}, ${dd(d.day)}/${dd(d.month)}/${d.year}';
}

/// Primeiro nome (para a saudação).
String primeiroNome(String? nome) => (nome ?? '').trim().split(RegExp(r'\s+')).first;

/// Telefone para o WhatsApp: só números, com o 55 do Brasil. null = inválido.
String? telefoneWhatsApp(String? telefone) {
  final n = (telefone ?? '').replaceAll(RegExp(r'\D'), '');
  if (n.length == 10 || n.length == 11) return '55$n';
  if ((n.length == 12 || n.length == 13) && n.startsWith('55')) return n;
  return null;
}

/// Telefone para ler: (45) 99999-8888.
String telefoneBr(String? telefone) {
  final n = (telefone ?? '').replaceAll(RegExp(r'\D'), '');
  final s = n.length > 11 && n.startsWith('55') ? n.substring(2) : n;
  if (s.length == 11) return '(${s.substring(0, 2)}) ${s.substring(2, 7)}-${s.substring(7)}';
  if (s.length == 10) return '(${s.substring(0, 2)}) ${s.substring(2, 6)}-${s.substring(6)}';
  return telefone ?? '';
}

/// Endereço do WhatsApp com o texto. Sem telefone, a pessoa escolhe o
/// contato dentro do WhatsApp.
Uri linkWhatsApp(String? telefone, String texto) {
  final t = telefoneWhatsApp(telefone);
  return Uri.parse('https://wa.me/${t ?? ''}?text=${Uri.encodeComponent(texto)}');
}

/// O que foi compartilhado (para registrar na plataforma).
class EnvioWhatsApp {
  const EnvioWhatsApp({this.contatoId, this.nome, this.destino, required this.texto, required this.meio});

  final String? contatoId;
  final String? nome;

  /// Telefone só com números (sem o 55), ou null quando escolhido no WhatsApp.
  final String? destino;
  final String texto;

  /// whatsapp | copiada
  final String meio;

  Map<String, dynamic> paraRegistro() => {
        if (contatoId != null) 'contato_id': contatoId,
        if (contatoId == null && (nome ?? '').trim().isNotEmpty) 'destino_nome': nome!.trim(),
        if (destino != null) 'destino': destino,
        'texto': texto,
        'meio': meio,
      };
}

/// Abre a folha "Mandar pelo WhatsApp": escolhe para quem (contatos do
/// cliente, outro número ou escolher no WhatsApp), mostra a mensagem pronta
/// (dá para editar) e abre o WhatsApp ou copia o texto.
///
/// [montarTexto] recebe o primeiro nome de quem vai receber (vazio se não
/// souber) e devolve o texto. Com [link], aparece também "Copiar só o link"
/// (para mandar por e-mail, por exemplo). Volta null se a pessoa desistiu.
Future<EnvioWhatsApp?> compartilharWhatsApp(
  BuildContext context, {
  required String titulo,
  required List<Map<String, dynamic>> contatos,
  String? contatoInicialId,
  required String Function(String primeiroNome) montarTexto,
  String? link,
  String? aviso,
}) =>
    showDialog<EnvioWhatsApp>(
      context: context,
      builder: (_) => _FolhaWhatsApp(
        titulo: titulo,
        contatos: contatos,
        contatoInicialId: contatoInicialId,
        montarTexto: montarTexto,
        link: link,
        aviso: aviso,
      ),
    );

class _FolhaWhatsApp extends StatefulWidget {
  const _FolhaWhatsApp({
    required this.titulo,
    required this.contatos,
    required this.contatoInicialId,
    required this.montarTexto,
    required this.link,
    required this.aviso,
  });

  final String titulo;
  final List<Map<String, dynamic>> contatos;
  final String? contatoInicialId;
  final String Function(String primeiroNome) montarTexto;
  final String? link;
  final String? aviso;

  @override
  State<_FolhaWhatsApp> createState() => _FolhaWhatsAppState();
}

class _FolhaWhatsAppState extends State<_FolhaWhatsApp> {
  static const _outro = 'outro';
  static const _escolher = 'escolher';

  final _texto = TextEditingController();
  final _numero = TextEditingController();
  final _nome = TextEditingController();
  late String _para;
  bool _editado = false;
  String? _erro;

  List<Map<String, dynamic>> get _comTelefone =>
      widget.contatos.where((c) => telefoneWhatsApp(c['telefone'] as String?) != null).toList();

  Map<String, dynamic>? get _contato {
    for (final c in widget.contatos) {
      if (c['id'] == _para) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final comTelefone = _comTelefone;
    final inicial = comTelefone.where((c) => c['id'] == widget.contatoInicialId).firstOrNull ?? comTelefone.firstOrNull;
    _para = inicial == null ? _escolher : '${inicial['id']}';
    _montar();
  }

  @override
  void dispose() {
    _texto.dispose();
    _numero.dispose();
    _nome.dispose();
    super.dispose();
  }

  String get _nomeDestino => _para == _outro ? _nome.text : '${_contato?['nome'] ?? ''}';

  /// Refaz o texto com o nome de quem recebe (se a pessoa não editou).
  void _montar() {
    if (_editado) return;
    _texto.text = widget.montarTexto(primeiroNome(_nomeDestino));
  }

  void _escolherPara(String para) => setState(() {
        _para = para;
        _erro = null;
        _montar();
      });

  EnvioWhatsApp? _envio(String meio) {
    final texto = _texto.text.trim();
    if (texto.isEmpty) {
      setState(() => _erro = 'A mensagem está vazia.');
      return null;
    }
    String? destino;
    String? contatoId;
    String? nome;
    if (_para == _outro) {
      final t = telefoneWhatsApp(_numero.text);
      if (t == null) {
        setState(() => _erro = 'Digite o celular com DDD (ex.: 45 99999-8888).');
        return null;
      }
      destino = t.substring(2);
      nome = _nome.text.trim();
    } else if (_para != _escolher) {
      final c = _contato;
      contatoId = c?['id'] as String?;
      nome = c?['nome'] as String?;
      destino = telefoneWhatsApp(c?['telefone'] as String?)?.substring(2);
    }
    return EnvioWhatsApp(contatoId: contatoId, nome: nome, destino: destino, texto: texto, meio: meio);
  }

  Future<void> _abrir() async {
    final e = _envio('whatsapp');
    if (e == null) return;
    bool ok;
    try {
      ok = await launchUrl(linkWhatsApp(e.destino, e.texto), mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() => _erro = 'Não deu para abrir o WhatsApp. Use "Copiar" e cole a mensagem.');
      return;
    }
    Navigator.of(context).pop(e);
  }

  Future<void> _copiar() async {
    final e = _envio('copiada');
    if (e == null) return;
    await Clipboard.setData(ClipboardData(text: e.texto));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Mensagem copiada.')));
    Navigator.of(context).pop(e);
  }

  Widget _opcao(String valor, String titulo, {String? subtitulo, bool ativo = true, Widget? aviso}) {
    final marcada = _para == valor;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      enabled: ativo,
      leading: Icon(marcada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: marcada ? Cores.indigo500 : Cores.neutro),
      title: Text(titulo),
      subtitle: subtitulo == null && aviso == null
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (subtitulo != null) Text(subtitulo),
              if (aviso != null) aviso,
            ]),
      onTap: ativo ? () => _escolherPara(valor) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('PARA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Cores.neutro)),
          for (final c in widget.contatos)
            _opcao(
              '${c['id']}',
              '${c['nome']}',
              subtitulo: telefoneWhatsApp(c['telefone'] as String?) == null
                  ? 'sem celular cadastrado'
                  : telefoneBr(c['telefone'] as String?),
              ativo: telefoneWhatsApp(c['telefone'] as String?) != null,
              aviso: c['aceita_whatsapp'] == false && telefoneWhatsApp(c['telefone'] as String?) != null
                  ? const Text('Não marcou que aceita WhatsApp', style: TextStyle(color: Cores.alerta, fontSize: 12))
                  : null,
            ),
          _opcao(_outro, 'Outro número'),
          if (_para == _outro)
            Padding(
              padding: const EdgeInsets.only(left: 40, bottom: 8),
              child: Column(children: [
                TextField(
                  controller: _numero,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Celular com DDD', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nome,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nome (opcional)', isDense: true),
                  onChanged: (_) => setState(_montar),
                ),
              ]),
            ),
          _opcao(_escolher, 'Escolher no WhatsApp', subtitulo: 'O WhatsApp abre para você escolher o contato'),
          const SizedBox(height: 12),
          TextField(
            controller: _texto,
            minLines: 4,
            maxLines: 12,
            maxLength: 4000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Mensagem',
              alignLabelWithHint: true,
              helperText: _editado ? 'Editada por você' : 'Pode editar antes de mandar',
            ),
            onChanged: (_) {
              if (!_editado) setState(() => _editado = true);
            },
          ),
          if (widget.aviso != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(widget.aviso!, style: const TextStyle(fontSize: 12, color: Cores.neutro)),
            ),
          if (_erro != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_erro!, style: const TextStyle(color: Cores.erro)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        if (widget.link != null)
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.link!));
              if (!context.mounted) return;
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Link copiado.')));
            },
            icon: const Icon(Icons.link, size: 18),
            label: const Text('Copiar só o link'),
          ),
        TextButton.icon(onPressed: _copiar, icon: const Icon(Icons.copy, size: 18), label: const Text('Copiar')),
        FilledButton.icon(
          onPressed: _abrir,
          icon: const Icon(Icons.send, size: 18),
          label: const Text('Abrir WhatsApp'),
        ),
      ],
    );
  }
}
