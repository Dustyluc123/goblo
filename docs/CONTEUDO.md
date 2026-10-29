# Conteúdo do jogo (para balancear sem programar)

Tudo o que dá para ajustar sem mexer em código fica em arquivos JSON. Depois de editar, reinicie o servidor (os do servidor são embutidos no binário com `go:embed`) ou rode o jogo de novo (os do cliente).

| Arquivo | Lado | O que define |
| --- | --- | --- |
| `server/data/game/items.json` | servidor | itens: nome, categoria, pilha, footprint, modelo, escala, colisão, luz |
| `server/data/game/recipes.json` | servidor | receitas da bancada |
| `server/data/game/houses.json` | servidor | níveis da casa: custo, footprint e cena |
| `server/data/game/objects.json` | servidor | árvores, pedras, flores, arbustos e enfeites de cada bioma (os que dão material) |
| `client/data/decoracao.json` | cliente | grama e plantinhas decorativas de cada bioma, e o tom dos objetos por bioma |

O servidor confere tudo ao subir (`game.LoadContent`): receita com item que não existe, casa maior que o lote ou flor sem item param o servidor com uma mensagem clara.

## Itens (`items.json`)

| Campo | Para quê |
| --- | --- |
| `id` | identificador estável (vai para o banco) |
| `name` | nome em português, na tela |
| `category` | `material`, `tool` (vai para a barra rápida e para a mão) ou `placeable` (vai para o lote) |
| `stack` | quantos cabem num dos 20 espaços (ferramentas: 1) |
| `tags` | grupos usados nas receitas: `"#flower"` aceita qualquer item com a tag `flower` |
| `footprint` | `[largura, profundidade]` em quadradinhos de 0,5 unidade (só colocáveis) |
| `model`, `scale` | modelo no cliente (caminho `res://`, nome do Nature Pack, `flower:cor` ou `primitive:…`) e escala |
| `height` | altura da caixa de colisão no cliente (0 = dá para atravessar, como caminhos e portões) |
| `light` | acende à noite (lampião) |

## Receitas (`recipes.json`)

`{"id": "fence", "result": "fence", "count": 2, "ingredients": {"wood": 2}}`: 2 madeiras dão 2 cercas. Valores atuais:

| Receita | Ingredientes | Dá |
| --- | --- | --- |
| Machado | 5 galhos + 1 pedra | 1 |
| Picareta | 5 galhos + 2 pedras | 1 |
| Cerca de madeira | 2 madeiras | 2 |
| Cerca curva, portão | 2 madeiras | 1 |
| Cerca viva (reta, curva, portão) | 3 galhos + 2 flores | 1 |
| Lampião | 2 madeiras + 2 pedras | 1 |
| Banco | 4 madeiras | 1 |
| Banquinho | 2 madeiras | 1 |
| Caminho de pedra | 1 pedra | 2 |
| Canteiro de flores | 3 flores | 1 |
| Barraquinha (natural, vermelha, verde) | 10 madeiras (+ 1 flor vermelha ou 1 frutinha) | 1 |
| Carrinho | 8 madeiras | 1 |
| Fonte | 30 pedras | 1 |
| Pedra decorativa grande / pequena | 3 / 2 pedras | 1 |
| Arbusto de frutinhas | 5 frutinhas | 1 |

Ajustes em relação ao briefing, para o jogo ficar mais gostoso: a cerca rende 2 por receita (cercar o lote não fica caro demais), o banquinho custa 2 madeiras, o caminho rende 2 peças e a pedra pequena custa 2. As barraquinhas coloridas pedem um item da cor, só para dar charme.

## Casa (`houses.json`)

| Nível | Nome | Custo | Footprint | Cena |
| --- | --- | --- | --- | --- |
| 1 | Barraca | 10 madeiras | 6 × 6 (3 × 3 unidades) | `client/scenes/houses/house_level_1.tscn` |
| 2 | Casinha | 30 madeiras + 20 pedras | 9 × 7 (4,5 × 3,5) | `house_level_2.tscn` |
| 3 | Casa grande | 60 madeiras + 50 pedras + 10 flores | 10 × 10 (5 × 5) | `house_level_3.tscn` |

A casa cresce a partir do mesmo canto; ao escolher o lugar da barraca, o jogo mostra também o contorno da casa grande, para sobrar espaço. As cenas são montadas com o Fantasy Town Kit por `client/tools/montar_casas.gd` (peças na escala 1,5: cada peça do kit = 3 quadradinhos; a porta é mais alta que o personagem). Dá para abrir e ajeitar as cenas no editor; só não rode o script de novo depois disso, senão ele sobrescreve.

## Objetos do mundo (`objects.json`)

Para cada bioma, uma lista de regras:

```json
{"kind": "tree", "models": ["CommonTree_1", …], "autumn": ["CommonTree_Autumn_1", …],
 "per_cell": 10, "scale": [1.3, 1.7], "spacing": 2.2, "drop": "branch", "chop": true}
```

| Campo | Para quê |
| --- | --- |
| `kind` | `tree`, `rock`, `flower`, `pebble`, `branch`, `bush` (frutinhas) ou `decor` (só enfeite) |
| `models` | modelos do Ultimate Nature Pack (`client/assets/quaternius/ultimate-nature/`) |
| `autumn` | versões de outono, **reservadas** para as estações da fase 2.5 (ainda não aparecem) |
| `per_cell` | quantos por célula, em média (uma célula tem ~500 unidades²) |
| `scale` | escala mínima e máxima (o personagem tem 1 de altura; as árvores ficam entre 3 e 5) |
| `spacing` | distância mínima até o vizinho |
| `drop` | árvore: o que cai ao sacudir (`branch`, `coconut` ou `none`) |
| `chop` | árvore: o machado tira madeira |
| `near_water` | só em células que encostam no oceano (salgueiros) |
| `colors` | flores: cores sorteadas (cada uma vira o item `flower_<cor>`) |
| `solid` | enfeite com colisão (troncos caídos, tocos) |

> [!WARNING]
> Mudar `objects.json` muda **as árvores de todo mundo** e os ids dos objetos (as coletas do dia de quem já mexeu nelas deixam de valer). Tudo bem durante o desenvolvimento; depois do lançamento, só acrescente regras no fim da lista de cada bioma.

Mapeamento atual (resumo):

| Bioma | Árvores | Pedras e outros | Chão decorativo (cliente) |
| --- | --- | --- | --- |
| floresta tropical | `CommonTree_*` densas, `PalmTree_*`, `Willow_*` perto da água | `Rock_Moss_*`, `BushBerries_*`, `Bush_*` | `Grass`, `Grass_2`, `Plant_*` |
| floresta | `CommonTree_*`, `BirchTree_*`, `Willow_*` perto da água | `Rock_Moss_*`, `TreeStump_Moss`, `WoodLog_Moss`, `Bush_*`, `BushBerries_*` | `Grass`, `Grass_2`, `Plant_*` |
| campo | `CommonTree_*` esparsas | `Rock_*`, `Bush_*`, `Wheat`, `BushBerries_1` | `Grass_Short`, `Grass` |
| praia | `PalmTree_*` (dão coco) | `Rock_*` pequenas | quase nada |
| deserto | `Cactus_*`, `CactusFlower*` | `Rock_*` | nada |
| montanha | `PineTree_*` esparsos | `Rock_*` grandes | `Grass_Short` rala |
| tundra | `PineTree_Snow_*`, `BirchTree_Snow_*`, `*_Dead_Snow_*` | `Rock_Snow_*`, `Bush_Snow_*`, `WoodLog_Snow`, `TreeStump_Snow` | quase nada |
| gelo | nenhuma | `Rock_Snow_*` raras | nada |

Toda célula de terra (menos gelo) também tem flores (4 cores), pedrinhas e galhos no chão, em quantidades por bioma.

## Decoração do cliente (`decoracao.json`)

Grama e plantinhas, sem interação nem colisão, espalhadas pelo cliente com semente no id da célula ([ADR 0011](decisoes/0011-espalhamento-deterministico.md)). A quantidade é multiplicada pela densidade da qualidade gráfica (baixa 0,4, média 0,7, alta 1,0). `tint` multiplica a cor do modelo; `object_tint` dá um tom aos objetos do servidor em cada bioma.
