# Página de aceite do cliente

Página pública, leve (HTML e JavaScript, sem o Flutter), onde o cliente abre o
link do orçamento, vê os itens e o PDF e aprova ou recusa:

    https://aceite.servpilot.com.br/a/<token>

(o endereço antigo, https://servia-ccdda.web.app/a/<token>, continua valendo).

Ela fala só com a Edge Function `aceite-publico` (pasta servia-plataforma).
Hospedada no Firebase Hosting do projeto `servia-ccdda`; quem publica é a
esteira (`.\atualizar`, etapa "Página de aceite"), só quando algo aqui muda.

Domínio próprio: aceite.servpilot.com.br, ligado no Firebase (Hosting > site
servia-ccdda > domínio personalizado) com os registros no Registro.br (guia 22b).
O link que o painel gera vem de `linkAceite` em
servia-apps/comum/lib/src/config.dart.
