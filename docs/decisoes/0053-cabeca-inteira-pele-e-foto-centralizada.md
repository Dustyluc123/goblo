# 0053 — Cabeça inteira, pele do jogador e acessórios no osso da cabeça

**Fase 4.2.** Corrige a 0052 (visual do personagem).

## O que estava errado

- **Cabelo separado gerava estranhezas** (cabeças carecas com cabelo de outra, coque achatado com uma "aba reta" embaixo do chapéu, penteados extras flutuando).
- **Óculos no pé.** O modelo dos óculos do pacote vem na origem (nos pés) e era preso ao osso da cabeça sem deslocamento. Como o vértice está no espaço do personagem, ficava onde foi desenhado: no chão.
- **Pele à mostra com outra cor.** Dois problemas:
  - o Godot já converte de sRGB para linear os parâmetros por instância do tipo cor; a 4.1 mandava a cor já convertida, que era convertida de novo. A pele escolhida saía bem mais escura e saturada que a bolinha do editor (#9c6644 virava #5f240d);
  - as faixas "de pele" da paleta também são cabelo, barba ou sapato em outros personagens, e a 4.1 escolhia a pele do corpo pelas mãos: em alguns personagens, luvas, sapatos ou a calça viravam pele e, em outros, parte da pele ficava com a cor original.
- **Objeto na mão da Personagem 1** ganhava a cor do casaco.

## Decisão

- **Cabeça = uma das 12 originais, inteira.** Saem do visual `hair`, `hairstyle` e `haircut` (cliente, servidor, `body.json`) e o acessório `cap-male-c`. A migração `0009_cabeca_inteira.sql` troca a escolha antiga pela cabeça original correspondente: quem usava o quepe fica com a `male-c` (que tem o quepe); quem usava o cabelo de outra cabeça fica com a cabeça de onde o cabelo veio (é o que mais se vê de longe); os outros mantêm a cabeça.
- **Chapéus** continuam presos ao osso da cabeça, com ajuste por cabeça em `cabecas.json` (`hats`) para cobrir o cabelo sem flutuar e sem deformar a cabeça. Coques e cabelo comprido saem por trás. Na `male-c`, o chapéu substitui o quepe.
- **Óculos** no osso da cabeça, no ponto dos olhos (`cabecas.json → face`): o mesmo dos óculos que já vêm desenhados em `male-a` e `male-e` (a posição bate no milímetro).
- **Pele por personagem:** a faixa de pele mais usada nas **orelhas** (que são só pele) e o outro tom do par dela (10/11, 12/13, 14/15; pescoço e decote usam o outro tom). Só esse par, só nas partes do próprio personagem e nunca no que sai do crânio (cabelo, pela forma). Nas pernas, a faixa só conta como pele se subir pela perna (embaixo dela é sapato). Cores do braço que não estão no tronco nem são pele (luvas, o que a mão segura) ficam como vieram, com qualquer roupa.
- **Tingir em vez de trocar a cor:** a pele é a textura original × (tom do jogador ÷ a cor da textura no meio da faixa clara do par, a do rosto). A referência vai no **UV2** e é lida da mesma textura, no mesmo espaço de cor, então sem tom escolhido fica idêntico ao pacote e com tom escolhido o rosto fica exatamente nele, mantendo o degradê (sombra, orelhas). A pele à mostra pela roupa usa a faixa do corpo e a mesma referência: fica do mesmo tom da pele do corpo.
- **Sem tom escolhido**, a pele do jogador é a original da **cabeça**: o corpo e as pernas de outro personagem acompanham o rosto.
- Tons vão para o shader em **sRGB** (`CharacterLook.skin_of`); cores de roupa continuam lineares na cor do vértice (essas não são convertidas; conferido numa captura sem luz).

## Consequências

- As 12 cabeças aceitam todos os tons (sem pintar cabelo, barba, bigode ou quepe); conferido em `tests/test_roupas.gd` e nas capturas (`docs/imagens/pele-e-roupas.jpg`).
- `tests/test_roupas.gd` agora também confere, nas 12 cabeças e nos 12 corpos, que óculos, chapéus, cachecol, aba do poncho, sola da sandália e capa estão no osso certo (peso 1) e perto de onde devem; que toda pele usa a referência da própria parte; que cabelo nunca vira pele; que o que a mão segura não muda de cor; e que os tons vão em sRGB.
- Cabeça nova do pacote: entra sozinha se tiver orelhas de pele e o mesmo crânio; senão, ajuste `SKULL_MIN`/`SKULL_MAX` e `cabecas.json`.
