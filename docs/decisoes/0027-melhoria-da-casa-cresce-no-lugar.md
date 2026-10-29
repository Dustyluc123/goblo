# 0027 — Melhoria da casa cresce a partir da casa atual

## Contexto

Ao melhorar a casa, o jogo dizia que não havia espaço mesmo com o lote vazio. A casa atual já era ignorada na conta, mas a casa nova crescia sempre a partir do mesmo canto: passava da borda do lote ou caía em cima da bancada (que fica no canto, em 11, 1), e a mensagem não dizia o que atrapalhava.

## Decisão

- Na melhoria, `x`, `y` e `rot` do pedido são ignorados. A posição preferida mantém a parede da porta no mesmo lugar e cresce para os lados (centralizada) e para trás (`upgradeOrigin`).
- Se a preferida passar da borda ou bater num objeto, o servidor procura a posição mais próxima que caiba no lote **e continue cobrindo a casa atual** (a casa cresce, não muda de lugar).
- Se todas baterem em objetos, o erro `overlap` diz quais (mensagem com os nomes e `details.blockers` com ids). O cliente pinta esses objetos de vermelho e oferece "Guardar no bolso e melhorar", que guarda cada um (`/lot/remove`) e tenta de novo.
- A obra tem posição própria (`pending_x`, `pending_y`, migração 0002): a casa atual continua no lugar até a obra ficar pronta, e só então assume a posição nova.
- Tamanhos mantidos: a casa grande (10 × 10) cabe no lote de 14 × 14 com uma faixa de 4 quadradinhos de quintal em L e a bancada (2 × 2) no canto.

## Consequências

- A casa pode andar alguns quadradinhos ao crescer perto da borda; a porta continua virada para o mesmo lado.
- Testes: `TestUpgradeWithHouseAloneInLot`, `TestUpgradeNearBorderFindsPosition`, `TestUpgradeBlockedByDecorationListsObjects` e o `--play-test` do cliente.
