#!/usr/bin/env bash
# Roda DOIS jogos headless ao mesmo tempo contra o mesmo servidor (dev) e confere que um vê o
# outro: entrar na área de interesse, movimento interpolado e chat (--mp-test). Sem janela.
#
#   tools/dois_clientes.sh [servidor]          # padrão http://127.0.0.1:8080
#
# Para jogar com DUAS JANELAS no mesmo Mac (você mesmo testando), use perfis diferentes:
#   godot --path . -- --profile=jogador1 &
#   godot --path . -- --profile=jogador2
cd "$(dirname "$0")/.."
G="${GODOT:-$HOME/sdk/godot/Godot.app/Contents/MacOS/Godot}"
S="${1:-http://127.0.0.1:8080}"
R=$RANDOM
A="DuplaA$R"
B="DuplaB$R"
SPAWN="--spawn=-23.55,-46.63"
perl -e 'alarm 150; exec @ARGV' "$G" --headless --path . -- --server="$S" --profile="dupla_a_$R" --nickname="$A" --country=BRA $SPAWN --mp-test=a --peer="$B" > "/tmp/goblo_dupla_a_$R.log" 2>&1 &
PA=$!
sleep 2
perl -e 'alarm 150; exec @ARGV' "$G" --headless --path . -- --server="$S" --profile="dupla_b_$R" --nickname="$B" --country=BRA $SPAWN --mp-test=b --peer="$A" > "/tmp/goblo_dupla_b_$R.log" 2>&1 &
PB=$!
wait $PA; RA=$?
wait $PB; RB=$?
grep -h "mp-test\|SCRIPT ERROR" "/tmp/goblo_dupla_a_$R.log" "/tmp/goblo_dupla_b_$R.log"
rm -f "/tmp/goblo_dupla_a_$R.log" "/tmp/goblo_dupla_b_$R.log"
if [[ $RA -eq 0 && $RB -eq 0 ]]; then echo "dois clientes: tudo certo"; exit 0; fi
echo "dois clientes: FALHOU (a=$RA, b=$RB)"; exit 1
