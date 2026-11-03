# 0050 — Corpo: clima, necessidades gentis e comida

**Fase 4.0.**

## Contexto

O mundo ganha temperatura de verdade e o personagem ganha sede, conforto térmico e fome. O Goblo é para relaxar: as necessidades só podem dar vantagem a quem cuida do personagem, nunca castigar.

## Decisão

- **Temperatura no servidor** (`game/climate.go`, `body.json → climate`): equador quente caindo até os polos (`(|lat|/90)^lat_curve`), estação do hemisfério (amplitude cresce com a latitude, pico do verão em `summer_peak_day`, meio ano depois no sul), hora local pela longitude (mais quente às 15h; amplitude por bioma: deserto 22 °C, floresta tropical 3 °C), graus a mais por bioma e desconto da altura acima das colinas. Contas fofas e coerentes, testadas: Manaus quente, Ushuaia fria em julho, Saara quente ao meio-dia e frio à meia-noite, Antártida gelada, montanha mais fria que a planície vizinha. `GET /temperature?lat=&lon=` responde a de qualquer ponto.
- **Temperatura sentida:** o ar mais a fogueira perto (colocada num lote ou acesa no chão), menos a sombra de árvore e a beira do mar quando faz calor. As roupas e os bônus mexem na **faixa de conforto** (12 a 26 °C), não na temperatura.
- **Necessidades (0 a 100), só no servidor:** sede (mais rápida no calor), fome (mais rápida correndo e coletando) e conforto (sobe na faixa confortável, cai fora dela). `game.Service.BodyTick` avança uma vez por segundo **só para quem está conectado** (`realtime/body.go`); com o jogo fechado, nada muda. O corpo fica na memória enquanto o jogador joga e vai para o banco (`player_body`, JSON) a cada 30 s e ao sair.
- **Efeito só na velocidade:** ótimo (todas ≥ 90) ×1,1; neutro ×1,0; crítico (alguma ≤ 1) ×0,75, e com fome no mínimo a tela fica levemente zonza. Nada de dano, morte ou itens perdidos. O **servidor valida o movimento** com o maior multiplicador dos últimos 3 s (folga para o cliente atrasado). **Modo tranquilo** (F6) desliga tudo e fica salvo.
- **Comida e bebida** (`items.json → food`): frutinhas e coco crus; cantil (cheio → pela metade → vazio) que enche numa fonte, num poço ou no chafariz da praça; 6 receitas de fogueira (`recipes.json`, `station: fire`) com bônus temporários (`body.json → buffs`) que só contam o tempo jogado. A água do mar não mata a sede (não existe item para ela).
- **Fogueira:** colocável no lote (aquece e serve para cozinhar sempre) ou acesa no chão por 10 minutos (uma por jogador; os outros veem pela mensagem `fire`).
- **Ingredientes novos** (cogumelo, ervas, grãos): objetos `forage` gerados pelo servidor como as flores, no fim da lista de cada bioma (os objetos que já existiam não mudam).

## Consequências

- Todos os números ficam em `body.json`, `items.json` e `recipes.json`.
- Uma ação que precise de "estar perto" de fogo ou água confere pela posição validada (`requireFire`, `requireWater`), como no ADR 0040.
- O cliente nunca muda necessidade nem velocidade por conta própria: mostra a mensagem `body`.
