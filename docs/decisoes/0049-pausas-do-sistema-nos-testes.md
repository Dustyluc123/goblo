# 0049 — As "travadas perto dos animais" dos testes headless são pausas do sistema

**Fase 4.0.**

## Contexto

O `--border-test` falhava de vez em quando com 5 ou 6 quadros de ~50 ms nos 20 s andando perto dos animais. O registro de travadas não mostrava nada anotado nesses quadros, e o processo do jogo só gastava ~4 ms.

## O que foi medido

- Desligando todos os animais, as travadas continuavam iguais.
- Uma sonda no começo e no fim de cada fase do quadro mostrou os ~50 ms caindo em lugares diferentes a cada vez (entre quadros, na física, no processo).
- **Um loop vazio do Godot** (`--headless`, sem o jogo) tem a mesma pausa: ~46 ms a cada ~3,6 s, com ou sem limite de fps. É o macOS pausando um programa de fundo, não o jogo.

## Decisão

- `FrameWork` mede o trabalho do jogo em cada quadro (processo + física), sem o tempo entre quadros.
- O teste da fronteira mede antes 10 s parado (linha de base das pausas do sistema) e só reprova se andando houver claramente mais quadros pesados (`≤ 4 × base + 2`, pior < 100 ms). Continua imprimindo também a contagem entre quadros, para comparação.

## Consequências

- O `travadas.log` dos testes headless continua mostrando essas pausas (sem nada anotado). Travada de verdade tem anotação (`HitchLog.note`) ou aparece também com a janela na frente.
