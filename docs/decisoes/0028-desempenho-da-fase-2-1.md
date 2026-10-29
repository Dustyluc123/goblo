# 0028 — Desempenho da fase 2.1: o que pesa e o que foi feito

## Contexto

O autor mediu, no Mac Intel com tela Retina e a janela maximizada: qualidade alta no bairro com 28 fps (872 draw calls, 915 mil triângulos) e média perto das casas com 47 fps. A meta é média com 60 fps estáveis e alta com no mínimo 45 fps, no bairro com 20 vizinhos e na floresta tropical.

A janela maximizada tem **3136 × 1930 pixels** (tela 3584 × 2240, escala 2). As medições foram feitas nesse tamanho com `--profile-scene` (parado, mesma câmera; desliga uma parte por vez e compara o tempo de GPU).

## O que o perfil mostrou (antes)

O gargalo é a **placa de vídeo**: a CPU de render ficou abaixo de 2 ms.

| Parte (bairro, 20 vizinhos) | Alta: GPU 17,1 ms, 1151 draw calls | Média: GPU 11,2 ms, 764 draw calls |
|---|---|---|
| Árvores e pedras do servidor | 7,0 ms, 430 draw calls | 2,1 ms, 141 |
| Sombra do sol | 4,8 ms, 480 draw calls (4 cascatas, árvores projetam) | 0,3 ms |
| Casas e lotes | 0,7 ms, **566 draw calls** | 0,6 ms, **484 draw calls** |
| Chão e oceano / grama / antisserrilhado | ~1 ms cada | ~0,3 ms cada |
| Céu e nuvens | < 0,5 ms | < 0,3 ms |

## Decisão

- **Lotes dos vizinhos numa malha só por material** (`Neighborhood._merge`): casa, decorações, plaquinha e obra viram 2 a 4 draw calls por lote em vez de ~25. O lote do próprio jogador continua peça por peça (modo construção, bancada, destaque dos objetos que atrapalham a obra).
- **Distância de visão por tipo** (presets em `quality.gd`): grama perto (`small_radius`), árvores e pedras no meio (`big_radius`), casas mais longe (`lot_radius`, com `visibility_range`). A névoa (fase 2.1, item 7) esconde onde cada coisa termina.
- **LOD mais agressivo** por preset (`mesh_lod_threshold`: 6 / 3 / 1,5 pixels). As malhas já têm níveis de detalhe gerados pela `ModelLibrary`; o Godot escolhe o nível por MultiMesh (pedaço inteiro), então pedaços longe já usam versões simples.
- **Sombras**: 2 cascatas na alta (eram 4) e 60 de distância (eram 90). Grama nunca projeta sombra; árvores só na alta.
- **Resolução do 3D e antisserrilhado**: alta com 3D em 75% (era 85%) e MSAA 2× (era 4×); média continua em 67% com FXAA. Na janela maximizada, a média renderiza o 3D em 2101 × 1293 e amplia com FSR.
- **Occlusion culling: não agora.** No bairro, as casas são pequenas e baixas e esconderiam pouco; a rasterização dos oclusores roda na CPU a cada quadro, e o planeta (o maior oclusor) já fica fora dos raios de carga. Reavaliar quando houver cidades com prédios.

## Depois (mesma cena, mesma janela)

| Cena | Alta | Média |
|---|---|---|
| Bairro com 20 vizinhos | GPU 12,2 ms, 641 draw calls | GPU 10,4 ms, 375 draw calls |
| Floresta tropical | GPU 12,2 ms, 501 draw calls | GPU 8,7 ms, 293 draw calls |

Os fps com a janela na frente estão na tabela do README.

## Multiplayer (como os pedaços vão funcionar)

Hoje o cliente pede ao servidor os pedaços (`/objects?cells=…`, `/lots?cells=…`) num raio em volta do personagem (`ChunkData.radius` = raio das árvores + 20). No multiplayer, o servidor guarda a posição de cada jogador e manda só os pedaços perto dele (o mesmo raio), com as mudanças (coletas, obras, outros jogadores) por assinatura do pedaço. Os raios de desenho continuam no cliente (por qualidade): ele recebe o pedaço inteiro e decide o que desenhar.
