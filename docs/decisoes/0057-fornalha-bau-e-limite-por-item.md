# 0057 — Fornalha, baú, limite por item e ferramentas por nível

**Fase 4.5.**

## Decisão

- **Limite por item em cada espaço do bolso** (`items.json → stack`, já existia): 999 para os materiais básicos (galho, madeira, pedra, flores, frutinhas…), 99 ou 50 para os raros (barras, diamante, auralita), 10 para o coração de cristal, 1 para ferramentas e roupas. Acima do limite, o item ocupa outro espaço (`slotsUsed`).
- **Ferramentas por nível** (`items.json → tool`, `tier`): picareta e machado de pedra (1), ferro (2), diamante (3) e goblita (4). O servidor usa sempre a melhor do bolso: a picareta mínima e os golpes dos minérios (ADR 0056); no globo, a pedra grande e a árvore dão um a mais por nível. Na barra rápida, só a melhor de cada tipo.
- **Fornalha** (receitas `station: furnace`, com `seconds` por unidade): a do lote (fabricável, colocável) ou a fornalha antiga da entrada de cada caverna. Gasta os ingredientes na hora e grava o que vai sair (`furnace_jobs`, migração 0010) com a hora em que fica pronto, depois do que já estava na fila. O jogador busca o que está pronto em qualquer fornalha; o que não cabe no bolso continua lá. Nada se perde se o jogo fechar.
- **Baú:** colocável no lote, com `chest_slots` espaços (o mesmo limite por item). O conteúdo fica no banco (`chest_items`, apagado junto com a peça); só o dono abre, guarda e tira, perto do baú. Com coisas dentro, não dá para guardar o baú.
- **Bancada:** lista só as receitas dela (fogueira e fornalha têm janelas próprias).

## Consequências

- Testes: limite por espaço, fornalha (espera, fila, bancada não derrete, fornalha antiga da caverna), baú (só o dono, guardar e tirar, não sai cheio), machado melhor.
