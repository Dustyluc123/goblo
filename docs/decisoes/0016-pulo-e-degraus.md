# 0016 — Pulo, degraus e alturas

**Status:** aceita (fase 1.5)

## Decisão
- Espaço pula para longe do centro do planeta com velocidade √(2·g·h): **altura 1,3** com gravidade 25. Sem pulo duplo; **coyote time de 0,12 s** e **jump buffer de 0,15 s**.
- **Subida automática de degraus de até 0,4** (`test_move` à frente e um degrau acima): a praia (0,4) e o campo (0,8) se conectam andando; colinas (degrau de 0,6) e montanhas (degraus de 1,2) pedem pulo.
- Animações `jump` (recomeça com TimeSeek a cada pulo) e `fall`, misturadas à locomoção num `AnimationTree`.
- O piloto automático de teste (`--route`) pula quando fica preso e desvia para o lado se o pulo não resolve.

## Consequências
A tabela de alturas (`biome.go`) e o pulo (`game_config.gd`) andam juntos: aumentar um degrau acima de 1,3 cria penhascos que não dá para subir.
