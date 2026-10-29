# CLAUDE.md

Guia para o Claude Code trabalhar no Goblo. Leia também `docs/ARQUITETURA.md`, `docs/API.md`, `docs/CONTEUDO.md`, `docs/BIOMAS.md` e `docs/decisoes/`.

## O projeto

MMO cozy no planeta Terra de verdade, visto como um globo de sala de aula, com um ciclo aconchegante: coletar → fabricar → construir e decorar o lote → voltar amanhã. Monorepo:

- `server/` — Go. **Fonte da verdade**: gera o mundo (grade, terra, país, bioma, altura) e aplica as regras do jogo (jogador, lote, objetos interativos, coleta e limites diários, inventário, fabricação, decoração, casa, moedas, animais, Goblopédia, aeroportos, passaportes e carimbos), com SQLite. Rotas em `docs/API.md`.
- `client/` — Godot 4 (renderizador Mobile) + GDScript. Baixa o mundo (com cache), pede as ações ao servidor e desenha. Só a grama decorativa é sorteada no cliente (determinística).
- `docs/` — arquitetura, API, conteúdo, dados, biomas, briefings das fases e ADRs em `docs/decisoes/`.

## Antes de tudo

- **PATH do Go:** neste Mac o Go fica em `~/sdk/go/bin` (instalado fora do Homebrew, que não suporta mais Mac Intel). Garanta que está no `PATH` (`export PATH="$HOME/sdk/go/bin:$PATH"`) ou chame `~/sdk/go/bin/go` direto. O Godot fica em `~/sdk/godot/Godot.app/Contents/MacOS/Godot`.
- **O servidor precisa estar rodando** (`cd server && GOBLO_DEV=1 go run ./cmd/server`, num terminal separado ou em segundo plano; leva ~4 s) antes de abrir o jogo ou rodar qualquer automação do cliente. O cliente não joga sem servidor.
- **Porta ocupada?** O autor costuma deixar um servidor rodando em `:8080`. Não mate o processo dele: suba o seu com `-addr :8081 -db /caminho/temporario.db` e passe `-- --server=http://127.0.0.1:8081` ao cliente.
- **Classe nova em GDScript** (`class_name`) só é reconhecida depois de `godot --headless --path client --import`.
- Envolva comandos do Godot em `perl -e 'alarm 200; exec @ARGV' …` para não travar a sessão se o jogo não fechar.
- Automações do cliente criam jogadores no banco. Use `--profile=NOME` (token em `user://NOME.cfg`) para não mexer no jogador do autor (`user://player.cfg`).

## Testes sem atrapalhar o Lucas

Regra permanente: o autor usa o Mac enquanto você trabalha (vídeo, outras janelas). Abrir o jogo não pode roubar o foco.

- **Prefira sempre `--headless`**: testes automáticos, import, validação de cenas, smoke/play-test e tudo que não precise de imagem.
- **Precisa de imagem (captura)?** Use `client/tools/sem_foco.sh -- <argumentos>`: abre com `open -g` (sem ativar o app), em janela comum 1600 × 900 com `--no-focus` (flag de janela sem foco do Godot), espera fechar e imprime a saída. Só nos testes; a configuração normal do jogo não muda.
- **Medição de fps** precisa da janela na frente (o macOS desacelera janelas em segundo plano): junte todas as medições num momento só, no fim do trabalho, e avise antes no terminal ("vou abrir o jogo na frente por uns 2 minutos para medir o desempenho").
- Feche o jogo assim que o teste terminar (as automações já fecham sozinhas; o script mata o processo se estourar o tempo).
- **Não controle o Mac do autor (regra permanente):** nada de `osascript`, AppleScript, "System Events", `screencapture` ou qualquer coisa que peça permissão de Acessibilidade, Automação ou Gravação de Tela, para nada. Capturas vêm do próprio jogo (`--screenshot`). Se precisar conferir algo que dependa disso, diga ao autor o que conferir e ele confere.

## Comandos

```bash
# Servidor (de dentro de server/)
GOBLO_DEV=1 go run ./cmd/server          # sobe em :8080 com o modo dev (rotas /dev/…)
go run ./cmd/server -addr :8081 -db /tmp/x.db   # outra porta e outro banco
go test ./...                            # testes (obrigatório antes de commitar)
go vet ./...
gofmt -l .                               # precisa sair vazio (o CI confere)
./scripts/baixar-dados.sh                # Natural Earth (terra, países e capitais 1:50m, regiões) + base IP → país da DB-IP
GOBLO_GOLDEN=1 go test ./internal/game -run AnimalGolden   # regera as poses de referência dos animais (servidor e cliente)

# Cliente (de dentro de client/, com o servidor rodando)
godot --path .                                                        # abre o jogo
godot --headless --path . --import                                    # importa (primeira vez / classes novas)
godot --headless --path . -- --smoke-test --jump --profile=t1          # nasce no lote, anda, pula
godot --headless --path . -- --play-test --profile=t2                  # ciclo inteiro (servidor com GOBLO_DEV=1)
godot --headless --fixed-fps 60 --path . -- --route=4.5,-61.1 --spawn=-23.55,-46.63
godot --path . -- --perf-test=20 --spawn=-3,-60 --quality=medium      # fps e GPU (janela NA FRENTE, avise antes)
tools/sem_foco.sh -- --profile-scene --neighbors=20 --window-size=3136x1930 --profile=perf   # o que pesa na GPU
godot --headless --path . -- --camera-test --profile=t3                # distância não muda sozinha, nada na frente sem transparência (servidor dev)
godot --headless --path . -s tests/test_minimapa.gd                    # seta do mini mapa (N, S, L, O); sem servidor
godot --headless --path . -s tests/test_animais.gd                     # trajeto dos animais igual ao do servidor; sem servidor
godot --headless --path . -s tests/test_estacoes.gd                    # estações iguais às do servidor; sem servidor
godot --headless --path . -- --border-test --profile=t4                # país exato nas fronteiras, linha no chão, travessia
godot --headless --path . -- --animal-test --profile=t5                # animais: trajeto comum, carinho, frutinha, fuga, custo (servidor dev)
godot --headless --path . -- --photo-test --profile=t6                 # câmera fotográfica e Goblopédia (servidor dev)
godot --headless --path . -- --season-test --profile=t7                # estações nos dois hemisférios e nos trópicos (servidor dev)
godot --headless --path . -- --travel-test --profile=t8                # barreira, passaporte, carimbo, aeroporto e voo (servidor dev)
godot --headless --path . -- --dev-test --profile=t9                   # botões novos do painel dev (servidor dev)
godot --headless --path . -- --cursor-test --profile=t10               # cursor capturado de novo depois de voo, H, teleporte, menus (servidor dev)
godot --headless --path . -- --hitch-test --profile=t11                # passeio com o registro de travadas; imprime as travadas por etapa (servidor dev)
tools/sem_foco.sh -- --hitch-test --profile=t12                        # o mesmo com janela (entra a compilação de shaders)
godot --path . -- --screenshot=/tmp/a.png --zoom=0.2 --utc=15 --ui=inventory   # PNG (ui: inventory, craft, house, dev, dev-viagem, dev-natureza, build, settings, perf, pedia, pedia-full, passport, passport-full, photo, selfie, hearts, welcome, airport, travel, flight; + --season=winter, --look=GRAUS, --country=XXX)
godot --headless --path . -s tools/montar_casas.gd                     # regera as cenas das casas (sobrescreve!)
tools/sem_foco.sh -s tools/montar_casas.gd -- --fotos=/tmp/casas --so-fotos   # fotos das casas (oitões, 4 lados), sem foco
```

Argumentos do cliente (depois de `--`): `--server=URL`, `--profile=NOME`, `--nickname=X` (+ `--country=BRA`), `--quality=…`, `--spawn=LAT,LON`, `--zoom=0..1`, `--utc=HORA`, `--no-cache`, `--equip=ITEM`, `--walk=SEG`, `--dir=…`, `--run`, `--moving`, `--jump`, `--smoke-test`, `--play-test`, `--screenshot=ARQ`, `--ui=…`, `--route=LAT,LON`, `--perf-test=SEG`, `--tour`, `--window-size=WxH`, `--ui-scale=X`, `--fps-limit=N`, `--fullscreen-test`, `--no-focus`. Lista completa no topo de `client/scripts/main.gd`.

Teclas no jogo: E interagir (também caixa de vendas, balcão do aeroporto, carinho e frutinha nos animais), Tab/I bolso, 1–5 ferramentas, B construir (R gira, clique coloca, X guarda), H casa, G Goblopédia, P passaporte, botão direito com a câmera fotográfica na mão (modo foto em primeira pessoa; F alterna com o selfie; roda dá zoom, clique fotografa), F1 modo dev, F2 desempenho e últimas travadas, F3/F4 tempo, F6 configurações (qualidade, limite de fps, tamanho da interface, mouse, tela cheia), F11 tela cheia. A câmera gira com o movimento do mouse (cursor capturado pelo `GameUi`; solto com menu aberto, no modo construção, com Alt e depois de Esc). Automações e `--no-focus` nunca capturam o cursor.

## Convenções

- **Identidade própria (regra permanente):** o Goblo nunca cita outro jogo, estúdio ou personagem de outro jogo: nem na interface, nem em textos, código (identificadores, comentários, nomes de arquivo), README, `CLAUDE.md`, ADRs ou briefings. Descreva com termos próprios ("cozy", "aconchegante", "a obra fica pronta no dia seguinte"). O CI roda `scripts/verificar-nomes.sh` e falha se achar algum (`--lista` mostra os nomes).
- **Idioma:** código (identificadores) em inglês; comentários, docs, mensagens de log, mensagens de erro da API, HUD e commits em português.
- **Commits:** pequenos, um por etapa lógica, no imperativo em português (`Adiciona coleta com E`). Rode `go test ./...` e `go vet ./...` antes de cada commit.
- **Decisões:** se algo não está no briefing, escolha a opção mais simples e registre um ADR curto em `docs/decisoes/NNNN-titulo.md` (contexto, decisão, consequências).
- **Coordenadas (servidor e cliente):** planeta na origem, norte em +Y, (0°, 0°) em +Z, (0°, 90° L) em +X. Cantos das células em sentido anti-horário visto de fora; `neighbors[k]` atravessa a aresta `vertices[k] → vertices[k+1]`; canto k = normalize(centro + vizinho[k−1] + vizinho[k]). O Godot usa sentido horário como face da frente, então `globe_builder.gd` inverte a ordem ao gravar triângulos.
- **Topo plano da célula:** `P = c·(raio + altura) + East·x + North·y`, `East = normalize(ref × c)`, `North = c × East`, `ref = Y` (ou `Z` se `|c.y| > 0,999`). `game.CellFrame` (Go) e `WorldData.cell_frame` (GDScript) precisam continuar iguais. Objetos e lotes trafegam como (célula, x, y).
- **Célula de um ponto:** a de centro mais próximo (`World.CellAt` no Go, `WorldData.find_cell` no GDScript). As duas precisam continuar equivalentes.
- **Lotes:** quadradinho de 0,5, lote de 14 × 14, até 4 por célula, id = célula × 4 + posição (`server/internal/game/lots.go`, ADR 0019). Footprint `[w, h]` com `rot` ímpar vira `[h, w]`; o servidor valida (`footprintRect`) e o cliente só repete a conta para a prévia (`LotGeom`).
- **Objetos interativos:** gerados pelo servidor (`objects.go`, semente no id da célula), id = célula × 64 + índice; todas as árvores e pedras grandes vêm do servidor e o cliente só espalha grama (ADR 0020). Mudar `objects.json` muda os objetos de todo mundo.
- **Regras só no servidor:** inventário, limites diários (por jogador), fabricação, colocação, casa. O cliente nunca muda o inventário por conta própria: aplica a resposta do servidor (`Session.set_inventory`, `GameMain.apply_lot_result`). Distância até o objeto ainda não é conferida (ADR 0021, `TODO(fase 3)`).
- **Dia do jogo:** vira às 5h no horário local da casa do jogador (longitude ÷ 15), `game.DayIndex`. Nada de `time.Now()` nas regras: use o `Clock` injetado (os testes usam `OffsetClock` sobre `FixedClock`).
- **Fronteiras (ADR 0031):** a terra é do 1:110m (forma do globo); os países, do 1:50m (`paises.geojson`, gerado por `cmd/filtra-paises`). O país de uma posição é o exato (`Geography.CountryAt`; no cliente, `BorderMap` pelo segmento mais perto, com teste de concordância em Go); o hexágono tem um país principal (bioma, lotes, mini mapa).
- **Animais (ADR 0032):** o servidor sorteia por célula e manda os pontos de passeio; a posição é `AnimalAt(animal, horário do servidor)` em Go e `AnimalPath.at` em GDScript, que precisam continuar iguais (arquivo de referência `testdata/animal_paths.json` + `tests/test_animais.gd`). Reações (fugir, seguir, carinho) são desvios só no cliente.
- **Estações (ADR 0034):** `game.SeasonAt` (Go) e `Seasons` (GDScript) com a mesma conta; o chão calcula no shader pela latitude (alfa da cor do vértice marca os biomas que mudam). Árvores trocam só o modelo desenhado (`drawn_model`), nunca o id. Nada de carregar modelo no meio do jogo: as versões de estação que valem hoje entram no pré-carregamento.
- **Moedas e passaportes (ADR 0035):** saldo só pelo `WalletRepository` (`AddCoins` nunca deixa negativo e grava o histórico); recompensas uma vez só (chave primária da Goblopédia e dos carimbos). Hexágonos de aeroporto não têm lotes novos, objetos nem animais. A barreira da fronteira e o carimbo a pé ficam no cliente até a fase 3.
- **Banco:** só por `game.Store`; SQL fica em `internal/store/sqlitestore`. Mudança de esquema = nova migração `NNNN_nome.sql` (nunca edite uma migração já aplicada).
- **Erros da API:** `game.Error` com código estável, status e mensagem em português; o cliente mostra `message`.
- **JSON no cliente:** o Godot lê números como float e escreve `12.0`; a `Api` converte números inteiros antes de enviar (o Go recusa `12.0` em campo int). Converta com `int(...)` ao ler ids.
- **Determinismo do mundo:** mesma frequência + mesmos dados = mesmo mundo (JSON e binário). Não use mapas sem ordenar nem aleatoriedade na geração.
- **Formato binário:** descrito em `server/internal/world/binary.go` e lido por `WorldData.from_binary`. Campo novo → suba `BinaryFormatVersion` e atualize os dois lados. Valores de `Biome` fazem parte do formato: só acrescente no fim.
- **Conteúdo balanceável:** itens, receitas, casas, objetos, economia (preços, recompensas, passagem, passaporte), animais e Goblopédia em `server/data/game/*.json`; grama em `client/data/decoracao.json` (`docs/CONTEUDO.md`). Não espalhe números de balanceamento pelo código.
- **Testes obrigatórios:** os do mundo (SP é `BRA`, biomas, escala, determinismo), os da fase 2 (dev 403, lote no país, lotes únicos, limites diários e virada das 5h, coletas por jogador, fabricação, colocação, casa, objetos determinísticos, IP → país) e os da fase 2.5 (fronteiras conhecidas, moedas sem saldo negativo, venda, recompensas sem repetição, animais determinísticos, estações por data e latitude, preço da viagem, passaporte obrigatório, carimbo único). Se mudar regras, dados, lotes ou objetos, eles precisam continuar passando.
- **GDScript, armadilhas:** `PackedInt32Array` (e os outros Packed*) são copiados; `(dict[k] as PackedInt32Array).append(x)` não altera o dicionário. `var x := dict["k"]` não compila (tipo Variant): use `var x: int = …`.
- **Godot:** cenas em `client/scenes/`, scripts em `client/scripts/` com `class_name`, shaders em `client/shaders/`. Os arquivos `.uid` vão para o Git; a pasta `.godot/` não. UI montada em código, no estilo de `UiStyle`.
- **Assets:** Kenney e Quaternius (CC0), em `client/assets/<autor>/<pacote>/`, com créditos em `client/assets/CREDITOS.md`. Kenney: GLB + `Textures/` + `License.txt`. Quaternius: Nature Pack só `FBX/`; animais em `.glb` (`tools/gltf_para_glb.py`). Nada de OBJ/Blends/prévias. Os `.import` vão para o Git. Pacotes originais (`kenney_*/`, `Ultimate */`) ficam fora do Git. Do Graveyard Kit, nada de Halloween (ADR 0017).
- **Modelos:** sempre pela `ModelLibrary.get_model(nome)` (junta as malhas, gera LOD, cacheia). Modelo novo nos JSON entra sozinho no pré-carregamento (lista `object_models` do `/content`).
- **Personagem:** escolhido por `@export_enum var character` em `player.gd` e escalado para `model_height`. Os modelos olham para +Z e são girados 180°. Animações num `AnimationTree`: `locomotion`, `air` e a ação única `action` (interact-right, pick-up). Ferramenta presa ao osso `arm-right`.
- **Desempenho:** metas: média com 60 fps estáveis e alta com no mínimo 45 fps, na janela maximizada do Mac Intel do autor (3136 × 1930 pixels, Retina), no bairro com 20 vizinhos e na floresta tropical (ADR 0028, tabela no README). O gargalo é a GPU. Para saber o que pesa, use `--profile-scene` (desliga uma parte por vez e mede a GPU) com `--window-size=3136x1930`; os fps de verdade só com `--perf-test` e a janela na frente. Trabalho caro vai para threads (`WorkerThreadPool`) ou é espalhado entre quadros; nada de carregar modelo no meio do jogo nem criar centenas de nós num quadro. Lotes de vizinhos viram uma malha por material (`Neighborhood._merge`); distâncias de desenho, LOD, sombras e resolução do 3D ficam nos presets de `quality.gd`.
- **Renderizador Mobile, armadilhas:** não tem SSAO/SSIL/névoa volumétrica; `GeometryInstance3D.transparency` não tem efeito (para transparência, use um material com pontilhado, como `CameraOcclusion._fade_materials`, ou com alfa). Evite `discard` em shaders do mundo (desliga o early-z).
- **Travadas (ADR 0036):** todo quadro acima de 25 ms vai para `user://travadas.log` (`HitchLog`). Trabalho novo que possa pesar anota com `HitchLog.note("o quê", ms)` e, se passar de poucos ms, vai para uma thread (`WorkerThreadPool`) ou é espalhado entre quadros (um pedaço, aeroporto, forma de colisão por quadro; lotes com limite de tempo). Pedaços do servidor entram um por quadro (`ChunkData._drain`); o nascimento e o teleporte esperam tudo (`load_now`). Material ou modelo novo entra sozinho no pré-aquecimento de shaders se vier da `ModelLibrary`; outros vão em `GameMain._warm_extras`. Nada de `find_cell` sem pista em laço (varre as 25 mil células). V-Sync sempre ligado; limite de fps em `FpsLimit` (F6).
- **Personagem no mapa:** nunca em oceano. Teleporte, chegada de voo, H e nascimento passam por `GameMain.land_point`; andando, `Player` volta o passo que terminaria no mar.
- **Interface:** o `GameUi` é o gerenciador: `menu_open()` e `captures(evento)` dizem se o mouse/teclado é da interface. Câmera, personagem, modo construção e interação perguntam a ele; janela nova só precisa entrar em `menu_open()` (isso também solta o cursor capturado) e usar `UiStyle.header(...)` (título + dica + botão X). Fluxo que mexe na tela sem ser menu (voo, teleporte, plaquinha) termina com `GameUi.restore_control()`: o cursor volta a ser capturado na hora. Nada mexe em `Input.mouse_mode` fora do `GameUi`.
- **Escala:** raio 1000, personagem ~1, andar 5,3, correr ×2,3, pulo 1,3, peças do Fantasy Town Kit ×1,5, árvores 3 a 5 de altura. Números do cliente em `game_config.gd`; tabela completa em `docs/ARQUITETURA.md`.

## Onde fica cada coisa

| Quero mexer em… | Arquivo |
| --- | --- |
| geração da grade | `server/internal/world/geodesic.go` |
| terra/oceano/país | `server/internal/world/terrain.go` |
| fronteiras exatas (país por posição, segmentos por célula) | `server/internal/world/borders.go`, `cmd/filtra-paises`; cliente: `border_map.gd`, `border_lines.gd`, `country_tracker.gd` |
| biomas e alturas | `server/internal/world/biome.go`, `regions.go` (+ `docs/BIOMAS.md`) |
| formato binário | `server/internal/world/binary.go` e `client/scripts/world_data.gd` |
| itens, receitas, casas, objetos por bioma, economia, animais, Goblopédia | `server/data/game/*.json` (+ `docs/CONTEUDO.md`) |
| moedas e caixa de vendas | `server/internal/game/money.go`; cliente: `sell_ui.gd`, `coin_icon.gd` |
| animais (sorteio, trajeto, frutinha) | `server/internal/game/animals.go`; cliente: `animals.gd`, `animal_path.gd` |
| Goblopédia e câmera fotográfica | `server/internal/game/pedia.go`; cliente: `photo_mode.gd`, `pedia_ui.gd`, `pedia_art.gd`, `pedia_photos.gd` |
| estações do ano | `server/internal/game/season.go`; cliente: `seasons.gd`, `season_fx.gd`, `shaders/terrain.gdshader` |
| aeroportos, viagem, passaportes e carimbos | `server/internal/game/airports.go`; cliente: `airports.gd`, `travel_ui.gd`, `passport_ui.gd`, `stamp_art.gd`, barreira em `main.gd` (`_border_guard`) e `player.gd` |
| regras (jogador, coleta, fabricação, lote, casa) | `server/internal/game/service.go` |
| modo dev (servidor) | `server/internal/game/dev.go`, `server/internal/httpapi/dev.go` |
| lotes (tamanho, posições) | `server/internal/game/lots.go` e `client/scripts/lot_geom.gd` |
| objetos interativos | `server/internal/game/objects.go` |
| banco e migrações | `server/internal/store/sqlitestore/` |
| apelido e palavrões | `server/internal/game/nickname.go` |
| IP → país | `server/internal/geoip/` |
| rotas HTTP | `server/internal/httpapi/` (+ `docs/API.md`) |
| conversa com o servidor, token | `client/scripts/api.gd`, `session.gd` |
| objetos e lotes por pedaço | `client/scripts/chunk_data.gd` |
| árvores, grama, colisão | `client/scripts/vegetation.gd`, `client/data/decoracao.json` |
| carregar e juntar modelos | `client/scripts/model_library.gd` |
| casas e decoração do bairro | `client/scripts/neighborhood.gd` |
| cenas das casas | `client/scenes/houses/`, `client/tools/montar_casas.gd` |
| tecla E e efeitos | `client/scripts/interaction.gd` |
| modo construção | `client/scripts/build_mode.gd` |
| janelas (bolso, bancada, dev, 1º acesso) | `client/scripts/game_ui.gd`, `inventory_ui.gd`, `craft_ui.gd`, `dev_panel.gd`, `first_access.gd`, `ui_style.gd` |
| movimento, pulo, voo, ferramenta na mão | `client/scripts/player.gd` |
| velocidades, pulo, câmera | `client/scripts/game_config.gd` |
| qualidade gráfica | `client/scripts/quality.gd` |
| malha do chão e do oceano | `client/scripts/globe_builder.gd`, `terrain.gd` |
| dia e noite, céu | `client/scripts/day_night.gd`, `client/shaders/sky.gdshader` |
| registro de travadas, limite de fps, pré-aquecimento de shaders | `client/scripts/hitch_log.gd`, `fps_limit.gd`, `shader_warmup.gd` |
| HUD, bússola, mini mapa (seta e casinha) | `client/scripts/hud.gd`, `compass.gd`, `minimap.gd`, `home_icon.gd` |
| câmera (mouse, zoom, chão) e objetos pontilhados na frente dela | `client/scripts/camera_rig.gd`, `camera_occlusion.gd`, caixas em `neighborhood.gd` (`occluders`) |
| vento e variação da vegetação, névoa, tonemapping | `client/shaders/foliage.gdshader`, `client/scripts/day_night.gd` |
| configurações (F6): qualidade, tamanho da interface, mouse, tela cheia | `client/scripts/settings_ui.gd`, `quality.gd`, `mouse_settings.gd` |
| verificação de nomes de outros jogos (CI) | `scripts/verificar-nomes.sh` |
| inicialização, identidade, atalhos, ações do dev, automações | `client/scripts/main.gd` |
| assets e créditos | `client/assets/` |

## Fora do escopo até a fase indicada

Multiplayer em tempo real, posição do jogador no servidor, validação de distância e de fronteira no servidor, reações dos animais vistas por todos, chat (fase 3, ver ADR 0005); loja de itens e troca entre jogadores (fase 4). Animais novos (mais pacotes depois). Interior da casa, pesca, música e efeitos sonoros, carros e navios, ferramentas que quebram e login de verdade ainda não têm fase. Não feche portas para eles.
