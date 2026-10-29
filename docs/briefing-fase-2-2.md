# Briefing — Fase 2.2: últimos ajustes antes da Fase 2.5

> Cole este arquivo inteiro no Claude Code. Salve uma cópia em `docs/briefing-fase-2-2.md` e **não deixe briefings soltos na raiz** (apague `briefing-fase-2-1.md` da raiz e adicione `/briefing-*.md` ao `.gitignore`, já que eu às vezes coloco o arquivo ali).

## Contexto

A Fase 2.1 ficou muito boa: o fps melhorou bastante, o jogo está mais bonito, melhorar a casa funciona, a casa no mini mapa ficou ótima e a coleta (árvores, pedras e flores) está gostosa. **Não mexa no que está funcionando.** São só quatro ajustes e uma regra nova.

Regras de sempre: commits pequenos em português, testes passando, push no final, `CLAUDE.md` atualizado, e testes sem roubar a minha tela (regra já registrada).

## 1. Câmera: só transparência, sem pular

A câmera se aproximar ou **subir** quando algo fica na frente **acabou com a fluidez**. Gravei um vídeo: a câmera vai parar quase em cima do personagem, olhando de cima, e às vezes fica **dentro do telhado**, com a tela inteira tomada pela cor do telhado.

- **Remova o afastamento/aproximação automático da câmera por colisão.** A distância e o ângulo da câmera só mudam quando **eu** mexo (mouse e zoom).
- Fique **só com a transparência**: tudo que estiver entre a câmera e o personagem (casas inteiras, **incluindo o telhado**, árvores, postes, decorações) fica semitransparente com um *fade* suave, entrando e saindo.
- Se a câmera ficar **dentro** de um objeto, esse objeto também some/fica transparente (nada de tela inteira com a cor de uma parede ou telhado).
- Avalie usar transparência por *dither* (pontilhado no shader) em vez de transparência real, se ficar mais barato e evitar problemas de ordem de desenho.
- Exceção: o chão e o terreno. A câmera não pode ir para baixo do chão; se o ângulo vertical levar a câmera para dentro do terreno, limite o ângulo de forma suave, sem saltos.
- Atualize o teste automático da câmera para garantir que a distância da câmera **não muda sozinha**.

## 2. Câmera controlada pelo mouse

Hoje a câmera gira com Q/C e com o botão direito. Quero que ela gire **com o movimento do mouse**, como nos jogos de terceira pessoa:

- Durante o jogo, o cursor fica **capturado e escondido**, e mover o mouse gira a câmera em volta do personagem (horizontal e vertical, com limites no vertical).
- Ao abrir **qualquer menu** (bancada, bolso, modo construção, painel dev, configurações, tela de primeiro acesso), o cursor é **liberado** automaticamente; ao fechar, volta a ser capturado. Use o gerenciador de interface que já existe.
- **Alt** (Option) segurado libera o cursor temporariamente, e **Esc** sem nenhum menu aberto libera o cursor (clique na janela para capturar de novo).
- No modo construção, o cursor fica visível para mirar onde colocar, e o giro da câmera passa para o botão direito segurado.
- Nas configurações (F6): **sensibilidade do mouse** e **inverter eixo vertical**, salvos em `user://`.
- Remova Q/C e atualize a linha de controles e o README.

## 3. Seta do jogador invertida no mini mapa

Quando ando para o **leste**, a seta no mini mapa aponta para o **oeste** (e vice-versa). Norte e sul parecem certos, então provavelmente o eixo leste-oeste está espelhado no cálculo do ângulo.

- Corrija para a seta apontar exatamente para onde o personagem está virado.
- Adicione um teste: andando para norte, sul, leste e oeste, o ângulo da seta bate com a direção.

## 4. Telhados que não encaixam

Em algumas casas, principalmente a partir da **casa grande**, o telhado não fecha com as paredes de baixo: aparecem frestas e dá para ver o lado de dentro.

- Revise a montagem dos telhados dos três níveis (peças `roof-*` e `roof-high-*`, cantos, pontas e oitões) para fechar completamente com as paredes, sem frestas e sem faces sobrepostas.
- Confira **as quatro rotações** da casa (a melhoria pode girar a casa) e os dois andares da casa grande.
- Mande capturas de cada nível, de perto, olhando os encontros entre telhado e parede, de vários ângulos.

## 5. Regra nova: não controlar o meu Mac

No último trabalho, você usou um comando que pede permissão para controlar o Mac, e eu aceitei sem querer. **Não use** `osascript`, AppleScript, "System Events", nem qualquer coisa que peça permissão de Acessibilidade, Automação ou Gravação de Tela, para nada. Registre isso no `CLAUDE.md`, na seção "Testes sem atrapalhar o Lucas". Se precisar verificar algo que dependa disso, me diga o que verificar e eu faço.

## Desempenho

Não precisa medir com a janela na frente desta vez. **Eu vou rodar `client/tools/medir_fps.sh`** com o Mac frio e te mando os números. Só não piore o desempenho com os ajustes da câmera (a transparência deve afetar só os poucos objetos entre a câmera e o personagem).

## Forma de trabalho

- Ordem: 5 → 3 → 2 → 1 → 4.
- No final, diga o que mudou e como testar cada item.
