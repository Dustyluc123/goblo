# Biomas

Cada célula de terra recebe um bioma e uma altura no servidor (`server/internal/world/biome.go` e `regions.go`). A meta não é precisão científica: é o mapa ficar **reconhecível e bonito**.

## Fontes

1. **Natural Earth 1:110m** — `land` (terra ou oceano) e `admin_0_countries` (país), como na fase 1.
2. **Natural Earth 1:50m `geography_regions_polys`** — polígonos de desertos, cordilheiras, planícies, bacias, planaltos e tundras, com nome e `SCALERANK`. Filtrados por `server/cmd/filtra-regioes` (278 de 522 regiões, coordenadas com 2 casas): `server/data/naturalearth/regioes.geojson`.
3. **Polígonos à mão** (em `regions.go`, precisão de centenas de km) para o que o Natural Earth não traz: Mata Atlântica, Sudeste Asiático, América Central, floresta da África Ocidental, savanas da África Oriental e do norte da Austrália.
4. **Regras de latitude** para o resto.

## Ordem de decisão (pelo centro da célula)

| Prioridade | Bioma | Regra |
| --- | --- | --- |
| 1 | `ice` | Antártida (`ATA`), Groenlândia (`GRL`) ou latitude > 80° N |
| 2 | `mountain` | cordilheiras com `SCALERANK` ≤ 3 (Andes, Himalaia, Alpes, Rochosas, Atlas…), Planalto do Tibete e Altiplano |
| 3 | `desert` | regiões "Desert" (Saara, Atacama, Gobi, Kalahari, Rub' al Khali…), Península Arábica, centro da Austrália, Grande Bacia, Tarim, Planalto do Colorado… |
| 4 | `tundra` | regiões "Tundra" (exceto o Escudo Canadense), latitude > 66° N ou < 50° S |
| 5 | `tropical_forest` | Bacia Amazônica, Bacia do Congo, Escudo das Guianas, Selvas, Yungas e os polígonos à mão |
| 6 | `grassland` | planícies de campo (Grandes Planícies, Pampas, estepes, Sahel, Llanos, Chaco…), cerrado (Planalto Central, Planalto Brasileiro), Deccan, savanas à mão |
| 7 | por latitude | \|lat\| < 12° → `tropical_forest`; < 35° → `grassland`; senão `forest` |

Depois, olhando os vizinhos:

- **`beach`**: terra de floresta, campo ou deserto vizinha do oceano com \|lat\| < 42°;
- a costa da Groenlândia vira `tundra` (o gelo fica no interior);
- **colinas e dunas**: cordilheiras pequenas (`SCALERANK` 4, como Serra do Mar e Mantiqueira), sopés e manchas de um ruído 3D determinístico (`noise.go`) sobem um degrau.

## Alturas (unidades do jogo acima do nível do mar)

| Bioma | Altura | Por quê |
| --- | --- | --- |
| `ocean` | 0 | |
| `beach` | 0,4 | quase no nível do mar; da praia para o campo (0,4) sobe andando |
| terras baixas (floresta, campo, deserto, tundra) | 0,8 | |
| colinas/dunas | 1,4 | degrau de 0,6: precisa pular (o pulo alcança 1,3) |
| `ice` | 1,4 (2,0 longe da costa) | |
| `mountain` | 1,4 + 1,2 por anel para dentro (até 8 anéis) | escalável pulando degrau por degrau; o miolo do Tibete chega a 5,0 e o ponto mais alto, a 6,2 |

O "anel" é a distância, em células, até a borda da montanha (busca em largura pelos vizinhos).

## Resultado (n = 50)

| Bioma | Células |
| --- | ---: |
| oceano | 17.718 |
| campo | 1.433 |
| floresta | 1.403 |
| deserto | 961 |
| montanha | 904 |
| praia | 787 |
| floresta tropical | 747 |
| gelo | 647 |
| tundra | 402 |

## Vegetação de cada bioma

Desde a fase 2, árvores, pedras, flores e arbustos de cada bioma vêm do **Ultimate Nature Pack** e são gerados pelo servidor (`server/data/game/objects.json`); a grama decorativa é do cliente (`client/data/decoracao.json`). O mapeamento completo está em [`CONTEUDO.md`](CONTEUDO.md#objetos-do-mundo-objectsjson).

## Limites conhecidos

- O Natural Earth não tem relevo: as montanhas saem dos polígonos de cordilheira, não de altitude real. Cordilheiras estreitas ficam com 1 ou 2 anéis.
- Cerrado e Caatinga viram `grassland`; não há bioma de savana separado.
- Os polígonos à mão são aproximados de propósito. Para refinar, troque por dados de ecorregiões (ex.: RESOLVE Ecoregions 2017, CC-BY 4.0) numa fase futura.
