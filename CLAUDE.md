# CLAUDE.md

Guia para o Claude Code trabalhar no Goblo. Leia também `docs/ARQUITETURA.md`, `docs/BIOMAS.md` e `docs/decisoes/`.

## O projeto

MMO cozy no planeta Terra de verdade, visto como um globo de sala de aula. Monorepo:

- `server/` — Go. **Fonte da verdade do mundo**: gera a grade geodésica, classifica terra/oceano/país/bioma/altura e serve `GET /world.bin` (binário), `GET /world` (JSON de depuração) e `GET /world/version`.
- `client/` — Godot 4 (renderizador Mobile) + GDScript. Baixa o mundo (com cache) e só desenha; nunca gera mundo. A única coisa que sorteia é a decoração, de forma determinística.
- `docs/` — arquitetura, dados, biomas, briefings das fases e ADRs em `docs/decisoes/`.

## Antes de tudo

- **PATH do Go:** neste Mac o Go fica em `~/sdk/go/bin` (instalado fora do Homebrew, que não suporta mais Mac Intel). Garanta que está no `PATH` (`export PATH="$HOME/sdk/go/bin:$PATH"`) ou chame `~/sdk/go/bin/go` direto. O Godot fica em `~/sdk/godot/Godot.app/Contents/MacOS/Godot`.
- **O servidor precisa estar rodando** (`cd server && go run ./cmd/server`, num terminal separado ou em segundo plano; leva ~4 s para gerar o mundo) antes de abrir o jogo ou rodar qualquer automação do cliente. Sem ele (e sem cache), o cliente não tem mundo para desenhar.
- **Classe nova em GDScript** (`class_name`) só é reconhecida depois de `godot --headless --path client --import`.
- Envolva comandos do Godot em `perl -e 'alarm 200; exec @ARGV' …` para não travar a sessão se o jogo não fechar.

## Comandos

```bash
# Servidor (de dentro de server/)
go run ./cmd/server                      # sobe em :8080 (n = 50, raio 1000)
go run ./cmd/server -frequency 30        # outra grade (10·n²+2 células)
go test ./...                            # testes (obrigatório antes de commitar)
go vet ./...
gofmt -l .                               # precisa sair vazio (o CI confere)
./scripts/baixar-dados.sh                # baixa de novo o Natural Earth e filtra as regiões

# Cliente (de dentro de client/, com o servidor rodando)
godot --path .                                        # abre o jogo
godot --editor --path .                               # abre o editor
godot --headless --path . --import                    # importa o projeto (primeira vez / classes novas)
godot --headless --path . -- --smoke-test --jump      # anda 3 s, pula: confere chão, terra e altura do pulo
godot --headless --fixed-fps 60 --path . -- --route=4.5,-61.1 [--run]   # mede SP → Pacaraima
godot --path . -- --perf-test=20 --spawn=-3,-60 --quality=medium        # fps e GPU na floresta tropical
godot --path . -- --screenshot=/tmp/a.png --zoom=0.2 --utc=15           # PNG da tela (precisa de janela)
godot --path . --write-movie /tmp/f.png --fixed-fps 15 -- --tour        # quadros para o GIF (janela 1280×720)
```

Argumentos do cliente (depois de `--`): `--server=URL`, `--quality=low|medium|high`, `--spawn=LAT,LON`, `--zoom=0..1`, `--utc=HORA`, `--no-cache`, `--walk=SEG`, `--dir=forward|back|left|right`, `--run`, `--moving`, `--jump`, `--smoke-test`, `--screenshot=ARQ`, `--route=LAT,LON` (`--limit=SEG`), `--perf-test=SEG`, `--tour`. Lista completa no topo de `client/scripts/main.gd`.

Atalhos no jogo: F2 painel de desempenho, F3 acelera o tempo, F4 horário real, F6 qualidade.

## Convenções

- **Idioma:** código (identificadores) em inglês; comentários, docs, mensagens de log, HUD e commits em português.
- **Commits:** pequenos, um por etapa lógica, no imperativo em português (`Gera grade geodésica no servidor`). Rode `go test ./...` e `go vet ./...` antes de cada commit.
- **Decisões:** se algo não está no briefing, escolha a opção mais simples e registre um ADR curto em `docs/decisoes/NNNN-titulo.md` (contexto, decisão, consequências).
- **Coordenadas (servidor e cliente):** planeta na origem, norte em +Y, (0°, 0°) em +Z, (0°, 90° L) em +X. Cantos das células em sentido anti-horário visto de fora; `neighbors[k]` atravessa a aresta `vertices[k] → vertices[k+1]`; canto k = normalize(centro + vizinho[k−1] + vizinho[k]). O Godot usa sentido horário como face da frente, então `globe_builder.gd` inverte a ordem ao gravar triângulos.
- **Célula de um ponto:** a de centro mais próximo (`World.CellAt` no Go, `WorldData.find_cell` no GDScript). As duas precisam continuar equivalentes.
- **Determinismo:** mesma frequência + mesmos dados = mesmo mundo (JSON e binário). Não use mapas sem ordenar nem aleatoriedade na geração; o ruído de colinas (`noise.go`) é por hash.
- **Formato binário:** descrito em `server/internal/world/binary.go` e lido por `WorldData.from_binary`. Campo novo → suba `BinaryFormatVersion` e atualize os dois lados. Valores de `Biome` fazem parte do formato: só acrescente no fim.
- **Decoração determinística:** sementes `cell_id × 16 + índice` no mulberry32 (`decor_rng.gd`). A qualidade só muda a camada pequena (subconjunto); árvores e pedras grandes são iguais para todos. Mudar `BiomeStyle.DECOR` muda as árvores de todo mundo (ADR 0011).
- **Testes de geografia:** SP é `BRA` e não é deserto nem gelo; (0, −30) é oceano; Amazônia tropical, Saara deserto, Himalaia montanha, Antártida gelo; oceano entre 60% e 80%; escala SP → Pacaraima. Se trocar dados, frequência, raio ou velocidade, esses testes precisam continuar passando.
- **GDScript, armadilha:** `PackedInt32Array` (e os outros Packed*) são copiados; `(dict[k] as PackedInt32Array).append(x)` não altera o dicionário. Acumule em `Array` e converta no fim.
- **Godot:** cenas em `client/scenes/`, scripts em `client/scripts/` com `class_name`, shaders em `client/shaders/`. Os arquivos `.uid` vão para o Git; a pasta `.godot/` não. UI montada em código.
- **Assets:** só da Kenney (CC0), em `client/assets/kenney/<pacote>/`, com créditos em `client/assets/CREDITOS.md`. Copie apenas GLB + `Textures/` + `License.txt` (ou PNG); nada de FBX/OBJ/prévias. Os `.import` vão para o Git. Pacotes originais ficam em `kenney-original/` ou `kenney_*/`, que estão no `.gitignore`. Do Graveyard Kit, só itens neutros (ADR 0017).
- **Personagem:** escolhido por `@export_enum var character` em `player.gd` e escalado para `model_height`. Os modelos olham para +Z e são girados 180°. Animações num `AnimationTree`: `locomotion` (BlendSpace1D idle/walk/sprint) e `air` (jump/fall).
- **Desempenho:** o alvo é 60 fps na qualidade média no MacBook Intel do autor. Antes e depois de mudar algo pesado, rode `--perf-test`. Trabalho caro vai para threads (`WorkerThreadPool`) ou é espalhado entre quadros; nada de criar centenas de nós num quadro.
- **Escala:** raio 1000, personagem ~1, andar 5,3, correr ×2,3, pulo 1,3. Números do cliente em `game_config.gd`; tabela completa em `docs/ARQUITETURA.md`.

## Onde fica cada coisa

| Quero mexer em… | Arquivo |
| --- | --- |
| geração da grade | `server/internal/world/geodesic.go` |
| terra/oceano/país | `server/internal/world/terrain.go` |
| biomas e alturas | `server/internal/world/biome.go`, `regions.go` (+ `docs/BIOMAS.md`) |
| formato binário | `server/internal/world/binary.go` e `client/scripts/world_data.gd` |
| raio e frequência padrão | `DefaultConfig` em `server/internal/world/world.go` |
| rotas HTTP | `server/internal/httpapi/httpapi.go` |
| velocidades, pulo, câmera | `client/scripts/game_config.gd` |
| qualidade gráfica | `client/scripts/quality.gd` |
| malha do chão e do oceano, colisão do chão | `client/scripts/globe_builder.gd`, `terrain.gd` |
| cores e decoração por bioma | `client/scripts/biome_style.gd` |
| vegetação por pedaços | `client/scripts/vegetation.gd` |
| movimento, pulo, oceano, animação | `client/scripts/player.gd` |
| dia e noite, céu | `client/scripts/day_night.gd`, `client/shaders/sky.gdshader` |
| oceano animado | `client/shaders/ocean.gdshader` |
| nuvens | `client/scripts/clouds.gd` |
| HUD, bússola, mini mapa | `client/scripts/hud.gd`, `compass.gd`, `minimap.gd` |
| câmera e zoom | `client/scripts/camera_rig.gd` |
| inicialização, cache, atalhos e automações | `client/scripts/main.gd` |
| assets e créditos | `client/assets/` |

## Fora do escopo até a fase indicada

Construção, grade de construção dentro do hexágono e cidades (fase 2); multiplayer, Nakama (fase 3, ver ADR 0005); fronteiras jogáveis e moeda (fase 4). Contas, banco de dados, NPCs, áudio, fusos horários reais, estações do ano, luzes de cidade e objetos de Halloween ainda não têm fase.
