# API do servidor

REST com JSON. O servidor sobe em `:8080` (`-addr` ou `GOBLO_ADDR`). Código em `server/internal/httpapi/`.

## Autenticação

Não há login. Na primeira vez, `POST /players` devolve um **token secreto** (64 caracteres hexadecimais). O cliente guarda o token em `user://player.cfg` e o manda em todas as rotas marcadas com 🔑:

```
Authorization: Bearer <token>
```

O servidor só guarda o **hash SHA-256** do token. Token errado ou ausente → `401 {"error":"unauthorized"}`.

## Erros

Todo erro de regra responde com um status HTTP e o corpo:

```json
{"error": "daily_limit", "message": "Você já sacudiu isso hoje. Volte amanhã!"}
```

`error` é um código estável (para o cliente decidir o que fazer); `message` é o texto em português para mostrar na tela.

| Código | Status | Quando |
| --- | --- | --- |
| `invalid` | 400 | corpo ou parâmetro inválido |
| `nickname_invalid` | 400 | apelido curto, longo, com caracteres proibidos ou palavrão |
| `country_invalid` | 400 | país que não existe no mundo |
| `wrong_action` | 400 | ação que não serve para o objeto (ex.: `pick` numa árvore) |
| `out_of_lot` | 400 | objeto ou casa fora da grade do lote |
| `unauthorized` | 401 | token ausente ou errado |
| `not_owner` | 403 | lote (ou objeto colocado) de outro jogador |
| `dev_only` | 403 | rota `/dev/…` sem `GOBLO_DEV=1` |
| `not_found` | 404 | objeto, receita ou item que não existe |
| `nickname_taken` | 409 | apelido já usado (sem diferenciar maiúsculas) |
| `no_lot` | 409 | não há lote livre no país |
| `daily_limit` | 409 | limite do dia já atingido |
| `no_tool` | 409 | falta machado ou picareta |
| `inventory_full` | 409 | o item não cabe nos 20 espaços |
| `missing_materials` | 409 | faltam materiais (a mensagem lista quais) |
| `overlap` | 409 | já tem alguma coisa nesses quadradinhos (na melhoria da casa, `details.blockers` lista os objetos: `[{"id", "item", "name"}]`) |
| `busy` | 409 | a obra da casa ainda não terminou |
| `max_level` | 409 | a casa já está no nível máximo |
| `not_for_sale` | 400 | a caixa de vendas não aceita o item |
| `no_passport` | 403 | sem o passaporte do país (viagem ou carimbo) |
| `no_coins` | 409 | moedas insuficientes (nada é cobrado) |
| `internal` | 500 | erro inesperado (vai para o log do servidor) |

## Mundo (sem token)

| Rota | Resposta |
| --- | --- |
| `GET /health` | `{"status":"ok"}` |
| `GET /world/version` | `{"version":"9ce1…","format":1,"frequency":50,"cells":25002}` |
| `GET /world.bin` | o mundo no formato binário (o que o jogo usa), com gzip, `ETag` e `304` |
| `GET /world` | o mesmo mundo em JSON, para depuração |
| `GET /borders?cells=1,2,3` | fronteiras exatas por célula (ADR 0031): `{"countries": [{"code","name"}], "cells": [{"cell", "country"} \| {"cell", "segs"}]}`. Célula longe de qualquer fronteira vem com `country` (a célula inteira); as outras vêm com `segs`, seis números por segmento: `lat1, lon1, lat2, lon2, índice em countries, 1 se separa dois países (linha no chão) ou 0 se é costa`. O país fica à esquerda de 1 → 2 |
| `GET /airports` | os aeroportos (um por país com hexágono): `{"airports": [{"country", "country_name", "name", "city", "cell", "lat", "lon", "x", "y", "small"}]}`; `x, y` é o balcão no plano da célula; `small` = só um ponto de chegada (país pequeno) |
| `GET /passport/prices` | preço do passaporte de cada país (todos, com ou sem aeroporto): `{"countries": [{"country", "name", "price"}]}` |

## Conteúdo e país (sem token)

### `GET /content`

Tudo o que o cliente precisa saber do conteúdo do jogo, lido de `server/data/game/*.json` (veja [`CONTEUDO.md`](CONTEUDO.md)):

```json
{
  "items": [{"id": "branch", "name": "Galho", "category": "material", "stack": 99, "model": "res://…", "scale": 0.22, …}],
  "recipes": [{"id": "axe", "result": "axe", "count": 1, "ingredients": {"branch": 5, "stone": 1}}],
  "houses": [{"level": 1, "name": "Barraca", "cost": {"wood": 10}, "footprint": [6, 6], "scene": "res://…"}],
  "object_models": ["BirchTree_1", …],
  "tile_size": 0.5, "lot_tiles": 14, "inventory_slots": 20, "rollover_hour": 5,
  "dev": false,
  "currency": {"singular": "moeda", "plural": "moedas"},
  "sell_prices": {"wood": 3, "stone": 2, …},
  "animals": {"cow": {"name": "Vaca", "model": "Cow", "height": 1.35, "shy": false, "walk": 0.8, "run": 4, "roam": 5.5, "leg": 16, "jump": "Jump_toIdle"}, …},
  "pedia": [{"id": "alpaca", "name": "Alpaca", "kind": "animal", "model": "Alpaca"}, …, {"id": "tree_snow", "name": "Árvore com neve", "kind": "tree", "season": "snow", "model": "PineTree_Snow_1"}]
}
```

### `GET /recipes`

Só as receitas: `{"recipes": [...]}`.

### `GET /geo?locale=pt_BR`

Sugere o país de um jogador novo:

1. pelo **IP da conexão**, na base IP to Country Lite da DB-IP (o IP é descartado logo depois, sem log);
2. se o IP for local (`127.0.0.1`, rede privada) ou desconhecido, pelo **idioma do sistema** que o cliente manda em `locale` (`OS.get_locale()`, ex.: `pt_BR` → Brasil);
3. senão, nada.

```json
{"country": "BRA", "country_name": "Brasil", "source": "locale"}
```

`source` é `ip`, `locale` ou `none`. A tela de primeiro acesso mostra a sugestão e deixa o jogador trocar.

## Jogador

### `POST /players`

Cria o jogador e escolhe um lote livre no país dele, com uma bancada.

```json
{"nickname": "Lucas", "country": "BRA"}
```

`201`:

```json
{"token": "c55bac10…", "me": { …igual ao GET /me… }}
```

### 🔑 `GET /me`

```json
{
  "id": 1, "nickname": "Lucas", "country": "BRA", "country_name": "Brasil",
  "lot": {
    "id": 85696, "cell": 21424, "slot": 0, "x0": -7.25, "y0": -7.25,
    "owner_id": 1, "owner": "Lucas",
    "house": {"level": 1, "name": "Barraca", "pending_level": 2, "ready_at": 1793263063, "x": 4, "y": 6, "rot": 0, "pending_x": 3, "pending_y": 6},
    "placements": [{"id": 1, "item": "workbench", "x": 11, "y": 1, "rot": 0}]
  },
  "inventory": [{"item": "branch", "count": 7}, {"item": "axe", "count": 1}],
  "slots_used": 2, "slots_max": 20,
  "day": {"index": 20754, "next_rollover": 1793263063, "server_time": 1793241608},
  "coins": 30,
  "passports": ["BRA", "PRY"]
}
```

- `house` é `null` sem casa. `level` é o nível pronto, no canto (`x`, `y`); `pending_level > 0` indica uma obra que fica pronta em `ready_at` (unix), no canto (`pending_x`, `pending_y`) — na melhoria a casa cresce e pode se deslocar (ADR 0027).
- `day.index` muda às **5h no horário local da casa do jogador** (pela longitude: 15° = 1 hora).
- `coins`: saldo de moedas. `passports`: o do país de residência primeiro (grátis), depois os comprados.

## Objetos e coleta

### 🔑 `GET /objects?cells=1,2,3`

Objetos interativos das células (até 512 por pedido), com o que **este** jogador já fez neles hoje. Objetos dentro de lotes ocupados não aparecem.

```json
{
  "day": {"index": 20754, "next_rollover": 1793263063, "server_time": 1793241608},
  "objects": [
    {"id": 1371137, "cell": 21424, "kind": "tree", "model": "CommonTree_3",
     "x": 1.0, "y": 8.84, "yaw": 0.7, "scale": 1.53, "drop": "branch", "chop": true,
     "state": {"shake": 1, "chop": 2}},
    {"id": 1371150, "cell": 21424, "kind": "flower", "model": "Flowers", "x": -3.1, "y": 2.2,
     "yaw": 4.1, "scale": 0.62, "item": "flower_red"}
  ]
}
```

- `id` = célula × 64 + índice: estável e igual para todos.
- A posição é `(x, y)` no plano do topo da célula: `P = c·(raio + altura) + East·x + North·y`, com `East = normalize(ref × c)`, `North = c × East`, `ref = (0, 1, 0)` (ou `(0, 0, 1)` se `|c.y| > 0,999`). Mesma conta em `server/internal/game/frame.go` e `WorldData.cell_frame`.
- `kind`: `tree`, `rock`, `flower`, `pebble`, `branch`, `bush`, `decor`.
- `state` só aparece se o jogador já fez algo no objeto hoje.
- A resposta também traz `animals` e `now_ms` (ADR 0032): `{"id", "cell", "species", "points": [[x, y], …], "speed", "leg"}`. O id é célula × 16 + índice; a posição em cada instante sai de `AnimalAt(animal, horário do servidor)` (`server/internal/game/animals.go`, repetida em `client/scripts/animal_path.gd`); `now_ms` é o horário do servidor para o cliente acertar o relógio. Hexágonos de aeroporto não têm objetos nem animais.

### 🔑 `POST /interact`

```json
{"object": 1371137, "action": "shake"}
```

| Objeto | Ação | Limite por dia (por jogador) | Dá |
| --- | --- | --- | --- |
| árvore | `shake` | 1 | 1–3 galhos (palmeira: 1 coco; cacto: nada) |
| árvore (`chop: true`) | `chop` (precisa de machado) | 3 | 1 madeira por golpe |
| pedra grande | `mine` (precisa de picareta) | 3 | 1 pedra por golpe |
| arbusto de frutinhas | `shake` | 1 | 1–3 frutinhas |
| flor | `pick` | 1 | 1 flor da cor dela; some só para este jogador até o dia seguinte |
| pedrinha / galho no chão | `pick` | 1 | 1 pedra / 1 galho |

```json
{
  "action": "shake",
  "gained": [{"item": "branch", "count": 2}],
  "state": {"shake": 1},
  "inventory": [ … ], "slots_used": 3,
  "message": "Você pegou 2× Galho!"
}
```

> O servidor ainda não sabe onde o jogador está (isso vem no multiplayer), então **não confere a distância** até o objeto. Veja o [ADR 0021](decisoes/0021-interacao-sem-distancia-ate-o-multiplayer.md).

## Fabricação

### 🔑 `POST /craft`

```json
{"recipe": "axe", "times": 1}
```

```json
{"crafted": {"item": "axe", "count": 1}, "consumed": [{"item": "branch", "count": 5}, {"item": "stone", "count": 1}],
 "inventory": [ … ], "slots_used": 4, "message": "Você fabricou 1× machado!"}
```

Ingredientes `#flower` aceitam qualquer flor (gasta primeiro a cor que o jogador tem mais).

## Lote

A grade do lote tem `lot_tiles × lot_tiles` (14 × 14) quadradinhos de `tile_size` (0,5) unidade. `(x, y)` é o quadradinho do canto mínimo; um item de `footprint [w, h]` com `rot` ímpar ocupa `[h, w]`.

### 🔑 `GET /lots?cells=1,2,3`

Lotes ocupados das células, de todos os jogadores (para desenhar o bairro): `{"lots": [ …mesmo formato de me.lot… ]}`.

### 🔑 `POST /lot/place`

```json
{"lot": 85696, "item": "lantern", "x": 4, "y": 4, "rot": 1}
```

Confere: o lote é do jogador, o item é colocável e está no inventário, cabe na grade e não sobrepõe nada (nem a casa). Responde `{"lot": {…}, "inventory": […], "slots_used": n}`.

### 🔑 `POST /lot/remove`

```json
{"placement": 12}
```

Guarda o objeto de volta no inventário (precisa caber). Mesma resposta de `/lot/place`.

### 🔑 `POST /lot/house`

```json
{"lot": 85696, "x": 4, "y": 6, "rot": 0}
```

Começa a obra do próximo nível. Na primeira casa, `x`, `y` e `rot` dizem onde ela fica; nas melhorias, são ignorados (a casa cresce no mesmo lugar e precisa caber). Desconta os materiais de `houses.json` e a obra fica pronta na **próxima virada do dia** (5h locais). Mesma resposta de `/lot/place`.

## Moedas, animais e Goblopédia

| Rota | Corpo | Faz |
| --- | --- | --- |
| 🔑 `POST /sell` | `{"items": [{"item": "wood", "count": 3}]}` | vende na caixa de vendas (preços em `economy.json`): `{"sold", "earned", "coins", "inventory", "slots_used", "message"}` |
| 🔑 `GET /transactions?limit=50` | — | histórico de moedas, mais novas primeiro: `{"transactions": [{"id", "delta", "balance", "reason", "ref", "created_at"}]}`; `reason`: `start`, `sell`, `pedia`, `stamp`, `travel`, `passport`, `dev` |
| 🔑 `POST /animal/feed` | `{"animal": 123}` | gasta uma frutinha (o animal come e vira amigo; marca a espécie como amiga na Goblopédia) |
| 🔑 `GET /pedia` | — | páginas da Goblopédia com o progresso: `{"entries": [{"id", "name", "kind", "model", "discovered", "first_at", "country", "country_name", "biome", "sightings", "friend"}]}` |
| 🔑 `POST /pedia/register` | `{"entry": "cow", "country": "ARG", "biome": "grassland"}` | registra uma foto: `{"entry", "first", "reward", "coins", "sightings", "message"}`; só a primeira foto paga `rewards.pedia_first` |

## Viagem e passaportes

| Rota | Corpo | Faz |
| --- | --- | --- |
| 🔑 `GET /travel/quotes?from=BRA` | — | destinos a partir do aeroporto `from`: `{"quotes": [{…aeroporto, "fare", "passport_price", "has_passport"}]}` |
| 🔑 `POST /travel` | `{"from": "BRA", "to": "ARG", "buy_passport": true}` | compra a passagem (e o passaporte do destino junto, com `buy_passport`) e carimba a chegada. Sem o passaporte e sem `buy_passport`: `403 no_passport`; sem moedas: `409 no_coins`, nada é cobrado |
| 🔑 `GET /passport` | — | livro de passaporte: `{"passports": [...], "stamps": [{"country", "name", "first_at"}], "coins"}` |
| 🔑 `POST /passport/buy` | `{"country": "LUX"}` | compra o passaporte de qualquer país |
| 🔑 `POST /passport/stamp` | `{"country": "PRY"}` | carimba a entrada a pé (precisa do passaporte); só a primeira visita dá carimbo e `rewards.stamp_first` |

`/travel`, `/passport/buy` e `/passport/stamp` respondem `{"passport", "stamp" (o carimbo novo, ou ausente), "reward", "price", "airport" (na viagem), "message"}`. O servidor ainda não sabe onde o jogador está: a barreira da fronteira fica no cliente (ADR 0035, TODO da fase 3).

## Modo dev (🔑, só com `GOBLO_DEV=1`)

Sem `GOBLO_DEV=1`, **toda** rota `/dev/…` responde `403 {"error":"dev_only"}` (há teste). Com o modo dev, o relógio do servidor pode ser adiantado.

| Rota | Corpo | Faz |
| --- | --- | --- |
| `GET /dev/status` | — | `{"dev": true}` (sem token) |
| `POST /dev/give` | `{"item": "wood", "count": 99}` | dá (ou tira, com número negativo) qualquer item |
| `POST /dev/finish-house` | — | conclui a obra na hora |
| `POST /dev/next-day` | — | adianta o relógio do servidor até logo depois da próxima virada do dia do jogador (limites zerados, obras prontas) |
| `POST /dev/real-time` | — | desfaz os adiantamentos: o relógio do servidor volta para a hora real, sem reiniciar (obras prontas continuam prontas) |
| `POST /dev/country` | `{"country": "JPN"}` | troca o país e muda o lote para um lote livre no país novo |
| `POST /dev/reset` | `{"what": "lot"}` | `lot` (casa e decoração; volta a bancada), `inventory`, `collections` (limites de hoje) ou `player` (apaga tudo) |
| `POST /dev/fake-neighbors` | `{"cell": 21424, "count": 20}` | cria jogadores falsos com casas prontas e decoração sorteada nos lotes livres mais perto da célula |
| `POST /dev/coins` | `{"amount": 500}` | dá (ou tira, com número negativo) moedas; o saldo nunca fica negativo |
| `POST /dev/pedia` | `{"action": "complete"}` | `complete` (todas as páginas descobertas e amigos, sem moedas) ou `reset` |
| `POST /dev/passport` | `{"action": "give", "country": "PRY"}` | `give` ou `remove` um passaporte; `complete` (todos os passaportes e um carimbo de cada país com aeroporto, sem moedas) ou `reset`. Responde o livro de passaporte |
| `POST /dev/travel` | `{"from": "BRA", "to": "JPN"}` | viagem de graça e sem passaporte; mesma resposta de `/travel` |

As respostas trazem o `GET /me` atualizado (menos `fake-neighbors`, que devolve `{"created": n}`, o reset de `player`, que devolve `{"deleted": true}`, e `pedia`, `passport` e `travel`, descritos acima).
