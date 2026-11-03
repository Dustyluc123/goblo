# 0043 — NPCs parados, um sistema de diálogo e a apresentação do guia

**Fase 3.5** (escrito na 4.0, descrevendo o que foi feito).

## Contexto

A fase 3.5 pediu os primeiros personagens do jogo (guia, lojista, atendente do aeroporto), com diálogos em arquivos de dados e uma apresentação do mundo na primeira vez. NPCs andando pelo mundo ficaram de fora de propósito.

## Decisão

- **NPCs parados** nos pontos da praça (`airports.gd`); o guia da apresentação aparece no lote do jogador. Usam os modelos do Mini Characters com chapéu, acessório e tom próprios (`npcs.json` → `roles`) e um balãozinho em cima, para não parecerem jogadores. Os nomes variam por país (`npcs.json` → `names`, escolhidos em `Content.NPCName`).
- **Um sistema de diálogo só** (`DialogUi`): retrato, nome, texto letra por letra (E ou clique completa e avança), até 4 respostas. Os textos ficam em `dialogs.json`; a fala em português é a chave da tradução.
- **Ações conhecidas:** uma resposta pode disparar uma ação da lista fechada `dialogActions` (`npcs.go`): abrir a loja, vender, abrir viagem ou passaportes, cumprir tarefa da apresentação, terminar. O servidor recusa `dialogs.json` com ação desconhecida. Ação nova = acrescentar na lista e tratar em `GameMain._on_dialog_action`.
- **Apresentação no servidor:** o progresso (vista ou não, tarefas cumpridas) fica no banco. As tarefas (sacudir uma árvore, fabricar o machado) são detectadas pelo servidor quando a ação acontece (`introProgress`) e pagas uma vez só. No modo dev, a apresentação é pulada; contas antigas não a veem.

## Consequências

- Conteúdo de diálogo muda sem mexer em código (só `dialogs.json`).
- NPCs que andam pedirão outra decisão (trajeto, colisão, rede); nada aqui fecha essa porta.
