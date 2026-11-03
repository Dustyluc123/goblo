# 0044 — Troca entre jogadores: negociação na memória, execução atômica

**Fase 3.5** (escrito na 4.0, descrevendo o que foi feito).

## Contexto

Dois jogadores perto um do outro precisam trocar itens e gobolares, vendo a oferta um do outro em tempo real, sem risco de duplicar ou perder nada.

## Decisão

- **Negociação no hub** (`realtime/trade.go`), só na memória: pedido (vale 30 s), abertura, ofertas, "pronto" e confirmação final. O protocolo está em `docs/PROTOCOLO.md` (`trade_*`).
- **Qualquer mudança na oferta desfaz os "pronto" e as confirmações dos dois.** Assim ninguém confirma algo diferente do que viu.
- **Só `Service.ExecuteTrade` mexe no banco**, numa transação: confere de novo bolso, espaço, distância (`reach.trade`) e bloqueio; move itens e gobolares e grava o histórico. Se algo mudou entre a confirmação e a execução, nada acontece e os "pronto" caem.
- Bloqueio e "não aceitar pedidos" (F6) valem para a troca. No modo dev, bots de número par aceitam e oferecem 3 madeiras.

## Consequências

- Uma queda do servidor no meio da negociação só perde a negociação, nunca itens.
- Trocas com muitos participantes ou leilões precisariam de outra estrutura.
