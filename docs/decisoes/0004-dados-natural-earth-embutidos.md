# 0004 — Dados do Natural Earth no Git e embutidos no binário

**Status:** aceita (fase 1)

## Contexto
O briefing pede um script para baixar os dados. Também queremos que `go test ./...` rode no CI e em qualquer máquina sem passo extra nem rede.

## Decisão
- `server/scripts/baixar-dados.sh` baixa a versão fixada (5.1.2) dos GeoJSON 1:110m.
- Os dois arquivos (≈1 MB) ficam versionados em `server/data/naturalearth/` e são embutidos com `go:embed` (pacote `server/data`).
- Pastas `data/raw/` ficam no `.gitignore` para downloads maiores no futuro (ex.: escala 1:50m).

## Por quê
É a opção mais simples: o binário roda de qualquer pasta, os testes são reprodutíveis e a versão dos dados fica registrada no Git.

## Consequências
- Atualizar os dados é rodar o script com outra versão e commitar o resultado; os testes de São Paulo/Atlântico/proporção de oceano protegem contra surpresas.
