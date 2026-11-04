# Briefing — Fase 4.5: cavernas, mineração, folclore e animais do mundo

> Cole este arquivo inteiro no Claude Code **depois que a Fase 4.2 estiver terminada e enviada**. Salve uma cópia em `docs/briefing-fase-4-5.md` (não deixe na raiz).

## Contexto

Regras de sempre do `CLAUDE.md`: commits pequenos em português, testes passando, push no final, **nenhuma menção a outros jogos** (nem no código, nem nos textos, nem nos documentos), nada de `osascript`/permissões do Mac, números de jogo em arquivos de dados, textos por `tr()`. Para medir fps com janela: avise no terminal e espere o meu "ok". Capturas pelo `tools/sem_foco.sh`.

O Goblo continua sendo um jogo para relaxar: nada assustador, nada que puna de verdade.

## 0. Correções da 4.2 (fazer primeiro)

1. **Acessório desconhecido:** há um acessório no editor que não sei o que é e não aparece no personagem. Descubra o que é e **remova**.
2. **Pele com o formato da roupa original:** com a regata, a pele mostrada segue o **formato da roupa que vem no corpo** (mangas, punhos, volumes), não o formato do corpo. Quando um espaço de roupa está ocupado, a parte coberta precisa usar uma **geometria de corpo "sem roupa"** (braços e pernas no formato do corpo, sem mangas nem barras). Crie um corpo base nesse estilo (um por tipo de corpo, ou um só para todos, se ficar bom) e use-o só nas regiões cobertas pelas peças equipadas. Registre num ADR.
3. **Editar a capa:** quando eu já tiver mais países do que cabem na capa, quero **escolher quais bandeiras aparecem** e em que ordem. Isso fica no guarda-roupa (C), na peça capa.
4. **Fotos trocadas na Goblopédia:** às vezes a foto de uma entrada aparece em outra (tirei foto de uma flor e depois de uma vaca, e a página da vaca mostrou a flor). Uma vez apareceu a foto de um **personagem antigo**. Provável causa: arquivos de foto com nome repetido ou sobrescrito, cache de textura reaproveitando a imagem errada, ou fotos de perfis diferentes (`--profile`) misturadas. Corrija:
   - cada foto com **nome único** e guardada **por conta e por perfil**;
   - a Goblopédia aponta para a foto pelo identificador, nunca pela posição na lista;
   - o cache de imagens é invalidado quando a foto muda;
   - teste: tirar fotos de vários assuntos em sequência, em dois perfis, e conferir que cada página mostra a foto certa.
5. **Galeria de fotos:** quero ver **todas** as fotos que tirei, não só as da Goblopédia. Uma aba "Fotos" na Goblopédia (ou uma tecla própria) com todas as fotos, mais recentes primeiro, com data e lugar, opção de apagar e de **escolher qual foto representa** uma entrada da Goblopédia.

## 1. Cavernas

### Entrada e mapa separado
- As cavernas **não** são buracos cavados no globo. Existem **entradas** no mundo (bocas de caverna nas encostas de montanhas e morros, algumas por país, geradas pelo servidor de forma determinística). Com **E** na entrada, a tela escurece e o jogador vai para um **mapa separado**, a caverna. Na saída, volta para a boca da caverna.
- Cada entrada leva sempre à **mesma caverna**: o layout é gerado pelo servidor a partir de uma semente (salões, túneis, um pouco de altura e de desafio de caminho), e termina na **sala do chefe**.
- Tamanhos e profundidade variam por caverna (algumas curtas, outras longas, com dificuldade crescente).

### Multiplayer
- Uma caverna é um lugar **compartilhado**: quem entra pela mesma boca está na mesma caverna e vê os outros jogadores. O servidor já sabe trabalhar com áreas de interesse; trate cada caverna como uma área separada do globo. Registre num ADR.
- Os minérios funcionam como as árvores: **todos veem os mesmos**, e o limite de coleta é **por jogador e por dia**.

### Luz e clima
- A caverna é **meio escura**, parecida com a noite do jogo: nem breu, nem claro.
- Há coisas que **brilham**: alguns minérios, cristais e cogumelos luminosos, com brilho suave.
- **Tocha:** fabricada com **carvão + galho**. Pode ser segurada na mão (barra rápida) e **colocada nas paredes/chão** para iluminar. Limite de tochas acesas por jogador por caverna; luz sem sombra e só as mais perto acesas (lição da fogueira).
- A temperatura dentro da caverna é amena e constante; as necessidades funcionam normalmente.
- Desempenho: as cavernas também precisam rodar a **60 fps na qualidade média**.

## 2. Minérios, fornalha e ferramentas

### Minérios
- **Carvão:** combustível para tochas, fogueira e fornalha.
- **Ferro** e **diamante:** progressão clássica (ferro mais comum e raso, diamante raro e fundo).
- **Dois minérios originais do Goblo**, que só existem nas cavernas. Nomes provisórios no arquivo de dados: **goblita** (cristal rosado que brilha) e **auralita** (mineral azul-esverdeado com veios dourados). Eu posso trocar os nomes depois.
- Cada minério exige uma **picareta mínima** e dá mais com picaretas melhores.

### Fornalha
- Nova estação fabricável (lote ou cavernas): transforma minério bruto em **barra** usando carvão (ferro bruto → barra de ferro etc.), com um pequeno tempo de espera.

### Ferramentas
- **Picaretas:** pedra (a atual) → **ferro** → **diamante** → **goblita**. Cada nível quebra minérios mais duros e precisa de menos golpes.
- **Machados** podem seguir os mesmos níveis (mais madeira por golpe ou mais golpes por dia).
- **Lanterna/capacete com luz:** utilitário para explorar sem segurar tocha (ocupa o espaço cabeça).
- A **câmera** continua como ferramenta de exploração (e funciona nas cavernas, com a Goblopédia registrando o que for de lá: cogumelos luminosos, cristais, criaturas da caverna).

### Bolso e baú
- **Limite por item em cada espaço do bolso**, no arquivo de dados (por exemplo, 999 para materiais básicos, menos para itens raros e 1 para ferramentas e roupas). Itens acima do limite ocupam um novo espaço.
- **Baú:** fabricável, colocado no lote, com espaços próprios para guardar itens. Só o dono abre. O servidor guarda o conteúdo.

## 3. Chefe da caverna (encontro rápido)

- No fim de cada caverna há um **chefe**: uma criatura **grande, fofa e original do Goblo** (nada assustador; por exemplo, um golem de pedra rechonchudo e sonolento com cristais nas costas). Crie o modelo no estilo dos nossos pacotes, com animações simples.
- **Mecânica:** ele bate no chão em ataques com **aviso visível antes** (sombra ou círculo no chão que aparece um pouco antes do impacto). O jogador só precisa **desviar** das áreas. Depois de algumas sequências, o chefe **cansa e adormece**: o jogador vence ao chegar até ele e interagir (E), sem violência.
- **Punição suave:** levar **3 acertos** teleporta o jogador para o **início da caverna**, sem perder nada. Pode tentar de novo.
- **Recompensa:** gobolares, um **minério exclusivo** (por exemplo, um cristal que só sai do chefe e é necessário para a picareta de goblita), uma entrada na Goblopédia e uma conquista. Recompensa **uma vez por dia por jogador**, por caverna.
- No multiplayer, cada jogador desvia dos ataques por conta própria, e a recompensa é individual. O chefe é o mesmo para todos que estão na sala.
- O servidor valida os acertos e a vitória (com a mesma lógica de validação de distância/posição que já existe).

## 4. Folclore de cada país

- Criaturas **raras** e **fofas**, inspiradas em lendas populares de cada país, aparecem de vez em quando no país de origem (em certos biomas, horários ou estações). Elas **não atacam** e somem depois de um tempo ou quando você chega perto demais: o desafio é **fotografá-las** para a Goblopédia, numa seção especial **"Lendas"**, com um texto curtinho sobre a lenda.
- **Regras importantes:**
  - **Só lendas populares de domínio público.** **Nenhum personagem com direitos autorais** (personagens de livros, filmes, desenhos ou marcas). Por exemplo, o "Grinch" é um personagem de livro protegido e **não pode** entrar; no lugar dele, use uma lenda popular americana.
  - **Nada assustador**: versões fofas e simpáticas.
  - **Nada sagrado ou religioso** de nenhum povo (divindades, espíritos de cultos, figuras de religiões vivas).
  - Evite estereótipos de povos e culturas.
  - Pesquise cada lenda e registre a origem e uma frase de descrição em `docs/FOLCLORE.md`.
- **Lista inicial sugerida** (confira e ajuste seguindo as regras acima): Brasil — **Mula sem Cabeça** (fogo azul fofo no lugar da cabeça), **Saci**, **Curupira**; Estados Unidos — **Pé-Grande**, **Jackalope**; Alemanha — **Wolpertinger**; México — **alebrije** (bichinho colorido do artesanato popular); Escócia — **monstro do lago Ness** (perto da costa, aparece só a cabeça); Irlanda — **leprechaun**; Noruega — **troll** de montanha simpático; Rússia — **pássaro de fogo**. Comece com **8 a 12** e deixe fácil adicionar mais pelo arquivo de dados.
- Os modelos são criados por você, **no mesmo estilo** dos nossos pacotes.

## 5. Animais do mundo

- Novos animais **no mesmo estilo** do pacote de animais atual (mesma proporção, mesmo tipo de cor chapada e cantos), com pelo menos as animações **parado**, **andar** e **correr**, e algumas com **comer**.
- Distribuídos pelo bioma **e pela região de origem real** de cada espécie. Sugestão para começar (**6 a 10**, priorizando qualidade): **capivara** e **arara** (América do Sul), **tucano**, **bicho-preguiça** (em árvores), **pinguim** (Antártida e sul do Chile/Argentina), **urso-polar** (Ártico), **camelo** (desertos da África e Ásia), **canguru** e **coala** (Austrália), **panda** (China).
- Mesmas regras dos animais atuais: os mesmos para todos, posição pelo horário do servidor, tímidos ou mansos, carinho e frutinha, **sem forma de machucar**.
- Todos entram na **Goblopédia** e seguem a regra de foto centralizada.
- **Qualidade antes de quantidade:** se algum animal não ficar bom o suficiente no estilo, deixe-o de fora e me diga.

## 6. Modo dev, testes e documentação

- Painel dev: ir para a entrada de caverna mais próxima, entrar em qualquer caverna, ir direto ao chefe, invencibilidade contra o chefe, dar minérios e ferramentas, fazer aparecer uma criatura de folclore ou um animal novo, encher o baú.
- **Testes em Go:** cavernas determinísticas (mesma entrada, mesmo layout), minérios e limites diários por jogador, picareta mínima por minério, fornalha, limite por item no bolso, baú (só o dono), chefe (3 acertos voltam ao início, recompensa uma vez por dia), folclore e animais por país/bioma, registro na Goblopédia.
- Atualize README, `docs/CONTEUDO.md`, `docs/FOLCLORE.md`, `docs/API.md`, `docs/PROTOCOLO.md` e os ADRs.

## Fora do escopo

Mar, pesca, barcos e Atlântida; veículos e petróleo; interior da casa; interface nova; música e sons; itens do `BACKLOG.md` não citados aqui.

## No final

O que mudou, como testar cada parte pelo modo dev (passo a passo), quais lendas e animais entraram (e quais ficaram de fora e por quê), decisões tomadas sozinho, desempenho nas cavernas, o que ficou pendente e o que ficou sem verificação visual.
