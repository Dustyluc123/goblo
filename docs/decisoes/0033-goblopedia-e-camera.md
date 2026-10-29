# 0033 — Goblopédia e câmera fotográfica

## Contexto

A fase 2.5 pede um álbum (Goblopédia, tecla G) que vai se completando com fotos de animais, flores raras e árvores em estação, com moedas no primeiro registro de cada coisa.

## Decisão

- **Câmera:** item de ferramenta (`camera`, receita na bancada). Com ela na mão, o botão direito entra no modo foto: a câmera do jogo vai para cima do ombro direito, a roda muda o campo de visão (18° a 70°) e o mouse mira (mais devagar com zoom). O cursor continua preso. Botão direito ou Esc saem.
- **O que conta como enquadrado:** a coisa precisa estar na frente, dentro do retângulo central (32% × 36% da tela), perto o bastante (animais até 38, árvores até 30, flores até 9 unidades) e sem nada sólido no caminho (raio contra a física). Até 3 coisas por foto, uma vez cada.
- **Fotos só no computador:** PNG da tela inteira (sem a moldura nem a interface) e uma miniatura em `user://fotos/`. O índice "primeira foto de cada coisa" é por perfil (`goblopedia_<perfil>.cfg`). O servidor guarda só o progresso: primeira data, país (posição exata) e bioma, quantas fotos e se já são amigos.
- **Recompensa única:** a linha da Goblopédia é criada uma vez por jogador e coisa; só a primeira foto preenche a data e paga `rewards.pedia_first`.
- **Amigos:** dar frutinha a um animal marca a espécie como amiga (mesmo antes da foto).
- **Flor azul rara:** sorteada pelo id da flor (`rare_chance` em `objects.json`), à parte da sequência de sorteios da célula, para não mudar nenhum outro objeto.
- **Desenhos das páginas:** cada animal e coisa é renderizado numa SubViewport quando o álbum abre; a página não descoberta mostra o mesmo desenho escurecido (silhueta) com "???".

## Consequências

- O servidor confia no cliente sobre o que estava na foto (como na coleta, ADR 0021). Na fase 3, com a posição do jogador no servidor, dá para conferir a distância até o animal.
- Trocar de computador mantém o progresso, mas não as fotos (a página avisa).

## Atualização (fase 2.6)

O modo foto passou a ser em **primeira pessoa**: a câmera fica nos olhos do personagem (`CameraRig.EYE_HEIGHT`) e o corpo some (a colisão continua). A tecla **F** alterna com o **selfie**: a câmera fica a `SELFIE_DISTANCE` na frente do personagem, olhando para ele, e o mouse a leva em volta dele. Ele vira para a câmera, faz a pose `holding-right` (braço esticado) e fica parado. A detecção do que está enquadrado não mudou: usa a câmera, então vale nos dois modos (o raio de visibilidade ignora o corpo do personagem).
