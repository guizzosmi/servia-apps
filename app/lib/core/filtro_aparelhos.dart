/// Busca de aparelhos (guia 108): o filtro, a ordem e o agrupamento por
/// ambiente, sem Flutter (testável com Dart puro). Tudo é comparado sem
/// acento e sem maiúscula.
library;

/// Minúsculas e sem acento ("Câmara" -> "camara").
String semAcento(Object? texto) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  final t = '${texto ?? ''}'.toLowerCase();
  final b = StringBuffer();
  for (final c in t.split('')) {
    final i = de.indexOf(c);
    b.write(i < 0 ? c : para[i]);
  }
  return b.toString();
}

/// Só letras e números ("AC-01" -> "ac01").
String _compacto(String texto) => semAcento(texto).replaceAll(RegExp(r'[^a-z0-9]'), '');

final _pedacos = RegExp(r'\d+|\D+');

/// Ordem natural do código: "AC-2" antes de "AC-10" (os números valem pelo valor).
int compararCodigo(Object? a, Object? b) {
  final x = semAcento(a).trim(), y = semAcento(b).trim();
  final px = _pedacos.allMatches(x).map((m) => m[0]!).toList();
  final py = _pedacos.allMatches(y).map((m) => m[0]!).toList();
  for (var i = 0; i < px.length && i < py.length; i++) {
    final c = _compararPedaco(px[i], py[i]);
    if (c != 0) return c;
  }
  if (px.length != py.length) return px.length.compareTo(py.length);
  return '${a ?? ''}'.compareTo('${b ?? ''}');
}

int _compararPedaco(String a, String b) {
  final na = RegExp(r'^\d+$').hasMatch(a), nb = RegExp(r'^\d+$').hasMatch(b);
  if (na && nb) {
    // Pelo valor, sem converter (o número pode ser maior que um int).
    final sa = a.replaceFirst(RegExp(r'^0+(?=\d)'), ''), sb = b.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (sa.length != sb.length) return sa.length.compareTo(sb.length);
    final c = sa.compareTo(sb);
    return c != 0 ? c : a.length.compareTo(b.length);
  }
  if (na != nb) return na ? -1 : 1; // número antes de letra
  return a.compareTo(b);
}

/// Unidades da capacidade (mesmos códigos do banco).
const unidadesCapacidade = {'btu_h': 'BTU/h', 'tr': 'TR', 'kw': 'kW'};

/// Nome do ambiente com o setor/andar ("Câmara fria 1 · Térreo"); '' sem ambiente.
String nomeDoAmbiente(Map? ambiente) => ambiente == null
    ? ''
    : [ambiente['nome'], ambiente['setor_andar']]
        .where((x) => x != null && '$x'.trim().isNotEmpty)
        .map((x) => '$x'.trim())
        .join(' · ');

/// 12000.0 -> 12000; 1.5 fica.
num _semDecimal(num n) => n == n.roundToDouble() ? n.toInt() : n;

/// Número digitado ("12", "12000", "12.000", "1,5"); null se não é número.
num? _numeroDigitado(String palavra) {
  if (RegExp(r'^\d+$').hasMatch(palavra)) return num.tryParse(palavra);
  // Milhar com ponto: 12.000, 1.500.000
  if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(palavra)) return num.tryParse(palavra.replaceAll('.', ''));
  if (RegExp(r'^\d+[.,]\d+$').hasMatch(palavra)) return num.tryParse(palavra.replaceAll(',', '.'));
  return null;
}

/// Código no formato "letras + número" ("ac-12", "ac12", "ac 012"): (letras, número).
(String, String)? _codigoComNumero(String texto) {
  final m = RegExp(r'^([a-z]+)[\s\-_/.]*(\d+)$').firstMatch(texto.trim());
  if (m == null) return null;
  return (m[1]!, m[2]!.replaceFirst(RegExp(r'^0+(?=\d)'), ''));
}

/// O aparelho combina com a busca? Cada palavra digitada precisa aparecer em
/// algum campo: código, ambiente e setor/andar, descrição, marca, modelo,
/// capacidade e nº de série. Um número sozinho ("12") vale o número do código
/// (AC-12, AC-012), do ambiente ("Sala 12") ou a capacidade inteira (12000 ou
/// 12.000), não um pedaço de outro número; com 4 dígitos ou mais vale também
/// dentro do nº de série e do modelo. Um código com número ("AC-12") acha o
/// AC-12, não o AC-120.
bool aparelhoCombina(Map aparelho, String busca, {Map? ambiente}) {
  final palavras = semAcento(busca).split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (palavras.isEmpty) return true;
  final codigo = semAcento(aparelho['codigo']).trim();
  final capacidade = num.tryParse('${aparelho['capacidade_valor'] ?? ''}');
  final unidade = unidadesCapacidade[aparelho['capacidade_unidade']] ?? '';
  final outros = <String>[
    for (final c in const ['descricao', 'marca', 'modelo', 'numero_serie', 'codigo_barras'])
      if (aparelho[c] != null) semAcento(aparelho[c]),
    if (ambiente != null) semAcento(ambiente['nome']),
    if (ambiente != null) semAcento(ambiente['setor_andar']),
    if (capacidade != null) semAcento('${_semDecimal(capacidade)} $unidade'),
  ].where((x) => x.trim().isNotEmpty).toList();
  final todos = [codigo, ...outros];

  bool palavraCombina(String p) {
    final n = _numeroDigitado(p);
    if (n != null) {
      if (capacidade != null && capacidade == n) return true;
      // Os números do código (todos os pedaços) e as palavras só de números dos outros campos.
      final numerosDoCodigo = RegExp(r'\d+').allMatches(codigo).map((m) => num.parse(m[0]!));
      if (numerosDoCodigo.any((x) => x == n)) return true;
      for (final t in outros) {
        for (final w in RegExp(r'[a-z0-9]+').allMatches(t)) {
          final palavra = w[0]!;
          if (RegExp(r'^\d+$').hasMatch(palavra) && num.parse(palavra) == n) return true;
        }
      }
      final digitos = p.replaceAll(RegExp(r'\D'), '');
      return digitos.length >= 4 && todos.any((t) => _compacto(t).contains(digitos));
    }
    final procurado = _codigoComNumero(p);
    final doCodigo = _codigoComNumero(codigo);
    if (procurado != null && doCodigo != null && procurado.$1 == doCodigo.$1) {
      // Código com o mesmo prefixo: vale o número inteiro (AC-12 não acha AC-120).
      if (procurado.$2 == doCodigo.$2) return true;
      return outros.any((t) => t.contains(p));
    }
    if (todos.any((t) => t.contains(p))) return true;
    final c = _compacto(p);
    return c.length >= 2 && todos.any((t) => _compacto(t).contains(c));
  }

  return palavras.every(palavraCombina);
}

/// Os aparelhos que combinam com a busca (na ordem em que vieram).
/// [ambienteDe]: o ambiente de um ambiente_id (ou null).
List<Map<String, dynamic>> filtrarAparelhos(
  Iterable<Map<String, dynamic>> aparelhos,
  String busca,
  Map<String, dynamic>? Function(Object? ambienteId) ambienteDe,
) =>
    [
      for (final e in aparelhos)
        if (aparelhoCombina(e, busca, ambiente: ambienteDe(e['ambiente_id']))) e,
    ];

/// Aparelhos de um ambiente, para a lista agrupada.
class GrupoAparelhos {
  const GrupoAparelhos(this.ambienteId, this.nome, this.aparelhos);

  /// null = sem ambiente.
  final String? ambienteId;

  /// "Câmara fria 1 · Térreo" ('' = sem ambiente).
  final String nome;
  final List<Map<String, dynamic>> aparelhos;
}

/// Agrupa por ambiente (pelo nome, na ordem natural; os sem ambiente por
/// último) e ordena cada grupo pelo código natural (AC-2 antes de AC-10).
List<GrupoAparelhos> agruparPorAmbiente(
  Iterable<Map<String, dynamic>> aparelhos,
  Map<String, dynamic>? Function(Object? ambienteId) ambienteDe,
) {
  final grupos = <String, List<Map<String, dynamic>>>{};
  final nomes = <String, String>{};
  for (final e in aparelhos) {
    final amb = e['ambiente_id'] == null ? null : ambienteDe(e['ambiente_id']);
    final chave = amb == null ? '' : '${e['ambiente_id']}';
    grupos.putIfAbsent(chave, () => []).add(e);
    nomes[chave] = nomeDoAmbiente(amb);
  }
  final chaves = grupos.keys.toList()
    ..sort((a, b) {
      if (a.isEmpty || b.isEmpty) return a.isEmpty == b.isEmpty ? 0 : (a.isEmpty ? 1 : -1);
      final c = compararCodigo(nomes[a], nomes[b]);
      return c != 0 ? c : a.compareTo(b);
    });
  return [
    for (final k in chaves)
      GrupoAparelhos(k.isEmpty ? null : k, nomes[k] ?? '',
          grupos[k]!..sort((x, y) => compararCodigo(x['codigo'], y['codigo']))),
  ];
}

/// O que vale na etiqueta lida: o texto inteiro ou, num link (`…/q/<token>`), o último pedaço.
List<String> valoresDaEtiqueta(String lido) {
  final inteiro = lido.trim().toLowerCase();
  final caminho = inteiro.split(RegExp(r'[?#]')).first;
  final ultimo =
      caminho.contains('/') ? (caminho.split('/').where((x) => x.isNotEmpty).lastOrNull ?? inteiro) : inteiro;
  return {inteiro, ultimo}.where((x) => x.isNotEmpty).toList();
}

/// Aparelhos desta etiqueta: o QR primeiro, depois o código e o código de
/// barras e, por último, o código sem os sinais ("ac01" acha "AC-01").
/// Os excluídos não contam.
List<Map<String, dynamic>> aparelhosDaEtiqueta(Iterable<Map<String, dynamic>> aparelhos, String lido) {
  final valores = valoresDaEtiqueta(lido);
  if (valores.isEmpty) return const [];
  final vivos = aparelhos.where((e) => e['excluido_em'] == null).toList();
  String campo(Map e, String c) => '${e[c] ?? ''}'.trim().toLowerCase();
  final compactos = valores.map(_compacto).where((x) => x.isNotEmpty).toSet();
  for (final regra in <bool Function(Map)>[
    (e) => valores.contains(campo(e, 'qr_token')),
    (e) => valores.contains(campo(e, 'codigo')),
    (e) => valores.contains(campo(e, 'codigo_barras')),
    (e) => compactos.contains(_compacto(campo(e, 'codigo'))),
  ]) {
    final achados = vivos.where(regra).toList();
    if (achados.isNotEmpty) return achados;
  }
  return const [];
}

/// "Com a Equipe Sul, dia 09/11 (líder Ana)": onde está a OS do aparelho que
/// está com outra equipe (a consulta com internet, guia 108).
String textoComOutraEquipe(Map os) {
  final d = '${os['data'] ?? ''}';
  final dia = d.length >= 10 ? '${d.substring(8, 10)}/${d.substring(5, 7)}' : '';
  final equipe = '${os['equipe'] ?? ''}'.trim();
  final lider = '${os['lider'] ?? ''}'.trim();
  final onde = [equipe.isEmpty ? 'Com outra equipe' : 'Com a $equipe', if (dia.isNotEmpty) 'dia $dia'].join(', ');
  return lider.isEmpty ? onde : '$onde (líder $lider)';
}

/// Os aparelhos da OS para a mensagem ao cliente ("Estou a caminho"): código, descrição e ambiente.
/// Um aparelho: "Aparelho: AC-03 · Split TCL 12.000 BTU/h · Câmara fria 2". Até [limite]: "Aparelhos:" e um
/// por linha, em ordem de código. Sem aparelho ou com mais que [limite] (ex.: a OS do PMOC, com todos os
/// aparelhos do local): '' (a linha some da mensagem).
String textoDosAparelhos(List<Map> aparelhos, Map? Function(Object? ambienteId) ambienteDe, {int limite = 3}) {
  if (aparelhos.isEmpty || aparelhos.length > limite) return '';
  final ordem = [...aparelhos]..sort((a, b) => compararCodigo(a['codigo'], b['codigo']));
  String linha(Map a) {
    final descricao = '${a['descricao'] ?? ''}'.trim().isNotEmpty
        ? '${a['descricao']}'.trim()
        : [a['marca'], a['modelo']].where((x) => x != null && '$x'.trim().isNotEmpty).join(' ');
    return [a['codigo'], descricao, nomeDoAmbiente(ambienteDe(a['ambiente_id']))]
        .where((x) => x != null && '$x'.trim().isNotEmpty)
        .map((x) => '$x'.trim())
        .join(' · ');
  }
  if (ordem.length == 1) return 'Aparelho: ${linha(ordem.first)}';
  return 'Aparelhos:\n${ordem.map((a) => '- ${linha(a)}').join('\n')}';
}
