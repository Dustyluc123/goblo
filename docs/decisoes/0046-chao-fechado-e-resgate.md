# 0046 — Chão fechado entre hexágonos e resgate de quem cai

**Fase 3.6.** Contexto: no Chile (célula 20575, montanha ao lado de mar e de hexágonos mais baixos) o personagem ficou preso caindo "dentro" do chão, com o céu aparecendo por baixo.

## O que estava errado

- Cada célula calculava os próprios cantos somando os centros numa ordem diferente; o mesmo canto saía com arredondamentos diferentes em cada vizinho (float de 32 bits em raio 1000) e sobravam frestas finíssimas. Um teste com raios de cima para baixo achou 1.762 raios em 83.504 que passavam direto, todos exatamente em cima de arestas ou cantos.
- A colisão do chão (ConcavePolygonShape3D) só valia de um lado. Quem atravessava um pouquinho uma parede ou o topo (canto, pulo, correção do servidor perto da fronteira) ficava "dentro" do hexágono, onde nada segura, e caía por dentro da coluna, vendo o céu pelas faces viradas para fora.

## Decisão

1. **Cantos idênticos:** `WorldData.corner(a, b, c)` soma os três centros sempre na ordem dos ids; as três células chegam ao mesmo canto bit a bit (malha de desenho e colisão).
2. **Colisão sobreposta:** na colisão, a borda de cada célula avança `GlobeBuilder.COLLISION_GROW` (0,01) para fora; topos e paredes de vizinhos se sobrepõem em vez de só encostar, inclusive entre pedaços montados em threads diferentes. O desenho não muda.
3. **Colisão dos dois lados:** `backface_collision = true` no chão.
4. **Resgate:** se o personagem ficar mais de `Player.FALL_RESCUE` (1 unidade) abaixo do topo da célula onde está, volta para cima dela (ou do hexágono de terra mais perto, se estiver embaixo do mar). Fica no registro de travadas e num aviso no console. Não tira a causa; é só a rede de segurança.

## Consequências

- `tests/test_frestas.gd` (sem servidor, com o mundo em cache) monta a colisão como o jogo (pedaços em thread) e joga raios nas bordas, cantos e a 0,02 e 0,15 de cada lado, em ~870 células (montanhas, litoral, os 12 pentágonos, a célula 20575 e os vizinhos). Todo raio precisa acertar. Também põe um personagem dentro do hexágono 20575 e confere que ele volta para cima.
- O servidor continua com a sua conta de cantos (float64); a diferença é de milésimos e não muda regra nenhuma.
