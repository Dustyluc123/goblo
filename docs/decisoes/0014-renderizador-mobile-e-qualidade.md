# 0014 — Renderizador Mobile e níveis de qualidade

**Status:** aceita (fase 1.5)

## Contexto
O jogo precisa rodar liso no MacBook Pro Intel (2019, Radeon Pro 5300M + UHD 630). Com o Forward+, a GPU gastava ~22 ms por quadro na floresta tropical.

## Decisão
- **Renderizador Mobile** (`renderer/rendering_method="mobile"`). Na mesma cena, a GPU caiu para ~11,7 ms; o estilo low-poly não usa nada exclusivo do Forward+ (SSAO, SDFGI, volumetria).
- **Qualidade** (`client/scripts/quality.gd`, salva em `user://settings.cfg`, F6 troca):

| | baixa | média (padrão) | alta |
| --- | --- | --- | --- |
| densidade da camada pequena | 40% | 70% | 100% |
| distância da grama / das árvores | 30 / 75 | 45 / 115 | 70 / 170 |
| sombras | não | sol, 2 cascatas, 40 u | sol + árvores, 4 cascatas, 90 u |
| antisserrilhado | nenhum | FXAA | MSAA 4× |
| nuvens | 30 | 50 | 80 |

- Mapa de sombras direcionais de 2048 (em vez de 4096), e sombras desligadas quando é noite onde o personagem está.

## Consequências
- Se um efeito novo precisar do Forward+, meça antes de trocar de volta (`--perf-test`).
- A qualidade alta não chega a 60 fps neste Mac; ela existe para máquinas melhores.
