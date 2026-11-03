<h1 align="center">Goblo</h1>

<p align="center">
  <strong>Um MMO cozy no planeta Terra de verdade.</strong><br />
  O globo da aula de geografia, pequeno e fofo, com os continentes e países reais: nasça no seu país, colete materiais, construa sua casa e conheça os vizinhos.
</p>

<p align="center">
  <img alt="Go" src="https://img.shields.io/badge/Go-1.27-00add8?logo=go&logoColor=white" />
  <img alt="Godot" src="https://img.shields.io/badge/Godot-4.7-478cbf?logo=godotengine&logoColor=white" />
  <img alt="GDScript" src="https://img.shields.io/badge/GDScript-2.0-355570?logo=godotengine&logoColor=white" />
  <img alt="SQLite" src="https://img.shields.io/badge/SQLite-Go_puro-003b57?logo=sqlite&logoColor=white" />
  <img alt="Natural Earth" src="https://img.shields.io/badge/dados-Natural_Earth-6aa84f" />
  <a href="https://github.com/Dustyluc123/goblo/actions/workflows/server.yml"><img alt="CI" src="https://github.com/Dustyluc123/goblo/actions/workflows/server.yml/badge.svg" /></a>
  <img alt="Testes" src="https://img.shields.io/badge/testes-85_passando-12a85f" />
  <img alt="Fase" src="https://img.shields.io/badge/fase-2.5_de_4-f4a6b8" />
</p>

<p align="center">
  <img src="docs/imagens/bairro.png" alt="Um bairro no Brasil: casas de madeira com telhado verde e casas grandes com telhado vermelho, cada uma no seu lote com plaquinha, lampiões e bancadas, no meio de uma floresta tropical" width="760" />
</p>

---

## Índice

- [O que é](#o-que-é)
- [O que já dá para fazer](#o-que-já-dá-para-fazer)
- [Telas](#telas)
- [Como testar com o modo dev](#como-testar-com-o-modo-dev)
- [Como testar a fase 2.5](#como-testar-a-fase-25)
- [Como testar a fase 2.6](#como-testar-a-fase-26)
- [Como testar a fase 3](#como-testar-a-fase-3)
- [Como testar a fase 4.1](#como-testar-a-fase-41)
- [Medições](#medições)
- [Arquitetura](#arquitetura)
- [Tecnologias](#tecnologias)
- [Estrutura de pastas](#estrutura-de-pastas)
- [Como rodar](#como-rodar)
- [Controles](#controles)
- [Testes](#testes)
- [Privacidade](#privacidade)
- [Dados](#dados)
- [Créditos](#créditos)
- [Roadmap](#roadmap)
- [Sobre mim](#sobre-mim)

## O que é

Um MMO cozy e aconchegante que se passa **no planeta Terra de verdade**, visto como o globo da aula de geografia: pequeno, estilizado e fofo, com os continentes e países reais divididos em hexágonos.

O ciclo central é tranquilo e diário: **coletar materiais → fabricar ferramentas e objetos → construir a casa e decorar o lote → voltar amanhã**. Cada hexágono do globo tem até quatro lotes, e quem mora no mesmo hexágono é vizinho.

## O que já dá para fazer

**Fase 1: o globo** ✅ e **Fase 1.5: um mundo de verdade** ✅

- Globo low-poly com os países reais, 25.002 hexágonos num planeta de raio 1000, zoom do personagem até o planeta inteiro
- Personagem animado que anda e pula por cima da esfera; São Paulo → Venezuela leva ~2 min andando
- Biomas do servidor, dia e noite pelo horário real (UTC), oceano animado, nuvens, bússola, mini mapa, configurações (F6: qualidade gráfica, tamanho da interface, tela cheia)

**Fase 2: coletar e construir**

- [x] **Primeiro acesso sem login:** apelido (com filtro de palavrões) e país sugerido pelo IP ou pelo idioma do sistema, que o jogador confirma ou troca. O servidor devolve um token secreto que o cliente guarda
- [x] **Lote próprio no seu país**, de 14 × 14 quadradinhos, com borda no chão, plaquinha com o seu apelido e uma bancada. **H** volta para casa
- [x] **Objetos do servidor**: árvores, pedras, flores, arbustos de frutinhas, pedrinhas e galhos, gerados de forma determinística (todo mundo vê os mesmos)
- [x] **Coleta com E:** sacudir árvores (galhos; palmeira dá coco), cortar com machado (madeira), quebrar pedras com picareta, colher flores e frutinhas, pegar o que está no chão. A árvore balança, o item faz um "pop" e o servidor confere os **limites do dia, por jogador**. O dia vira às **5h no seu horário**
- [x] **Inventário** de 20 espaços (Tab ou I), **barra rápida** com as ferramentas (1 a 5) e a ferramenta aparece na mão
- [x] **Bancada** com 21 receitas (machado, picareta, cercas, cerca viva, lampião, banco, caminho, canteiro, barraquinhas, carrinho, fonte…), num arquivo de dados para balancear sem programar
- [x] **Modo construção (B):** prévia transparente verde ou vermelha, R gira, clique coloca, X guarda de volta. Tudo encaixa na grade e o servidor valida
- [x] **Casa em três níveis** (barraca → casinha → casa grande), montada com o Fantasy Town Kit. A obra aparece com andaime e fica **pronta no dia seguinte**
- [x] **Bairro:** as casas e a decoração dos vizinhos aparecem com o nome do dono; lampiões acendem à noite
- [x] **Ultimate Nature Pack** em todos os biomas: palmeiras e salgueiros, bétulas, pinheiros com neve, cactos floridos, pedras com musgo
- [x] **Banco SQLite** (Go puro, sem cgo) com migrações e repositórios trocáveis
- [x] **Modo dev (F1)** para testar tudo sem jogar: dar itens, obra na hora, dia seguinte, voar, teleportar, trocar país, resets e 20 vizinhos falsos

**Fase 2.1: polimento** ✅

- [x] **Câmera que não entra em nada** (na fase 2.2 virou só transparência, ver abaixo)
- [x] **Melhorar a casa funciona:** a casa cresce no lugar, com a porta do mesmo lado, acha sozinha uma posição que caiba e, se decorações atrapalharem, diz quais, marca em vermelho e guarda no bolso com um clique
- [x] **Sem texturas piscando** nos cantos das casas, no telhado e na sacada
- [x] **Menus capturam mouse e teclado** (a roda rola a lista, não dá zoom) e todos têm botão **X**
- [x] **Mini mapa** com a casinha do seu lote e uma setinha para onde você está virado; na visão afastada, um marcador mostra a sua casa
- [x] **Desempenho:** lotes dos vizinhos juntados numa malha por material, LOD e distâncias por tipo, sombras e resolução do 3D ajustadas por qualidade ([ADR 0028](docs/decisoes/0028-desempenho-da-fase-2-1.md))
- [x] **Mais bonito:** tonemapping AgX, luz do céu, névoa de distância na cor do horizonte, glow leve, vento na vegetação, AO nos vértices e paleta pastel ([ADR 0029](docs/decisoes/0029-visual-luz-nevoa-vento.md))
- [x] **Relógio do modo dev** volta para a hora real sem reiniciar o servidor
- [x] O Goblo não cita outros jogos (verificação no CI)

**Fase 2.2: últimos ajustes** ✅

- [x] **Câmera só com transparência:** a distância e o ângulo só mudam quando você mexe; o que fica entre a câmera e o personagem (casas com telhado, árvores, postes) fica pontilhado com fade suave, e some se a câmera estiver dentro dele ([ADR 0030](docs/decisoes/0030-camera-so-com-transparencia.md))
- [x] **Câmera no mouse:** o cursor fica capturado durante o jogo e é solto nos menus, no modo construção, com Alt e com Esc; sensibilidade e eixo invertido no F6
- [x] **Seta do mini mapa** aponta para o lado certo (leste e oeste estavam trocados)

**Fase 2.5: explorar e colecionar** ✅

- [x] **Fronteiras precisas:** o país vem da **posição exata** (Natural Earth 1:50m, ponto em polígono), não mais do hexágono de ~140 km. HUD com o país certo, **linha tracejada com marquinhos** no chão onde dois países se encontram e uma **plaquinha "Bem-vindo!"** ao cruzar. Países pequenos (Luxemburgo, Andorra, Mônaco…) passam a existir ([ADR 0031](docs/decisoes/0031-fronteiras-pela-posicao-exata.md))
- [x] **Gobolares:** saldo no servidor, mostrado no HUD; **caixa de vendas** no lote (E) paga na hora pela madeira, pedra, flores, frutinhas e cocos; recompensas pelo primeiro registro na Goblopédia e pelo primeiro carimbo de cada país; histórico de transações
- [x] **Animais:** os 12 do Ultimate Animated Animals pelos biomas (vacas, cavalos e burros nos campos, cervos e raposas nas florestas, alpacas nas montanhas, lobos na tundra, cachorros perto dos bairros). **Os mesmos para todos os jogadores**: o servidor sorteia quais existem e a posição sai do horário do servidor ([ADR 0032](docs/decisoes/0032-animais-deterministicos.md)). Tímidos fogem se você correr; **E** faz carinho (coraçõezinhos) ou dá frutinha (o animal come e segue você por um tempo)
- [x] **Câmera fotográfica e Goblopédia (G):** com a câmera na mão, o botão direito mira por cima do ombro, a roda dá zoom e o clique tira a foto (salva no seu computador). O que estiver enquadrado entra no álbum: animais, a **flor azul rara** e **árvores de outono e com neve** ([ADR 0033](docs/decisoes/0033-goblopedia-e-camera.md))
- [x] **Estações do ano reais** pela data e pelo hemisfério: no fim de outubro, outono no norte (árvores de outono, chão dourado, folhas caindo) e primavera no sul (verde mais claro e florzinhas); inverno com neve e flocos caindo. Transição gradual, nada nos trópicos, e o globo afastado e o mini mapa mostram os dois hemisférios ([ADR 0034](docs/decisoes/0034-estacoes-do-ano.md))
- [x] **Aeroportos e passaportes:** um aeroporto perto da capital de cada país, montado com o Fantasy Town Kit (terminal, pista, biruta); no balcão (E), destinos com preço pela distância e passaportes. A viagem afasta até o globo e desenha um arco até o destino. **Para entrar num país (a pé ou de avião) você precisa do passaporte dele**; o do seu país é grátis. **Livro de passaporte (P)** com um carimbo único por país visitado ([ADR 0035](docs/decisoes/0035-aeroportos-viagem-e-passaportes.md))
- [x] **Modo dev (F1)** com gobolares, passaportes, barreira, linhas e polígonos de fronteira, estação forçada, animais, Goblopédia e voo de graça

**Fase 2.6: ajustes da 2.5** ✅

- [x] **Modo foto em primeira pessoa:** a câmera vai para os olhos do personagem e o corpo some; **F** troca para o **selfie** (câmera na frente, personagem fazendo pose com o cenário atrás) e volta. A Goblopédia registra o que está enquadrado nos dois modos
- [x] **Cursor depois da viagem:** no fim do voo (e depois de casa, teleporte, menus, aviso da fronteira e plaquinha) o mouse volta a girar a câmera na hora, sem clique; tudo passa pelo gerenciador de interface (`--cursor-test`)
- [x] **Travadas:** registro em `user://travadas.log` de todo quadro acima de 25 ms, com o que estava acontecendo, e as últimas no F2. Com ele: linhas de fronteira (até 320 ms por pedaço) e leitura dos pedaços do servidor em threads, aeroportos, colisão do chão e lotes espalhados entre quadros, shaders pré-aquecidos na tela de carregamento e **limite de fps** no F6 (30, 60 ou sem limite; V-Sync sempre ligado) ([ADR 0036](docs/decisoes/0036-travadas-e-limite-de-fps.md))
- [x] **Nunca no oceano:** andar, teleporte, chegada de voo, nascimento e H sempre terminam em terra

**Fase 3: fronteiras vivas e multiplayer** ✅

- [x] **Fronteira não corta lote:** lote novo fica inteiro no país do dono e a 2 unidades da fronteira (países pequenos, como a Albânia, ficam com o melhor lote que houver); para o dono, o lote e a margem contam como o país dele, e ninguém fica preso em bolsões ([ADR 0037](docs/decisoes/0037-lotes-e-fronteiras.md))
- [x] **Fronteira viva:** cortina de luz pastel com brilhinhos, marcos com bandeirolas de festa e cadeadinho. Com os dois passaportes ela abre (cortina baixa, corda em arco, cadeado aberto), anima ao comprar o passaporte, faz uma onda quando você encosta e solta confete ao atravessar ([ADR 0038](docs/decisoes/0038-fronteira-viva.md))
- [x] **Multiplayer em tempo real** no nosso próprio servidor ([ADR 0039](docs/decisoes/0039-tempo-real-no-servidor-proprio.md), protocolo em [docs/PROTOCOLO.md](docs/PROTOCOLO.md)): os outros jogadores aparecem com o personagem escolhido, o apelido e as animações, com movimento liso (interpolação de ~110 ms); o servidor valida velocidade, oceano e fronteira e corrige com suavidade; reconecta sozinho
- [x] **Chat (Enter), emotes (T) e jogadores por perto (J)** com silenciar e bloquear; árvore balançando e decoração surgindo na hora quando um vizinho mexe
- [x] **Escolha de personagem** (os 12 do Mini Characters) no primeiro acesso e no F6
- [x] **O servidor confere** a distância na coleta, bancada, caixa de vendas, frutinha, Goblopédia e balcão do aeroporto, a barreira da fronteira e o carimbo a pé ([ADR 0040](docs/decisoes/0040-validacoes-no-servidor.md))
- [x] **Ferramentas:** bots no modo dev (F1 → Rede), simulação de atraso e perda, ping no F2, bots em Go e teste de carga
- [x] **Para jogar com amigos (sem publicar):** Dockerfile, [docs/DEPLOY.md](docs/DEPLOY.md), exportação para macOS e Windows e endereço do servidor configurável

**Fase 3.5: economia viva e os primeiros personagens** ✅

- [x] **Gobolar (G$):** o dinheiro ganha nome e moedinha própria com um "G"; os NPCs chamam de "goblinhos". Nome, símbolo e apelido ficam em `economy.json`
- [x] **Preço por país:** um cálculo só de preço (`Service.Price`) com modificadores por país em `countries.json` (hoje todos neutros); o histórico guarda o país, o preço e o imposto, e cada país tem um cofre (zerado, sem tela). É a base para os governos de jogadores no futuro ([ADR 0041](docs/decisoes/0041-economia-por-pais.md))
- [x] **Tudo pode ser vendido:** a caixa de vendas aceita qualquer item, com quantidade e "tudo deste tipo"; ferramentas e itens raros pedem confirmação. A loja paga 25% a mais
- [x] **Praça central em cada país** ([ADR 0042](docs/decisoes/0042-loja-e-praca-central.md)): aeroporto novo (terminal de vidro, torre de controle, pista com faixas e luzes, biruta, portão de embarque, carros e um **avião pastel** feito em código, que também aparece no arco do voo), **loja** com estoque do dia igual para o país inteiro (ferramentas, câmera e sementes sempre; itens do dia e exclusivos regionais trocam às 5h do país), chafariz e bancos. Países pequenos usam o balcão compartilhado
- [x] **NPCs e diálogos** ([ADR 0043](docs/decisoes/0043-npcs-dialogos-e-apresentacao.md)): guia, lojista e atendente do aeroporto, com nome por país, chapeuzinho, acessório e balãozinho; caixa de diálogo com retrato, texto letra por letra e respostas. Os diálogos ficam em `dialogs.json`
- [x] **Apresentação do guia:** na primeira vez, o guia aparece no lote, conta como o mundo funciona e passa duas tarefas com seta e recompensa (sacudir uma árvore e fabricar um machado). Botão **Pular apresentação** sempre à vista; **F6 → Rever a apresentação**. O progresso fica no servidor; contas antigas não veem
- [x] **Troca entre jogadores** ([ADR 0044](docs/decisoes/0044-troca-entre-jogadores.md)): **E** perto de outro jogador ou **J → Propor troca**; os dois montam a oferta (itens e gobolares) vendo tudo na hora, marcam **Pronto** (qualquer mudança desfaz) e confirmam. O servidor executa de uma vez só, conferindo bolso, distância e bloqueio. F6 liga e desliga os pedidos
- [x] **Pronto para traduzir** ([ADR 0045](docs/decisoes/0045-textos-prontos-para-traducao.md)): os textos em português são as chaves; `client/tools/extrair_textos.py` gera `client/i18n/goblo.pot` com a interface e os dados do servidor

Encerrada do jeito que está; o que ficou de fora está em [`docs/BACKLOG.md`](docs/BACKLOG.md) ([progresso](docs/progresso-fase-3-5.md)).

**Fase 3.6: polimento** ✅

- [x] **Aeroporto na escala do personagem** ([ADR 0047](docs/decisoes/0047-aeroporto-na-escala-do-personagem.md)): avião ~4× maior (porta mais alta que o personagem, asa maior que a casa grande; 10× não caberia no hexágono), com porta, escadinha e trem de pouso; pista mais larga e comprida na diagonal do hexágono; carros na altura do personagem; terminal e torre de concreto, vidro azulado, branco e um toque de verde; pisos sem faces no mesmo plano (acabou o piscar da pista). A praça é juntada numa thread (~4 ms no quadro, antes ~30 ms)
- [x] **Sem frestas entre hexágonos** ([ADR 0046](docs/decisoes/0046-chao-fechado-e-resgate.md)): cantos iguais bit a bit nos vizinhos, colisão sobreposta e dos dois lados e, se mesmo assim o personagem for parar abaixo do chão, ele volta para cima do hexágono. Teste com 83 mil raios nas bordas, cantos, litoral, montanhas e pentágonos (inclui a célula 20575 do Chile)
- [x] **Bandeiras nas fronteiras** ([ADR 0048](docs/decisoes/0048-bandeiras-nos-marcos.md)): em cada marco, um mastro com uma bandeirinha tremulando; de cada lado, a bandeira do país vizinho, visível de longe, aberta ou fechada. Atlas com os 240 países (flag-icons, MIT), bandeira neutra para as áreas sem código ISO

| Aeroporto de longe | Ao lado do avião |
| --- | --- |
| ![Aeroporto de longe](docs/imagens/aeroporto-de-longe.jpg) | ![Personagem ao lado do avião](docs/imagens/aeroporto-aviao.jpg) |
| **Carros e pista** | **Bandeiras na fronteira (do Brasil, vendo o Paraguai e a Argentina)** |
| ![Carros e pista de perto](docs/imagens/aeroporto-carros-pista.jpg) | ![Bandeiras na fronteira](docs/imagens/fronteira-bandeiras.jpg) |

**Fase 4.0: clima, necessidades, roupas, personagem e flores** ✅

- [x] **Temperatura do mundo** ([ADR 0050](docs/decisoes/0050-corpo-clima-e-necessidades.md)): o servidor calcula pela latitude, estação, bioma, altura e hora local; fogueira aquece, sombra de árvore e beira do mar refrescam. Termômetro no HUD; o personagem treme no frio, sua e se abana no calor e solta vapor da respiração no gelado
- [x] **Necessidades gentis:** sede, conforto e fome só dão vantagem: tudo em dia = um pouco mais rápido; alguma no mínimo = um pouco mais devagar (com fome, a tela fica zonza). Nada de dano, morte ou itens perdidos, e nada cai com o jogo fechado. **Modo tranquilo** no F6
- [x] **Comida:** frutinhas, coco e cantil; fogueira (no lote ou acesa no chão) com 6 receitas que dão bônus por alguns minutos; ingredientes novos (cogumelo, ervas, grãos)
- [x] **Roupas** ([ADR 0051](docs/decisoes/0051-visual-roupas-e-editor.md)): 14 peças em cinco espaços, com proteção contra frio e calor; fabricar ou comprar (algumas típicas de cada região); **tinta de flores** muda a cor; guarda-roupa na tecla **C**; todo mundo vê. **Capa de bandeiras** com os países carimbados
- [x] **Editor de personagem:** as partes dos 12 personagens são separáveis (mesmo esqueleto): cabeça, tronco e pernas de quem quiser, tom de pele, cor do cabelo, penteados e óculos. No primeiro acesso, no **espelho** do lote e no F6. Uma malha só por personagem (mais leve que antes)
- [x] **Flores:** 15 espécies novas por bioma e estação (girassol, lavanda, ipê-amarelo, edelvais, lótus…), algumas raras; flores decorativas bem mais densas; seção **Flores** na Goblopédia

| Partes, pele, cabelo e roupas misturados | Capa de bandeiras e penteados |
| --- | --- |
| ![Personagens com partes misturadas](docs/imagens/personagens-misturados.jpg) | ![Personagens de costas, com a capa](docs/imagens/personagens-costas-capa.jpg) |
| **Editor de personagem** | **Fogueira, termômetro e necessidades** |
| ![Editor](docs/imagens/editor-de-personagem.jpg) | ![Fogueira e HUD do corpo](docs/imagens/fogueira-e-corpo.jpg) |

**Fase 4.1: desempenho e acabamento do personagem** ✅ ([ADR 0052](docs/decisoes/0052-roupas-por-regiao-cabelo-separado-e-desempenho.md))

- [x] **Desempenho:** luz das fogueiras sem sombra e só nas mais perto, fogo e partículas por qualidade, flores decorativas com distância própria (somem antes da grama), objetos pequenos sem sombra, tela zonza sem cópia da tela. Menos chamadas de desenho que na Fase 3 (tabela em [Medições](#medições))
- [x] **Roupa substitui a original:** cada espaço vestido troca a parte da roupa do personagem (regata deixa os braços com a pele, short deixa a canela); espaço vazio = roupa original. **Capa** não pinta mais o personagem inteiro. Teste automático das 14 peças (`tests/test_roupas.gd`)
- [x] **Editor:** obrigatório no primeiro acesso (a escolha de personagem pronto saiu); rosto, **cabelo** (separado da cabeça nas 12), penteado, tom de pele, cor do cabelo, tronco, pernas e acessório independentes; o quepe virou acessório
- [x] **Chapéus** encaixados no alto da cabeça (ajuste por cabeça em `client/data/cabecas.json`), com o cabelo achatado embaixo
- [x] **Guarda-roupa:** personagem parado de frente; gira com o mouse ou A/D, aproxima com a roda, botões de costas e de frente
- [x] **Ícones** de tintas, cantil (com os goles que restam) e bebidas mostrando o líquido

| 12 cabeças × chapéus | Roupas no lugar da original |
| --- | --- |
| ![Grade de cabeças e chapéus](docs/imagens/cabecas-e-chapeus.jpg) | ![Personagens com roupas](docs/imagens/roupas-por-regiao.jpg) |
| **Editor no primeiro acesso** | **Guarda-roupa** |
| ![Editor no primeiro acesso](docs/imagens/editor-primeiro-acesso.jpg) | ![Guarda-roupa](docs/imagens/guarda-roupa-4-1.jpg) |

![Ícones de tintas, cantil e bebidas](docs/imagens/icones-liquidos.png)

## Telas

**Antes e depois do visual da fase 2.1** (mesmo lugar, mesma hora, qualidade alta):

| | Antes | Depois |
| --- | --- | --- |
| Bairro, 11h | <img src="docs/imagens/antes-bairro.jpg" alt="Bairro antes: verde saturado e chapado, sem névoa" width="400" /> | <img src="docs/imagens/depois-bairro.jpg" alt="Bairro depois: cores pastel, névoa ao fundo e luz mais suave" width="400" /> |
| Floresta tropical | <img src="docs/imagens/antes-floresta.jpg" alt="Floresta antes" width="400" /> | <img src="docs/imagens/depois-floresta.jpg" alt="Floresta depois, com névoa e sombras mais macias" width="400" /> |
| Fim de tarde, 17h24 | <img src="docs/imagens/antes-tarde.jpg" alt="Fim de tarde antes" width="400" /> | <img src="docs/imagens/depois-tarde.jpg" alt="Fim de tarde depois, com luz quente nas copas" width="400" /> |
| Noite, 22h | <img src="docs/imagens/antes-noite.jpg" alt="Noite antes" width="400" /> | <img src="docs/imagens/depois-noite.jpg" alt="Noite depois" width="400" /> |

| Primeiro acesso | Bancada | Bolso (inventário) |
| --- | --- | --- |
| <img src="docs/imagens/primeiro-acesso.png" alt="Tela de boas-vindas com campo de apelido, sugestão de país pelo idioma do computador e lista pesquisável de países" width="300" /> | <img src="docs/imagens/bancada.png" alt="Menu da bancada com a lista de receitas e os ingredientes do machado, em verde porque o jogador tem tudo" width="300" /> | <img src="docs/imagens/bolso.png" alt="Inventário de 20 espaços com machado, picareta, madeira, pedras, galhos e flores, com ícones 3D" width="300" /> |

| Modo construção | Noite no bairro | Modo dev |
| --- | --- | --- |
| <img src="docs/imagens/construcao.png" alt="Prévia transparente de uma fonte em vermelho fora do lote, com a barra de objetos para colocar" width="300" /> | <img src="docs/imagens/noite.png" alt="O mesmo bairro à noite, céu azul-escuro e um lampião aceso no lote do jogador" width="300" /> | <img src="docs/imagens/modo-dev.png" alt="Painel do modo dev com a lista pesquisável de itens, quantidade e botões Dar e Kit inicial" width="300" /> |

| Amazônia | Andes | Saara |
| --- | --- | --- |
| <img src="docs/imagens/floresta.png" alt="Floresta tropical densa com árvores e palmeiras do Ultimate Nature Pack" width="300" /> | <img src="docs/imagens/montanha.png" alt="Montanhas em degraus no Peru com pinheiros e pedras grandes" width="300" /> | <img src="docs/imagens/deserto.png" alt="Deserto cor de areia na Líbia com cactos e pedras" width="300" /> |

## Como testar com o modo dev

1. **Servidor em modo dev** (terminal 1, deixe aberto):
   ```bash
   cd server
   GOBLO_DEV=1 go run ./cmd/server
   ```
   O log mostra `MODO DEV LIGADO`. Sem `GOBLO_DEV=1`, todas as rotas `/dev/…` respondem 403.
2. **Abra o jogo** no Godot (F5). Na primeira vez, escolha um apelido e confirme o país. Você nasce no seu lote, com uma bancada.
3. Aperte **F1** para abrir o **painel dev**. Na aba **Itens**, clique em **Kit inicial** (machado, picareta, madeira, pedras, galhos e flores) ou procure qualquer item, escolha a quantidade e clique em **Dar**.
4. **Coleta:** chegue perto de uma árvore e aperte **E** para sacudir. Aperte **1** para segurar o machado e **E** de novo para cortar (3 vezes). Com a picareta (**2**), quebre uma pedra grande. Colha flores e pegue pedrinhas.
5. **Limites:** tente sacudir a mesma árvore de novo ("Já sacudida hoje"). No painel, aba **Jogador**, clique em **Avançar para o dia seguinte**: os limites voltam.
6. **Fabricação:** aperte **H** para voltar para casa, chegue perto da bancada e aperte **E**. Fabrique um lampião e uma cerca.
7. **Decoração:** aperte **B**, escolha o objeto na barra, mire com o mouse dentro do lote (verde = pode), **R** para girar, clique para colocar. **X** com o mouse em cima guarda de volta.
8. **Casa:** na bancada, aba **Casa**, clique em **Escolher o lugar e construir** e clique no lote (o contorno mostra o tamanho da casa grande, para sobrar espaço). Aparece o andaime. No painel, **Concluir a obra agora** (ou **Avançar para o dia seguinte**). Depois melhore para casinha e casa grande.
9. **Vizinhos:** no painel, **Criar 20 vizinhos falsos aqui perto**. Passeie pelo bairro.
10. **Mundo:** aba **Mundo**: procure um país e clique em **Ir para o país**, ou digite lat/lon. Ligue **Voar (noclip)** (Espaço sobe, Ctrl desce, Shift acelera). **F3** acelera o tempo para ver os lampiões à noite.
11. **Resets:** aba **Jogador**: trocar de país (muda o lote), resetar lote, inventário, coletas de hoje ou apagar o jogador (volta à tela de primeiro acesso).

> [!TIP]
> O relógio adiantado pelo "dia seguinte" volta para a hora real no botão **Voltar o relógio do servidor para a hora real** (aba Jogador), sem reiniciar o servidor. O banco fica em `server/goblo.db`; apague o arquivo para começar do zero.

## Como testar a fase 2.5

Com o servidor em modo dev (`GOBLO_DEV=1`) e o jogo aberto, aperte **F1**:

1. **Gobolares e caixa de vendas:** aba **Itens**, dê **Kit inicial**. Volte para casa (**H**), chegue na **caixa de vendas** (ao lado da bancada) e aperte **E**: venda madeira e veja o saldo subir no HUD. Para dar gobolares direto, use **Dar gobolares** na aba Itens.
2. **Fronteiras:** aba **Mundo**, digite lat **-25,5** e lon **-54,35** (Foz do Iguaçu) e clique **Ir**. Ande para o oeste: a linha tracejada com marquinhos aparece no chão e, sem passaporte, você desliza ao longo dela com o aviso. Na aba **Viagem**, selecione o Paraguai (aba Mundo) e clique **Dar passaporte**: agora dá para entrar, aparece a plaquinha "Bem-vindo!" e o carimbo novo. **P** abre o livro do passaporte. Para ver a costa e os polígonos, ligue **Polígonos de debug**; para andar livre, desligue a **Barreira**.
3. **Animais:** vá para um campo (lat **-34,6**, lon **-60,5**, pampa argentino) ou uma floresta (**48,5**, **2,0**, França). Ande devagar até um animal e aperte **E** (carinho). Dê **Frutinhas** (aba Itens) e aperte **E** de novo: ele come e segue você. Corra (Shift) na direção de um cervo ou raposa: ele foge. Aba **Natureza**: **Criar perto de mim** e **Listar carregados**.
4. **Câmera e Goblopédia:** aba Itens, dê **Câmera fotográfica** (ou fabrique na bancada). Aperte o número dela (1–5) para segurar, **botão direito** para mirar, **roda** para zoom e **clique** para fotografar um animal. Aperte **G**: a página dele está lá, com país, bioma e a foto. **Completar** e **Zerar a Goblopédia** ficam na aba Natureza.
5. **Estações:** aba **Natureza**, clique **Inverno**, **Outono**, **Primavera** e **Verão** (vale para o hemisfério norte; o sul fica com a oposta) e afaste a câmera (roda) para ver os dois hemisférios. **Data real** volta ao normal. Fotografe uma árvore de outono para a Goblopédia.
6. **Aeroporto e viagem:** aba **Viagem**: selecione um país na aba Mundo e clique **Voar de graça para lá** para conhecer um aeroporto. No balcão (**E**), escolha um destino (dê gobolares antes) e clique **Comprar passaporte e viajar**: a tela escurece, a câmera vai até o globo, o arco liga os aeroportos e você chega no destino com carimbo novo. **H** sempre volta para casa.

## Como testar a fase 2.6

1. **Modo foto:** F1 → aba Itens → dê a **Câmera fotográfica** e segure (1–5). **Botão direito**: a visão vai para os olhos do personagem (o corpo some). Mexa o mouse e a roda. Aperte **F**: selfie, com o personagem fazendo pose e o cenário atrás; o mouse gira a câmera em volta dele. **F** de novo volta. Fotografe um animal nos dois modos (pampa: aba Mundo, **-34,6** e **-60,5**) e confira na Goblopédia (**G**).
2. **Cursor depois do voo:** num aeroporto (aba Viagem → **Voar de graça para lá**), use o balcão (**E**), escolha um destino com clique duplo e viaje. Quando a tela clarear, mexa o mouse **sem clicar**: a câmera tem que girar. Repita com **H**, com o teleporte da aba Mundo, depois de fechar o bolso (Tab) e ao cruzar uma fronteira.
3. **Travadas:** jogue normalmente por 10 minutos (ande, corra, voe, afaste a câmera, entre em florestas e bairros). **F2** mostra as últimas travadas na tela. No fim, mande o arquivo `~/Library/Application Support/Godot/app_userdata/Goblo/travadas.log`. Cada linha é uma travada: hora, duração, onde você estava e, depois do `|`, o que aconteceu naquele quadro (por exemplo "shaders compilados: 3 na hora de desenhar", "pedaço 468 carregado", "animal criado: fox", "janela sem foco"). Cada sessão começa com uma linha `== sessão` com a qualidade, a janela, o limite de fps e o V-Sync.
4. **Limite de fps:** **F6** → Limite de fps: 30, 60 (padrão) ou sem limite. O V-Sync fica sempre ligado. Com 30, a placa esquenta menos.
5. **Oceano:** `godot --headless --path . -- --smoke-test --spawn=48.5,2.0` termina em terra (antes terminava no mar da Normandia).

## Como testar a fase 3

Servidor em modo dev (`GOBLO_DEV=1`), jogo aberto:

1. **Fronteira viva:** F1 → Mundo → vá para **-25,5** e **-54,35** (Foz do Iguaçu) e ande para o oeste. A cortina rosa e lilás, as bandeirolas e o cadeado aparecem, e ao encostar a cortina faz uma onda. F1 → Viagem → dê o passaporte do Paraguai: a fronteira abre animando. Atravesse e veja o confete. Em **Visão da fronteira** dá para ver todas abertas ou todas fechadas.
2. **Outros jogadores sem abrir outro jogo:** F1 → **Rede** → **Criar 5 bots perto**. Eles andam, acenam, sentam e falam. Teste o chat (**Enter**, escreva, Enter de novo), os emotes (**T** e depois 1 a 5) e a lista (**J**, com Silenciar e Bloquear). Na mesma aba, simule rede ruim (atraso e perda) e veja os bots continuarem lisos. **F2** mostra o ping, os pacotes por segundo e quantos jogadores estão visíveis.
3. **Dois jogos no mesmo Mac:** abra dois terminais em `client/` e rode `godot --path . -- --profile=jogador1` em um e `godot --path . -- --profile=jogador2` no outro (cada perfil é um jogador). Leve os dois para o mesmo lugar (F1 → Mundo) e converse. Sem janela, `tools/dois_clientes.sh` faz isso sozinho e confere.
4. **Personagem:** **F6** → Personagem. Quem está perto vê a troca na hora.
5. **Validações do servidor:** tente coletar uma árvore pelo F1 → Mundo teleportando para longe e voltando: o servidor só aceita de perto. Sem passaporte, mesmo com a barreira do cliente desligada (F1 → Viagem), o servidor segura você na fronteira.
6. **Teste de carga:** `cd server && scripts/teste-de-carga.sh 100 60` (servidor de teste na porta 8090, banco temporário).

## Como testar a fase 3.5

Servidor em modo dev (`GOBLO_DEV=1`), jogo aberto. No modo dev a apresentação é pulada sozinha; o resto é igual ao jogo normal.

1. **Apresentação do guia:** F1 → **Loja e NPCs** → **Mostrar a apresentação agora**. O guia aparece do seu lado; clique ou **E** completa a fala e passa para a próxima. Responda "Bora!", sacuda a árvore com a seta amarela em cima (+15 gobolares) e o guia volta a falar; depois fabrique o machado na bancada (mais 15). Teste também o **Pular apresentação** (na caixa ou em cima da tela, com Alt + clique) e o **F6 → Rever a apresentação**. Para ver como uma conta nova: **Marcar como não vista** e abra o jogo de novo (nesse login o modo dev não pula).
2. **Gobolares e venda:** **E** na caixa de vendas do lote: cada item tem preço, dá para escolher a quantidade ou vender tudo de um tipo; o machado e a flor azul pedem confirmação. F1 → Itens → **Dar gobolares** se precisar.
3. **Praça e loja:** F1 → Mundo → teleporte para a capital (ou **H**, F1 → Viagem → voar de graça). Converse com o **lojista** (**E**): ele comenta o item do dia; "Quero comprar" abre a loja e "Quero vender" vende por um pouco mais. F1 → Loja e NPCs → **Repor o estoque agora** troca os itens do dia. Compare dois países: os exclusivos mudam (moinho na Holanda, fardo de feno no Brasil, lanterna no Japão…).
4. **Aeroporto:** **E** no balcão ou na **atendente**: ela pergunta o destino, oferece o passaporte e explica como funciona. Viaje e veja o avião no arco do voo.
5. **Troca com bot:** F1 → Loja e NPCs → **Abrir uma troca com um bot**. Ele oferece 3 madeiras; ponha algo do seu lado, marque **Pronto** (ele fica pronto junto) e **Confirmar troca**. Mude a oferta depois de pronto e veja os dois "Pronto" caírem. Os bots da aba Rede também servem: **J → Propor troca** (os de número par aceitam, os ímpares recusam).
6. **Troca entre dois jogos:** `godot --path . -- --profile=jogador1` e `--profile=jogador2`, os dois no mesmo lugar, **E** um no outro.
7. **Diálogos soltos:** F1 → Loja e NPCs → escolha um diálogo e **Abrir diálogo**.

Automações sem janela: `godot --headless --path . -- --npc-test --profile=t14` (apresentação, loja, atendente e troca com bot).

## Como testar a fase 3.6

Servidor em modo dev (`GOBLO_DEV=1`), jogo aberto.

1. **Aeroporto:** F1 → Mundo → teleporte para o país (ou F1 → Viagem → voar de graça). O avião fica na pista, com a escadinha na porta; os carros estão no pátio. Ande em volta, passe embaixo da asa e veja a pista de perto (não pisca mais). Viaje para ver o avião no arco do voo. Captura: `tools/sem_foco.sh -- --ui=airport --country=BRA --plaza=2.6,-0.6 --look=150 --zoom=0.12 --screenshot=/tmp/a.png`.
2. **Fresta do Chile:** F1 → Mundo → lat **-52.19**, lon **-72.99** → Teleportar (célula 20575, montanha ao lado do mar e de hexágonos mais baixos). Ande e pule pelas beiradas e desça os degraus: nada de cair por dentro. Sem servidor: `godot --headless --path . -s tests/test_frestas.gd`.
3. **Bandeiras:** F1 → Mundo → lat **-25.5**, lon **-54.47** (Brasil, perto do Paraguai e da Argentina). De longe dá para ver as bandeiras do outro lado; atravesse (F1 → Viagem → passaporte) e olhe para trás: agora aparece a do Brasil. `--border-test` confere os lados.

## Como testar a fase 4.0

Servidor em modo dev (`GOBLO_DEV=1`), jogo aberto. O painel F1 ganhou as abas **Corpo** e **Visual**.

1. **Temperatura e necessidades:** veja o termômetro e as barras no canto de cima. F1 → Corpo → força −15 °C (treme, vapor, conforto caindo) ou 45 °C (suor, sede caindo mais rápido). **Encher** todas: "Tudo em dia" e um pouco mais rápido; **Zerar** a fome: mais devagar e a tela zonza. **Congelar** para testar sem pressa. Viaje para lugares diferentes (Saara ao meio-dia e de madrugada, Patagônia, Antártida) e compare.
2. **Comida:** F1 → Corpo → **Dar ingredientes, fogueira e cantil**. Fora do lote, clique na fogueira no bolso (acende no chão); **E** nela abre a fogueira para cozinhar. Clique numa comida no bolso para comer: o bônus aparece no HUD com o tempo. Encha o cantil no chafariz da praça ou num poço (fabrique na bancada) com **E**.
3. **Roupas:** F1 → Visual → **Dar todas as roupas e tintas**; **C** abre o guarda-roupa (passe o mouse numa peça para ver antes de vestir), clique para vestir; pinte com as tintas. Vestido de casaco, F1 → Corpo → −15 °C: o conforto não cai.
4. **Capa de bandeiras:** compre na loja da praça (ou F1 → Visual), vista e viaje: os retalhos aumentam a cada carimbo.
5. **Editor:** F6 → **Editar personagem** (ou o espelho do lote, ou F1 → Visual). Uma conta nova vê o editor antes da apresentação do guia.
6. **Flores:** F1 → Visual → **Mostrar todas as flores do bioma aqui**; fotografe para a Goblopédia (G → Flores). Mude a estação (F1 → Natureza) para ver as flores de cada época.

Automações sem janela: `--body-test` (corpo, comida, fogueira, roupas, editor, modo tranquilo).

## Como testar a fase 4.1

Servidor em modo dev (`GOBLO_DEV=1`).

1. **Editor no primeiro acesso:** abra com um perfil novo (`godot --path client -- --profile=novo`): depois do apelido e do país, o editor aparece antes do mundo e só sai com **Começar a jogar** (Esc não fecha). Troque o **rosto** e veja o cabelo ficar; troque o **cabelo** (12 cabeças, "Sem cabelo"), o **tom de pele** e a **cor do cabelo**: cada um muda só a sua parte. Acessório **Quepe azul**.
2. **Roupas no lugar da original:** F1 → Visual → **Dar todas as roupas e tintas**; **C**. Vista a regata (braços com a pele, sem a camiseta por baixo), o short (canela com a pele), a sandália (pé com a pele), o casaco, a calça e a bota. Tire cada uma: volta a roupa original. Vista a **capa**: o personagem continua com as cores dele.
3. **Chapéus:** vista cada chapéu com cabeças e cabelos diferentes: o chapéu fica no alto da cabeça, sem flutuar, e o cabelo não atravessa.
4. **Guarda-roupa:** o personagem fica parado de frente. Arraste com o mouse ou use A/D para girar, a roda aproxima até o rosto, **Ver de costas** e **De frente**.
5. **Ícones:** no bolso, tintas (cada uma com a cor), cantil (cheio: dois riscos azuis; pela metade: um; vazio: nenhum), suco e chá.
6. **Desempenho:** `client/tools/medir_fps.sh` (janela na frente, ~4 min). À noite, perto de várias fogueiras (F1 → Corpo), só as mais perto iluminam.

Sem janela: `godot --headless --path client -s tests/test_roupas.gd` (as 14 peças só mudam o próprio espaço). Capturas sem foco: `tools/foto_cabecas.gd` (12 cabeças × chapéus), `tools/foto_personagens.gd`, `tools/foto_icones.gd`.

## Medições

Medido neste Mac (MacBook Pro 2019, Intel Core i7-9750H, AMD Radeon Pro 5300M, tela Retina), Godot 4.7.2 com o renderizador Mobile.

**Fase 2.1: o que pesa na GPU** (`--profile-scene`, parado, janela maximizada de 3136 × 1930 pixels, bairro com 20 vizinhos; medições feitas em sequência, nas mesmas condições). Detalhes e decisões no [ADR 0028](docs/decisoes/0028-desempenho-da-fase-2-1.md).

| Cena | Qualidade | Antes: GPU / draw calls | Depois da otimização: GPU / draw calls |
| --- | --- | ---: | ---: |
| Bairro, 20 vizinhos | Alta | 17,1 ms / 1.151 | 12,2 ms / 641 |
| Bairro, 20 vizinhos | Média | 11,2 ms / 764 | 10,4 ms / 375 |
| Floresta tropical | Alta | — | 12,2 ms / 501 |
| Floresta tropical | Média | — | 8,7 ms / 293 |
| Globo afastado | Média | 1.755 draw calls | 201 draw calls |

Números do autor antes da fase (janela grande): alta no bairro 28 fps (872 draw calls), média perto das casas 47 fps.

> [!WARNING]
> **Fps com a janela na frente: medição inconclusiva.** A rodada de `--perf-test` (antes e depois, na mesma sessão) deu valores que pioraram ao longo do tempo independentemente do código (o tempo de GPU da mesma cena subiu de 27 para 45 ms), sinal de aquecimento ou de outro programa usando a placa. O visual novo (névoa, glow, vento) também custa GPU na alta: nas medições em segundo plano, o glow sozinho ficou em ~1,7 ms. Para medir de verdade: feche vídeos e outros apps, deixe o Mac esfriar e rode `client/tools/medir_fps.sh` (~4 min).

**Carga** (com o mundo em cache):

| O quê | Tempo |
| --- | --- |
| Ler o mundo binário | 0,2–0,4 s |
| Montar as malhas do globo | 0,6–0,9 s |
| Pré-carregar ~130 modelos (em paralelo) | 1,8 s |
| Buscar objetos e lotes em volta e montar a vegetação | 0,5–0,7 s |
| Servidor: gerar o mundo e abrir o banco | ~3,7 s, uma vez |
| `GET /objects` de um pedaço (16 células, ~500 objetos) | 3 ms, 47 KB |

**Decisões de otimização:**

- **Modelos juntados numa malha só:** as árvores do Ultimate Nature Pack têm 2 a 4 materiais de cor sólida; as cores viram cor por vértice e cada modelo vira **1 draw call** por pedaço, com LOD gerado de novo. As casas também viram uma malha só ([ADR 0025](docs/decisoes/0025-malhas-juntadas-e-pre-carregamento.md)).
- **Pré-carregamento em paralelo:** antes, cada modelo novo era processado no thread principal na primeira vez que aparecia, e o pior quadro chegava a 133 ms. Agora todos são carregados no `WorkerThreadPool` durante a entrada: o pior quadro caiu para 17 ms.
- **MultiMesh por modelo e pedaço**, com o buffer montado de uma vez. Objetos colhidos ficam escondidos (escala zero) sem refazer o pedaço.
- **Só o que está perto:** objetos e lotes são pedidos por pedaço em volta do personagem e soltos quando ele se afasta; colisão das árvores só a até 40 unidades, direto no `PhysicsServer3D`; só os 6 lampiões mais próximos ganham luz de verdade.
- Da fase 1.5: renderizador Mobile, malha do globo em 96 grupos, grama sorteada em threads, HUD leve.

**Fase 3: teste de carga** (`scripts/teste-de-carga.sh`, 100 bots na mesma região por 60 s, servidor e bots no mesmo Mac):

| O quê | Resultado |
| --- | --- |
| CPU do servidor | ~75% de um núcleo (o perfil mostra que quase tudo é rede: acordar goroutines e escrever no socket; a lógica do jogo fica em ~10%) |
| Memória do servidor | ~135 MB (quase toda do mundo e das fronteiras; parado já usa isso) |
| Banda por jogador | ~12–13 KB/s recebidos (vendo os 40 mais perto, 15 fotos por segundo) e ~0,3 KB/s mandados |
| Correções indevidas | 0 |

**Fase 3: travadas.log do autor** (2 min, alta, janela 3584 × 2240, floresta tropical): não eram picos, e sim o jogo inteiro em 23 a 39 fps, caindo conforme os bots chegavam. A CPU dos outros jogadores é quase zero (`--crowd-test`: 40 jogadores somam menos de 0,1 ms por quadro); o peso estava na placa de vídeo. Correções: o 3D tem no máximo 1000, 1300 e 1450 linhas (baixa, média e alta), igual à tela de referência, então numa tela maior a placa trabalha o mesmo tanto; os outros jogadores só fazem sombra nos 6 mais perto, com nome até 30 unidades e personagem até 70. Falta medir de novo com a janela.

**Fase 2.6: travadas** (`--hitch-test`, sem janela, só CPU, qualidade alta): de 28 para 11 quadros acima de 25 ms no mesmo passeio. Pior caso antes: 320 ms (linhas de fronteira de um pedaço), 200 ms (uma dúzia de aeroportos no mesmo quadro), 46 ms (JSON de um pedaço). Os que sobram são de teleporte e da estação forçada pelo modo dev. Com janela (em segundo plano, então só vale o custo de cada parte), a montagem de um lote de vizinho caiu de 3–23 ms para ~1 ms e a de árvores e grama de um pedaço de ~16 ms para até 3 ms por quadro. A compilação de shaders na hora de desenhar ainda aparece algumas vezes: o registro de uma partida de verdade (`travadas.log`) vai dizer quais.

**Fase 4.1: Fase 3 × antes da 4.1 × depois da 4.1** (`--perf-test=15`, janela na frente, 3136 × 2116, Mac Intel com Radeon Pro 5300M; as três versões rodando no mesmo momento, cada uma com o próprio servidor, o mesmo lote com 20 vizinhos, alternando a versão em cada cena para o aquecimento da placa pesar igual; uma rodada por cena). Média de fps, 1% piores quadros, GPU por quadro e draw calls ([ADR 0052](docs/decisoes/0052-roupas-por-regiao-cabelo-separado-e-desempenho.md)):

| Cena | Qualidade | Fase 3 | Antes da 4.1 | Depois da 4.1 |
| --- | --- | ---: | ---: | ---: |
| Bairro (20 vizinhos) | Alta | 50,4 · 17,7 · 15,4 ms · 787 | 47,2 · 14,9 · 14,9 ms · 848 | **48,9** · 16,6 · 14,3 ms · 687 |
| Bairro (20 vizinhos) | Média | 58,4 · 20,8 · 11,0 ms · 511 | 57,5 · 20,3 · 11,1 ms · 548 | **58,7** · 29,0 · 10,6 ms · 474 |
| Bairro + 20 bots | Alta | (falhou) | 42,2 · 12,9 · 15,4 ms · 881 | **46,2** · 16,1 · 14,5 ms · 724 |
| Bairro + 20 bots | Média | 58,7 · 25,6 · 10,9 ms · 573 | 55,0 · 16,9 · 11,0 ms · 632 | **56,6** · 19,3 · 10,8 ms · 524 |
| Floresta tropical | Alta | 54,7 · 18,3 · 15,5 ms · 717 | 49,4 · 16,2 · 15,0 ms · 783 | **50,0** · 15,9 · 14,7 ms · 644 |
| Floresta tropical | Média | 57,8 · 23,4 · 11,4 ms · 539 | 55,1 · 18,2 · 11,3 ms · 587 | **54,2** · 16,0 · 11,3 ms · 523 |
| Pampa florido | Alta | 59,6 · 40,2 · 10,7 ms · 619 | 59,3 · 28,8 · 11,0 ms · 726 | **59,7** · 40,3 · 10,2 ms · 545 |
| Pampa florido | Média | 59,9 · 48,0 · 9,8 ms · 429 | 59,9 · 45,6 · 9,7 ms · 499 | **59,9** · 51,6 · 9,7 ms · 405 |

O que isso mostra:

- **A 4.0 custou pouco na placa** (GPU por quadro quase igual à Fase 3) **e mais em chamadas de desenho** (+60 a +110 por cena, dos modelos pequenos novos: flores para colher e ingredientes) **e em picos**: o pior quadro chegava a 125–134 ms no bairro. Na 4.1 as chamadas de desenho ficaram **abaixo da Fase 3** em todas as cenas, a GPU caiu um pouco e o pior quadro no bairro voltou para 39–77 ms. Com 20 bots vestidos na alta: 42,2 → 46,2 fps.
- **Meta da alta (mínimo 45 fps): atingida** em todas as cenas (46,2 a 59,7).
- **Meta da média (60 estáveis): atingida no pampa florido, quase no bairro (58,7) e não na floresta tropical (54,2) nem no bairro com bots (56,6).** O que falta não é a placa: a GPU fica em 10–11 ms por quadro (cabe nos 16,7 ms dos 60 fps). A média cai pelos picos (1% piores em 16–29 fps) que o `--perf-test` pega andando sem parar e carregando pedaços novos do mundo, e eles **já existiam na Fase 3** (57,8 na floresta tropical). Próximo passo: o `--hitch-test` com janela para ver o que cada pico estava fazendo (pedaços de grama, colisão, shaders) e espalhar esse trabalho entre quadros.
- Uma rodada por cena: diferenças de 1 a 2 fps estão dentro da variação entre rodadas. A rodada da Fase 3 com bots na alta não imprimiu resultado (o jogo não fechou a tempo).
- Sem janela (`--profile-scene`, alta, bairro com 20 bots e 4 fogueiras), as partes da 4.0 somavam ~2 ms de GPU: outros personagens 0,7, fogueiras 0,5, flores 0,3; os scripts gastam menos de 0,15 ms de CPU cada (`--cpu-test`).

**Fase 2.5: custo do que entrou** (sem janela, só CPU; os fps com janela ficam para `client/tools/medir_fps.sh`): os animais custam ~0,9 ms por quadro com 12 animais carregados (o máximo; os mais longe são atualizados menos vezes por segundo). As partículas das estações são 160 (média) ou 320 (alta), nenhuma na baixa. O chão calcula a estação no próprio shader, sem malha nova; árvores de outono e com neve só trocam o modelo do MultiMesh.

## Arquitetura

O servidor define o mundo e aplica as regras; o cliente pede e desenha. Isso já prepara o terreno para o multiplayer: todo mundo recebe o mesmo planeta e as mesmas regras.

```mermaid
flowchart LR
    ne[("Natural Earth")]
    content[("data/game/*.json<br/>itens, receitas,<br/>casas, objetos")]
    subgraph server["server/ — Go"]
        world["world<br/>grade, países, biomas"]
        game["game<br/>jogador, lote, coleta,<br/>fabricação, casa"]
        db[("SQLite<br/>Go puro")]
        api["HTTP<br/>/world.bin · /me · /objects<br/>/interact · /craft · /lot/…"]
    end
    subgraph client["client/ — Godot 4"]
        globe["globo, céu,<br/>personagem"]
        chunks["ChunkData<br/>objetos e lotes por pedaço"]
        draw["Vegetation + Neighborhood"]
        play["Interaction (E)<br/>BuildMode (B)"]
        ui["bolso, bancada,<br/>modo dev"]
    end
    ne --> world
    content --> game
    world --> game
    game <--> db
    world --> api
    game --> api
    api -- "binário" --> globe
    api -- "JSON + token" --> chunks
    chunks --> draw
    play -- "pedidos" --> api
    ui --> play
```

Princípios que guiaram o código:

- **O servidor é a fonte da verdade.** Mundo, objetos que dão material, inventário, limites do dia, lotes e casas são decididos no servidor. O cliente pede ("sacudi a árvore X") e mostra a resposta.
- **Determinístico.** Os objetos de cada célula saem de uma semente no id da célula: todo mundo vê as mesmas árvores, e o servidor não precisa guardá-las, só as coletas ([ADR 0020](docs/decisoes/0020-objetos-interativos-no-servidor.md)).
- **Regras sem saber do banco.** `internal/game` só conhece a interface `game.Store`; hoje é SQLite, amanhã pode ser PostgreSQL ([ADR 0018](docs/decisoes/0018-sqlite-em-go-puro-atras-de-repositorios.md)). O relógio é injetável, então os testes viram o dia e concluem obras sem esperar.
- **Balancear sem programar.** Itens, receitas, casas e objetos de cada bioma ficam em JSON ([`docs/CONTEUDO.md`](docs/CONTEUDO.md)).
- **Só o que está perto.** Objetos, lotes, colisão e luzes existem só em volta do personagem, por pedaços.

Mais detalhes em [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md), todas as rotas em [`docs/API.md`](docs/API.md) e as decisões em [`docs/decisoes/`](docs/decisoes/).

## Tecnologias

| Camada | Ferramenta | Por quê |
| --- | --- | --- |
| Servidor | Go 1.27, biblioteca padrão | Binário único, rápido, testes embutidos |
| Banco | SQLite com [`modernc.org/sqlite`](https://pkg.go.dev/modernc.org/sqlite) | Go puro, sem cgo nem Xcode; migrações versionadas |
| Geometria | [`paulmach/orb`](https://github.com/paulmach/orb) | GeoJSON e point-in-polygon prontos |
| IP → país | [DB-IP IP to Country Lite](https://db-ip.com) | Gratuita (CC BY 4.0), carregada na memória |
| Cliente | Godot 4.7 + GDScript | Leve, código aberto, exporta para tudo; física com `up_direction` livre |
| Arte 3D | [Kenney](https://www.kenney.nl) e [Quaternius](https://quaternius.com) (CC0) | Personagens, casas modulares e natureza low-poly fofos |
| Dados | Natural Earth 1:110m e 1:50m | Domínio público, com nomes dos países em português |
| CI | GitHub Actions | `gofmt`, `go vet` e `go test -race` a cada push |

## Estrutura de pastas

```
.
├── client/                         # Godot 4
│   ├── assets/kenney/              # Mini Characters, Fantasy Town Kit, Car Kit, Watercraft… (CC0)
│   ├── assets/quaternius/          # Ultimate Nature Pack, Ultimate Animated Animals (CC0)
│   ├── data/decoracao.json         # grama e plantinhas de cada bioma
│   ├── scenes/                     # main, player e houses/house_level_1..3
│   ├── scripts/                    # world_data, terrain, vegetation, neighborhood, interaction, build_mode, UI…
│   ├── shaders/
│   └── tools/montar_casas.gd       # monta as casas com as peças do kit
├── server/                         # Go
│   ├── cmd/server/                 # main.go
│   ├── internal/world/             # grade, terreno, biomas, binário (+ testes)
│   ├── internal/game/              # regras: jogador, lote, objetos, coleta, fabricação, casa, dev (+ testes)
│   ├── internal/store/sqlitestore/ # SQLite e migrações (+ testes)
│   ├── internal/geoip/             # IP → país (+ testes)
│   ├── internal/httpapi/           # rotas HTTP (+ testes)
│   ├── data/naturalearth/          # GeoJSON embutido
│   ├── data/game/                  # itens, receitas, casas e objetos (JSON)
│   └── scripts/baixar-dados.sh
├── tools/gltf_para_glb.py
├── docs/                           # ARQUITETURA, API, CONTEUDO, BIOMAS, DADOS, briefings, decisoes/, imagens/
├── CLAUDE.md
└── README.md
```

## Como rodar

Pré-requisitos: [Go 1.27+](https://go.dev/dl/) e [Godot 4.7+](https://godotengine.org/download) (versão padrão, não a .NET).

> **No meu Mac** (Intel), Go e Godot foram instalados fora do Homebrew, em `~/sdk`. O Go fica em `~/sdk/go/bin`, que precisa estar no `PATH`. Para deixar isso permanente:
>
> ```bash
> echo 'export PATH="$HOME/sdk/go/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
> go version   # go1.27.3 darwin/amd64
> ```
>
> O Godot fica em `~/sdk/godot/Godot.app` (dá para arrastar para `/Applications`).

> [!IMPORTANT]
> **O servidor precisa estar rodando antes de dar Play no Godot.** O cliente não gera nada: o mundo, o jogador, os objetos e as casas vêm do servidor. Deixe o servidor aberto num **terminal separado** enquanto joga. Sem ele, o jogo mostra "Sem resposta do servidor" e fica tentando de novo a cada 3 segundos.

**1. Servidor (terminal 1, deixe aberto)**

```bash
cd server
./scripts/baixar-dados.sh        # opcional: baixa a base IP → país da DB-IP (fora do Git)
GOBLO_DEV=1 go run ./cmd/server  # com o modo dev; sem GOBLO_DEV=1 é o modo normal
# mundo gerado versão=9ce1… células=25002 …
# banco aberto arquivo=goblo.db migração=1
# servidor no ar endereço=:8080
```

A inicialização leva uns 4 segundos. Opções (flag ou variável de ambiente):

| Flag | Variável | Padrão | O quê |
| --- | --- | --- | --- |
| `-addr` | `GOBLO_ADDR` | `:8080` | endereço HTTP |
| `-db` | `GOBLO_DB` | `goblo.db` | arquivo do banco SQLite (fora do Git) |
| `-geoip` | `GOBLO_GEOIP` | `data/raw/dbip-country-lite.csv.gz` | base IP → país (opcional) |
| `-frequency` | `GOBLO_FREQUENCY` | `50` | grade (células = 10·n²+2) |
| `-radius` | `GOBLO_RADIUS` | `1000` | raio do planeta |
| | `GOBLO_DEV=1` | desligado | modo desenvolvedor (rotas `/dev/…` e F1 no jogo) |

**2. Cliente (Godot)**

Com o servidor no ar, abra o Godot, clique em **Importar**, escolha `client/project.godot` e aperte **F5**. Ou, num segundo terminal:

```bash
cd client
~/sdk/godot/Godot.app/Contents/MacOS/Godot --path .
```

O cliente procura o servidor em `http://127.0.0.1:8080`. Para trocar: `godot --path . -- --server=http://outro:8080`, a variável `GOBLO_SERVER_URL` ou a opção `goblo/server_url` no `project.godot`.

No macOS, o token do jogador fica em `~/Library/Application Support/Godot/app_userdata/Goblo/player.cfg` e o mundo em cache na pasta `cache/` ao lado. Apague o `player.cfg` para criar outro jogador (ou use `-- --profile=outro`).

**Trocar o personagem:** selecione o nó `Player` em `scenes/main.tscn` e escolha outro na propriedade **Character** do Inspetor (12 opções).

## Controles

| Tecla | Ação |
| --- | --- |
| W A S D / setas | andar (relativo à câmera) |
| Shift | correr |
| Espaço | pular |
| **E** | interagir: sacudir, cortar, quebrar, colher, pegar, abrir a bancada, a caixa de vendas e o balcão do aeroporto, conversar com NPCs, propor troca a um jogador do lado, fazer carinho ou dar frutinha a um animal; no diálogo, completa a fala e passa para a próxima (1 a 4 escolhem a resposta) |
| **Tab** ou **I** | bolso (inventário): clique numa comida para comer, numa roupa para vestir, na fogueira para acender fora do lote |
| **C** | guarda-roupa (vestir, tirar, pintar) |
| **1** a **5** | segurar / guardar uma ferramenta |
| **B** | modo construção (no seu lote) |
| **R** / clique / **X** | no modo construção: girar, colocar, guardar |
| **H** | voltar para casa (de qualquer lugar) |
| **G** | Goblopédia (álbum de fotos) |
| **P** | livro de passaporte |
| **Enter** | chat: abre, Enter manda, Esc fecha |
| **T** | emotes: acenar, sim, não, sentar, comemorar (1 a 5) |
| **J** | jogadores por perto (propor troca, silenciar e bloquear) |
| Botão direito (câmera na mão) | modo foto em primeira pessoa; **F** alterna com o selfie; **roda** dá zoom, **clique** fotografa, botão direito ou Esc sai |
| Mover o mouse | girar a câmera (o cursor fica capturado e escondido durante o jogo) |
| **Alt** (Option) segurado | soltar o cursor enquanto segura |
| Esc ou o **X** no canto | fechar janelas, sair do modo construção; sem nada aberto, solta o cursor (clique na janela para voltar) |
| Botão direito + arrastar | girar a câmera com o cursor solto (modo construção, Alt, depois do Esc) |
| Roda do mouse / dois dedos no trackpad | zoom, do personagem até o planeta inteiro |
| **F1** | painel do modo dev (servidor com `GOBLO_DEV=1`) |
| F2 | painel de desempenho, com a rede (ping, pacotes, jogadores visíveis) e as últimas travadas |
| F3 / F4 | acelerar o tempo do céu / voltar ao horário real |
| F6 | configurações: personagem, qualidade (baixa, média, alta), limite de fps (30, 60, sem limite), tamanho da interface, sensibilidade do mouse, inverter eixo vertical, tela cheia, pedidos de troca, rever a apresentação |
| F11 | tela cheia |

## Testes

```bash
cd server
go test ./...
go vet ./...
```

Mais de 100 testes. Além dos do mundo (grade, biomas, escala, formato binário), os da fase 2 conferem:

- rotas `/dev/…` bloqueadas (403) sem `GOBLO_DEV=1`, e funcionando com ele;
- criação de jogador com lote no país certo, preferindo biomas agradáveis (China, Austrália, EUA, Rússia), e lote mesmo na Groenlândia (só gelo e tundra);
- dois jogadores nunca recebem o mesmo lote (criação em paralelo até esgotar os lotes de um país pequeno);
- limites diários: sacudir 1 vez, 3 golpes de machado, 3 de picareta, e reset às 5h locais com relógio falso (às 4h59 ainda não, às 5h sim);
- a coleta de um jogador não afeta outro; flor colhida some só para quem colheu;
- fabricação consome os materiais certos (inclusive "qualquer flor") e falha sem materiais, sem gastar nada;
- não dá para construir no lote dos outros, fora da grade ou sobrepondo; guardar devolve ao inventário; 20 espaços;
- a casa só fica pronta depois da virada do dia; a melhoria cresce a partir da casa atual (sozinha no lote funciona, perto da borda acha uma posição que caiba, com decoração no caminho falha listando os objetos);
- o relógio do modo dev volta para a hora real depois do "dia seguinte";
- objetos determinísticos, dentro da célula e sem encavalar; objetos somem dos lotes ocupados;
- 90% das células comportam 4 lotes;
- país: IP local cai no idioma do sistema; IPs conhecidos (linhas reais da DB-IP) dão o país certo, inclusive IPv6;
- apelidos: palavrões disfarçados são barrados ("P0RR4", "m.e.r.d.a"), nomes inocentes passam ("Curió", "computador");
- migrações rodam uma vez só; transação que falha não grava nada; apagar o jogador apaga o lote.

E os da fase 2.5:

- fronteiras: pontos 20 a 30 km para dentro de cada lado de Foz do Iguaçu × Ciudad del Este × Puerto Iguazú, Corumbá × Puerto Quijarro, Tabatinga × Letícia, Strasbourg × Kehl, e Luxemburgo, Andorra e Liechtenstein; a regra do cliente concorda com o ponto em polígono em 1.800 pontos sorteados;
- gobolares: não dá para gastar o que não tem (saldo nunca negativo, nada muda numa compra recusada), a venda credita o valor certo, as recompensas não se repetem;
- animais determinísticos (mesmo id e mesma posição no mesmo horário), dentro da célula, fora dos lotes, andando e parando sem saltos, e um arquivo de referência que o cliente confere;
- Goblopédia: recompensa só na primeira foto, frutinha marca amizade, flor rara não muda os outros objetos;
- estações por data e latitude (15 de janeiro: inverno em Berlim, verão em São Paulo, sem estação em Manaus; fim de outubro: outono no norte e primavera no sul);
- aeroportos perto das capitais, preço da viagem pela distância, passaporte obrigatório, carimbo único por país, nenhum lote novo no hexágono do aeroporto.

E os da fase 3:

- lote novo nunca cruza a fronteira; ponto de um lote antigo que cruza conta como país do dono só para ele; nenhum bolsão inacessível em quatro fronteiras (busca em largura numa grade de 0,5 unidade);
- tempo real com clientes WebSocket de verdade: andar normal não é corrigido, salto de velocidade, mar e fronteira sem passaporte são; com o passaporte entra e ganha o carimbo pelo servidor; área de interesse (entra e sai); chat com filtro de palavrões, tamanho e limite por segundo; bloqueio; conexão duplicada derruba a antiga; reconexão lembra a posição e recusa nascer longe sem o modo dev;
- distância conferida no servidor: coleta, bancada, caixa de vendas, frutinha, Goblopédia (com a direção da câmera) e balcão do aeroporto, que libera a chegada do voo uma vez só.

O cliente tem testes automáticos que rodam sem janela (com o servidor no ar; o `--play-test` precisa de `GOBLO_DEV=1`):

```bash
cd client
godot --headless --path . -- --smoke-test --jump --profile=teste          # nasce no lote, anda, pula
godot --headless --path . -- --play-test --profile=teste2                 # coleta, fabricação, decoração e casa
godot --headless --path . -- --camera-test --profile=teste3               # a câmera nunca entra em casas, árvores ou no chão
godot --headless --path . -- --border-test --profile=teste4               # país exato nas fronteiras e linha no chão
godot --headless --path . -- --animal-test --profile=teste5               # animais: trajeto comum, carinho, frutinha, fuga, custo
godot --headless --path . -- --photo-test --profile=teste6                # câmera fotográfica e Goblopédia
godot --headless --path . -- --season-test --profile=teste7               # estações nos dois hemisférios e nos trópicos
godot --headless --path . -- --travel-test --profile=teste8               # barreira, passaporte, carimbo, aeroporto e voo
godot --headless --path . -- --dev-test --profile=teste9                  # botões novos do painel dev
godot --headless --path . -- --npc-test --profile=teste14                 # apresentação, loja, atendente e troca com bot (fase 3.5)
godot --headless --path . -- --body-test --profile=teste15                # corpo, comida, fogueira, roupas, editor e modo tranquilo (fase 4.0)
godot --headless --path . -s tests/test_frestas.gd                        # sem frestas entre hexágonos e resgate de quem cai (fase 3.6; sem servidor, mundo em cache)
python3 tools/extrair_textos.py                                           # (da raiz: client/tools/…) gera client/i18n/goblo.pot
godot --headless --path . -- --cursor-test --profile=teste10              # cursor volta depois do voo, H, teleporte, menus
godot --headless --path . -- --hitch-test --profile=teste11               # passeio com o registro de travadas (travadas.log)
godot --headless --path . -- --crowd-test --profile=teste12               # custo de CPU de 0 a 40 jogadores por perto (bots do modo dev)
tools/dois_clientes.sh http://127.0.0.1:8080                              # dois jogos se vendo: área de interesse, interpolação e chat
godot --headless --path . -s tests/test_animais.gd                        # trajeto dos animais igual ao do servidor
godot --headless --path . -s tests/test_estacoes.gd                       # estações iguais às do servidor
godot --path . -- --perf-test=20 --spawn=-3,-60                           # fps na floresta tropical (janela na frente)
tools/sem_foco.sh -- --profile-scene --neighbors=20 --window-size=3136x1930   # o que pesa na GPU (sem roubar o foco)
```

## Privacidade

- **IP:** quando um jogador novo abre o jogo, o servidor usa o IP da conexão **só para sugerir o país**, consultando uma base local (DB-IP, sem enviar nada para fora). O IP é descartado na hora: **não é guardado no banco nem aparece no log**. Rodando na própria máquina (IP `127.0.0.1`), o país vem do idioma do sistema (`pt_BR` → Brasil). De qualquer jeito, o jogador confirma ou troca o país na tela.
- **Identidade:** não há e-mail nem senha. O jogo cria um token aleatório guardado só no seu computador; o servidor guarda apenas um hash dele.
- **O que o servidor guarda:** apelido, país, lote, inventário, o que você coletou em cada dia, o que colocou no lote, gobolares (com o histórico), passaportes, carimbos e o progresso da Goblopédia.
- **Fotos:** as fotos da câmera ficam só no seu computador (`user://fotos/`); o servidor guarda apenas o que foi registrado, onde e quando.

## Dados

- **Mapa:** [Natural Earth](https://www.naturalearthdata.com/), escalas 1:110m (terra, a forma do globo) e 1:50m (países, capitais e regiões para os biomas), domínio público. Embutido no binário do servidor.
- **Fronteiras disputadas:** usamos a versão padrão do Natural Earth (a visão *de facto* do projeto), sem tomar lado.
- **Bandeiras:** [flag-icons](https://github.com/lipis/flag-icons) 7.6.0, licença MIT, num atlas em `client/assets/lipis/flag-icons/` (montado por `client/tools/montar_bandeiras.gd`). Cobre todos os 240 países e territórios do jogo. Mesma regra neutra das fronteiras: cada área do Natural Earth usa a bandeira do seu código ISO 3166-1; as que não têm código (Chipre do Norte, Somalilândia e o Glaciar de Siachen) ganham uma bandeirinha neutra com o código do jogo. Taiwan, marcado como `CN-TW` no Natural Earth, usa o código ISO `TW`.
- **IP → país:** [IP to Country Lite](https://db-ip.com/db/download/ip-to-country-lite) da DB-IP, licença [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). **IP Geolocation by [DB-IP](https://db-ip.com).** Baixada por `server/scripts/baixar-dados.sh`, fora do Git.

Detalhes em [`docs/DADOS.md`](docs/DADOS.md); o método dos biomas em [`docs/BIOMAS.md`](docs/BIOMAS.md); o conteúdo do jogo em [`docs/CONTEUDO.md`](docs/CONTEUDO.md).

## Créditos

- **[Kenney](https://www.kenney.nl)** (CC0): Mini Characters (personagem), **Fantasy Town Kit** (casas e decoração), Car Kit e Watercraft Pack (guardados para o futuro), Mini Forest, Graveyard Kit e Monster Builder Pack.
- **[Quaternius](https://quaternius.com)** (CC0): **Ultimate Nature Pack** (toda a natureza dos biomas) e **Ultimate Animated Animals** (os animais da fase 2.5).
- **[Natural Earth](https://www.naturalearthdata.com/)**: mapa, domínio público.
- **[DB-IP](https://db-ip.com)**: IP Geolocation by DB-IP, CC BY 4.0.
- **[flag-icons](https://github.com/lipis/flag-icons)** (MIT, © Panayiotis Lipiridis): as bandeiras dos marcos da fronteira.

Detalhes, versões e o que foi copiado de cada pacote em [`client/assets/CREDITOS.md`](client/assets/CREDITOS.md).

## Roadmap

1. **Fase 1: o globo.** Globo, personagem andando e servidor do mundo. ✅
2. **Fase 1.5: um mundo de verdade.** Escala, pulo, biomas, vegetação, dia e noite, oceano, nuvens e navegação. ✅
3. **Fase 2: coletar e construir.** Jogador e país, lotes, coleta, inventário, bancada, decoração, casa em níveis, bairro, banco de dados e modo dev. ✅
4. **Fase 2.5: explorar e colecionar.** Fronteiras pela posição exata, gobolares e caixa de vendas, animais andando pelos biomas, câmera fotográfica e Goblopédia, estações do ano reais por hemisfério, aeroportos com viagem pelo globo, passaportes e carimbos. ✅ Ajustes da 2.6: modo foto em primeira pessoa e selfie, cursor depois do voo, registro de travadas e limite de fps. ✅
5. **Fase 3: fronteiras vivas e multiplayer.** Lotes longe das fronteiras, fronteira que abre com o passaporte, outros jogadores em tempo real no nosso servidor (sem Nakama, [ADR 0039](docs/decisoes/0039-tempo-real-no-servidor-proprio.md)), chat, emotes, validações no servidor e preparo para jogar com amigos. ✅
6. **Fase 3.5: economia viva e os primeiros personagens.** Gobolar, preço por país, vender tudo, praça central com loja e aeroporto novo, NPCs com diálogo, apresentação do guia e troca entre jogadores. ✅ **Fase 3.6: polimento.** Aeroporto na escala do personagem, chão sem frestas e bandeiras nas fronteiras. ✅
7. **Fase 4.0: clima, necessidades, roupas, personagem e flores.** ✅ Ajustes da 4.1: desempenho, roupas no lugar da original, cabelo separado, editor no primeiro acesso, guarda-roupa e ícones. ✅ **Fase 4.5:** cavernas e folclore. **Fase 5.0:** redesenho da interface, música e sons.

## Sobre mim

Sou **Lucas Barreto**, desenvolvedor. Criei o Goblo para juntar duas coisas de que gosto, jogos e geografia, e praticar arquitetura de jogo online desde o primeiro dia: servidor como fonte da verdade, geometria esférica, testes automatizados e um cliente 3D com identidade própria.

- LinkedIn: [linkedin.com/in/lucas-barreto-santana-67aa932b6](https://www.linkedin.com/in/lucas-barreto-santana-67aa932b6/)
- E-mail: [lucasbrsantana@gmail.com](mailto:lucasbrsantana@gmail.com)

Gostou do projeto, achou um bug ou tem uma ideia? Abra uma issue ou me chame no LinkedIn.

## Licença

[MIT](LICENSE) © 2026 Lucas Barreto. Dados do Natural Earth em domínio público, assets da Kenney e do Quaternius em CC0, bandeiras do flag-icons em MIT, base IP → país da DB-IP em CC BY 4.0.
