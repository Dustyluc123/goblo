# 0006 — Na visão afastada, a câmera gira em volta do planeta (o globo fica parado)

**Status:** aceita (fase 1)

## Contexto
O briefing pede que, na visão afastada, o globo gire devagar sozinho. Girar o nó do planeta de verdade giraria também a colisão e o personagem, misturando física com efeito visual.

## Decisão
A câmera (e a luz, que acompanha a câmera) gira em volta do eixo norte–sul. Visualmente é o mesmo efeito; o mundo físico fica parado. Ao aproximar o zoom, o giro é desfeito aos poucos e a câmera volta para o personagem.

## Consequências
- Física e posição do personagem nunca dependem do giro.
- Como a luz acompanha a câmera, não há dia e noite. Se um ciclo de dia e noite entrar no futuro, a luz passa a ser fixa no mundo.
