# 0058 — Folclore, animais do mundo e criaturas feitas em código

**Fase 4.5.**

## Contexto

O briefing pede criaturas do folclore de cada país (raras, fofas, só fotografáveis) e animais novos no estilo do pacote atual, pela região de origem. Não há pacote com esses bichos.

## Decisão

- **Criaturas em código** (`client/scripts/creature_models.gd`): cada criatura é um esqueleto com uma malha só (uma chamada de desenho), formas simples facetadas (caixas, esferas e cilindros de poucos lados) com cor chapada, cada vértice preso a um osso com peso 1. As animações são geradas por código com os nomes do pacote de animais (Idle, Idle_2, Walk, Gallop, Eating, Jump_toIdle), por tipo de andar (quadrúpede, bípede, ave, saltador, flutuante); o golem tem Slam, Sleep e Wake. Assim os animais novos usam o mesmo `Animals` (trajeto comum, carinho, frutinha, fuga) e a mesma Goblopédia. Foto de conferência: `tools/foto_criaturas.gd`.
- **Animais do mundo** (`animals.json → regional`): capivara, arara, tucano, pinguim, urso-polar, camelo, canguru, coala e panda, por bioma, país e faixa de latitude/longitude. Sorteio separado e depois dos outros animais: nenhum animal que já existia muda de id ou de lugar. O bicho-preguiça ficou de fora: ele vive nas árvores, e os animais andam no chão (precisaria de outro sistema de trajeto).
- **Folclore** (`folklore.json`, `game/folklore.go`): o tempo é dividido em janelas de `window` minutos; em cada janela, cada célula do país que combina com os biomas (e a latitude, se houver) sorteia se a criatura aparece, quando e por quanto tempo, nas horas locais da lenda. Todo mundo vê a mesma criatura no mesmo lugar. O cliente pergunta quem está por perto a cada 20 s (`GET /legends`); a criatura passeia devagar em volta do ponto e some num "puf" se o jogador chega a menos de `shy` (só no cliente). O servidor confere a foto pela mesma conta (`LegendsNear`). Seção **Lendas** na Goblopédia, com a historinha. O modo dev faz uma aparecer na frente do jogador (para todos, 10 minutos).
- **Regras das lendas:** só lendas populares de domínio público, versões fofas, nada sagrado de nenhum povo, sem estereótipos. Origem e descrição em `docs/FOLCLORE.md`.

## Consequências

- Testes: cada lenda tem onde aparecer só no país dela e aparece em alguns dias, a mesma resposta na mesma hora; cada animal novo só na região dele.
- Modelo novo de criatura: um caso em `CreatureModels._spec` e o id em `IDS`.
