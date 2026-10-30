/// Endereço da plataforma (Supabase) e chave pública.
///
/// A chave publishable é PÚBLICA: pode ficar dentro do app e do painel.
/// NUNCA coloque aqui a secret key nem a senha do banco.
///
/// Ambientes (guia 40): sem nada, o app e o painel usam o projeto de
/// desenvolvimento (servia-dev). A versão de produção é gerada com
/// `--dart-define-from-file=ambientes/prod.json` (a esteira faz isso com
/// `-Ambiente prod`), que troca o endereço e a chave pública.
class Config {
  static const ambiente = String.fromEnvironment('AMBIENTE', defaultValue: 'dev');
  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://srtokvosnwtyewiempyw.supabase.co');
  static const supabaseChavePublica =
      String.fromEnvironment('SUPABASE_CHAVE_PUBLICA', defaultValue: 'sb_publishable_qUKXkM5nd3KhUgOc8Auk9A_g9K2xxrH');

  /// true na versão de produção (sem a faixa "Teste" e com o envio de erros).
  static bool get producao => ambiente == 'prod';

  /// Lojas (guia 41): onde o técnico atualiza o app quando a versão dele
  /// fica abaixo da mínima.
  static const linkLojaAndroid = 'https://play.google.com/store/apps/details?id=app.servia.servia_app';
  static const linkLojaIphone = 'https://apps.apple.com/app/servpilot/id0000000000';

  /// Domínio dos e-mails técnicos do login por matrícula + PIN
  /// (`<matricula>@<codigo-da-conta>.<dominio>`). Igual ao segredo
  /// DOMINIO_EMAIL_APP das funções (padrão app.servpilot.com.br). Ninguém
  /// recebe e-mail nesse endereço: é só a forma de o Supabase guardar o login.
  static const dominioEmailApp = 'app.servpilot.com.br';

  /// Endereço da página de aceite do cliente (Firebase Hosting do projeto
  /// servia-ccdda, site servia-ccdda, com o domínio próprio).
  static const linkAceite = 'https://aceite.servpilot.com.br';

  /// Endereço do painel publicado (Firebase Hosting, site servpilot-painel).
  static const linkPainel = 'https://painel.servpilot.com.br';
}
