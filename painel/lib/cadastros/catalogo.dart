import 'package:flutter/material.dart';

import 'definicoes.dart';

/// Todos os cadastros do painel. Para criar um cadastro novo basta
/// acrescentar uma CadastroDef aqui (e a tabela no banco, com RLS).

// ---------- listas de opções (iguais aos "check" do banco) ----------

const _tiposCliente = [Opcao('pj', 'Pessoa jurídica'), Opcao('pf', 'Pessoa física')];

// Mesmos códigos de mensagem_modelos.evento (ver "Notificações e mensagens").
const _avisos = [
  Opcao('visita_agendada', 'Visita agendada'),
  Opcao('a_caminho', 'Técnico a caminho'),
  Opcao('orcamento', 'Orçamento'),
  Opcao('lembrete_orcamento', 'Lembrete de orçamento'),
  Opcao('concluido', 'Serviço concluído'),
  Opcao('preventiva_realizada', 'Preventiva realizada'),
];

const _funcoesContato = [
  Opcao('aprovador', 'Aprova orçamentos'),
  Opcao('recebe_relatorio', 'Recebe relatórios'),
  Opcao('financeiro', 'Financeiro'),
  Opcao('acompanhamento', 'Acompanha atendimentos'),
];

const _categoriasTipo = [
  Opcao('climatizacao', 'Climatização'),
  Opcao('refrigeracao', 'Refrigeração'),
  Opcao('eletrica', 'Elétrica'),
  Opcao('mecanica', 'Mecânica'),
  Opcao('outro', 'Outro'),
];

const _unidadesMedicao = [
  Opcao('psi', 'psi'),
  Opcao('bar', 'bar'),
  Opcao('c', '°C'),
  Opcao('a', 'A (corrente)'),
  Opcao('v', 'V (tensão)'),
  Opcao('kg', 'kg'),
  Opcao('outro', 'Outra'),
];

const _tiposValor = [
  Opcao('numero', 'Número'),
  Opcao('texto', 'Texto'),
  Opcao('sim_nao', 'Sim/Não'),
];

const _unidadesCapacidade = [
  Opcao('btu_h', 'BTU/h'),
  Opcao('tr', 'TR'),
  Opcao('kw', 'kW'),
  Opcao('outro', 'Outra'),
];

const _situacoesEquip = [
  Opcao('ativo', 'Ativo'),
  Opcao('inativo', 'Inativo'),
  Opcao('removido', 'Removido'),
];

const _tiposProduto = [Opcao('produto', 'Produto'), Opcao('servico', 'Serviço')];

const _funcoesColab = [
  Opcao('tecnico', 'Técnico'),
  Opcao('ajudante', 'Ajudante'),
  Opcao('lider', 'Líder'),
  Opcao('outro', 'Outro'),
];

const _baseComissao = [
  Opcao('servico', 'Serviços'),
  Opcao('produto', 'Produtos'),
  Opcao('ambos', 'Serviços e produtos'),
];

const _momentoComissao = [
  Opcao('fechamento_os', 'No fechamento do atendimento'),
  Opcao('recebimento', 'No recebimento'),
];

const _papelMembro = [Opcao('lider', 'Líder'), Opcao('membro', 'Membro')];

const _categoriasGlossario = [
  Opcao('jargao', 'Jargão'),
  Opcao('peca', 'Peça'),
  Opcao('cliente', 'Cliente'),
  Opcao('local', 'Local'),
];

const _ufs = [
  'AC', 'AL', 'AM', 'AP', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MG', 'MS', 'MT', 'PA',
  'PB', 'PE', 'PI', 'PR', 'RJ', 'RN', 'RO', 'RR', 'RS', 'SC', 'SE', 'SP', 'TO',
];

final _opcoesUf = [for (final u in _ufs) Opcao(u, u)];

String? _codigoMedicao(Object? v) {
  final s = (v ?? '').toString();
  if (s.isEmpty) return null;
  return RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(s)
      ? null
      : 'Use letras minúsculas, números e _ (ex.: pressao_succao)';
}

// ---------- cadastros ----------

final List<CadastroDef> catalogo = [
  CadastroDef(
    chave: 'clientes',
    tabela: 'clientes',
    titulo: 'Clientes',
    singular: 'Cliente',
    icone: Icons.people_alt_outlined,
    colunasBusca: const ['nome', 'nome_fantasia', 'documento'],
    colunas: const [
      ColunaDef('nome', 'Nome', flex: 3),
      ColunaDef('documento', 'CPF/CNPJ', tipo: TipoCampo.documento),
      ColunaDef('telefone', 'Telefone', tipo: TipoCampo.telefone),
      ColunaDef('ativo', 'Ativo', tipo: TipoCampo.simNao, flex: 1),
    ],
    campos: [
      const CampoDef('tipo', 'Tipo',
          tipo: TipoCampo.opcoes, opcoes: _tiposCliente, obrigatorio: true,
          padrao: 'pj', metade: true),
      const CampoDef('documento', 'CPF/CNPJ', tipo: TipoCampo.documento, metade: true),
      const CampoDef('nome', 'Nome / razão social', obrigatorio: true),
      const CampoDef('nome_fantasia', 'Nome fantasia'),
      const CampoDef('email', 'E-mail', tipo: TipoCampo.email, metade: true),
      const CampoDef('telefone', 'Telefone', tipo: TipoCampo.telefone, metade: true),
      const CampoDef('telefone2', 'Telefone 2', tipo: TipoCampo.telefone, metade: true),
      const CampoDef('ativo', 'Ativo', tipo: TipoCampo.simNao, padrao: true, metade: true),
      const CampoDef('avisos_desligados', 'Avisos que o cliente NÃO quer receber',
          tipo: TipoCampo.multiOpcoes, opcoes: _avisos),
      const CampoDef('observacoes', 'Observações', tipo: TipoCampo.textoLongo),
    ],
    filhos: const [
      FilhoDef('locais', 'cliente_id'),
      FilhoDef('contatos', 'cliente_id'),
    ],
    podeExcluir: (r) => r['interno'] != true,
    aviso: 'O cliente "interno" (a própria empresa) é criado automaticamente '
        'e serve para a manutenção própria.',
  ),

  CadastroDef(
    chave: 'locais',
    tabela: 'locais',
    titulo: 'Locais',
    singular: 'Local',
    icone: Icons.place_outlined,
    noMenu: false,
    colunasBusca: const ['nome', 'cidade', 'bairro'],
    colunas: const [
      ColunaDef('nome', 'Nome', flex: 3),
      ColunaDef('cidade', 'Cidade'),
      ColunaDef('regiao', 'Região'),
      ColunaDef('distancia_km', 'Km', tipo: TipoCampo.numero, flex: 1),
    ],
    campos: [
      const CampoDef('cliente_id', 'Cliente',
          tipo: TipoCampo.lookup, obrigatorio: true,
          lookup: Lookup(tabela: 'clientes')),
      const CampoDef('nome', 'Nome do local', obrigatorio: true,
          ajuda: 'Ex.: Matriz, Loja Centro, Fábrica 2'),
      const CampoDef('cep', 'CEP', metade: true),
      const CampoDef('logradouro', 'Logradouro', metade: true),
      const CampoDef('numero', 'Número', metade: true),
      const CampoDef('complemento', 'Complemento', metade: true),
      const CampoDef('bairro', 'Bairro', metade: true),
      const CampoDef('cidade', 'Cidade', metade: true),
      CampoDef('uf', 'UF', tipo: TipoCampo.opcoes, opcoes: _opcoesUf, metade: true),
      const CampoDef('regiao', 'Região', metade: true,
          ajuda: 'Agrupa locais próximos no planejamento'),
      const CampoDef('distancia_km', 'Distância da base (km)',
          tipo: TipoCampo.numero, metade: true,
          ajuda: 'Usada na cobrança de deslocamento'),
      const CampoDef('contato_padrao_id', 'Contato padrão',
          tipo: TipoCampo.lookup, metade: true, somenteNaEdicao: true,
          lookup: Lookup(
              tabela: 'contatos', colunaDetalhe: 'cargo',
              colunaFiltro: 'cliente_id', campoPai: 'cliente_id')),
      const CampoDef('latitude', 'Latitude', tipo: TipoCampo.numero, metade: true),
      const CampoDef('longitude', 'Longitude', tipo: TipoCampo.numero, metade: true),
      const CampoDef('instrucoes_acesso', 'Instruções de acesso',
          tipo: TipoCampo.textoLongo,
          ajuda: 'Portaria, horários, EPI exigido, com quem falar'),
      const CampoDef('ativo', 'Ativo', tipo: TipoCampo.simNao, padrao: true),
    ],
    filhos: const [FilhoDef('ambientes', 'local_id')],
  ),

  const CadastroDef(
    chave: 'ambientes',
    tabela: 'ambientes',
    titulo: 'Ambientes',
    singular: 'Ambiente',
    icone: Icons.meeting_room_outlined,
    noMenu: false,
    colunasBusca: ['nome', 'setor_andar'],
    colunas: [
      ColunaDef('nome', 'Nome', flex: 3),
      ColunaDef('setor_andar', 'Setor/andar'),
      ColunaDef('area_m2', 'Área (m²)', tipo: TipoCampo.numero, flex: 1),
    ],
    campos: [
      CampoDef('local_id', 'Local',
          tipo: TipoCampo.lookup, obrigatorio: true,
          lookup: Lookup(tabela: 'locais', colunaDetalhe: 'cidade')),
      CampoDef('nome', 'Nome do ambiente', obrigatorio: true,
          ajuda: 'Ex.: Sala de reuniões, Câmara fria 1'),
      CampoDef('setor_andar', 'Setor / andar', metade: true),
      CampoDef('area_m2', 'Área (m²)', tipo: TipoCampo.numero, metade: true),
      CampoDef('ocupantes_fixos', 'Ocupantes fixos', tipo: TipoCampo.inteiro, metade: true,
          ajuda: 'Usado no PMOC'),
      CampoDef('ocupantes_variaveis', 'Ocupantes variáveis',
          tipo: TipoCampo.inteiro, metade: true),
      CampoDef('observacoes', 'Observações', tipo: TipoCampo.textoLongo),
      CampoDef('ativo', 'Ativo', tipo: TipoCampo.simNao, padrao: true),
    ],
  ),

  const CadastroDef(
    chave: 'contatos',
    tabela: 'contatos',
    titulo: 'Contatos',
    singular: 'Contato',
    icone: Icons.contact_phone_outlined,
    noMenu: false,
    colunasBusca: ['nome', 'cargo', 'email', 'telefone'],
    colunas: [
      ColunaDef('nome', 'Nome', flex: 3),
      ColunaDef('cargo', 'Cargo'),
      ColunaDef('telefone', 'Telefone', tipo: TipoCampo.telefone),
      ColunaDef('funcoes', 'Funções', tipo: TipoCampo.multiOpcoes, opcoes: _funcoesContato, flex: 3),
    ],
    campos: [
      CampoDef('cliente_id', 'Cliente',
          tipo: TipoCampo.lookup, obrigatorio: true,
          lookup: Lookup(tabela: 'clientes')),
      CampoDef('local_id', 'Local (se o contato for de um local só)',
          tipo: TipoCampo.lookup,
          lookup: Lookup(
              tabela: 'locais', colunaDetalhe: 'cidade',
              colunaFiltro: 'cliente_id', campoPai: 'cliente_id')),
      CampoDef('nome', 'Nome', obrigatorio: true, metade: true),
      CampoDef('cargo', 'Cargo', metade: true),
      CampoDef('telefone', 'Telefone (com DDD)', tipo: TipoCampo.telefone, metade: true),
      CampoDef('email', 'E-mail', tipo: TipoCampo.email, metade: true),
      CampoDef('funcoes', 'Funções', tipo: TipoCampo.multiOpcoes, opcoes: _funcoesContato),
      CampoDef('aceita_whatsapp', 'Aceita receber mensagens por WhatsApp',
          tipo: TipoCampo.simNao,
          ajuda: 'Marque só com a autorização do contato (LGPD). A data fica registrada.'),
      CampoDef('ativo', 'Ativo', tipo: TipoCampo.simNao, padrao: true),
    ],
    antesDeSalvar: _consentimentoWhatsapp,
  ),

  const CadastroDef(
    chave: 'equipamentos',
    tabela: 'equipamentos',
    titulo: 'Equipamentos',
    singular: 'Equipamento',
    icone: Icons.ac_unit,
    select: '*, clientes(nome), locais(nome), tipos_equipamento(nome)',
    colunasBusca: ['codigo', 'descricao', 'marca', 'modelo', 'numero_serie'],
    ordem: 'codigo',
    colunaTitulo: 'codigo',
    acoes: [AcaoCadastro('Etiquetas QR', Icons.qr_code_2, '/etiquetas')],
    colunas: [
      ColunaDef('codigo', 'Código', flex: 1),
      ColunaDef('descricao', 'Descrição', flex: 3),
      ColunaDef('clientes.nome', 'Cliente'),
      ColunaDef('locais.nome', 'Local'),
      ColunaDef('situacao', 'Situação', tipo: TipoCampo.opcoes, opcoes: _situacoesEquip, flex: 1),
    ],
    campos: [
      CampoDef('codigo', 'Código (plaqueta/patrimônio)', obrigatorio: true, metade: true,
          ajuda: 'O número da plaqueta do cliente (pode repetir entre clientes diferentes)'),
      CampoDef('qr_token', 'Código do QR', somenteLeitura: true, somenteNaEdicao: true,
          metade: true, ajuda: 'Gerado pelo sistema; vai na etiqueta QR'),
      CampoDef('cliente_id', 'Cliente',
          tipo: TipoCampo.lookup, obrigatorio: true, metade: true,
          lookup: Lookup(tabela: 'clientes')),
      CampoDef('local_id', 'Local',
          tipo: TipoCampo.lookup, obrigatorio: true, metade: true,
          lookup: Lookup(
              tabela: 'locais', colunaDetalhe: 'cidade',
              colunaFiltro: 'cliente_id', campoPai: 'cliente_id')),
      CampoDef('ambiente_id', 'Ambiente',
          tipo: TipoCampo.lookup, metade: true,
          lookup: Lookup(
              tabela: 'ambientes', colunaDetalhe: 'setor_andar',
              colunaFiltro: 'local_id', campoPai: 'local_id')),
      CampoDef('tipo_equipamento_id', 'Tipo de equipamento',
          tipo: TipoCampo.lookup, metade: true,
          lookup: Lookup(tabela: 'tipos_equipamento')),
      CampoDef('descricao', 'Descrição', ajuda: 'Ex.: Split hi-wall recepção'),
      CampoDef('marca', 'Marca', metade: true),
      CampoDef('modelo', 'Modelo', metade: true),
      CampoDef('numero_serie', 'Número de série', metade: true),
      CampoDef('codigo_barras', 'Código de barras', metade: true),
      CampoDef('capacidade_valor', 'Capacidade', tipo: TipoCampo.numero, metade: true),
      CampoDef('capacidade_unidade', 'Unidade da capacidade',
          tipo: TipoCampo.opcoes, opcoes: _unidadesCapacidade, metade: true),
      CampoDef('fluido_refrigerante', 'Fluido refrigerante', metade: true,
          ajuda: 'Ex.: R-410A, R-32, R-22'),
      CampoDef('carga_fluido_kg', 'Carga de fluido (kg)', tipo: TipoCampo.numero, metade: true),
      CampoDef('data_instalacao', 'Data de instalação', tipo: TipoCampo.data, metade: true),
      CampoDef('garantia_ate', 'Garantia até', tipo: TipoCampo.data, metade: true),
      CampoDef('situacao', 'Situação',
          tipo: TipoCampo.opcoes, opcoes: _situacoesEquip, obrigatorio: true,
          padrao: 'ativo', metade: true),
      CampoDef('observacoes', 'Observações', tipo: TipoCampo.textoLongo),
    ],
  ),

  const CadastroDef(
    chave: 'produtos',
    tabela: 'produtos',
    titulo: 'Produtos e serviços',
    singular: 'Produto/serviço',
    icone: Icons.inventory_2_outlined,
    colunasBusca: ['descricao', 'codigo', 'codigo_barras'],
    ordem: 'descricao',
    colunaTitulo: 'descricao',
    colunas: [
      ColunaDef('codigo', 'Código', flex: 1),
      ColunaDef('descricao', 'Descrição', flex: 4),
      ColunaDef('tipo', 'Tipo', tipo: TipoCampo.opcoes, opcoes: _tiposProduto, flex: 1),
      ColunaDef('unidade', 'Un.', flex: 1),
      ColunaDef('preco_venda', 'Preço', tipo: TipoCampo.numero, flex: 1),
    ],
    campos: [
      CampoDef('tipo', 'Tipo',
          tipo: TipoCampo.opcoes, opcoes: _tiposProduto, obrigatorio: true,
          padrao: 'produto', metade: true),
      CampoDef('codigo', 'Código', metade: true),
      CampoDef('descricao', 'Descrição', obrigatorio: true),
      CampoDef('unidade', 'Unidade', obrigatorio: true, padrao: 'un', metade: true,
          ajuda: 'un, m, kg, h, visita…'),
      CampoDef('codigo_barras', 'Código de barras', metade: true),
      CampoDef('preco_venda', 'Preço de venda (R\$)',
          tipo: TipoCampo.numero, obrigatorio: true, padrao: 0, metade: true),
      CampoDef('preco_custo', 'Preço de custo (R\$)', tipo: TipoCampo.numero, metade: true),
      CampoDef('garantia_dias', 'Garantia (dias)', tipo: TipoCampo.inteiro, metade: true),
      CampoDef('ativo', 'Ativo', tipo: TipoCampo.simNao, padrao: true, metade: true),
      CampoDef('sinonimos', 'Como os técnicos chamam',
          tipo: TipoCampo.listaTexto,
          ajuda: 'Separe por vírgula. Ajuda a IA a reconhecer o item no áudio '
              '(ex.: "cap de partida, capacitor").'),
    ],
  ),

  const CadastroDef(
    chave: 'tipos-equipamento',
    tabela: 'tipos_equipamento',
    titulo: 'Tipos de equipamento',
    singular: 'Tipo de equipamento',
    icone: Icons.category_outlined,
    colunas: [
      ColunaDef('nome', 'Nome', flex: 3),
      ColunaDef('categoria', 'Categoria', tipo: TipoCampo.opcoes, opcoes: _categoriasTipo),
      ColunaDef('ativo', 'Ativo', tipo: TipoCampo.simNao, flex: 1),
    ],
    campos: [
      CampoDef('nome', 'Nome', obrigatorio: true, metade: true,
          ajuda: 'Ex.: Split hi-wall, Câmara fria, Self contained'),
      CampoDef('categoria', 'Categoria',
          tipo: TipoCampo.opcoes, opcoes: _categoriasTipo, obrigatorio: true,
          padrao: 'climatizacao', metade: true),
      CampoDef('ativo', 'Ativo', tipo: TipoCampo.simNao, padrao: true),
    ],
    filhos: [FilhoDef('modelos-medicao', 'tipo_equipamento_id')],
    aviso: 'Os tipos de equipamento e as medições valem para todas as empresas da conta.',
  ),

  const CadastroDef(
    chave: 'modelos-medicao',
    tabela: 'modelos_medicao',
    titulo: 'Medições deste tipo',
    singular: 'Medição',
    icone: Icons.speed_outlined,
    noMenu: false,
    colunasBusca: ['nome', 'codigo'],
    ordem: 'ordem',
    colunas: [
      ColunaDef('ordem', 'Ordem', flex: 1),
      ColunaDef('nome', 'Nome', flex: 3),
      ColunaDef('unidade', 'Unidade', tipo: TipoCampo.opcoes, opcoes: _unidadesMedicao, flex: 1),
      ColunaDef('faixa_min', 'Mín.', tipo: TipoCampo.numero, flex: 1),
      ColunaDef('faixa_max', 'Máx.', tipo: TipoCampo.numero, flex: 1),
      ColunaDef('obrigatoria_preventiva', 'Obrig. prev.', tipo: TipoCampo.simNao, flex: 1),
    ],
    campos: [
      CampoDef('tipo_equipamento_id', 'Tipo de equipamento',
          tipo: TipoCampo.lookup, obrigatorio: true,
          lookup: Lookup(tabela: 'tipos_equipamento')),
      CampoDef('nome', 'Nome', obrigatorio: true, metade: true,
          ajuda: 'Ex.: Pressão de sucção'),
      CampoDef('codigo', 'Código', obrigatorio: true, metade: true,
          ajuda: 'Ex.: pressao_succao (usado pela IA)', validar: _codigoMedicao),
      CampoDef('unidade', 'Unidade',
          tipo: TipoCampo.opcoes, opcoes: _unidadesMedicao, obrigatorio: true, metade: true),
      CampoDef('tipo_valor', 'Tipo de valor',
          tipo: TipoCampo.opcoes, opcoes: _tiposValor, obrigatorio: true,
          padrao: 'numero', metade: true),
      CampoDef('faixa_min', 'Faixa normal: mínimo', tipo: TipoCampo.numero, metade: true),
      CampoDef('faixa_max', 'Faixa normal: máximo', tipo: TipoCampo.numero, metade: true),
      CampoDef('ordem', 'Ordem na tela', tipo: TipoCampo.inteiro, padrao: 0, metade: true),
      CampoDef('obrigatoria_preventiva', 'Obrigatória na preventiva',
          tipo: TipoCampo.simNao, metade: true),
      CampoDef('ativo', 'Ativo', tipo: TipoCampo.simNao, padrao: true),
    ],
  ),

  const CadastroDef(
    chave: 'colaboradores',
    tabela: 'colaboradores',
    titulo: 'Colaboradores',
    singular: 'Colaborador',
    icone: Icons.engineering_outlined,
    colunasBusca: ['nome', 'telefone', 'email'],
    colunas: [
      ColunaDef('nome', 'Nome', flex: 3),
      ColunaDef('funcao', 'Função', tipo: TipoCampo.opcoes, opcoes: _funcoesColab),
      ColunaDef('telefone', 'Telefone', tipo: TipoCampo.telefone),
      ColunaDef('ativo', 'Ativo', tipo: TipoCampo.simNao, flex: 1),
    ],
    campos: [
      CampoDef('nome', 'Nome', obrigatorio: true),
      CampoDef('funcao', 'Função',
          tipo: TipoCampo.opcoes, opcoes: _funcoesColab, obrigatorio: true,
          padrao: 'tecnico', metade: true),
      CampoDef('documento', 'CPF', tipo: TipoCampo.documento, metade: true),
      CampoDef('telefone', 'Telefone', tipo: TipoCampo.telefone, metade: true),
      CampoDef('email', 'E-mail', tipo: TipoCampo.email, metade: true),
      CampoDef('especialidades', 'Especialidades', tipo: TipoCampo.listaTexto,
          ajuda: 'Separe por vírgula (ex.: câmara fria, VRF, elétrica)'),
      CampoDef('comissao_percentual', 'Comissão (%)',
          tipo: TipoCampo.numero, padrao: 0, metade: true),
      CampoDef('comissao_base', 'Comissão sobre',
          tipo: TipoCampo.opcoes, opcoes: _baseComissao, obrigatorio: true,
          padrao: 'servico', metade: true),
      CampoDef('comissao_momento', 'Comissão gerada',
          tipo: TipoCampo.opcoes, opcoes: _momentoComissao, obrigatorio: true,
          padrao: 'fechamento_os', metade: true),
      CampoDef('ativo', 'Ativo', tipo: TipoCampo.simNao, padrao: true, metade: true),
    ],
    aviso: 'Colaborador é quem executa serviços. O acesso ao app (usuário e senha) '
        'é liberado na tela de usuários, na próxima etapa.',
  ),

  const CadastroDef(
    chave: 'equipes',
    tabela: 'equipes',
    titulo: 'Equipes',
    singular: 'Equipe',
    icone: Icons.groups_outlined,
    colunas: [
      ColunaDef('cor', 'Cor', tipo: TipoCampo.cor, flex: 1),
      ColunaDef('nome', 'Nome', flex: 4),
      ColunaDef('ativa', 'Ativa', tipo: TipoCampo.simNao, flex: 1),
    ],
    campos: [
      CampoDef('nome', 'Nome', obrigatorio: true, metade: true),
      CampoDef('cor', 'Cor no quadro', tipo: TipoCampo.cor, obrigatorio: true,
          padrao: '#2F6DB5', metade: true),
      CampoDef('ativa', 'Ativa', tipo: TipoCampo.simNao, padrao: true),
    ],
    filhos: [FilhoDef('equipe-membros', 'equipe_id')],
    aviso: 'Esta é a composição padrão. No dia a dia a equipe pode se dividir '
        'ou se juntar a outra pela parte diária, sem mexer aqui.',
  ),

  const CadastroDef(
    chave: 'equipe-membros',
    tabela: 'equipe_membros',
    titulo: 'Membros',
    singular: 'Membro',
    icone: Icons.person_outline,
    noMenu: false,
    select: '*, colaboradores(nome)',
    colunasBusca: [],
    ordem: 'papel',
    colunaTitulo: 'papel',
    colunas: [
      ColunaDef('colaboradores.nome', 'Colaborador', flex: 3),
      ColunaDef('papel', 'Papel', tipo: TipoCampo.opcoes, opcoes: _papelMembro),
      ColunaDef('ativo', 'Ativo', tipo: TipoCampo.simNao, flex: 1),
    ],
    campos: [
      CampoDef('equipe_id', 'Equipe',
          tipo: TipoCampo.lookup, obrigatorio: true,
          lookup: Lookup(tabela: 'equipes', colunaAtivo: 'ativa')),
      CampoDef('colaborador_id', 'Colaborador',
          tipo: TipoCampo.lookup, obrigatorio: true,
          lookup: Lookup(tabela: 'colaboradores', colunaDetalhe: 'funcao')),
      CampoDef('papel', 'Papel na equipe',
          tipo: TipoCampo.opcoes, opcoes: _papelMembro, obrigatorio: true,
          padrao: 'membro', metade: true,
          ajuda: 'Cada equipe tem um líder só'),
      CampoDef('ativo', 'Ativo', tipo: TipoCampo.simNao, padrao: true, metade: true),
    ],
  ),

  const CadastroDef(
    chave: 'glossario',
    tabela: 'glossario',
    titulo: 'Glossário da IA',
    singular: 'Termo',
    icone: Icons.menu_book_outlined,
    colunasBusca: ['termo'],
    ordem: 'termo',
    colunaTitulo: 'termo',
    colunas: [
      ColunaDef('termo', 'Termo', flex: 2),
      ColunaDef('variantes', 'Variantes', tipo: TipoCampo.listaTexto, flex: 4),
      ColunaDef('categoria', 'Categoria', tipo: TipoCampo.opcoes, opcoes: _categoriasGlossario),
    ],
    campos: [
      CampoDef('termo', 'Termo correto', obrigatorio: true, metade: true,
          ajuda: 'Como deve aparecer no texto final'),
      CampoDef('categoria', 'Categoria',
          tipo: TipoCampo.opcoes, opcoes: _categoriasGlossario, obrigatorio: true,
          padrao: 'jargao', metade: true),
      CampoDef('variantes', 'Como costuma ser falado/escrito', tipo: TipoCampo.listaTexto,
          ajuda: 'Separe por vírgula. Ex.: termo "Friella" → "friela, frieli"'),
    ],
    aviso: 'Palavras que a transcrição costuma errar (nomes de clientes, peças, gírias). '
        'A IA usa esta lista para corrigir os textos.',
  ),
];

/// Registra a data e a origem do consentimento para WhatsApp (LGPD).
void _consentimentoWhatsapp(Map<String, dynamic> dados, Map<String, dynamic>? original) {
  final antes = original?['aceita_whatsapp'] == true;
  final agora = dados['aceita_whatsapp'] == true;
  if (agora && !antes) {
    dados['consentimento_em'] = DateTime.now().toUtc().toIso8601String();
    dados['consentimento_origem'] = 'painel';
  }
  if (!agora && antes) {
    dados['consentimento_em'] = null;
    dados['consentimento_origem'] = 'revogado_painel';
  }
}

CadastroDef? cadastroPorChave(String chave) =>
    catalogo.where((d) => d.chave == chave).firstOrNull;

List<CadastroDef> get cadastrosDoMenu => catalogo.where((d) => d.noMenu).toList();

/// Colunas deste cadastro que apontam para o pai (ex.: cliente_id em locais).
/// Depois de gravado, o registro não muda de pai.
Set<String> colunasPaiDe(String chave) => {
      for (final d in catalogo)
        for (final f in d.filhos)
          if (f.cadastro == chave) f.colunaPai,
    };
