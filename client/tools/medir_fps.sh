#!/usr/bin/env bash
# Mede os fps nas cenas da meta de desempenho (ADR 0028), com a janela NA FRENTE e
# maximizada. Feche vídeos e outros apps pesados antes e deixe o Mac esfriar: a GPU
# esquenta e as últimas medições saem piores. Leva ~4 minutos.
#
#   tools/medir_fps.sh [servidor] [perfil]
#
# O perfil precisa ter 20 vizinhos (F1 → "Criar 20 vizinhos falsos aqui perto").
cd "$(dirname "$0")/.."
G="${GODOT:-$HOME/sdk/godot/Godot.app/Contents/MacOS/Godot}"
S="${1:-http://127.0.0.1:8080}"
P="${2:-player}"
run() {
	echo "== $1"; shift
	perl -e 'alarm 120; exec @ARGV' "$G" --path . -- --server="$S" --profile="$P" --utc=15 "$@" 2>&1 | grep -E "desempenho|tempo médio|janela"
	sleep 20  # a GPU esfria um pouco entre as medições
}
run "alta, bairro" --perf-test=15 --quality=high
run "média, bairro" --perf-test=15 --quality=medium
run "alta, floresta tropical" --perf-test=15 --quality=high --spawn=-3,-60
run "média, floresta tropical" --perf-test=15 --quality=medium --spawn=-3,-60
run "média, globo afastado" --perf-test=12 --quality=medium --zoom=1
