# 0029 — Visual: luz, névoa e vento, sem trocar os modelos

## Contexto

Mesmo na qualidade alta o jogo parecia chapado: luz ambiente de cor fixa, sem névoa, nada se mexia e os verdes do chão, das árvores e da grama não combinavam. O renderizador é o Mobile (ADR 0014), que **não tem SSAO, SSIL nem névoa volumétrica**, e o alvo é uma placa de notebook.

## Decisão

Só efeitos baratos, ligados aos presets:

| Efeito | Onde | Qualidades |
|---|---|---|
| Tonemapping AgX + ajuste de cor (saturação 1,28, contraste 1,07) | `day_night.gd` | todas |
| Luz ambiente metade do céu (gradiente), metade de uma cor que muda com a hora (rosada no crepúsculo) | `day_night.gd` | todas |
| Sol mais quente e mais fraco perto do horizonte | `day_night.gd` | todas |
| Glow leve (soft light) | `day_night.gd` | média e alta |
| Névoa de distância (modo profundidade) na cor do horizonte, de 30% a 95% do raio das árvores; some no zoom afastado | `day_night.gd`, `main.gd` | todas |
| AO nos vértices: a cor por vértice escurece perto da base de árvores, pedras, grama e paredes | `model_library.gd` | todas (custo zero no jogo) |
| Vento: a vegetação balança conforme a altura do vértice, cada instância na sua fase | `shaders/foliage.gdshader` | todas |
| Variação de tom e brilho por instância (±8%) | `shaders/foliage.gdshader` | todas |
| Manchas grandes no chão (mais secas / mais úmidas) | `shaders/terrain.gdshader` | todas |
| Paleta pastel: chão mais claro e quente, copas e grama puxadas para o mesmo tom, barrancos da cor do topo | `biome_style.gd`, `data/decoracao.json` | todas |

O destaque da célula atual ficou mais sutil.

## Consequências

- Sem SSAO, a "sombra de contato" vem da AO nos vértices e da sombra do sol; se um dia o jogo for para o Forward+, dá para ligar SSAO só na alta.
- O vento é só conta no vértice (o pixel custa o mesmo que o material simples). A variação por instância usa a posição da instância como semente, então é estável entre execuções.
- O custo de cada efeito em fps está na tabela do README (medido com a janela na frente).
