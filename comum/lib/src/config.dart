/// Endereço da plataforma (Supabase) e chave pública.
///
/// A chave publishable é PÚBLICA: pode ficar dentro do app e do painel.
/// NUNCA coloque aqui a secret key nem a senha do banco.
class Config {
  static const supabaseUrl = 'https://srtokvosnwtyewiempyw.supabase.co';
  static const supabaseChavePublica =
      'sb_publishable_qUKXkM5nd3KhUgOc8Auk9A_g9K2xxrH';

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
