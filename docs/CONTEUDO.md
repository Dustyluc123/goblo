# Conteúdo do jogo (para balancear sem programar)

Tudo o que dá para ajustar sem mexer em código fica em arquivos JSON. Depois de editar, reinicie o servidor (os do servidor são embutidos no binário com `go:embed`) ou rode o jogo de novo (os do cliente).

| Arquivo | Lado | O que define |
| --- | --- | --- |
| `server/data/game/items.json` | servidor | itens: nome, categoria, pilha, footprint, modelo, escala, colisão, luz |
| `server/data/game/recipes.json` | servidor | receitas da bancada |
| `server/data/game/houses.json` | servidor | níveis da casa: custo, footprint e cena |
| `server/data/game/objects.json` | servidor | árvores, pedras, flores, arbustos e enfeites de cada bioma (os que dão material), com a flor rara |
| `server/data/game/economy.json` | servidor | nome do gobolar, saldo inicial, preços da caixa de vendas, bônus da loja, recompensas, preço da passagem e do passaporte |
| `server/data/game/countries.json` | servidor | modificadores de preço por país (impostos, preço do passaporte, margem da loja); hoje todos neutros |
| `server/data/game/shop.json` | servidor | estoque da loja da praça: itens fixos, do dia e exclusivos regionais, com os preços de compra |
| `server/data/game/npcs.json` | servidor | NPCs (guia, lojista, atendente): personagem, acessório, cor, diálogo e nomes por país |
| `server/data/game/dialogs.json` | servidor | falas dos NPCs, respostas e ações, e a apresentação do guia (tarefas) |
| `server/data/game/animals.json` | servidor | espécies de animais, quais vivem em cada bioma e os cachorros dos bairros |
| `server/data/game/goblopedia.json` | servidor | páginas da Goblopédia além dos animais (flor rara, árvores em estação) |
| `client/data/decoracao.json` | cliente | grama e plantinhas decorativas de cada bioma, e o tom dos objetos por bioma |
| `client/data/cabecas.json` | cliente | encaixe dos chapéus em cada cabeça, corte do cabelo embaixo do chapéu e nomes dos cabelos no editor (fase 4.1, ADR 0052) |

O servidor confere tudo ao subir (`game.LoadContent`): receita com item que não existe, casa maior que o lote ou flor sem item param o servidor com uma mensagem clara.

## Itens (`items.json`)

| Campo | Para quê |
| --- | --- |
| `id` | identificador estável (vai para o banco) |
| `name` | nome em português, na tela |
| `category` | `material`, `tool` (vai para a barra rápida e para a mão) ou `placeable` (vai para o lote) |
| `stack` | quantos cabem num dos 20 espaços; acima disso, o item ocupa outro espaço (fase 4.5: 999 para os básicos, menos para os raros, 1 para ferramentas e roupas) |
| `tool`, `tier` | fase 4.5: tipo de ferramenta (`pickaxe`, `axe`, `torch`) e nível (1 pedra, 2 ferro, 3 diamante, 4 goblita). O servidor usa a melhor do bolso |
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
| Caixa de vendas | 4 madeiras + 1 pedra | 1 (o lote novo já vem com uma) |
| Câmera fotográfica | 3 madeiras + 4 pedras + 1 flor amarela | 1 (ferramenta: vai para a barra rápida) |

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

## Dinheiro (`economy.json`)

O dinheiro é o **gobolar** (plural gobolares, símbolo **G$**); os NPCs chamam de "goblinhos" (`currency`: `singular`, `plural`, `symbol`, `slang`; troque à vontade). O saldo fica no servidor e cada mudança vai para o histórico (`GET /transactions`), com o país, o preço e o imposto.

| Campo | Valor atual | Para quê |
| --- | --- | --- |
| `starting_coins` | 30 | saldo de quem começa agora |
| `sell_prices` | materiais: madeira 3, pedra 2, flor 2 (azul rara: 6), galho 1, frutinhas 1, coco 4, sementes 1; ferramentas: machado e picareta 12, câmera 20; decoração: de 2 (caminho) a 60 (moinho) | quanto a caixa de vendas paga por unidade. **Todo item precisa ter preço** (o servidor não sobe sem, e há teste) |
| `shop_buy_bonus` | 1,25 | a loja da praça paga isso × a caixa de vendas (arredondado para cima) |
| `rewards.pedia_first` | 25 | primeira foto de cada página da Goblopédia (uma vez só) |
| `rewards.stamp_first` | 10 | primeiro carimbo de cada país no passaporte (uma vez só) |
| `rewards.intro_task` | 15 | cada tarefa da apresentação do guia (uma vez por conta) |
| `travel` | base 20 + 8 por 1.000 km, mínimo 25 | passagem de avião entre dois aeroportos (distância pela superfície da Terra). Brasil → Paraguai: ~31; Brasil → Japão: ~162 |
| `passport.default` | 60 | preço de um passaporte; `passport.countries` aceita exceções por país (`{"JPN": 90}`) |

O passaporte do país de residência é grátis e já vem com o jogador.

## Preço por país (`countries.json`)

Todo preço do jogo passa por uma função só no servidor, `Service.Price(contexto, item, país)` ([ADR 0041](decisoes/0041-economia-por-pais.md)). Os contextos são `sell_box` (caixa de vendas), `shop_sell` (vender na loja), `shop_buy` (comprar na loja), `passport` e `travel`. A resposta separa o preço (`base`), o imposto (`tax`) e o total; o imposto vai para o cofre do país (tabela `treasuries`, sem tela por enquanto).

| Campo (em `default` ou em `countries.XXX`) | Valor atual | Para quê |
| --- | --- | --- |
| `goods_tax` | 0 | imposto sobre compra e venda de itens (fração, 0 a 1) |
| `passport_tax`, `travel_tax` | 0 | imposto sobre passaporte e passagem |
| `passport_price` | 0 | preço do passaporte do país (0 = o de `economy.json`) |
| `shop_markup` | 1,0 | multiplica o preço de compra na loja do país |

Hoje nenhum país muda nada. No futuro, quem governar um país poderá mexer nos números dele.

## Loja da praça (`shop.json`)

Cada país tem uma loja na praça central, ao lado do aeroporto ([ADR 0042](decisoes/0042-loja-e-praca-central.md)). O estoque do dia é o mesmo para todo mundo no país e muda às **5h do horário do aeroporto** (sorteio pelo país e pelo dia).

| Campo | Valor atual | Para quê |
| --- | --- | --- |
| `fixed` | machado, picareta, câmera, sementes de flores | sempre à venda |
| `rotating` + `rotating_count` | 13 decorações (bandeiras, poste, banco de jardim, roda de carroça, cerca viva alta, vasos de flores, cone, lampião, banco, fonte), 4 por dia | os "itens do dia" |
| `regional` | moinho (Holanda, Bélgica, Alemanha, Dinamarca, França, Polônia), fardo de feno (Brasil, Argentina, Uruguai, Paraguai, EUA, Canadá, Austrália, Nova Zelândia), chafariz da praça (Itália, Espanha, Portugal, França, Marrocos, México), coluna de pedra (Grécia, Turquia, Itália, Egito, Peru), lanterna de vidro (Japão, China, Coreia, Vietnã, Tailândia, Taiwan) | exclusivos: aparecem em dias alternados só nesses países |
| `prices` | machado 40, picareta 40, câmera 60, sementes 4, decorações de 10 (cone) a 180 (moinho) | preço de compra (antes de `shop_markup` e imposto) |

As sementes (receita `flowerbed_seeds`: 2 sementes + 1 madeira) viram um canteiro na bancada.

## NPCs (`npcs.json`)

Três papéis, sempre parados no lugar ([ADR 0043](decisoes/0043-npcs-dialogos-e-apresentacao.md)): **guia** (na praça e na apresentação), **lojista** (na loja) e **atendente** (no balcão do aeroporto). Cada papel tem `title`, `character` (um dos Mini Characters), `accessory` (do mesmo pacote; vazio = nenhum), `tint` (cor do chapeuzinho e do retrato) e `dialog` (o diálogo que abre ao conversar). `names` dá a lista de nomes por país (`default` para os outros); o nome de cada NPC sai de um sorteio fixo pelo país.

## Diálogos (`dialogs.json`)

Cada diálogo é uma lista de falas; uma fala pode ter `options` (até 4 respostas). Cada resposta pode levar para outro diálogo (`next`) e/ou pedir uma ação ao jogo (`action`):

| Ação | Faz |
| --- | --- |
| `open_shop` / `open_shop_sell` | abre a loja (comprar / vender) do país do NPC |
| `open_travel` / `open_passports` | abre o balcão do aeroporto (destinos / passaportes) |
| `intro_task` (+ `task`) | começa uma tarefa da apresentação (seta em cima do alvo) |
| `intro_done` | termina a apresentação |
| `intro_restart` | começa a apresentação de novo |
| `end` | só fecha |

Nas falas, `{name}` vira o nome do NPC, `{player}` o apelido do jogador, `{country}` o país, `{item_of_day}` um item do dia da loja, `{currency}` o nome do dinheiro (plural) e `{slang}` o apelido (goblinhos). O servidor confere ao subir que todo `next`, ação e tarefa existem.

**Apresentação do guia** (`intro`): `start` é o primeiro diálogo; `tasks` são as tarefas guiadas, cada uma com uma ação de coleta (`action`: `shake`, `chop`, `mine`, `pick`) ou uma receita (`recipe`) e o diálogo que o guia fala depois (`after`). Hoje: sacudir uma árvore e fabricar um machado, com 15 gobolares cada.

Os textos estão em português e são as chaves da tradução: depois de mudar, rode `python3 client/tools/extrair_textos.py` ([ADR 0045](decisoes/0045-textos-prontos-para-traducao.md)).

## Animais (`animals.json`)

Cada espécie: `name`, `model` (arquivo em `client/assets/quaternius/ultimate-animated-animals/`), `height` (o personagem tem ~1), `shy` (tímido: foge galopando se o jogador correr perto), `walk` e `run` (unidades/s), `roam` (raio da área de passeio), `leg` (segundos de cada trecho: anda e depois fica parado) e `jump` (nome da animação de pulinho).

| Bioma | Animais | Grupos por célula | Tamanho do grupo |
| --- | --- | --- | --- |
| Campo (`grassland`) | vaca, touro, cavalo, cavalo branco, burro | 0,9 | 1 a 3 |
| Floresta (`forest`) | cervo, alce-macho, raposa | 0,7 | 1 a 2 |
| Floresta tropical | cervo, raposa (provisório, até termos animais tropicais) | 0,45 | 1 a 2 |
| Montanha | alpaca | 0,7 | 1 a 3 |
| Tundra | lobo, husky | 0,45 | 1 a 2 |
| Praia, deserto, gelo | nenhum por enquanto | — | — |
| Perto dos bairros (biomas agradáveis com lotes) | shiba, husky | 0,35 por lote ocupado | até 2 por célula |

**Fase 4.5 (`regional`):** grupos por região de origem, além do bioma (`biomes`, `countries`, `lat`, `lon`), com sorteio separado (os animais antigos não mudam). Modelos `creature:…` são feitos no cliente.

| Animal | Onde |
| --- | --- |
| capivara | campos, matas e praias da América do Sul (BRA, ARG, PRY, URY, BOL, PER, COL, VEN, GUY, SUR, ECU) |
| arara, tucano | floresta tropical da América do Sul |
| pinguim | gelo, tundra e praia ao sul de 46° S (Antártida, Patagônia) |
| urso-polar | gelo e tundra ao norte de 62° N |
| camelo | desertos da África e da Ásia (5° a 50° N, 20° O a 120° L) |
| canguru | campos, desertos e matas da Austrália |
| coala | matas do leste da Austrália |
| panda | matas e montanhas do centro da China |

Tímidos: cervo, alce-macho, raposa, lobo. Mansos (deixam chegar sempre): vaca, touro, cavalo, burro, alpaca, shiba, husky. Mudar `animals.json` muda os animais de todo mundo (o sorteio é por célula).

## Goblopédia (`goblopedia.json`)

As espécies de `animals.json` entram sozinhas. Os `extras` são as outras páginas:

| Página | Como registrar |
| --- | --- |
| Flor azul | fotografar uma flor azul (rara: `rare_chance` 4% em `objects.json`, sorteada pelo id, sem mudar os outros objetos); colhida, vira o item Flor azul (vale 6 na caixa de vendas) |
| Árvore de outono | fotografar uma árvore com o modelo de outono (bioma temperado, outono no hemisfério dela) |
| Árvore com neve | fotografar uma árvore com neve (inverno; na tundra, o ano todo) |

A primeira foto de cada página paga `rewards.pedia_first`. Dar frutinha a um animal marca a espécie como amiga.

## Estações

As estações vêm da data real (UTC) e do hemisfério (fórmula em `server/internal/game/season.go` e `client/scripts/seasons.gd`, ADR 0034); não há arquivo de dados. Mudam só floresta, campo, tundra e montanha fora dos trópicos. Os modelos trocados são as versões `*_Autumn_*` e `*_Snow_*` do Nature Pack (árvores comuns, bétulas, pinheiros e salgueiros; pedras, arbustos, troncos e tocos só têm a de neve). A transição dura ~20 dias em volta de cada virada (20/3, 21/6, 22/9 e 21/12).

## Corpo: clima e necessidades (`body.json`, fase 4.0)

Tudo do corpo fica em `server/data/game/body.json` (ADR 0050):

- **`climate`**: temperatura do ar. Equador `equator` (27 °C) caindo até `equator + pole_drop` nos polos pela curva `(|lat|/90)^lat_curve`; estação com amplitude `season_amp_tropics` a `season_amp` (cresce com a latitude) e pico do verão no dia `summer_peak_day` (norte); hora local com pico às `daily_peak_hour` e amplitude `daily` por bioma; `offset` por bioma; `height_lapse` graus por unidade de altura acima de `base_height` (as montanhas altas esfriam).
- **`comfort`**: faixa confortável (12 a 26 °C). Roupas com `cold` baixam o mínimo; com `heat`, sobem o máximo.
- **`sources`**: fogueira (`warmth` graus no centro, até zero em `radius`; acesa no chão dura `minutes`), sombra de árvore e beira do mar (refrescam `cooling` graus quando o ar passa de `above`).
- **`needs`**: quedas por minuto jogado (`thirst_per_min`, `hunger_per_min`, mais `thirst_hot_extra` no calor, `hunger_run_extra` correndo e `hunger_per_collect` por coleta), recuperação do conforto e os limites dos níveis (`optimal_at`, `critical_at`, `dizzy_hunger`).
- **`speed`**: multiplicador da velocidade no ótimo (1,1), neutro (1) e crítico (0,75).
- **`buffs`**: bônus da comida: `fast` (velocidade ×1,12), `steady` (necessidades caem pela metade), `warm` e `cool` (8 °C a mais de proteção).
- **`look`**: opções do editor (partes dos 12 personagens, tons de pele, cores de cabelo, penteados extras e acessórios).

Valores de referência (testados): Manaus 23–32 °C o ano todo; Ushuaia abaixo de 5 °C em julho; Saara acima de 35 °C ao meio-dia e abaixo de 20 °C à meia-noite em janeiro; Antártida abaixo de −5 °C.

### Comida e bebida (`items.json → food`)

| Item | Fome | Sede | Bônus | Como |
| --- | --- | --- | --- | --- |
| Frutinhas | 6 | 4 | — | arbusto |
| Coco | 8 | 30 | — | coqueiro |
| Cogumelo, ervas | 4, 2 | —, 2 | — | coletar (floresta; campo e montanha) |
| Cantil cheio / pela metade | — | 35 | — | encher numa fonte, poço ou no chafariz da praça |
| Frutinhas assadas | 20 | 2 | Barriga cheia 4 min | fogueira: 3 frutinhas |
| Espetinho de cogumelo | 30 | — | Quentinho 5 min | fogueira: 2 cogumelos, 1 galho |
| Sopa de ervas | 35 | 15 | Barriga cheia 6 min | fogueira: 2 ervas, 1 cogumelo, 1 coco |
| Suco de frutinhas | 5 | 45 | Refrescado 5 min | fogueira: 2 frutinhas, 1 coco |
| Chá de ervas | — | 40 | Quentinho 6 min | fogueira: 2 ervas, 1 cantil cheio (o cantil volta vazio) |
| Pãozinho de grãos | 40 | — | Pernas leves 5 min | fogueira: 3 grãos |

Novos colocáveis: **fogueira** (galhos, pedra, madeira; aquece e cozinha), **poço** (enche o cantil) e **espelho** (abre o editor).

### Roupas (`items.json → wear`)

Espaços: cabeça, corpo, pernas, pés e costas. `cold`/`heat` em graus de proteção; `color` e `colors` (as cores que a tinta pode dar). O **tecido** sai de 3 flores na bancada; a **tinta** de 2 flores da mesma cor (vermelha, amarela, branca, roxa, azul, rosa).

| Peça | Espaço | Frio | Calor | Como |
| --- | --- | --- | --- | --- |
| Gorro | cabeça | 6 | — | 2 tecidos |
| Chapéu de palha | cabeça | — | 6 | 3 grãos, 1 galho |
| Boné | cabeça | — | 3 | 1 tecido, 1 flor azul |
| Gorro de pele | cabeça | 9 | — | loja (países frios) |
| Chapéu de sol | cabeça | 1 | 7 | loja (países quentes) |
| Cachecol | corpo | 4 | — | 2 tecidos |
| Casaco | corpo | 10 | — | 4 tecidos, 1 madeira; loja (alguns países) |
| Regata | corpo | — | 5 | 2 tecidos |
| Poncho | corpo | 7 | 1 | loja (Andes e vizinhos) |
| Calça | pernas | 4 | — | 3 tecidos |
| Bermuda | pernas | — | 4 | 2 tecidos |
| Botas | pés | 4 | — | 1 tecido, 2 madeiras |
| Sandálias | pés | — | 3 | 2 galhos, 1 tecido |
| Capa de bandeiras | costas | 2 | — | loja de todo país (mostra os carimbos) |

## Flores (fase 4.0)

As flores colhíveis vêm do servidor (`objects.json`, kind `flower`, com `seasons`: em que estações aparecem; `none` = trópicos e biomas sem estação). Cada espécie é um item com a tag `flower`, `color` e `rarity`, e vira página da Goblopédia (seção Flores) sozinha.

| Flor | Onde | Estações | Raridade |
| --- | --- | --- | --- |
| Girassol | campo, floresta tropical | verão, trópicos | comum |
| Lavanda | campo, montanha | primavera, verão | comum |
| Papoula | floresta, campo | primavera, verão | comum |
| Margarida | campo, floresta | primavera a outono | comum |
| Tulipa | floresta, campo | primavera | incomum |
| Campainha-azul | floresta | primavera | incomum |
| Galanto | floresta | inverno | incomum |
| Urze | tundra, montanha | verão, outono | comum |
| Genciana | montanha, tundra | primavera, verão | incomum |
| Edelvais | montanha | verão | rara |
| Cacto florido | deserto | sempre | comum |
| Hibisco | floresta tropical, praia | sempre | comum |
| Orquídea | floresta tropical | sempre | rara |
| Ipê-amarelo (arvorezinha) | floresta tropical, campo | trópicos, primavera | incomum |
| Flor de lótus | praia (beira d'água) | trópicos, verão | rara |

As cinco flores antigas (vermelha, amarela, branca, roxa e azul) continuam e agora somem no inverno. As **flores decorativas** (só enfeite) ficam em `client/data/decoracao.json → flowers`, por bioma e estação, no mesmo MultiMesh da grama, com densidade e distância próprias por qualidade (`flower_density`, `flower_radius` em `quality.gd`; somem antes da grama, fase 4.1).

## Cabeças, chapéus e óculos (`cabecas.json`, fase 4.2)

A cabeça é uma das 12 originais do Mini Characters, inteira (rosto e cabelo, como vieram; [ADR 0053](decisoes/0053-cabeca-inteira-pele-e-foto-centralizada.md)). Não há cabelo, cor do cabelo nem penteado separados. No arquivo:

- `anchor`: ponto de encaixe dos chapéus no alto do crânio (preso ao osso da cabeça);
- `hats`: ajuste por cabeça para o chapéu cobrir o cabelo dela sem flutuar (`offset` [x, y, z], `scale`, `rot` em graus); `default` para as outras. Coques e cabelos compridos saem por trás do chapéu;
- `face`: ponto dos óculos (os mesmos que já vêm em `male-a` e `male-e`), preso ao osso da cabeça; `faces`: ajuste por cabeça (`offset`, `scale`);
- `cap_heads`: cabeças cujo "cabelo" é um quepe (`male-c`): com chapéu vestido, o quepe sai.

Tons de pele e acessórios oferecidos ficam em `server/data/game/body.json → look` (o servidor valida). A pele de cada personagem é o par de faixas da paleta das orelhas dele; o tom escolhido vale para a cabeça, o corpo, as pernas e a pele que a roupa deixa à mostra. As 12 cabeças aceitam todos os tons sem pintar cabelo, barba, bigode ou quepe.

Roupas substituem a parte da roupa original do espaço delas (cor por região, sem malha a mais). Peça nova: item com `wear` em `items.json` e a regra da região em `CharacterLook` (`_body_color`, `_legs_color`) ou a forma em `_add_hat`/`_build`; o `client/tests/test_roupas.gd` confere que ela só muda o próprio espaço.

Ícones de líquidos: tintas usam `primitive:paint_RRGGBB` (o pote cheio da cor), o cantil `primitive:canteen_N` (N = goles que restam, na janelinha da frente).

## Cavernas (`caves.json`, fase 4.5)

Bocas por país (`entrances`: uma a cada `per_land_cells` células, entre `min` e `max`, em montanha ou morro), desenho dos salões (`layout`), minérios, enfeites que brilham, tochas, temperatura, baú, fornalha e o chefe. Detalhes no `_doc` do arquivo e no [ADR 0056](decisoes/0056-cavernas-em-mapa-separado.md).

| Minério | Item | Picareta mínima | Golpes | Dá | Profundidade |
| --- | --- | --- | --- | --- | --- |
| Carvão | `coal` | pedra | 3 | 2–3 | toda |
| Ferro | `iron_ore` | pedra | 4 | 1–2 | até 85% |
| Goblita (brilha) | `goblita` | ferro | 4 | 1–2 | a partir de 30% |
| Diamante | `diamond` | ferro | 6 | 1 | a partir de 60% |
| Auralita (brilha) | `auralita` | diamante | 6 | 1 | a partir de 70% |

Cada nível acima do mínimo: um golpe a menos e um item a mais. Cada minério quebra uma vez por dia por jogador.

**Chefe (`boss`):** `attacks` ataques por sequência, um a cada `interval` s, aviso de `warn` s, círculos de `circle_radius`, `sequences` sequências até dormir por `sleep` s; `dodge_to_win` desvios para vencer; `hits` acertos voltam ao começo. Recompensa (`reward`): gobolares, o coração de cristal e a conquista, uma vez por dia por caverna.

**Receitas novas:** tocha (carvão + galho → 4), fornalha, baú, picaretas e machados de ferro, diamante e goblita (a de goblita precisa do coração de cristal), capacete com luz, luminária de auralita. **Fornalha** (`station: furnace`, `seconds` por unidade): barras de ferro, goblita e auralita e carvão de madeira.

## Folclore (`folklore.json`, fase 4.5)

`window` (minutos de cada sorteio), `shy` (a criatura some com o jogador mais perto que isso), e cada lenda com `country`, `story`, `biomes`, `lat` (opcional), `water` (só a cabeça, na beira do mar), `hours` (horas locais), `seasons`, `chance` (por célula e janela), `duration` (minutos) e `colors`. A lista e a origem de cada uma estão em [`docs/FOLCLORE.md`](FOLCLORE.md).
