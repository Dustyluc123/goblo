# Briefing — Fase 3.5: economia e gente

> Cole este arquivo inteiro no Claude Code. Salve uma cópia em `docs/briefing-fase-3-5.md` (não deixe na raiz).

## Contexto

A Fase 3 ficou excelente: multiplayer, fronteiras vivas e emotes funcionando, sem travadas. **Não mexa no que funciona.**

Esta fase dá vida à economia e coloca os primeiros personagens do jogo: **o dinheiro ganha nome, tudo pode ser vendido, cada país ganha uma praça central com loja e aeroporto de verdade, jogadores podem trocar itens e aparecem NPCs com diálogo**, incluindo um guia que apresenta o mundo na primeira vez.

Regras de sempre (`CLAUDE.md`): commits pequenos em português, testes passando, push no final, nenhuma menção a outros jogos, nada de `osascript`/permissões do Mac, números de jogo em arquivos de dados. **Pode usar `tools/sem_foco.sh` para capturas de tela**, mas pergunte antes se for abrir algo que não seja por esse script.

**Registre no `CLAUDE.md`:** comemorar sentado depois do emote de sentar é **intencional**. Não corrigir.

## Pendência da Fase 3

Eu vou instalar os modelos de exportação do Godot 4.7.2. Se já estiverem instalados quando você começar (confira sem abrir janela), gere os executáveis de macOS e Windows em `client/export/` e confira no modo headless. Se não estiverem, deixe para o fim e me lembre.

## 1. O dinheiro tem nome: gobolar

- Nome oficial: **gobolar** (plural **gobolares**). Símbolo: **G$**. No dia a dia, os NPCs chamam de **goblinhos** ("isso custa 30 goblinhos!").
- Troque "moedas" em toda a interface, textos, código, dados e documentação. O nome continua configurável num arquivo de dados.
- Crie um ícone próprio para o gobolar (moedinha low-poly fofa, com um "G" ou um globinho gravado) para o HUD e os menus.
- Preparar para tradução no futuro: todos os textos visíveis do jogo passam a vir de um arquivo de textos (por exemplo, o sistema de tradução do Godot com CSV ou `.po`), com o português como idioma padrão. **Não traduza agora**; só deixe pronto para traduzir depois.

## 2. Preparar a economia para o futuro

No futuro, cada país terá governo próprio, eleito pelos jogadores, que poderá definir impostos, preços de passaporte e um mercado público. **Não implemente nada disso agora**, mas organize a economia para não fechar essa porta:

- Todo preço do jogo passa por uma função única no servidor, do tipo `preco(item, pais, contexto)`, que hoje devolve o preço base, mas já aceita **modificadores por país** (imposto sobre produto, preço de passaporte, preço de viagem) vindos de um arquivo de dados por país. Por enquanto, todos os países usam os valores padrão.
- O histórico de transações registra **em qual país** cada transação aconteceu e separa preço e imposto (o imposto hoje é zero).
- Crie o conceito de **cofre do país** (saldo por país, hoje sempre zero) no banco, sem interface.
- Registre num ADR a visão de governo por país e como essa estrutura vai sustentá-la.

## 3. Vender tudo

- **Todo item** do jogo tem preço de venda no arquivo de dados (materiais, flores, frutas, coco, decorações fabricadas, ferramentas, câmera, itens da loja). Itens sem preço definido não podem existir: adicione um teste que falha se algum item não tiver preço.
- A **caixa de vendas** do lote aceita qualquer item, com seleção de quantidade e "vender tudo deste tipo".
- A **loja** também compra itens, pagando um pouco mais que a caixa de vendas (número no arquivo de dados), para dar motivo para ir até ela.
- Ferramentas e itens raros pedem confirmação antes de vender.

## 4. Praça central de cada país (loja + aeroporto + guia)

Cada país ganha uma **praça central**, perto da capital, reunindo o **aeroporto**, a **loja** e um ponto de encontro. A mesma regra dos aeroportos vale para países pequenos: se não couber, um balcão compartilhado.

### Loja
- Uma loja por país, na praça central.
- **Estoque que muda todo dia** (na virada das 5h do horário local do país): um pouco de itens fixos (ferramentas, câmera, sementes de flores) e alguns itens rotativos (decorações que não podem ser fabricadas, móveis, variações de cor). Todos os jogadores do mesmo país veem o mesmo estoque do dia.
- Alguns itens podem ser **exclusivos do país ou da região** (por exemplo, uma decoração típica), para dar motivo para viajar.
- Compra e venda passam pela função de preço do item 2.
- Atendida por um **NPC lojista** (ver item 6).

### Aeroporto com cara de aeroporto
- Refaça o aeroporto para parecer um aeroporto pequeno e fofo: terminal com vidraça, **torre de controle**, pista com marcações, biruta, portão de embarque e alguns veículos de pátio (use os modelos do **Car Kit** que fizerem sentido, como caminhonetes, vans ou rebocadores).
- **Avião:** não temos modelo. **Crie um avião low-poly no mesmo estilo** dos pacotes que usamos (formas simples, cantos chanfrados, cores pastel, proporções fofas e um pouco "gordinhas"), montado por código ou gerado como malha e salvo como cena. Ele fica parado na pista e aparece no voo, seguindo o arco sobre o globo.
- O balcão passa a ser atendido por um **NPC atendente** com diálogo.

## 5. Troca entre jogadores

- Clicando num jogador perto (ou pela lista J), posso **propor uma troca**.
- Janela de troca: cada um coloca itens e gobolares do seu lado. Os dois veem tudo em tempo real. Ambos clicam em **"Pronto"**; se qualquer lado mudar algo, o "Pronto" dos dois é desfeito. Depois, uma **confirmação final**.
- O servidor executa a troca de forma **atômica** (ou tudo acontece, ou nada), confere que os dois têm os itens e estão perto, e registra no histórico.
- Dá para recusar, cancelar a qualquer momento e bloquear pedidos de troca (respeitando o bloqueio que já existe).
- **Testes:** troca atômica, desfazer o "pronto" quando algo muda, não trocar o que não tem, jogadores longe, jogador bloqueado.

## 6. NPCs e diálogos

### Sistema de diálogo
- Um sistema único e reaproveitável: caixa de fala bonita na parte de baixo da tela, com nome e retratinho do NPC, texto aparecendo letra por letra (clique ou E para completar ou avançar) e **opções de resposta** quando houver.
- Os diálogos ficam em **arquivos de dados** (não no código), prontos para tradução.
- Os NPCs usam os personagens do **Mini Characters** com variações (cores, acessórios do pacote como óculos e chapéus, se houver), para não parecerem jogadores. Eles têm um nome e um pequeno ícone em cima da cabeça indicando que dá para conversar.

### NPCs desta fase (todos parados no seu lugar)
- **Guia:** um NPC simpático que apresenta o mundo (ver item 7).
- **Lojista**, um por loja: cumprimenta, abre a loja, comenta o item do dia.
- **Atendente do aeroporto**, um por aeroporto: pergunta para onde vou, oferece o passaporte quando preciso e vende a passagem (o menu de viagem que já existe abre a partir do diálogo).
- Os nomes dos NPCs podem variar por país (lista de nomes no arquivo de dados).

**Não faça NPCs andando pelo mundo** nesta fase. Essa decisão ainda está em aberto.

## 7. Apresentação do mundo (primeira vez)

- Na **primeira vez** de cada conta, logo depois de escolher apelido, personagem e país, o **Guia** aparece no lote e apresenta o Goblo numa conversa curta e fofa (uns 6 a 10 balões): o que é o globo, como coletar, a bancada, a casa, a Goblopédia, o passaporte, os gobolares, que existem outros jogadores e que a loja e o aeroporto ficam na praça central do país.
- Pode incluir 2 ou 3 pequenas tarefas guiadas (por exemplo, sacudir uma árvore, fabricar o machado), com setinha apontando, que dão alguns gobolares de recompensa.
- Botão **"Pular apresentação"** sempre visível.
- **No modo dev, a apresentação é pulada automaticamente.** Contas que já existem não veem.
- Nas configurações (F6): **"Rever a apresentação"**. No painel dev: "Mostrar a apresentação agora" e "Marcar como não vista".
- O progresso da apresentação fica no servidor.

## 8. Modo dev, testes e documentação

- Painel dev: dar gobolares, forçar a troca do estoque da loja, abrir qualquer diálogo, mostrar a apresentação, abrir uma troca com um bot.
- Bots: alguns aceitam pedidos de troca automaticamente, para eu testar sozinho.
- Testes em Go: todo item tem preço; função de preço por país; venda e compra; estoque diário igual para o mesmo país e diferente entre dias; troca atômica; apresentação vista uma vez por conta.
- Atualize README, `docs/CONTEUDO.md` (preços, estoque da loja, NPCs, diálogos), `docs/API.md`, `docs/PROTOCOLO.md` e os ADRs.

## Fora do escopo agora

Governo, eleições e impostos de verdade (só a estrutura do item 2); NPCs andando pelo mundo; roupas e customização; temperatura, sede e frio; cavernas; folclore; casas com variações de material; tradução de fato; redesenho geral da interface; música e sons.

## No final

O que mudou, como testar cada parte (passo a passo com modo dev e bots), decisões tomadas sozinho, o que ficou pendente e o que ficou sem verificação visual.
