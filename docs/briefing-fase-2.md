# Briefing — Fase 2: coletar e construir

> Cole este arquivo inteiro no Claude Code, na pasta do projeto. Peça para ele salvar uma cópia em `docs/briefing-fase-2.md` antes de começar.

## Contexto

As Fases 1 e 1.5 estão prontas e ficaram ótimas: globo grande com grade `n = 50`, biomas, vegetação por pedaços, dia e noite real, oceano, nuvens, bússola, mini mapa e personagem com pulo. **Não refaça o que funciona.**

Esta fase cria o ciclo central do jogo, num ritmo cozy: **coletar materiais → fabricar ferramentas e objetos → construir a casa e decorar o lote → voltar amanhã.**

Regras de sempre: commits pequenos em português, `go test ./...` e `go vet ./...` passando antes de cada commit, push no `main` no final, README, `CLAUDE.md` e ADRs atualizados. Desempenho continua sendo requisito: 60 fps no meu Mac Intel na qualidade padrão.

## Visão do ciclo

1. O jogador entra pela primeira vez, escolhe um apelido e **nasce no país dele**, num lote só dele.
2. Ele **sacode árvores** para pegar galhos, **colhe flores** e pega pedrinhas no chão.
3. Na **bancada** do lote, fabrica um **machado** e uma **picareta**.
4. Com o machado, **bate nas árvores** para tirar madeira (a árvore não cai). Com a picareta, **bate nas pedras grandes** para tirar pedra.
5. Com os materiais, **constrói a casa** a partir de uma planta pronta. A obra fica **pronta no dia seguinte**.
6. Fabrica e coloca **decorações** livremente no lote: cerca, flores, banco, poste, caminho.
7. Anda pelo bairro e **vê as casas dos outros jogadores** que moram por perto.
8. No dia seguinte, as árvores e pedras dão material de novo.

## 1. Modo desenvolvedor (fazer primeiro)

Eu preciso testar tudo sem ter que jogar de verdade.

- O servidor só aceita comandos de dev quando iniciado com `GOBLO_DEV=1`. Sem isso, as rotas de dev respondem 403. **Teste isso.**
- No cliente, **F1** abre um painel de dev (só funciona se o servidor disser que está em modo dev) com:
  - dar qualquer material ou item em qualquer quantidade;
  - construir na hora (pular a espera da obra);
  - avançar para o "dia seguinte" (resetar os limites diários);
  - voar e atravessar objetos (noclip);
  - teleportar para um país (lista) ou para uma latitude/longitude;
  - trocar o país do jogador;
  - resetar o lote, o inventário e o jogador inteiro;
  - acelerar o tempo (o F3 que já existe pode continuar).
- Deixe o modo dev fácil de usar: lista pesquisável de itens e países.

## 2. Jogador, identidade e país

- **Identidade simples, sem login:** na primeira vez, o jogador escolhe um **apelido** (com filtro de palavrões). O servidor devolve um **token secreto**, que o cliente guarda em `user://`. Nas próximas vezes, o cliente se identifica com o token.
- **Descobrir o país:**
  1. o servidor tenta descobrir pelo **IP da conexão**, usando uma base gratuita de IP → país (por exemplo a *IP to Country Lite* da DB-IP, licença CC BY 4.0; confira a licença e dê o crédito). **Não guarde o IP**: use só para descobrir o país e descarte;
  2. se não der (rodando local, o IP é `127.0.0.1`), o cliente usa o **idioma/região do sistema** (`OS.get_locale()`, por exemplo `pt_BR` → Brasil);
  3. a tela de primeiro acesso **mostra o país detectado e deixa o jogador confirmar ou trocar** numa lista.
- Documente no README o que é feito com o IP (privacidade).

## 3. Lotes

- Cada hexágono de terra (região) é dividido em **lotes**. Cada lote é uma grade de **16 × 16 quadradinhos de 1 unidade** (ajuste se ficar grande ou pequeno demais; configurável). Um hexágono comporta vários lotes, e quem mora no mesmo hexágono é **vizinho**.
- No primeiro acesso, o servidor escolhe um **lote livre no país do jogador**, preferindo biomas agradáveis (`grassland`, `forest`, `tropical_forest`, `beach`) e evitando `desert`, `ice`, `tundra` e `mountain` quando houver opção. O personagem nasce no lote.
- O terreno do lote é **plano** (achate a área sob ele) e tem uma borda sutil desenhada no chão para o jogador saber onde é dele.
- Dentro do lote não nasce vegetação aleatória que atrapalhe a construção (limpe a área).
- Só o dono constrói e decora no próprio lote. **O servidor valida isso.**
- Um botão ou atalho **"voltar para casa"** (H) teleporta o jogador para o lote.

## 4. Objetos interativos e coleta

**Decisão de arquitetura importante:** hoje a vegetação é espalhada no cliente a partir de uma semente. Os objetos que dão material (**árvores, pedras grandes, flores e itens no chão**) precisam ser conhecidos pelo **servidor**, para ele validar a coleta. Então:

- o **servidor gera** os objetos interativos de cada célula de forma determinística (por `id` da célula) e os envia por pedaços ao cliente, cada um com um `id` estável;
- a **grama decorativa** e os enfeites sem interação continuam sendo espalhados só no cliente, como hoje;
- garanta que árvores interativas e decorativas não se sobreponham. Registre a decisão num ADR.

**Interações** (tecla **E** perto do objeto, com um aviso na tela tipo "E: sacudir"):

| Objeto | Sem ferramenta | Com ferramenta |
|---|---|---|
| Árvore | **sacudir**: caem de 1 a 3 **galhos** (1 vez por dia por árvore, por jogador). A árvore balança. | **machado**: 3 golpes por dia por árvore, por jogador, cada um dá 1 **madeira**. A árvore **nunca cai** nem some. |
| Pedra grande | — | **picareta**: 3 golpes por dia por pedra, por jogador, cada um dá 1 **pedra**. A pedra não some. |
| Flor | **colher**: dá 1 **flor** (da cor da flor). Para aquele jogador, ela some até o dia seguinte. | — |
| Item no chão (pedrinha, galho) | **pegar**. Renascem todo dia. | — |
| Arbusto de frutinhas (`BushBerries_*`) | **colher**: dá de 1 a 3 **frutinhas** (1 vez por dia por arbusto, por jogador). | — |

Árvores sem folhas (`*_Dead_*`), cactos e palmeiras também podem ser sacudidos, mas palmeira dá **coco** em vez de galho (1 vez por dia) e cacto não dá nada (só balança). O coco é mais um material para receitas futuras; pode entrar já no inventário.

- **Os limites são por jogador.** Todo mundo vê as mesmas árvores, e o que um jogador coleta não tira nada dos outros.
- O **dia** vira às **5h da manhã no horário local do jogador** (o dia do jogo). Use o horário local aproximado pela longitude, que já existe no jogo.
- Animações simples: o personagem usa `interact-right` ou `pick-up`; os itens fazem um "pop" fofinho ao entrar no inventário.
- **O servidor é a fonte da verdade do inventário.** O cliente pede ("sacudi a árvore X"), e o servidor confere o limite diário e devolve o resultado. Como ainda não há posição do jogador no servidor (isso vem na Fase 3), por enquanto aceite a interação sem conferir a distância, mas deixe um `TODO` e um ADR explicando que a validação de distância entra no multiplayer.

## 4b. Assets novos e biomas com o Ultimate Nature Pack

Adicionei novos pacotes (todos **CC0**) na pasta do projeto. **Procure-os no repositório** e organize como antes, em `client/assets/<autor>/<pacote>/`, sempre com o `License.txt`, depois removendo as pastas originais do Git e atualizando `client/assets/CREDITOS.md` e o README:

| Pacote | Autor | Formato a manter | O que é | Uso |
|---|---|---|---|---|
| **Ultimate Nature Pack** | Quaternius | **só `FBX/`** (não há glTF; o Godot 4 importa FBX nativamente). Descarte `OBJ/` e `Blends/` | 150 modelos: árvores comuns, bétulas, pinheiros, salgueiros, palmeiras, cactos, arbustos, frutinhas, pedras (normal, com musgo e com neve), tocos, troncos, grama, flores, trigo, milho, vitória-régia. Quase tudo tem versões **normal, outono, neve e seca** | **agora**: biomas e objetos interativos |
| **Fantasy Town Kit** | Kenney | `GLB format/` + `Textures/` | peças modulares de casas, cercas, sebes, lampião, fonte, barraquinha, carrinho, caminhos, moinhos | **agora**: casas e decoração |
| **Ultimate Animated Animals** | Quaternius | **só `glTF/`**. Descarte `FBX/`, `OBJ/`, `Blends/` e o `Preview.mp4` | 12 animais animados (alpaca, touro, vaca, cervo, burro, raposa, 2 cavalos, husky, shiba, alce-macho, lobo) com `Idle`, `Walk`, `Gallop`, `Eating`, `Jump` etc. | **guardar** para a Fase 2.5 (não colocar no mundo agora) |
| **Car Kit** | Kenney | `GLB format/` + `Textures/` | 50 veículos e peças | **guardar** para o futuro |
| **Watercraft Pack** | Kenney | `GLB format/` + `Textures/` | 46 barcos, navios e boias | **guardar** para o futuro |

Os animais em glTF vêm com os dados embutidos em base64 (36 MB). Se o import ficar lento ou pesado, converta para `.glb` no import e registre num ADR.

**Trocar a vegetação dos biomas pelo Ultimate Nature Pack** (tanto a interativa, gerada no servidor, quanto a decorativa, espalhada no cliente). Mapeamento sugerido, que fica num arquivo de dados para eu ajustar:

| Bioma | Árvores | Pedras e outros | Chão decorativo |
|---|---|---|---|
| `tropical_forest` | `PalmTree_*`, `CommonTree_*` grandes e densas, `Willow_*` perto da água | `Rock_Moss_*`, `BushBerries_*`, `Plant_*` | `Grass`, `Grass_2`, `Plant_*` |
| `forest` | `CommonTree_*`, `BirchTree_*`, `Willow_*` | `Rock_Moss_*`, `TreeStump_Moss`, `WoodLog_Moss`, `Bush_*`, `BushBerries_*` | `Grass`, `Flowers` |
| `grassland` | `CommonTree_*` esparsas | `Rock_*`, `Bush_*`, `Wheat` | `Grass_Short`, `Flowers` |
| `beach` | `PalmTree_*` | `Rock_*` pequenas | quase nada |
| `desert` | `Cactus_*`, `CactusFlower*` | `Rock_*` | nada |
| `mountain` | `PineTree_*` esparsos | `Rock_*` grandes | `Grass_Short` rala |
| `tundra` | `PineTree_Snow_*`, `BirchTree_Snow_*`, `*_Dead_Snow_*` | `Rock_Snow_*`, `Bush_Snow_*`, `WoodLog_Snow`, `TreeStump_Snow` | quase nada |
| `ice` | nenhuma ou rara | `Rock_Snow_*` | nada |

- Retire a vegetação antiga dos pacotes de Halloween/Graveyard dos biomas se o Nature Pack cobrir melhor; mantenha o que continuar combinando.
- As versões de **outono** (`*_Autumn_*`) ficam **reservadas para as estações do ano** da Fase 2.5. Não use agora, mas deixe o mapeamento pronto para isso.
- Ajuste a escala dos modelos do Nature Pack para combinar com o personagem da Kenney (as árvores devem parecer árvores ao lado dele, sem ficar gigantes).
- Desempenho: o pacote tem muitas variações. Use `MultiMesh` por modelo e limite o número de variações carregadas por pedaço, se preciso. A meta de 60 fps no Mac Intel continua valendo.

## 5. Inventário e fabricação

- **Inventário** com 20 espaços (itens iguais se empilham até 99), aberto com **Tab** ou **I**. Visual fofo e aconchegante, com cartões creme.
- **Barra rápida** para escolher a ferramenta na mão (teclas 1 a 5). A ferramenta aparece na mão do personagem (se não houver modelo nos pacotes, faça um modelo simples low-poly com primitivas).
- **Bancada de trabalho:** todo lote já começa com uma. Perto dela, **E** abre o menu de **receitas**.
- Receitas iniciais (ajuste os números para o jogo ficar gostoso). Os modelos de decoração vêm do **Fantasy Town Kit** e do **Ultimate Nature Pack**:
  - **machado:** 5 galhos + 1 pedra;
  - **picareta:** 5 galhos + 2 pedras;
  - **cerca de madeira** (`fence`, `fence-curved`) e **portão** (`fence-gate`): 2 madeiras;
  - **cerca viva** (`hedge`, `hedge-curved`, `hedge-gate`): 3 galhos + 2 flores;
  - **lampião** (`lantern`): 2 madeiras + 2 pedras (acende à noite, com luz suave);
  - **banco** (`stall-bench`) e **banquinho** (`stall-stool`): 4 madeiras;
  - **caminho de pedra** (peças `road*`): 1 pedra;
  - **canteiro de flores** (`Flowers` do Nature Pack): 3 flores;
  - **barraquinha** (`stall`, `stall-red`, `stall-green`): 10 madeiras;
  - **carrinho** (`cart`): 8 madeiras;
  - **fonte** (`fountain-round`): 30 pedras;
  - **pedra decorativa** (`rock-large`, `rock-small`): 3 pedras;
  - **arbusto de frutinhas** (`BushBerries_*`): 5 frutinhas (ver coleta).
- **As receitas ficam num arquivo de dados no servidor** (JSON ou YAML), não espalhadas pelo código, e o cliente recebe a lista do servidor. Assim eu consigo balancear sem programar.
- As ferramentas não quebram nesta fase.

## 6. Construção

### Casa (planta pronta, em níveis)

- Três níveis: **barraca → casinha → casa grande**. Cada nível pede materiais (exemplo: barraca = 10 madeiras; casinha = 30 madeiras + 20 pedras; casa grande = 60 madeiras + 50 pedras + 10 flores. Ajuste no arquivo de dados).
- O jogador escolhe onde colocar a casa no lote (com prévia), e o servidor desconta os materiais.
- A obra aparece com **andaimes ou uma placa "em obras"** e fica **pronta na próxima virada do dia (5h local)**. No modo dev, dá para concluir na hora.
- Melhorar de nível segue o mesmo processo, no mesmo lugar.
- **Não precisa ter interior** nesta fase. A casa é só por fora.

### Decoração livre

- **Modo construção** (tecla **B**): escolha um item do inventário que seja colocável, veja a **prévia transparente** (verde onde pode, vermelha onde não pode), gire de 90 em 90 graus (**R**), confirme para colocar e use **X** para guardar de volta no inventário.
- Tudo encaixa na grade 16 × 16 do lote. Objetos não se sobrepõem.
- O servidor valida tudo: dono do lote, limites do lote, sobreposição e se o jogador tem o item.

### Casas com o Fantasy Town Kit

O **Kenney Fantasy Town Kit** é **modular**: tem paredes de madeira e de pedra (com porta, janela, arco), telhados (`roof-*`, `roof-high-*`), chaminé, sacada, escadas, pilares etc. **Monte as três casas como cenas do Godot a partir dessas peças**:

- **barraca:** pequena e simples, de madeira (por exemplo, 2 × 2 peças de `wall-wood*` com porta e um telhado baixo `roof-gable`), com cara de primeira casa;
- **casinha:** de madeira, com porta, janelas com venezianas (`wall-wood-window-shutters`), telhado de duas águas e chaminé;
- **casa grande:** dois andares, base de pedra e andar de cima de madeira, `roof-high-*`, sacada (`balcony-wall*`) e chaminé.

Cada casa vira uma cena (`house_level_1.tscn` etc.) com o tamanho em quadradinhos do lote documentado. Fofura e proporção importam mais que tamanho: compare com a altura do personagem.

## 7. Persistência no servidor

- Banco **SQLite** usando um driver **em Go puro, sem cgo** (por exemplo `modernc.org/sqlite`). No meu Mac Intel, ferramentas que dependem do Xcode estão dando problema, então evite cgo.
- Acesso ao banco atrás de **interfaces de repositório** (`PlayerRepository`, `LotRepository` etc.), para trocar por PostgreSQL depois sem mexer nas regras. Deixe isso num ADR.
- **Migrações versionadas** em SQL.
- Tabelas sugeridas: jogadores, lotes, inventário, coletas diárias (jogador + objeto + dia + contagem), construções/decorações colocadas e obras em andamento.
- O arquivo do banco fica fora do Git.
- **Relógio injetável** nas regras (para testar a virada do dia e a obra pronta sem esperar).

## 8. Ver as casas dos vizinhos

- O cliente pede ao servidor os lotes das células perto do jogador e **desenha as casas e decorações dos outros jogadores**, com uma plaquinha com o apelido do dono na frente do lote.
- Carrega e descarrega por pedaços, junto com a vegetação.
- No modo dev, um comando para **criar 20 jogadores falsos** com casas e decorações aleatórias perto de mim, para eu ver o bairro cheio.

## API (sugestão)

REST com JSON, autenticada pelo token no cabeçalho:

- `POST /players` (cria jogador: apelido + país) e `GET /me`;
- `GET /objects?cells=...` (objetos interativos por pedaço, com o estado para o meu jogador);
- `POST /interact` (sacudir, golpear, colher, pegar);
- `GET /recipes`, `POST /craft`;
- `GET /lots?cells=...` (lotes e construções de todo mundo por pedaço);
- `POST /lot/place`, `POST /lot/remove`, `POST /lot/house`;
- `/dev/...` (só com `GOBLO_DEV=1`).

Fique à vontade para melhorar os nomes. Documente tudo em `docs/API.md`.

## Testes em Go (obrigatórios)

- rotas de dev bloqueadas sem `GOBLO_DEV=1`;
- criação de jogador e atribuição de lote no país certo, preferindo biomas agradáveis;
- dois jogadores nunca recebem o mesmo lote;
- limites diários: sacudir 1 vez, 3 golpes de machado, 3 de picareta, e reset na virada das 5h locais (com relógio falso);
- a coleta de um jogador não afeta outro;
- fabricação consome os materiais certos e falha sem materiais;
- não é possível construir no lote de outro, fora da grade ou sobrepondo objetos;
- a casa fica pronta só depois da virada do dia (relógio falso);
- os objetos interativos são determinísticos;
- detecção de país: IP local cai no fallback; IP conhecido devolve o país certo.

## Fora do escopo agora (não implementar)

Animais, aeroporto e viagem entre países, passaporte e carimbos, Goblopédia e colecionáveis, interior da casa, multiplayer em tempo real (jogadores andando), chat, dinheiro e loja, troca entre jogadores, pesca, música e efeitos sonoros, carros e navios, ferramentas que quebram, login de verdade. **Esses itens vêm nas próximas fases**; não feche portas para eles.

## Forma de trabalho

- Execute a fase inteira de uma vez e me entregue pronto para revisar.
- Ordem sugerida: modo dev → organizar assets novos e trocar a vegetação dos biomas → banco e identidade → país e lote → objetos interativos e coleta → inventário e bancada → decoração livre → casa em níveis e obra → casas dos vizinhos → testes, desempenho e documentação.
- Decisões que não estão aqui: escolha a mais simples, registre num ADR e siga.
- No final, me diga o que mudou, **como testar com o modo dev** (passo a passo), o que precisa de assets novos e o que ficou pendente.

## Roadmap

1. Fase 1: globo, personagem, servidor. ✅
2. Fase 1.5: um mundo de verdade. ✅
3. **Fase 2: coletar e construir.** ← agora
4. Fase 2.5: explorar e colecionar (animais do Ultimate Animated Animals andando pelos biomas, **estações do ano reais por hemisfério** usando as versões de outono e neve do Nature Pack, aeroporto com viagem animada pelo globo, passaporte com carimbos, Goblopédia com fotos dos animais).
5. Fase 3: multiplayer em tempo real.
6. Fase 4: economia (dinheiro, loja, troca) e regras de fronteira.
