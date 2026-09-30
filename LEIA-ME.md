# servia-apps

Código Flutter do ServIA.

| Pasta | O que é | Como rodar |
| --- | --- | --- |
| `comum/` | Pacote compartilhado: tema e cores, endereço do Supabase, sessão (token, papéis, troca de empresa) e mensagens de erro | Não roda sozinho; é usado pelo painel e pelo app |
| `painel/` | Painel web do gestor (Flutter Web): login, escolha de empresa e cadastros | `cd painel` e `flutter run -d chrome --web-port 5000` |
| `app/` | App do técnico (Android agora, iPhone depois), offline: parte do dia, serviço e sincronização | Celular no cabo: `cd app` e `flutter run` |

## Painel: onde fica cada coisa

```
painel/lib/
  main.dart                 liga o Supabase e abre o app
  rotas.dart                endereços das telas e regras de acesso (login, empresa, papel)
  telas/                    login, escolha de empresa, moldura com menu, início, lista e formulário
  cadastros/
    definicoes.dart         o "motor": tipos de campo, colunas, filhos
    catalogo.dart           a descrição de cada cadastro (tabela, colunas, campos)
    servico.dart            leitura e gravação no banco
    lista.dart, campos.dart lista com busca e campos especiais (busca de registro, múltipla escolha, cor)
  servicos/
    funcoes.dart            chamada das Edge Functions
    etiquetas_pdf.dart      PDF A4 das etiquetas QR
```

Telas fora do motor de cadastros: usuários e aparelhos (só o admin, gravam pelas funções
`usuarios-admin` e `dispositivo-acao`) e etiquetas QR.

Para criar um cadastro novo: crie a tabela no `servia-plataforma` (com `aplicar_padrao_empresa`)
e acrescente uma `CadastroDef` em `catalogo.dart`. Lista, busca, formulário, validação e
exclusão lógica já vêm prontos.

## App: onde fica cada coisa

```
app/lib/
  main.dart                 liga o Supabase (sessão no cofre do aparelho) e abre o app
  rotas.dart                login, hoje, serviço, sincronização, aparelho desconectado
  core/
    cofre.dart              cofre do aparelho: sessão, chave do banco, id do aparelho
    banco_local.dart        banco do celular criptografado (SQLCipher) e fila de ações
    sincronizacao.dart      envia a fila (sync_enviar) e baixa o que mudou (sync_baixar)
    estado.dart             login, registro do aparelho, sair
    consultas.dart          leituras prontas para as telas
  telas/, widgets/
```

Toda tela lê o banco do celular; toda ação vira uma operação na fila, com a mudança aplicada na
hora no banco local. A plataforma confere as regras quando a fila sobe.
