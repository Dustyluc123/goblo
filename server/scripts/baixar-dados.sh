#!/usr/bin/env bash
# Baixa os dados do Natural Earth (domínio público) usados pelo servidor.
# Fonte: https://www.naturalearthdata.com — espelho em GeoJSON mantido pelo próprio projeto:
#   https://github.com/nvkelso/natural-earth-vector
#
# - 1:110m land: terra/oceano (usado como vem);
# - 1:50m admin_0_countries e populated_places_simple: países e capitais, filtrados para
#   paises.geojson e capitais.json (fronteiras pela posição exata, aeroportos; ADR 0031);
# - 1:50m geography_regions_polys: desertos, cordilheiras etc. para os biomas. É grande
#   (4 MB), então fica em data/raw/ (fora do Git) e é filtrado para regioes.geojson.
#
# Uso: ./scripts/baixar-dados.sh   (rode de dentro de server/)
set -euo pipefail

VERSAO="${NATURAL_EARTH_VERSAO:-v5.1.2}"
BASE="https://raw.githubusercontent.com/nvkelso/natural-earth-vector/${VERSAO}/geojson"
SERVER="$(cd "$(dirname "$0")/.." && pwd)"
DESTINO="${SERVER}/data/naturalearth"
BRUTO="${SERVER}/data/raw"

mkdir -p "$DESTINO" "$BRUTO"
echo "Baixando ne_110m_land.geojson (${VERSAO})..."
curl -fsSL "${BASE}/ne_110m_land.geojson" -o "${DESTINO}/ne_110m_land.geojson"

for arquivo in ne_50m_admin_0_countries.geojson ne_50m_populated_places_simple.geojson; do
  echo "Baixando ${arquivo} (${VERSAO})..."
  curl -fsSL "${BASE}/${arquivo}" -o "${BRUTO}/${arquivo}"
done
echo "Filtrando países e capitais..."
(cd "$SERVER" && go run ./cmd/filtra-paises "${BRUTO}/ne_50m_admin_0_countries.geojson" \
  "${BRUTO}/ne_50m_populated_places_simple.geojson" "${DESTINO}/paises.geojson" "${DESTINO}/capitais.json")

echo "Baixando ne_50m_geography_regions_polys.geojson (${VERSAO})..."
curl -fsSL "${BASE}/ne_50m_geography_regions_polys.geojson" -o "${BRUTO}/ne_50m_geography_regions_polys.geojson"
echo "Filtrando regiões para biomas..."
(cd "$SERVER" && go run ./cmd/filtra-regioes "${BRUTO}/ne_50m_geography_regions_polys.geojson" "${DESTINO}/regioes.geojson")

# Base IP → país "IP to Country Lite" da DB-IP (CC BY 4.0, atualizada todo mês). Opcional:
# sem ela, o país do jogador novo vem só do idioma do sistema. Fica fora do Git.
MES="$(date +%Y-%m)"
MES_ANTERIOR="$(date -v-1m +%Y-%m 2>/dev/null || date -d '1 month ago' +%Y-%m)"
echo "Baixando a base IP → país da DB-IP..."
for m in "$MES" "$MES_ANTERIOR"; do
  if curl -fsSL "https://download.db-ip.com/free/dbip-country-lite-${m}.csv.gz" -o "${BRUTO}/dbip-country-lite.csv.gz"; then
    echo "  dbip-country-lite ${m} (IP Geolocation by DB-IP, https://db-ip.com, CC BY 4.0)"
    break
  fi
done

echo "Pronto: ${DESTINO}"
ls -lh "$DESTINO"
