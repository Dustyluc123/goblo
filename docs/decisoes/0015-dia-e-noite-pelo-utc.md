# 0015 — Dia e noite pelo horário real (UTC)

**Status:** aceita (fase 1.5); substitui a [0006](0006-camera-gira-em-vez-do-globo.md) no que diz respeito à luz

## Decisão
- O sol (`DirectionalLight3D`) aponta a partir do **ponto subsolar**: latitude = declinação solar aproximada (−23,44° × cos(2π/365,24 × (dia do ano + 10))) e longitude = −15° × (hora UTC − 12 + equação do tempo).
- Do lado oposto, uma luz azulada fraca ("lua", sem brilho especular nem sombra) e uma luz ambiente fria deixam a noite azul-escura e com o caminho visível. No zoom afastado, as duas ficam mais fracas para a linha dia/noite aparecer no globo.
- O céu é um shader (`sky.gdshader`): gradiente de dia, entardecer ou noite relativo ao "para cima" do personagem, disco do sol, estrelas e, no zoom afastado, o espaço.
- O HUD mostra a **hora solar local** pela longitude (sem fusos horários, que ficam para depois). F3 acelera o tempo (×60, ×600, ×3600) e F4 volta ao horário real.
- O giro automático na visão afastada continua sendo da câmera (0006), mas a luz não segue mais a câmera.

## Consequências
Sem estações do ano além da declinação, sem lua de verdade nem luzes de cidade (fora do escopo).
