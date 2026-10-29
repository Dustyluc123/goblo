# 0013 — Pedaços (chunks) para desenho, colisão e vegetação

**Status:** aceita (fase 1.5)

## Contexto
O globo inteiro tem ~300 mil vértices e, em florestas, milhares de árvores. Desenhar e colidir tudo pesaria no Mac Intel.

## Decisão
- **Pedaços:** a direção de cada célula é projetada num cubo; cada face é dividida em 16×16 quadrados (1.536 pedaços, ~16 células e ~100 unidades cada). A chave é calculada em O(1) (`WorldData.chunk_key`).
- **Desenho do chão:** 96 grupos (4×4 pedaços) com uma malha de terra e uma de oceano cada. Geometria indexada; o sombreamento flat vem das derivadas no shader.
- **Colisão do chão:** `ConcavePolygonShape3D` só nos pedaços a até 60 unidades do personagem, no máximo 2 novos por atualização.
- **Vegetação:** por pedaço, duas camadas ("big" até 115 unidades e "small" até 45, na qualidade média), com um `MultiMeshInstance3D` por modelo. O sorteio roda no `WorkerThreadPool` e devolve o buffer do MultiMesh pronto. Colisão (cilindro ou caixa) só para árvores e pedras grandes a até 40 unidades, criada direto no `PhysicsServer3D` com formas compartilhadas por modelo e escala.
- No zoom afastado, a vegetação some e não carrega nada.

## Consequências
- A busca de pedaços próximos varre 1.536 entradas (0,4 ms) a cada 0,3 s. Se a grade crescer muito, troque por vizinhança de pedaços.
- A fase 2 (grade de construção dentro do hexágono) deve reaproveitar os mesmos pedaços para carregar construções.
