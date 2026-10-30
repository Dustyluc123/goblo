# 0037 — Lotes e fronteiras: lote novo longe da linha, lote antigo é do país do dono

## Contexto

Desde a fase 2.5 o país vem da posição exata (ADR 0031), mas os lotes continuaram sendo escolhidos pelo país principal do hexágono. Uma fronteira podia passar por dentro de um lote. Sem o passaporte do outro lado, o dono ficava sem acesso a um pedaço da própria casa.

## Decisão

- **Lote novo** (`assignLot`): cada lote possível ganha um **nível de encaixe** no país do dono (`Service.LotTier`, guardado em cache). Os níveis são conferidos com amostras a cada `sample_step` unidades no lote e numa margem em volta:
  - **0:** o lote inteiro fica no país e a margem não toca outro país. A margem é `borders.lot_margin` (2 unidades) em `rules.json`; mar na margem pode, por causa da costa.
  - **1:** o lote inteiro fica no país, mas perto da fronteira.
  - **2:** a maior parte do lote fica no país.
  - **3:** não serve.

  O jogador ganha o primeiro lote livre do melhor nível disponível. Nos países grandes é sempre nível 0. Os níveis 1 e 2 existem para países pequenos que cabem num hexágono cortado por fronteiras: a Albânia, por exemplo, ficaria sem nenhum lote só com o nível 0.
- **Regra de passagem** (`Service.PassageCountry` e `CanWalk`; no cliente, `_border_guard`):
  - Para o **dono**, o lote dele e a margem em volta contam como o país dele. Isso vale para lotes antigos que cruzam fronteira e para lotes de nível 2.
  - O hexágono de casa continua livre para o dono (ADR 0035). Assim ele nunca é bloqueado no lote nem no caminho até o resto do país.
  - Para os **outros jogadores**, nada muda: vale a fronteira de verdade. Isso evita bolsões. Se um lote valesse como território do dono para todo mundo, poderia cortar uma faixa do país vizinho e deixá-la sem acesso a pé.
- **Lotes antigos:** `GET /dev/border-lots` lista os que não passariam na regra nova: cruzando a fronteira ou só perto dela. O servidor também diz quantos são no log ao subir. `POST /dev/border-lots/move` muda cada um para o primeiro lote de nível 0 livre no país do dono, levando a casa, a obra e os objetos (`Store.MoveLot`, que troca o id do lote e dos objetos numa transação). Os objetos ficam nas mesmas posições, porque todo lote tem o mesmo tamanho. No banco do autor, em 29/10/2026: **0 lotes** (21 lotes, todos no Brasil). Por isso a migração não roda sozinha. A regra do território do dono já protege quem estiver nessa situação.
- **Testes:**
  - lote novo nunca cruza a fronteira (Paraguai, Uruguai, Bélgica, Países Baixos, Áustria, Suíça e Albânia);
  - num lote que cruza a fronteira, o ponto do outro lado conta como do dono para o dono e do país de verdade para o visitante;
  - nenhum bolsão em quatro fronteiras: busca em largura numa grade de 0,5 unidade, em que o alcance a pé de quem está em cada país é igual à área do país ligada pela geografia;
  - o dono chega a todo o lote e ao resto do país.

## Consequências

- `World.FindCell` (busca subindo pelos vizinhos a partir de uma pista) entra no servidor. É a mesma de `WorldData.find_cell`, e o multiplayer vai usá-la a cada passo.
- A escolha do lote fica um pouco mais cara na primeira vez em cada país (até ~500 consultas de país por lote). Depois o resultado vem da cache.
- Se o Natural Earth mudar de versão, os níveis mudam junto. Os lotes já ocupados ficam onde estão: aparecem em `/dev/border-lots` e continuam protegidos pela regra do dono.
