# 0030 — Câmera só com transparência (sem colisão)

## Contexto

Na fase 2.1 a câmera não atravessava nada: uma esfera lançada do personagem fazia a câmera se aproximar ao bater em algo e subir quando o espaço atrás apertava. Na prática isso acabou com a fluidez: a câmera ia parar quase em cima do personagem, olhando de cima, e às vezes ficava dentro do telhado, com a tela tomada pela cor dele.

## Decisão

- **A distância e o ângulo só mudam quando o jogador mexe** (mouse e zoom). Saem a esfera de colisão, a aproximação e a subida automáticas.
- **Tudo entre a câmera e o personagem fica semitransparente** (`CameraOcclusion`), com fade de 0,25 s entrando e saindo: casas inteiras (com o telhado), árvores, pedras grandes, postes e decorações altas. Quem está no caminho: esferas dos objetos do servidor e caixas orientadas de cada lote (`Neighborhood.occluders`: casa e decorações com altura). Dois pontos do personagem (perto dos pés e do peito) precisam ficar visíveis.
- **Câmera dentro de um objeto:** ele some de vez (opacidade 0), em vez de cobrir a tela.
- **Transparência por pontilhado (dither),** não por alfa. O objeto continua no passe opaco, com a profundidade certa, sem problema de ordem de desenho entre as faces da casa (paredes de dentro aparecendo por cima das de fora). Usamos o pontilhado do fade por distância do Godot (ruído de gradiente intercalado, regular e estável na tela), com os limites escolhidos para a opacidade ficar constante. O alpha hash foi testado e descartado: o ruído aleatório parecia chuvisco.
- **Custo:** só os objetos desbotados (poucos) ganham cópias de material com `discard`; o resto do mundo segue sem. A sombra fica inteira: uma cópia só de sombra entra no lugar enquanto o objeto está desbotado.
- **Lotes dos vizinhos:** a malha juntada passa a ser duas (casa e resto), para a casa desbotar sozinha sem levar o lote inteiro. Custa alguns draw calls a mais por lote vizinho (os materiais que a casa e as decorações dividem).
- **Exceção, o chão:** se o ângulo levaria a câmera para dentro do terreno (morro atrás), ela inclina o mínimo necessário, subindo rápido e voltando devagar, sem salto. A trava de altura mínima continua como rede de segurança.

## Consequências

- A câmera pode ficar do outro lado de uma parede; o que fica no meio desbota. Grama e flores nunca contam.
- `--camera-test` agora confere que a distância e o ângulo não mudam sozinhos, que a câmera não vai para baixo do chão e que o que está no caminho está desbotado; com `--screenshot=X.png` salva também `X_casa.png`, `X_telhado.png` e `X_dentro.png`.
- Na primeira vez que um material desbota, o Godot pode precisar compilar a variante pontilhada do shader.
