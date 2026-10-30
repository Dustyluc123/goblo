# 0042 — Praça central: loja com estoque do dia, aeroporto de verdade e NPCs

## Contexto

A fase 3.5 pede, em cada país, uma praça central perto da capital com o aeroporto, uma loja e um ponto de encontro, atendidos por NPCs.

## Decisão

- **A praça fica no hexágono do aeroporto** (ADR 0035), que já não tem lotes, objetos nem animais.
  - Nos países com aeroporto de verdade: o terminal com vidraça e o balcão (atendente), a torre de controle, a pista com marcações, a biruta, o portão de embarque, veículos de pátio do Car Kit, o avião parado e a loja (lojista).
  - Nos países pequenos (menos de 3 hexágonos), a loja divide o balcão com o aeroporto.
  - Os pontos ficam em `airports.go` e `shop.go` (`ShopPoint`).
- **Estoque do dia** (`shop.json`):
  - itens fixos (ferramentas, câmera, sementes);
  - alguns rotativos (decorações que não se fabricam, móveis, variações de cor), sorteados com a semente país + dia;
  - exclusivos regionais (o moinho nos Países Baixos e vizinhos, o fardo de feno nas Américas e na Oceania…).

  O dia é o do jogo no horário do aeroporto (vira às 5h locais), então todos do país veem o mesmo estoque. O modo dev adianta o estoque de um país (`/dev/shop/restock`).
- **A loja compra qualquer item**, pagando `shop_buy_bonus` (1,25) vezes a caixa de vendas, para valer a ida até a praça.
- **Distância:** comprar e vender exige estar no balcão da loja (`reach.shop`, com o tempo real ligado, como no ADR 0040).

## Consequências

- Mudar `shop.json` muda o estoque de todo mundo. É o lugar para balancear e para criar exclusivos novos.
- A posição do balcão da loja é a mesma para o servidor e para o cliente: as duas usam o plano do hexágono do aeroporto.
