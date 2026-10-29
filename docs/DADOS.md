# Dados

## Geografia (Natural Earth)

| Arquivo | Conteúdo |
| --- | --- |
| `server/data/naturalearth/ne_110m_land.geojson` | polígonos de terra |
| `server/data/naturalearth/ne_110m_admin_0_countries.geojson` | países (nível 0), com códigos ISO e nomes em português |
| `server/data/naturalearth/regioes.geojson` | regiões geográficas da escala 1:50m (desertos, cordilheiras, planícies, bacias, planaltos, tundras), filtradas para os biomas |

- **Fonte:** [Natural Earth](https://www.naturalearthdata.com/), versão 5.1.2, pelo espelho GeoJSON oficial [nvkelso/natural-earth-vector](https://github.com/nvkelso/natural-earth-vector). Terra e países na escala 1:110m; regiões (`ne_50m_geography_regions_polys`) na 1:50m.
- **Filtro das regiões:** o arquivo original tem 4,3 MB e fica em `server/data/raw/` (fora do Git). `go run ./cmd/filtra-regioes` mantém só as classes usadas e as propriedades `NAME`, `FEATURECLA` e `SCALERANK`, com coordenadas de 2 casas: 278 regiões, 583 KB. Como os biomas usam essas regiões, veja [`BIOMAS.md`](BIOMAS.md).
- **Licença:** domínio público ([termos de uso](https://www.naturalearthdata.com/about/terms-of-use/)). Não exige atribuição, mas citamos a fonte mesmo assim.
- **Como baixar de novo:** `cd server && ./scripts/baixar-dados.sh` (troque a versão com `NATURAL_EARTH_VERSAO=v5.x.y`).

Os arquivos ficam no Git (≈1,5 MB) e são embutidos no binário com `go:embed`; veja [`decisoes/0004-dados-natural-earth-embutidos.md`](decisoes/0004-dados-natural-earth-embutidos.md).

### Observações

- As fronteiras do Natural Earth seguem a visão *de facto* do projeto. Para um jogo isso basta, mas fronteiras disputadas podem precisar de atenção antes da fase 4 (fronteiras jogáveis).
- Na escala 1:110m, ilhas pequenas não aparecem. Com a grade de 25.002 células, 162 dos 177 países têm pelo menos uma célula.

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
