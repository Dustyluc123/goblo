# 0031 — Fronteiras pela posição exata, com os países do Natural Earth 1:50m

## Contexto

Até a fase 2.2, o país era decidido por hexágono (~22 unidades, ~140 km na escala do jogo) e os países vinham do Natural Earth 1:110m. Perto de uma fronteira o HUD errava com frequência, e países pequenos (Luxemburgo, Andorra, Mônaco…) não existiam. A fase 2.5 também precisa da fronteira exata para os passaportes e os carimbos.

## Decisão

- **Dados:** países e capitais do **Natural Earth 1:50m** (`paises.geojson`, `capitais.json`), filtrados por `cmd/filtra-paises` (só código, A2 e nome; coordenadas de 4 casas). São 240 países e ~100 mil pontos, 1,8 MB no Git. O 1:10m tem 548 mil pontos (~8 MB filtrado) e o ganho não aparece: 1 unidade do jogo ≈ 6,4 km, e o erro do 1:50m é de 1 a 2 km. A **terra** continua no 1:110m, para a forma do globo (e os lotes já ocupados) não mudar.
- **País de um ponto:** ponto em polígono no 1:50m (`Geography.CountryAt`). O hexágono continua com um **país principal** (o do centro; se o 1:50m deixar o centro no mar, o país mais perto até 2°), usado para bioma, lotes e mini mapa. O HUD, os carimbos e a barreira do passaporte usam a posição exata.
- **Índice espacial:** cada anel vira segmentos orientados com o país à esquerda (externo anti-horário, buracos horário), num índice de quadrados de 1° × 1°. Segmentos iguais em sentidos opostos são **fronteira compartilhada** (viram linha no chão); os outros são costa.
- **Cliente:** `GET /borders?cells=…` manda, por célula, o país inteiro (célula longe de qualquer fronteira) ou os segmentos que passam a até 0,35° dela. O cliente decide o país pelo **segmento mais perto** (à esquerda dele → é aquele país). Um teste em Go confere que essa regra concorda com o ponto em polígono em 1.800 pontos sorteados perto de fronteiras.
- **Áreas disputadas:** versão padrão do Natural Earth, sem tomar lado (registrado no README e em `docs/DADOS.md`).

## Consequências

- O mundo muda de versão (alguns hexágonos de fronteira trocam de país principal e de bioma); o cliente baixa de novo sozinho. Os lotes continuam nas mesmas células.
- A barreira do passaporte fica no cliente enquanto o servidor não sabe a posição do jogador (ADR 0035). Na fase 3 (multiplayer), o servidor recebe a posição e confere a fronteira com `CountryAt`.
- Países sem hexágono próprio (Vaticano, Mônaco…) existem para o HUD, carimbos e passaportes, mas não têm lotes nem aeroporto próprio.
