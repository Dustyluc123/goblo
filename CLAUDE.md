# CLAUDE.md

Guia para o Claude Code trabalhar no Goblo. Leia também `docs/ARQUITETURA.md` e `docs/decisoes/`.

## O projeto

MMO cozy no planeta Terra de verdade, visto como um globo de sala de aula. Monorepo:

- `server/` — Go. **Fonte da verdade do mundo**: gera a grade geodésica, classifica terra/oceano/país e serve `GET /world`.
- `client/` — Godot 4 + GDScript. Baixa o mundo e só desenha; nunca gera mundo.
- `docs/` — arquitetura, dados, briefings das fases e ADRs em `docs/decisoes/`.

## Antes de tudo

- **PATH do Go:** neste Mac o Go fica em `~/sdk/go/bin` (instalado fora do Homebrew, que não suporta mais Mac Intel). Garanta que está no `PATH` (`export PATH="$HOME/sdk/go/bin:$PATH"`) ou chame `~/sdk/go/bin/go` direto. O Godot fica em `~/sdk/godot/Godot.app/Contents/MacOS/Godot`.
- **O servidor precisa estar rodando** (`cd server && go run ./cmd/server`, num terminal separado ou em segundo plano) antes de abrir o jogo ou rodar qualquer automação do cliente (`--smoke-test`, `--screenshot`, `--tour`). Sem ele, o cliente não tem mundo para desenhar.

## Comandos

```bash
# Servidor (de dentro de server/)
go run ./cmd/server                      # sobe em :8080
go run ./cmd/server -frequency 30        # outra grade (10·n²+2 células)
go test ./...                            # testes (obrigatório antes de commitar)
go vet ./...
gofmt -l .                               # precisa sair vazio (o CI confere)
./scripts/baixar-dados.sh                # baixa de novo o Natural Earth

# Cliente (de dentro de client/, com o servidor rodando)
godot --path .                                        # abre o jogo
godot --editor --path .                               # abre o editor
godot --headless --path . --import                    # importa o projeto (primeira vez / CI)
godot --headless --path . -- --smoke-test             # anda 3 s e confere: em terra, no chão
godot --headless --path . -- --smoke-test --walk=30   # anda até a costa e confere o bloqueio do oceano
godot --path . -- --screenshot=/tmp/a.png --zoom=0.5  # PNG da tela (precisa de janela)
godot --path . --write-movie /tmp/f.png --fixed-fps 15 -- --tour   # quadros para o GIF
```

Argumentos do cliente (depois de `--`): `--server=URL`, `--spawn=LAT,LON`, `--zoom=0..1`, `--walk=SEG`, `--dir=forward|back|left|right`, `--run`, `--moving`, `--smoke-test`, `--screenshot=ARQ`, `--tour`. Exemplo para ver a animação de corrida: `--screenshot=/tmp/a.png --zoom=0.05 --walk=1.5 --moving --run`. A URL do servidor também vem de `GOBLO_SERVER_URL` ou de `goblo/server_url` no `project.godot`.

## Convenções

- **Idioma:** código (identificadores) em inglês; comentários, docs, mensagens de log, HUD e commits em português.
- **Commits:** pequenos, um por etapa lógica, no imperativo em português (`Gera grade geodésica no servidor`). Rode `go test ./...` antes de cada commit.
- **Decisões:** se algo não está no briefing, escolha a opção mais simples e registre um ADR curto em `docs/decisoes/NNNN-titulo.md` (contexto, decisão, consequências).
- **Coordenadas (servidor e cliente):** planeta na origem, norte em +Y, (0°, 0°) em +Z, (0°, 90° L) em +X. Cantos das células em sentido anti-horário visto de fora; `neighbors[k]` atravessa a aresta `vertices[k] → vertices[k+1]`. O Godot usa sentido horário como face da frente, então `globe_builder.gd` inverte a ordem ao gravar triângulos.
- **Célula de um ponto:** a de centro mais próximo (`World.CellAt` no Go, `WorldData.find_cell` no GDScript). As duas precisam continuar equivalentes.
- **Determinismo:** mesma frequência + mesmos dados = mesmo JSON. Há teste para isso; não use mapas sem ordenar nem aleatoriedade na geração.
- **Testes de geografia:** São Paulo é `BRA`, (0, -30) é oceano, oceano entre 60% e 80%. Se trocar dados ou frequência, esses testes precisam continuar passando.
- **Godot:** cenas em `client/scenes/`, scripts em `client/scripts/` com `class_name`. Os arquivos `.uid` vão para o Git; a pasta `.godot/` não. UI montada em código (`hud.gd`) para ficar fácil de revisar.
- **Assets:** só da Kenney (CC0), em `client/assets/kenney/`, com créditos em `client/assets/CREDITOS.md`. Copie apenas GLB + `Textures/` (os GLB procuram `Textures/colormap.png` pelo caminho relativo) ou PNG; nada de FBX/OBJ/prévias. Os `.import` vão para o Git. Pacotes originais baixados ficam em `kenney-original/`, que está no `.gitignore`.
- **Personagem:** escolhido por `@export_enum var character` em `player.gd` e escalado para `model_height` medindo as malhas. Os modelos olham para +Z e são girados 180° (a frente no Godot é -Z). As animações vêm sem loop do GLB; `player.gd` liga o loop e monta um `AnimationTree` com `BlendSpace1D` (0 idle, 1 walk, 2 sprint).
- **Escala:** raio 100, personagem ~1, velocidade 4,5. Tabela completa em `docs/ARQUITETURA.md`.

## Onde fica cada coisa

| Quero mexer em… | Arquivo |
| --- | --- |
| geração da grade | `server/internal/world/geodesic.go` |
| terra/oceano/país | `server/internal/world/terrain.go` |
| formato do JSON / cache | `server/internal/world/world.go` |
| rotas HTTP | `server/internal/httpapi/httpapi.go` |
| cores e malha do globo | `client/scripts/globe_builder.gd` |
| movimento, bloqueio do oceano, personagem e animação | `client/scripts/player.gd` |
| assets e créditos | `client/assets/` |
| câmera e zoom | `client/scripts/camera_rig.gd` |
| HUD | `client/scripts/hud.gd` |
| fluxo de inicialização e automações | `client/scripts/main.gd` |

## Fora do escopo até a fase indicada

Construção (fase 2); multiplayer, Nakama (fase 3, ver ADR 0005); fronteiras jogáveis e moeda (fase 4). Contas, banco de dados, NPCs, áudio e arte final ainda não têm fase.
