# 0053 — Cabeça inteira, pele do jogador, acessórios na cabeça e foto centralizada

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

---

## Goblopédia: registro só com o assunto centralizado

### Por que flores e árvores não registravam

- **Flores:** o cliente só procurava a flor azul (`flower_blue`). Desde a 4.0 todo item com a tag `flower` tem página, mas as outras 19 espécies nunca eram enviadas.
- **Flores decorativas:** são as mais numerosas (e as que mais aparecem nas fotos), mas só existem no cliente; não havia como registrar.
- **Árvores de outono e com neve:** o cliente troca o modelo aos poucos, árvore por árvore, perto da virada da estação (limiar pelo id); o servidor exigia a estação "oficial" da célula. Perto da virada, uma árvore já laranja era recusada. E com a estação forçada no modo dev (F1), o servidor continuava na data real.

### Decisão

- **Enquadramento** (`rules.json → photo`): o assunto precisa estar na área central (`center`, 35% da largura e da altura), visível (nada sólido entre a câmera e ele; o raio pode bater no próprio tronco) e com um tamanho mínimo na tela (`min_size`, 5% da altura), até a distância do tipo (`max_dist`). Com mais de um, vale **o mais centralizado** (uma foto registra uma coisa só).
- **Mira:** no centro da moldura; fica dourada e mostra o nome do assunto (ou "???" se ainda não foi descoberto) quando há um assunto bem enquadrado. O cartão do corpo some do visor. Ao fotografar, a mensagem do servidor confirma ("Novo na Goblopédia: Ipê-amarelo!").
- **Servidor:** o cliente manda a direção, a posição da câmera e o ponto enquadrado (`look`, `cam`, `at`). O servidor confere um cone de 20° (mais o que 1,5 unidade vale na distância), a câmera a até 6 unidades do personagem e a distância do tipo, e:
  - animal: um da espécie no trajeto comum, perto do ponto enquadrado (com a folga das reações locais);
  - flor do servidor: uma daquele item, perto do ponto;
  - flor decorativa: a espécie nasce no bioma do ponto naquela estação (com ±10 dias de folga, a mistura da virada), pelas regras de `objects.json` (`Content.FlowerGrows`). O cliente recebe a mesma tabela no `/content` (`flower_biomes`) e só acende a mira no que vai registrar. Um teste confere que toda flor de `decoracao.json` nasce no mesmo bioma e estação para o servidor;
  - árvore: o servidor calcula a mesma versão que o cliente desenha (`game.TreeVariant` = `Seasons.variant_at`, com um dia de folga), com 60 casos iguais nos testes dos dois lados.
- **Modo dev:** forçar a estação no F1 avisa o servidor (`POST /dev/season`), que confere árvores e flores pela mesma data.
- **Selfie:** vale igual; o que está centralizado atrás do personagem (o raio ignora o próprio personagem).

### Consequências

- Testes: `photo_test.go` (cada uma das 20 flores, árvore de outono e com neve, flor decorativa, fora do centro, longe, espécie que não nasce ali, estação forçada no modo dev) e `--photo-test` (mira com ??? e com o nome, só o assunto registra, fora do centro, atrás de uma parede, longe, selfie, uma flor do servidor e uma decorativa) e `--season-test` (árvore de outono e com neve).
- Flores da primavera que são só enfeite (as brancas, amarelas e roxas na tundra e na montanha) não registram: o servidor não tem essas cores lá. A mira não acende nelas.
