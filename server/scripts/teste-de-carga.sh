#!/usr/bin/env bash
# Teste de carga do multiplayer (fase 3): sobe um servidor de teste (porta 8090, banco
# temporário, modo dev), solta N bots na mesma região e mede CPU, memória e banda do
# servidor. Não mexe no servidor da porta 8080 nem no goblo.db.
#
#   scripts/teste-de-carga.sh [bots] [segundos]      # padrão: 100 bots, 60 s
set -euo pipefail
cd "$(dirname "$0")/.."
N="${1:-100}"
SECS="${2:-60}"
TMP="$(mktemp -d)"
go build -o "$TMP/server" ./cmd/server
go build -o "$TMP/bots" ./cmd/bots
GOBLO_DEV=1 "$TMP/server" -addr :8090 -db "$TMP/carga.db" > "$TMP/server.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null; rm -rf "$TMP"' EXIT
for i in $(seq 1 60); do curl -s localhost:8090/health >/dev/null && break; sleep 1; done
echo "servidor no ar (pid $SRV); $N bots por $SECS s"
"$TMP/bots" -server http://127.0.0.1:8090 -n "$N" -duration "${SECS}s" > "$TMP/bots.txt" 2>&1 &
BOTS=$!
sleep 15  # os bots entram e o mundo deles é gerado
echo "amostras do servidor (a cada 5 s): CPU % de um núcleo, memória MB"
SUM=0; MAX=0; K=0; MEMMAX=0
while kill -0 $BOTS 2>/dev/null; do
  read -r CPU RSS < <(ps -o %cpu=,rss= -p $SRV)
  printf "  CPU %5s%%  memória %5d MB\n" "$CPU" $((RSS / 1024))
  SUM=$(echo "$SUM + $CPU" | bc); K=$((K + 1))
  if (( $(echo "$CPU > $MAX" | bc) )); then MAX=$CPU; fi
  if (( RSS / 1024 > MEMMAX )); then MEMMAX=$((RSS / 1024)); fi
  sleep 5
done
wait $BOTS || true
cat "$TMP/bots.txt" | grep -v "^20" || true
TOKEN=$(curl -s -X POST localhost:8090/players -H 'Content-Type: application/json' -d '{"nickname":"Medidor","country":"BRA"}' | sed -E 's/.*"token":"([^"]+)".*/\1/')
STATS=$(curl -s localhost:8090/dev/online -H "Authorization: Bearer $TOKEN")
echo "servidor: CPU média $(echo "scale=1; $SUM / $K" | bc)% e máxima $MAX% de um núcleo; memória máxima $MEMMAX MB"
echo "$STATS" | python3 -c 'import sys,json; s=json.load(sys.stdin)["stats"]; t=s["uptime_ms"]/1000; print("servidor mandou %.0f KB/s e recebeu %.0f KB/s em média desde que subiu (%d s)" % (s["bytes_out"]/1024/t, s["bytes_in"]/1024/t, t))'
