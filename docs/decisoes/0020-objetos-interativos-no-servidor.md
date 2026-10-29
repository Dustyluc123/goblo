# 0020 — Objetos interativos gerados pelo servidor

**Status:** aceita (fase 2). Substitui em parte o [ADR 0011](0011-espalhamento-deterministico.md).

## Contexto
Na fase 1.5, toda a vegetação era espalhada pelo cliente a partir de uma semente. Agora árvores, pedras grandes, flores, arbustos e itens no chão dão material, e o servidor precisa validar a coleta (limite do dia, ferramenta). Para isso ele precisa saber quais objetos existem e onde.

## Decisão
- O **servidor gera** os objetos de cada célula de forma determinística (gerador SplitMix64 com semente no id da célula), a partir de `server/data/game/objects.json`. Nada é guardado: o servidor gera de novo quando precisa (é rápido) e só guarda as **coletas** (jogador + objeto + ação + dia).
- Cada objeto tem **id estável** (célula × 64 + índice) e posição `(x, y)` no plano do topo da célula. O cliente pede por pedaço (`GET /objects?cells=…`).
- **Todas** as árvores e pedras grandes vêm do servidor, inclusive enfeites grandes sem interação (tocos, troncos caídos, arbustos, trigo, `kind: "decor"`). O cliente só espalha **grama e plantinhas** (`client/data/decoracao.json`), que não têm colisão nem interação.
- Assim, **árvores interativas e decorativas nunca se sobrepõem**: só existe um tipo de árvore. Na geração, cada objeto respeita uma distância mínima (`spacing`) dos outros da célula.
- Objetos que caem dentro (ou a até 1 unidade) de um **lote ocupado** são filtrados na resposta; a grama do cliente também pula os lotes. Os ids dos outros objetos não mudam, porque a geração não olha os lotes.
- Os limites são **por jogador**: todo mundo vê as mesmas árvores e o que um coleta não tira nada dos outros. Flores e itens do chão somem só para quem pegou, até o dia seguinte (5h locais).

## Consequências
- O cliente não precisa reproduzir a geração (nem a colisão das árvores): o servidor manda tudo pronto. A colisão das árvores continua sendo montada no cliente, a partir dos objetos recebidos.
- Mudar `objects.json` muda os objetos de todo mundo e invalida as coletas do dia (veja `docs/CONTEUDO.md`).
- A grama decorativa continua determinística no cliente ([ADR 0011](0011-espalhamento-deterministico.md)), com `client/data/decoracao.json` no lugar da tabela antiga em `biome_style.gd`.
