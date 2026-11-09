import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'acoes_orcamento.dart';
import 'arquivos.dart';
import 'banco_local.dart';
import 'eqp_dados.dart';
import 'estado.dart';
import 'resumo.dart';
import 'sincronizacao.dart';

/// Uma foto de equipamento tirada no app: o arquivo fica no aparelho até a
/// operação subir; [caminho] é onde ela fica na plataforma (bucket "fotos").
class FotoEqp {
  const FotoEqp({required this.local, required this.caminho});
  final String local;
  final String caminho;

  Map<String, dynamic> get anexo =>
      {'bucket': 'fotos', 'caminho': caminho, 'local': local, 'tipo': 'image/jpeg', 'pasta': 'equipamentos'};
}

/// Registros da Gestão de Equipamentos pelo app (guia 104). Como as outras
/// ações: entram na fila (com a hora do celular), mudam o aparelho na hora e
/// sobem quando houver internet. A plataforma confere tudo de novo, inclusive
/// a ordem dos eventos.
class AcoesEqp {
  AcoesEqp._();

  static const _uuid = Uuid();
  static EstadoApp get _estado => EstadoApp.instancia;
  static BancoLocal get _banco => _estado.banco!;
  static Sincronizador get _sync => _estado.sync!;

  static String novoId() => _uuid.v4();

  static String _pastaPlataforma(String id) {
    final conta = _estado.conta!;
    final agora = DateTime.now();
    return '${conta.contaId}/${conta.empresaId}/${agora.year}/${agora.month.toString().padLeft(2, '0')}/$id';
  }

  /// Foto pela câmera, reduzida (1600 px, JPEG), na pasta de equipamentos do app.
  static Future<FotoEqp?> tirarFoto() async {
    final foto = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, maxHeight: 1600, imageQuality: 70);
    if (foto == null) return null;
    final id = novoId();
    final pasta = await Arquivos.pastaEquipamentos();
    await pasta.create(recursive: true);
    final destino = p.join(pasta.path, 'eqp-$id.jpg');
    await File(destino).writeAsBytes(await foto.readAsBytes(), flush: true);
    return FotoEqp(local: destino, caminho: '${_pastaPlataforma('eqp-$id')}.jpg');
  }

  /// Aceite de quem recebe (ou devolve): o resumo em PDF com a assinatura,
  /// guardado no aparelho. Devolve o que vai na operação e os anexos.
  static Future<(Map<String, dynamic>, List<Map<String, dynamic>>)> aceite(ConteudoResumo conteudo, Decisao d) async {
    final id = novoId();
    final png = d.png ?? Uint8List(0);
    final pdf = await ResumoPdf.gerar(
      conteudo,
      RegistroAssinatura(
        nome: d.nome.trim(),
        documento: d.documento,
        png: d.png,
        decisao: 'ciente',
        em: DateTime.now(),
        tecnico: AcoesOrcamento.nomeDoTecnico,
      ),
    );
    final pasta = await Arquivos.pastaEquipamentos();
    await pasta.create(recursive: true);
    final localPng = p.join(pasta.path, 'aceite-$id-assinatura.png');
    final localPdf = p.join(pasta.path, 'aceite-$id-resumo.pdf');
    await File(localPng).writeAsBytes(png, flush: true);
    await File(localPdf).writeAsBytes(pdf, flush: true);
    final base = _pastaPlataforma(id);
    return (
      <String, dynamic>{
        'aceite_id': id,
        'nome': d.nome.trim(),
        if (d.documento != null && d.documento!.trim().isNotEmpty) 'documento_pessoa': d.documento!.trim(),
        'assinatura_caminho': '$base-assinatura.png',
        'resumo_caminho': '$base-resumo.pdf',
        'resumo_sha256': sha256.convert(pdf).toString(),
      },
      <Map<String, dynamic>>[
        {'bucket': 'assinaturas', 'caminho': '$base-assinatura.png', 'local': localPng, 'tipo': 'image/png', 'pasta': 'equipamentos'},
        {'bucket': 'assinaturas', 'caminho': '$base-resumo.pdf', 'local': localPdf, 'tipo': 'application/pdf', 'pasta': 'equipamentos'},
      ],
    );
  }

  /// Registra o evento (saída, chegada, transferência, recolher, retorno, mover, manutenção).
  /// [dados]: o que a plataforma recebe (eqp_app_registrar); [anexos]: os arquivos que sobem antes.
  static Future<void> registrar({
    required Map<String, dynamic> ficha,
    required String evento,
    required Map<String, dynamic> dados,
    required List<Map<String, dynamic>> anexos,
  }) async {
    final registroId = novoId();
    await _sync.registrar(
      'eqp_registrar',
      {
        ...dados,
        'registro_id': registroId,
        'equipamento_id': ficha['id'],
        'evento': evento,
        // Só para o app: os arquivos que sobem antes (a plataforma ignora).
        if (anexos.isNotEmpty) 'arquivos': anexos,
        // Para a tela de sincronização e a ficha (a plataforma ignora).
        'rotulo': '${eventosEqp[evento] ?? evento} · ${ficha['codigo']}',
      },
      aplicarLocal: () => _aplicarLocal(ficha, evento, dados),
    );
  }

  /// A ficha no aparelho já mostra o novo status (a próxima sincronização traz o da plataforma).
  static Future<void> _aplicarLocal(Map<String, dynamic> ficha, String evento, Map<String, dynamic> dados) async {
    final ativa = _banco.eqpReservaAtiva(ficha['id']);
    final reserva = _banco.um('eqp_reservas', dados['alocacao_id']);
    String status = '${ficha['status']}';
    Object? local = ficha['local_atual_id'];
    String? localNome = ficha['local_atual'] as String?;
    Object? com = ficha['com'];
    switch (evento) {
      case 'saida':
        status = dados['direto'] == true ? 'em_uso' : 'em_transito';
        if (reserva != null) {
          await _banco.alterar('eqp_reservas', reserva['id'], {'situacao': 'ativa'});
          local = reserva['local_id'];
          localNome = reserva['local'] as String?;
          com = reserva['com'];
        }
      case 'chegada':
        status = ativa != null ? 'em_uso' : 'retornado';
      case 'transferencia':
        status = dados['em_transito'] == true ? 'em_transito' : 'em_uso';
        if (reserva != null) {
          if (ativa != null) await _banco.apagarIds('eqp_reservas', ['${ativa['id']}']);
          await _banco.alterar('eqp_reservas', reserva['id'], {'situacao': 'ativa'});
          local = reserva['local_id'];
          localNome = reserva['local'] as String?;
          com = reserva['com'];
        } else if (dados['local_id'] != null) {
          local = dados['local_id'];
          localNome = _banco.um('locais', local)?['nome'] as String? ?? localNome;
        }
      case 'recolher':
      case 'retorno':
        status = evento == 'recolher' ? 'em_transito' : 'retornado';
        if (ativa != null) await _banco.apagarIds('eqp_reservas', ['${ativa['id']}']);
        local = dados['local_id'] ?? ficha['local_base_id'];
        localNome = _banco.um('eqp_locais', local)?['nome'] as String? ?? localNome;
        com = null;
      case 'mover':
        local = dados['local_id'] ?? local;
        localNome = _banco.um('eqp_locais', local)?['nome'] as String? ?? localNome;
      case 'iniciar_manutencao':
        status = 'em_manutencao';
    }
    await _banco.alterar('eqp_fichas', ficha['id'], {
      'status': status,
      'status_desde': DateTime.now().toUtc().toIso8601String(),
      'local_atual_id': local,
      'local_atual': localNome,
      'com': com,
      if (dados['leitura'] != null) 'leitura_atual': dados['leitura'],
    });
  }
}
