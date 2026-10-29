# 0032 — Animais determinísticos pelo horário do servidor

## Contexto

A fase 2.5 coloca animais andando pelo mundo, e todos os jogadores precisam ver o mesmo animal no mesmo lugar. O servidor ainda não sabe a posição dos jogadores (fase 3) e não deve simular milhares de animais.

## Decisão

- **Quais animais existem:** o servidor sorteia por célula (`GenerateAnimals`, semente no id da célula), a partir de `animals.json` (espécies por bioma e cachorros perto dos bairros). Cada animal tem um **id estável** (célula × 16 + índice) e até 6 **pontos de passeio**, já conferidos no servidor: dentro da célula, fora dos lotes ocupados, longe de árvores e pedras, e com caminho livre entre quaisquer dois pontos. Os animais vão junto com `GET /objects`.
- **Onde cada um está:** uma função só do animal e do horário do servidor (`AnimalAt` em Go, `AnimalPath.at` em GDScript). O tempo é cortado em trechos de `leg` segundos; em cada trecho o animal anda do ponto sorteado para o trecho anterior até o sorteado para este e depois fica parado (comendo, olhando ou parado). O hash usa só multiplicações de 32 bits, feitas em pedaços de 16 bits no GDScript, e um arquivo de referência (`testdata/animal_paths.json`) garante que as duas linguagens dão exatamente as mesmas poses.
- **Relógio:** `/objects` manda `now_ms`; o cliente guarda a diferença para o relógio local. O "dia seguinte" do modo dev adianta os animais junto.
- **Reações locais:** fugir (tímidos, quando o jogador corre perto), seguir (amigo, depois da frutinha) e parar no carinho são um **desvio** somado ao trajeto comum, só neste cliente. Quando a reação acaba, o desvio volta a zero andando e o animal reencontra o trajeto de todo mundo.

## Multiplayer (fase 3)

Os outros jogadores continuam vendo o animal no trajeto comum. Para que vejam também uma reação, basta o servidor repassar um evento curto (id do animal, tipo, instante, ponto de partida); cada cliente aplica o mesmo desvio, que é determinístico a partir desse evento, e o animal volta ao trajeto comum do mesmo jeito para todos. Nada disso exige o servidor simular os animais.

## Consequências

- Lote novo pode mudar os pontos de passeio dos animais da célula (são conferidos contra os lotes), mas o mesmo para todos. Os cachorros dos bairros usam um sorteio separado, então um lote novo não muda os animais do bioma.
- Os animais não têm colisão: o personagem passa por eles (são poucos e se afastam ou param).
- Desempenho: só os 12 mais perto (até 45 unidades) ganham modelo, e os mais longe são atualizados menos vezes por segundo. No teste headless, ~0,9 ms de CPU por quadro com 12 animais.
