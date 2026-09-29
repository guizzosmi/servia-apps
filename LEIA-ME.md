# servia-apps

Código Flutter do ServIA.

| Pasta | O que é | Como rodar |
| --- | --- | --- |
| `comum/` | Pacote compartilhado: tema e cores, endereço do Supabase, sessão (token, papéis, troca de empresa) e mensagens de erro | Não roda sozinho; é usado pelo painel e pelo app |
| `painel/` | Painel web do gestor (Flutter Web): login, escolha de empresa e cadastros | `cd painel` e `flutter run -d chrome --web-port 5000` |
| `app/` | App do técnico (Android), offline | Etapa 4 |

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
    lista.dart, campos.dart lista com busca e campos especiais (busca de registro, múltipla escolha)
```

Para criar um cadastro novo: crie a tabela no `servia-plataforma` (com `aplicar_padrao_empresa`)
e acrescente uma `CadastroDef` em `catalogo.dart`. Lista, busca, formulário, validação e
exclusão lógica já vêm prontos.
