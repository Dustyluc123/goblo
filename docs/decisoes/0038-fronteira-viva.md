# 0038 — Fronteira viva: cortina de luz, bandeirolas e cadeadinhos

## Contexto

A faixa tracejada da fase 2.5 mostra onde a fronteira está, mas não diz se o jogador pode passar. A fase 3 pede uma fronteira acima do chão, bonita e fofa ("enfeite de festa, não cerca"), que mude com os passaportes de cada jogador.

## Decisão

- **Peças** (`BorderLines`, shader `border_curtain.gdshader`), só onde dois países se encontram:
  - **Faixa tracejada no chão.** Fica como era.
  - **Cortina de luz.** Faixa vertical até ~1,05 de altura (o personagem tem 1), em rosa e lilás quando fechada e menta e amarelinho quando aberta. É mais forte embaixo e some para cima, com onda lenta de lado a lado e brilhinhos subindo, tudo calculado no shader.
  - **Marcos.** Os postes de antes, mais uma corda com bandeirolas de festa em cinco cores pastel e um cadeadinho em cima: um billboard com um atlas de dois ícones, desenhado em código.
- **Linhas contínuas.** Os segmentos compartilhados viram linhas ligando as pontas iguais, por par de países. Antes cada segmento do 1:50m (0,2 a 0,3 unidade) era tratado sozinho, e quase nunca ganhava marco.
- **Marcos em lugares globais.** Ficam onde a linha cruza uma grade global de 6 unidades, com pelo menos 3 entre um e outro. Assim a posição é a mesma vista de qualquer pedaço.
- **Estado por jogador.** O par está **aberto** se o jogador tem os passaportes dos dois países. Cada par tem os próprios materiais, e abrir ou fechar só muda o parâmetro `openness` (0 a 1), sem remontar malha:
  - a cortina desce a 35% e fica mais transparente;
  - a corda sobe em arco;
  - o cadeado abre.
- **Animações.**
  - Comprar ou ganhar um passaporte (`Session.passports_changed`) anima a troca em 1,6 s.
  - Encostar numa fronteira fechada dispara uma onda que se espalha do ponto de contato, junto com a mensagem que já existia.
  - Atravessar a pé solta uma chuvinha de confete (`SeasonFx.confetti`) e mostra a plaquinha "Bem-vindo!".
- **Desempenho.**
  - As contas rodam numa thread, e o nó de um pedaço entra no quadro seguinte (um por quadro).
  - A cortina some com a distância da câmera (22 a 38 unidades) e acima de 30% de zoom.
  - Não há sombras nem escrita de profundidade.
  - O `--border-test` anda 20 s ao longo da fronteira Brasil–Paraguai sem limite de fps e conta os quadros acima de 25 ms (0 na primeira medição).
- **Modo dev** (F1 → Viagem): "Visão da fronteira" com as opções pelos passaportes, todas abertas e todas fechadas. Só a visão muda; a regra continua a mesma.

## Consequências

- Só a fronteira entre dois países ganha cortina. A costa não ganha, e no modo debug só aparece a faixa colorida.
- No 1:50m, algumas fronteiras são ilhas de segmentos que não se ligam. Nelas a corda de bandeirolas pode faltar entre dois marcos.
- **Sem verificação visual** nesta fase (o autor pediu para não abrir o Godot com janela): cores, altura e transparência da cortina, o desenho do cadeado, as bandeirolas penduradas e o confete.
