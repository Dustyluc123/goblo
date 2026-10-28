# Dados geográficos

| Arquivo | Conteúdo |
| --- | --- |
| `server/data/naturalearth/ne_110m_land.geojson` | polígonos de terra |
| `server/data/naturalearth/ne_110m_admin_0_countries.geojson` | países (nível 0), com códigos ISO e nomes em português |

- **Fonte:** [Natural Earth](https://www.naturalearthdata.com/), escala 1:110m, versão 5.1.2, pelo espelho GeoJSON oficial [nvkelso/natural-earth-vector](https://github.com/nvkelso/natural-earth-vector).
- **Licença:** domínio público ([termos de uso](https://www.naturalearthdata.com/about/terms-of-use/)). Não exige atribuição, mas citamos a fonte mesmo assim.
- **Como baixar de novo:** `cd server && ./scripts/baixar-dados.sh` (troque a versão com `NATURAL_EARTH_VERSAO=v5.x.y`).

Os arquivos ficam no Git (≈1 MB) e são embutidos no binário com `go:embed`; veja [`decisoes/0004-dados-natural-earth-embutidos.md`](decisoes/0004-dados-natural-earth-embutidos.md).

## Observações

- As fronteiras do Natural Earth seguem a visão *de facto* do projeto. Para um jogo isso basta, mas fronteiras disputadas podem precisar de atenção antes da fase 4 (fronteiras jogáveis).
- Na escala 1:110m, ilhas pequenas não aparecem e alguns países pequenos não têm nenhuma célula na grade de 4.002 células (124 dos 177 países aparecem).
