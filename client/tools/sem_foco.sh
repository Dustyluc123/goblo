#!/usr/bin/env bash
# Roda o Goblo (com janela) sem roubar o foco de quem está usando o Mac.
#
#   tools/sem_foco.sh -- --screenshot=/tmp/a.png --profile=t1 ...
#   tools/sem_foco.sh -s tools/montar_casas.gd -- --fotos=/tmp/c --so-fotos
#
# O que vem antes do "--" vai para o Godot (ex.: -s script); o que vem depois, para o jogo.
#
# Usa `open -g` (abre em segundo plano, sem ativar o app), pede ao jogo a janela sem foco
# (--no-focus) e espera ele fechar. A saída do jogo aparece no terminal no final.
# Só para testes: a configuração normal do jogo não muda.
# Variáveis: GODOT (caminho do executável), GOBLO_TIMEOUT (segundos, padrão 200).
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT_APP="${GODOT_APP:-$HOME/sdk/godot/Godot.app}"
TIMEOUT="${GOBLO_TIMEOUT:-200}"
ENGINE_ARGS=()
if [[ " $* " == *" -- "* ]]; then
	while [[ $# -gt 0 && "$1" != "--" ]]; do
		ENGINE_ARGS+=("$1")
		shift
	done
	shift
fi
LOG="$(mktemp -t goblo-sem-foco)"
# -g: não traz para a frente; -n: instância nova; -W: espera fechar.
perl -e "alarm $TIMEOUT; exec @ARGV" open -g -n -W -a "$GODOT_APP" \
	--stdout "$LOG" --stderr "$LOG" \
	--args --path "$PWD" ${ENGINE_ARGS[@]+"${ENGINE_ARGS[@]}"} -- --no-focus --goblo-test-id=$$ "$@" || status=$?
# Se estourou o tempo, fecha só o jogo deste teste.
pkill -f "goblo-test-id=$$" 2>/dev/null || true
cat "$LOG"
rm -f "$LOG"
exit "${status:-0}"
