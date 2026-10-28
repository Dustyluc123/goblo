#!/usr/bin/env bash
# Baixa os dados do Natural Earth (escala 1:110m, domínio público) usados pelo servidor.
# Fonte: https://www.naturalearthdata.com — espelho em GeoJSON mantido pelo próprio projeto:
#   https://github.com/nvkelso/natural-earth-vector
# Uso: ./scripts/baixar-dados.sh   (rode de dentro de server/)
set -euo pipefail

VERSAO="${NATURAL_EARTH_VERSAO:-v5.1.2}"
BASE="https://raw.githubusercontent.com/nvkelso/natural-earth-vector/${VERSAO}/geojson"
DESTINO="$(cd "$(dirname "$0")/.." && pwd)/data/naturalearth"

mkdir -p "$DESTINO"
for arquivo in ne_110m_land.geojson ne_110m_admin_0_countries.geojson; do
  echo "Baixando ${arquivo} (${VERSAO})..."
  curl -fsSL "${BASE}/${arquivo}" -o "${DESTINO}/${arquivo}"
done
echo "Pronto: ${DESTINO}"
ls -lh "$DESTINO"
