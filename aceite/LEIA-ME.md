# Página de aceite do cliente

Página pública, leve (HTML e JavaScript, sem o Flutter), onde o cliente abre o
link do orçamento, vê os itens e o PDF e aprova ou recusa:

    https://servia-ccdda.web.app/a/<token>

Ela fala só com a Edge Function `aceite-publico` (pasta servia-plataforma).
Hospedada no Firebase Hosting do projeto `servia-ccdda`; quem publica é a
esteira (`.\atualizar`, etapa "Página de aceite"), só quando algo aqui muda.

Domínio próprio: quando houver (ex.: aceite.servia.com.br), é só ligar no
Firebase (Hosting > Adicionar domínio personalizado) e trocar `linkAceite` em
servia-apps/comum/lib/src/config.dart.
