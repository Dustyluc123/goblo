# 0024 — Modo desenvolvedor com GOBLO_DEV e relógio adiantável

**Status:** aceita (fase 2)

## Contexto
Para testar o ciclo (coletar, fabricar, construir, voltar amanhã) sem jogar de verdade, o autor precisa de atalhos: dar itens, concluir obras, avançar o dia, teleportar, voar, criar vizinhos. Esses atalhos não podem existir num servidor de verdade.

## Decisão
- As rotas `/dev/…` só são registradas com **`GOBLO_DEV=1`**. Sem isso, qualquer `/dev/…` responde `403 dev_only` (há teste para cada rota).
- Com o modo dev, as regras usam um **`OffsetClock`** (relógio real + deslocamento). "Dia seguinte" adianta esse relógio até logo depois da próxima virada do jogador: os limites zeram e as obras ficam prontas **pelas regras de verdade**, sem atalho especial. Vale para todos os jogadores do servidor, o que é o esperado num servidor de teste.
- No cliente, **F1** abre o painel só se o servidor disser que está em modo dev (`"dev": true` no `/content`). Teleporte, voo (noclip) e tempo do céu (F3/F4) são só do cliente.
- O mesmo relógio injetável (`game.Clock`) é usado nos testes, com uma base fixa.

## Consequências
- O relógio adiantado não volta sozinho: reinicie o servidor para voltar à hora real.
- Vizinhos falsos ficam no banco (com `fake = 1`) até um reset ou até apagar o arquivo do banco.
