# Dados

## Geografia (Natural Earth)

| Arquivo | Conteúdo |
| --- | --- |
| `server/data/naturalearth/ne_110m_land.geojson` | polígonos de terra |
| `server/data/naturalearth/paises.geojson` | países (nível 0) da escala 1:50m: código ISO A3, ISO A2 e nome em português (240 países, 1,8 MB) |
| `server/data/naturalearth/capitais.json` | capital de cada país (lugares povoados 1:50m), para os aeroportos |
| `server/data/naturalearth/regioes.geojson` | regiões geográficas da escala 1:50m (desertos, cordilheiras, planícies, bacias, planaltos, tundras), filtradas para os biomas |

- **Fonte:** [Natural Earth](https://www.naturalearthdata.com/), versão 5.1.2, pelo espelho GeoJSON oficial [nvkelso/natural-earth-vector](https://github.com/nvkelso/natural-earth-vector). Terra na escala 1:110m (a forma do globo); países, capitais (`ne_50m_admin_0_countries`, `ne_50m_populated_places_simple`) e regiões (`ne_50m_geography_regions_polys`) na 1:50m.
- **Filtro dos países:** `go run ./cmd/filtra-paises` junta os países que repetem o código (Austrália e ilhas Ashmore e Cartier), guarda só código, A2 e nome, com coordenadas de 4 casas (~11 m), e escolhe a capital de cada país ("Admin-0 capital"; sem ela, a maior cidade). Os originais ficam em `server/data/raw/`. Por que 1:50m e não 1:10m: [ADR 0031](decisoes/0031-fronteiras-pela-posicao-exata.md).
- **Filtro das regiões:** o arquivo original tem 4,3 MB e fica em `server/data/raw/` (fora do Git). `go run ./cmd/filtra-regioes` mantém só as classes usadas e as propriedades `NAME`, `FEATURECLA` e `SCALERANK`, com coordenadas de 2 casas: 278 regiões, 583 KB. Como os biomas usam essas regiões, veja [`BIOMAS.md`](BIOMAS.md).
- **Licença:** domínio público ([termos de uso](https://www.naturalearthdata.com/about/terms-of-use/)). Não exige atribuição, mas citamos a fonte mesmo assim.
- **Como baixar de novo:** `cd server && ./scripts/baixar-dados.sh` (troque a versão com `NATURAL_EARTH_VERSAO=v5.x.y`).

Os arquivos ficam no Git (≈2,6 MB) e são embutidos no binário com `go:embed`; veja [`decisoes/0004-dados-natural-earth-embutidos.md`](decisoes/0004-dados-natural-earth-embutidos.md).

### Observações

- **Áreas disputadas:** usamos a versão padrão do Natural Earth (a visão *de facto* do projeto), sem tomar lado. Ela inclui, por exemplo, Kosovo, Somalilândia, Chipre do Norte e Saara Ocidental como áreas próprias.
- O país de uma posição é decidido pelo 1:50m (ponto em polígono); cada hexágono ainda tem um "país principal" (o do centro, ou o mais perto se o 1:50m deixar o centro no mar), usado para bioma, lotes e mini mapa. Países pequenos (Luxemburgo, Andorra, Mônaco, Liechtenstein, San Marino, Vaticano…) existem pela posição exata, mesmo sem célula própria.

## IP → país (DB-IP)

| Arquivo | Conteúdo |
| --- | --- |
| `server/data/raw/dbip-country-lite.csv.gz` | faixas de IP (IPv4 e IPv6) → código ISO A2 do país; ~4,5 MB, 710 mil faixas |

- **Fonte:** [IP to Country Lite](https://db-ip.com/db/download/ip-to-country-lite) da DB-IP, atualizada todo mês.
- **Licença:** [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/). Crédito exigido: **"IP Geolocation by DB-IP"** com link para <https://db-ip.com>. O servidor mostra o crédito no log ao carregar a base, e ele está no README.
- **Fora do Git:** baixe com `cd server && ./scripts/baixar-dados.sh` (tenta o mês atual e o anterior). Sem a base, o servidor funciona e o país do jogador novo vem só do idioma do sistema.
- **Uso:** só para sugerir o país de um jogador novo (`GET /geo`). O IP não é guardado nem registrado ([ADR 0022](decisoes/0022-identidade-por-token-e-pais-pelo-ip.md)).
- **Testes:** `server/internal/geoip/testdata/amostra.csv` tem 7 linhas reais da base (outubro de 2026) para os testes rodarem sem o arquivo completo.

## Conteúdo do jogo

Itens, receitas, casas e objetos de cada bioma ficam em `server/data/game/*.json` e `client/data/decoracao.json`. Veja [`CONTEUDO.md`](CONTEUDO.md).
