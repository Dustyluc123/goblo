#!/usr/bin/env bash
# Falha se o repositório citar outro jogo (ou estúdio/personagem de outro jogo) no código,
# nos textos do jogo ou na documentação. O Goblo tem identidade própria.
#
#   scripts/verificar-nomes.sh          confere os arquivos do Git
#   scripts/verificar-nomes.sh --lista  mostra a lista de nomes proibidos
#
# A lista fica em base64 para os próprios nomes não aparecerem no repositório.
# Para acrescentar um nome: decodifique, edite e codifique de novo (base64).
set -euo pipefail
cd "$(dirname "$0")/.."

LISTA_B64='YW5pbWFsIGNyb3NzaW5nfG5vb2t8c3RhcmRld3xtaW5lY3JhZnR8cGFsaWF8emVsZGF8cG9rW2XDqV1tb258dGVycmFyaWF8Zm9ydG5pdGV8cm9ibG94fHRoZSBzaW1zfHZhbGhlaW18aGFydmVzdCBtb29ufHN0b3J5IG9mIHNlYXNvbnN8Y296eSBncm92ZXxzcGlyaXRmYXJlcnxubyBtYW4uP3Mgc2t5fHdhcmNyYWZ0fHJ1bmVzY2FwZXxoYWJib3xjbHViIHBlbmd1aW58c2Vjb25kIGxpZmV8Z2VvZ3Vlc3NyfHN1cGVyIG1hcmlvfG5pbnRlbmRvfGRyZWFtbGlnaHR8d3lsZGUgZmxvd2Vyc3xjb3JhbCBpc2xhbmR8c3VuIGhhdmVufHBvcnRpYXxzbGltZSByYW5jaGVyfG9vYmxldHN8ZmFlIGZhcm18c2VhIG9mIHRoaWV2ZXN8Z2Vuc2hpbnxhbmltYWwgamFtfHRvd25zY2FwZXJ8dGlueSBnbGFkZXx1bnBhY2tpbmd8YSBzaG9ydCBoaWtl'
PADRAO="$(printf '%s' "$LISTA_B64" | base64 --decode)"

if [[ "${1:-}" == "--lista" ]]; then
	printf '%s\n' "$PADRAO" | tr '|' '\n'
	exit 0
fi

# -I pula binários; -w só palavras inteiras; -i sem diferenciar maiúsculas.
# Os dados geográficos (nomes de lugares reais) e as licenças dos assets ficam de fora.
if git grep -nIiwE "$PADRAO" -- . 	':!server/data/naturalearth/**' ':!server/data/regions/**' ':!server/data/geoip/**' 	':!**/License.txt' ':!**/LICENSE*'; then
	echo
	echo "Achei nomes de outros jogos (acima). O Goblo não cita outros jogos: reescreva com termos próprios."
	exit 1
fi
echo "Nenhum nome de outro jogo encontrado."
