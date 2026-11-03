# 0047 — Aeroporto na escala do personagem (pista na diagonal do hexágono)

**Fase 3.6.** Contexto: o personagem (~1 de altura) era maior que o avião (3,2 de comprimento), os carros do pátio eram de brinquedo, a pista piscava (faixas e peças de estrada no mesmo plano) e o terminal parecia uma casa de vila.

## Decisão

- **Avião ~4× maior, não 10×.** O briefing pediu "cerca de 10 vezes", com duas referências: a porta pelo menos da altura do personagem e a asa bem maior que uma casa grande. Com 10× o avião teria 32 de comprimento e 30 de envergadura, e o hexágono do aeroporto tem ~27 de ponta a ponta (~23 de lado a lado): não cabe. Ficou em `PLANE_SCALE = 3` (o modelo tem 4 de comprimento): 12 de comprimento, ~11 de envergadura (a casa grande tem ~5), fuselagem de 3,4 e porta de ~1,4. O modelo ganhou porta do lado esquerdo e trem de pouso (no voo, uma versão com as rodas recolhidas e escala 16).
- **Pista na diagonal do hexágono.** A praça é desenhada num sistema próprio (u, v): a pista (17 × 4,6) corre ao longo de u, do lado v < 0; terminal, torre, balcão, loja e chafariz do lado v > 0. O servidor escolhe o ângulo da praça entre as direções dos cantos da célula (o que deixa mais folga até a borda) e, nos 11 hexágonos menores (de 129), encolhe a praça inteira um pouco (até 75%) para caber. `GET /airports` manda `rot`, `scale`, o balcão (`x`, `y`) e a loja (`shop_x`, `shop_y`), e o servidor confere a distância nos mesmos pontos (`game/plaza.go`). Teste: `TestPlazaFitsInEveryAirportCell`.
- **Nada no mesmo plano.** Pisos são caixas próprias com topos em alturas diferentes (calçada 0,03, pátio 0,05, pista 0,08, faixas 0,11), enterradas 0,3 no chão; saiu a pista de peças de estrada.
- **Carros pela altura:** van e caminhonete com 1,5, caminhão de entrega com 1,8 (a porta fica da altura do personagem).
- **Terminal com cara de aeroporto:** bloco de concreto cinza, saguão de vidro azulado, laje e montantes brancos, faixa verde (a cor do Goblo, `UiStyle.ACCENT`), marquise sobre o balcão de check-in. A torre segue a mesma paleta.
- **Desempenho:** nenhuma peça vira nó. Cada peça é um pedido (arrays + transformação + material) e uma thread junta tudo numa malha por material (`Neighborhood._merge_arrays`); o bloco do terminal fica numa malha à parte, para o pontilhado da câmera. A praça custava ~25–30 ms num quadro só (peças + junção); agora ~4 ms (colisão, NPCs e placas) e o resto na thread. Os materiais novos entram no pré-aquecimento de shaders.

## Consequências

- O balcão e a loja mudaram de lugar no plano da célula; quem guarda posições antigas não é afetado (nada disso vai para o banco).
- `--ui=airport --plaza=U,V` põe o personagem em qualquer ponto da praça, para capturas.
