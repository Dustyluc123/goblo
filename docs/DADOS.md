# Dados geográficos

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

## Observações

- As fronteiras do Natural Earth seguem a visão *de facto* do projeto. Para um jogo isso basta, mas fronteiras disputadas podem precisar de atenção antes da fase 4 (fronteiras jogáveis).
- Na escala 1:110m, ilhas pequenas não aparecem. Com a grade de 25.002 células, 162 dos 177 países têm pelo menos uma célula.
