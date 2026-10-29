# 0009 — Planeta com raio 1000 e grade n = 50

**Status:** aceita (fase 1.5)

## Contexto
No teste da fase 1, o globo (raio 100) era pequeno demais: atravessar países era rápido demais para um MMO. A meta é ir de São Paulo à fronteira da Venezuela (Pacaraima) em 1min30–2min andando e em menos de 1 min correndo.

## Decisão
- Raio **1000** e frequência **n = 50** (25.002 células, hexágono com ~23 unidades). Padrão em `DefaultConfig` (`server/internal/world/world.go`); ambos configuráveis.
- Velocidades em `client/scripts/game_config.gd`: **5,3 u/s andando** e **×2,3 correndo** (12,2 u/s).
- O trajeto tem 548 unidades em linha reta. Medido com o piloto automático (`--route`, com desvios e pulos): 110–116 s andando e 50–56 s correndo.
- Precisão: com `float` de 32 bits, a resolução numa coordenada de módulo 1000 é ~6·10⁻⁵ unidade (0,06 mm se o personagem tem 1 m). Não é preciso compilar o Godot em precisão dupla.

## Consequências
- Mudar raio, frequência ou velocidade exige medir de novo e atualizar o teste `TestScaleSaoPauloToPacaraima`.
- Mudar `n` muda todos os ids de célula; quando houver terrenos salvos (fase 2), isso vira uma migração.
