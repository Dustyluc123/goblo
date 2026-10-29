# 0011 — Espalhamento determinístico da vegetação

**Status:** aceita (fase 1.5); na fase 2 vale só para a grama e as plantinhas do cliente. Árvores, pedras e flores agora vêm do servidor ([ADR 0020](0020-objetos-interativos-no-servidor.md)).

## Contexto
No multiplayer, todos os jogadores precisam ver as mesmas árvores no mesmo lugar, principalmente as que têm colisão. A vegetação é decoração do cliente (não vem do servidor), então precisa ser reproduzível.

## Decisão
- Cada entrada da lista de decoração de um bioma (`BiomeStyle.DECOR`) numa célula usa um gerador **mulberry32** (`client/scripts/decor_rng.gd`) com semente `cell_id × 16 + índice_da_entrada`.
- A ordem dos sorteios é fixa: quantidade, e para cada objeto o triângulo do hexágono, duas coordenadas baricêntricas, giro, escala e um número de "manter". O objeto fica no topo plano da célula (a 80% do raio).
- **A qualidade gráfica não muda árvores nem pedras grandes** (as que têm colisão). Ela só afeta a camada pequena (grama, plantas, pedrinhas): um objeto pequeno aparece se o número de "manter" for menor que a densidade, então a qualidade baixa mostra um subconjunto da alta.
- O mulberry32 foi escolhido por caber em poucas linhas e ser fácil de reproduzir em Go, se o servidor precisar validar colisões no futuro. A saída em GDScript foi conferida contra a implementação de referência.

## Consequências
- Mudar a ordem dos sorteios, a lista de um bioma ou o `INSET` muda a posição das árvores para todo mundo. Trate como mudança de formato.
- A colisão das árvores roda no cliente; na fase 3, se ela importar para a regra do jogo, o servidor reproduz o mesmo sorteio.
