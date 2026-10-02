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
  /// DOMINIO_EMAIL_APP das funções (padrão servia.app).
  static const dominioEmailApp = 'servia.app';

  /// Endereço da página de aceite do cliente (Firebase Hosting do projeto
  /// servia-ccdda). Com domínio próprio, troque aqui (ex.: https://aceite.servia.com.br).
  static const linkAceite = 'https://servia-ccdda.web.app';
}
