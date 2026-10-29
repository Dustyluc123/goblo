# 0019 — Lotes de 14 × 14 quadradinhos de 0,5 unidade, 4 por hexágono

**Status:** aceita (fase 2)

## Contexto
O briefing sugere lotes de 16 × 16 quadradinhos de 1 unidade, "ajuste se ficar grande ou pequeno demais", e que um hexágono comporte vários lotes. Mas um hexágono tem ~500 unidades² (raio interno ~12), e um lote de 16 × 16 unidades ocupa 256: caberia um só. Além disso, a escala que deixa as casas do Fantasy Town Kit proporcionais ao personagem (porta mais alta que ele) é ×1,5, ou seja, cada peça do kit mede 1,5 unidade.

## Decisão
- **Quadradinho de 0,5 unidade** (`TileSize`). Uma peça do kit (1,5) ocupa exatamente 3 quadradinhos; uma cerca, 1 × 3; um lampião, 1 × 1. O personagem tem ~0,4 de largura, então 1 quadradinho ≈ a largura dele, como no Animal Crossing.
- **Lote de 14 × 14 quadradinhos** (7 × 7 unidades, `LotTiles`). Com 16 × 16 (8 × 8), só 55% das células comportavam 4 lotes; com 14 × 14, 90% comportam (27.773 lotes no mundo; há teste).
- Cada célula tem até **4 lotes**, num quadriculado 2 × 2 em volta do centro, com um corredor de 0,5 entre eles, no plano do topo da célula (veja `Frame`). Um lote só existe se os 4 cantos ficam dentro da célula com 0,3 de folga.
- **id do lote = célula × 4 + posição**: estável, e chave primária no banco, então dois jogadores nunca recebem o mesmo lote.
- O topo de cada célula já é plano, então o lote não precisa achatar terreno.
- O jogador novo ganha um lote no país dele: biomas agradáveis (campo, floresta, floresta tropical, praia) primeiro e, dentro deles, as células mais perto do "centro" do país. Assim os jogadores de um país enchem as mesmas células e viram vizinhos.

## Consequências
- Configurável em `server/internal/game/lots.go` (`TileSize`, `LotTiles`); o cliente recebe os dois valores no `/content`.
- Casas: barraca 6 × 6, casinha 9 × 7, casa grande 10 × 10. Num lote de 14 × 14 sobra espaço para decorar, mas é preciso deixar a casa crescer (o jogo mostra o contorno da casa grande ao escolher o lugar).
- Hexágonos próximos dos 12 pentágonos às vezes têm 3 lotes.
