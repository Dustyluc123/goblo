# CLAUDE.md

Guia para o Claude Code trabalhar no Goblo. Leia também `docs/ARQUITETURA.md`, `docs/API.md`, `docs/CONTEUDO.md`, `docs/BIOMAS.md` e `docs/decisoes/`.

## O projeto

MMO cozy no planeta Terra de verdade, visto como um globo de sala de aula, com o ciclo do Animal Crossing: coletar → fabricar → construir e decorar o lote → voltar amanhã. Monorepo:

- `server/` — Go. **Fonte da verdade**: gera o mundo (grade, terra, país, bioma, altura) e aplica as regras do jogo (jogador, lote, objetos interativos, coleta e limites diários, inventário, fabricação, decoração, casa), com SQLite. Rotas em `docs/API.md`.
- `client/` — Godot 4 (renderizador Mobile) + GDScript. Baixa o mundo (com cache), pede as ações ao servidor e desenha. Só a grama decorativa é sorteada no cliente (determinística).
- `docs/` — arquitetura, API, conteúdo, dados, biomas, briefings das fases e ADRs em `docs/decisoes/`.

## Antes de tudo

- **PATH do Go:** neste Mac o Go fica em `~/sdk/go/bin` (instalado fora do Homebrew, que não suporta mais Mac Intel). Garanta que está no `PATH` (`export PATH="$HOME/sdk/go/bin:$PATH"`) ou chame `~/sdk/go/bin/go` direto. O Godot fica em `~/sdk/godot/Godot.app/Contents/MacOS/Godot`.
- **O servidor precisa estar rodando** (`cd server && GOBLO_DEV=1 go run ./cmd/server`, num terminal separado ou em segundo plano; leva ~4 s) antes de abrir o jogo ou rodar qualquer automação do cliente. O cliente não joga sem servidor.
- **Porta ocupada?** O autor costuma deixar um servidor rodando em `:8080`. Não mate o processo dele: suba o seu com `-addr :8081 -db /caminho/temporario.db` e passe `-- --server=http://127.0.0.1:8081` ao cliente.
- **Classe nova em GDScript** (`class_name`) só é reconhecida depois de `godot --headless --path client --import`.
- Envolva comandos do Godot em `perl -e 'alarm 200; exec @ARGV' …` para não travar a sessão se o jogo não fechar.
- Automações do cliente criam jogadores no banco. Use `--profile=NOME` (token em `user://NOME.cfg`) para não mexer no jogador do autor (`user://player.cfg`).

## Comandos

```bash
# Servidor (de dentro de server/)
GOBLO_DEV=1 go run ./cmd/server          # sobe em :8080 com o modo dev (rotas /dev/…)
go run ./cmd/server -addr :8081 -db /tmp/x.db   # outra porta e outro banco
go test ./...                            # testes (obrigatório antes de commitar)
go vet ./...
gofmt -l .                               # precisa sair vazio (o CI confere)
./scripts/baixar-dados.sh                # Natural Earth + regiões + base IP → país da DB-IP

# Cliente (de dentro de client/, com o servidor rodando)
godot --path .                                                        # abre o jogo
godot --headless --path . --import                                    # importa (primeira vez / classes novas)
godot --headless --path . -- --smoke-test --jump --profile=t1          # nasce no lote, anda, pula
godot --headless --path . -- --play-test --profile=t2                  # ciclo inteiro (servidor com GOBLO_DEV=1)
godot --headless --fixed-fps 60 --path . -- --route=4.5,-61.1 --spawn=-23.55,-46.63
godot --path . -- --perf-test=20 --spawn=-3,-60 --quality=medium      # fps e GPU (precisa de janela)
godot --path . -- --screenshot=/tmp/a.png --zoom=0.2 --utc=15 --ui=inventory   # PNG (ui: inventory, craft, house, dev, build, first)
godot --path . -s tools/montar_casas.gd -- --fotos=/tmp/casas          # regera as casas e fotografa (sobrescreve as cenas!)
```

Argumentos do cliente (depois de `--`): `--server=URL`, `--profile=NOME`, `--nickname=X` (+ `--country=BRA`), `--quality=…`, `--spawn=LAT,LON`, `--zoom=0..1`, `--utc=HORA`, `--no-cache`, `--equip=ITEM`, `--walk=SEG`, `--dir=…`, `--run`, `--moving`, `--jump`, `--smoke-test`, `--play-test`, `--screenshot=ARQ`, `--ui=…`, `--route=LAT,LON`, `--perf-test=SEG`, `--tour`. Lista completa no topo de `client/scripts/main.gd`.

Teclas no jogo: E interagir, Tab/I bolso, 1–5 ferramentas, B construir (R gira, clique coloca, X guarda), H casa, F1 modo dev, F2 desempenho, F3/F4 tempo, F6 qualidade, Q/C câmera.

## Convenções

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
- **Banco:** só por `game.Store`; SQL fica em `internal/store/sqlitestore`. Mudança de esquema = nova migração `NNNN_nome.sql` (nunca edite uma migração já aplicada).
- **Erros da API:** `game.Error` com código estável, status e mensagem em português; o cliente mostra `message`.
- **JSON no cliente:** o Godot lê números como float e escreve `12.0`; a `Api` converte números inteiros antes de enviar (o Go recusa `12.0` em campo int). Converta com `int(...)` ao ler ids.
- **Determinismo do mundo:** mesma frequência + mesmos dados = mesmo mundo (JSON e binário). Não use mapas sem ordenar nem aleatoriedade na geração.
- **Formato binário:** descrito em `server/internal/world/binary.go` e lido por `WorldData.from_binary`. Campo novo → suba `BinaryFormatVersion` e atualize os dois lados. Valores de `Biome` fazem parte do formato: só acrescente no fim.
- **Conteúdo balanceável:** itens, receitas, casas e objetos em `server/data/game/*.json`; grama em `client/data/decoracao.json` (`docs/CONTEUDO.md`). Não espalhe números de balanceamento pelo código.
- **Testes obrigatórios:** os do mundo (SP é `BRA`, biomas, escala, determinismo) e os da fase 2 (dev 403, lote no país, lotes únicos, limites diários e virada das 5h, coletas por jogador, fabricação, colocação, casa, objetos determinísticos, IP → país). Se mudar regras, dados, lotes ou objetos, eles precisam continuar passando.
- **GDScript, armadilhas:** `PackedInt32Array` (e os outros Packed*) são copiados; `(dict[k] as PackedInt32Array).append(x)` não altera o dicionário. `var x := dict["k"]` não compila (tipo Variant): use `var x: int = …`.
- **Godot:** cenas em `client/scenes/`, scripts em `client/scripts/` com `class_name`, shaders em `client/shaders/`. Os arquivos `.uid` vão para o Git; a pasta `.godot/` não. UI montada em código, no estilo de `UiStyle`.
- **Assets:** Kenney e Quaternius (CC0), em `client/assets/<autor>/<pacote>/`, com créditos em `client/assets/CREDITOS.md`. Kenney: GLB + `Textures/` + `License.txt`. Quaternius: Nature Pack só `FBX/`; animais em `.glb` (`tools/gltf_para_glb.py`). Nada de OBJ/Blends/prévias. Os `.import` vão para o Git. Pacotes originais (`kenney_*/`, `Ultimate */`) ficam fora do Git. Do Graveyard Kit, nada de Halloween (ADR 0017).
- **Modelos:** sempre pela `ModelLibrary.get_model(nome)` (junta as malhas, gera LOD, cacheia). Modelo novo nos JSON entra sozinho no pré-carregamento (lista `object_models` do `/content`).
- **Personagem:** escolhido por `@export_enum var character` em `player.gd` e escalado para `model_height`. Os modelos olham para +Z e são girados 180°. Animações num `AnimationTree`: `locomotion`, `air` e a ação única `action` (interact-right, pick-up). Ferramenta presa ao osso `arm-right`.
- **Desempenho:** o alvo é 60 fps na qualidade média no MacBook Intel do autor (hoje: 60 fps, GPU ~10 ms na floresta tropical). Antes e depois de mudar algo pesado, rode `--perf-test` com a janela em primeiro plano. Trabalho caro vai para threads (`WorkerThreadPool`) ou é espalhado entre quadros; nada de carregar modelo no meio do jogo nem criar centenas de nós num quadro.
- **Escala:** raio 1000, personagem ~1, andar 5,3, correr ×2,3, pulo 1,3, peças do Fantasy Town Kit ×1,5, árvores 3 a 5 de altura. Números do cliente em `game_config.gd`; tabela completa em `docs/ARQUITETURA.md`.

## Onde fica cada coisa

| Quero mexer em… | Arquivo |
| --- | --- |
| geração da grade | `server/internal/world/geodesic.go` |
| terra/oceano/país | `server/internal/world/terrain.go` |
| biomas e alturas | `server/internal/world/biome.go`, `regions.go` (+ `docs/BIOMAS.md`) |
| formato binário | `server/internal/world/binary.go` e `client/scripts/world_data.gd` |
| itens, receitas, casas, objetos por bioma | `server/data/game/*.json` (+ `docs/CONTEUDO.md`) |
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
| HUD, bússola, mini mapa | `client/scripts/hud.gd`, `compass.gd`, `minimap.gd` |
| inicialização, identidade, atalhos, ações do dev, automações | `client/scripts/main.gd` |
| assets e créditos | `client/assets/` |

## Fora do escopo até a fase indicada

Animais andando, estações do ano, aeroporto, passaporte e Goblopédia (fase 2.5); multiplayer em tempo real, posição do jogador no servidor, validação de distância, chat (fase 3, ver ADR 0005); dinheiro, loja, troca e fronteiras jogáveis (fase 4). Interior da casa, pesca, música e efeitos sonoros, carros e navios, ferramentas que quebram e login de verdade ainda não têm fase. Não feche portas para eles.
