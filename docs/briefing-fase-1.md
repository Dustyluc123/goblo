# Briefing — Fase 1: o globo

> Cole este arquivo inteiro no Claude Code, na pasta do projeto. Peça para ele salvar uma cópia em `docs/briefing-fase-1.md` antes de começar.

## Repositório e Git

- Esta pasta é um clone do repositório **https://github.com/Dustyluc123/goblo**. Trabalhe direto nela.
- **Já existe um `README.md` no repositório.** Leia antes de qualquer coisa. Ao reescrever o README no fim da fase, preserve o que já estiver lá (textos, links, ideias) e incorpore no novo formato, em vez de apagar.
- Você pode e deve fazer commits ao longo do trabalho: **commits pequenos, um por etapa lógica**, com mensagens em português no imperativo (ex.: `Gera grade geodésica no servidor`, `Adiciona movimento do personagem na esfera`).
- Antes de cada commit, rode os testes do servidor (`go test ./...`) e só faça o commit se passarem.
- Crie um `.gitignore` adequado para Go e Godot (`.godot/`, binários, `data/raw/` ou o que não deve ir para o Git).
- Faça `git push` para o `main` ao final da fase, depois que tudo estiver passando. Se o push falhar por falta de permissão, avise e deixe os commits locais.

## O jogo (visão geral, para dar contexto)

Um MMO cozy e aconchegante que se passa **no planeta Terra de verdade**, visto como o globo da aula de geografia: pequeno, estilizado, fofo, com os continentes e países reais. No futuro, os jogadores vão andar pelo globo, pegar um terreno perto de uma cidade real, construir, atravessar fronteiras entre países e negociar com uma moeda do jogo, todos no mesmo mundo ao mesmo tempo.

**Nome:** Goblo.

**Esta fase NÃO tem:** construção, multiplayer, contas, moeda, fronteiras jogáveis, personagens customizados. Só o globo, o personagem andando nele e o servidor que define o mundo.

## Objetivo da Fase 1

Ao final, eu abro o jogo e:

1. Vejo um globo low-poly fofo com os continentes reais, dividido em hexágonos.
2. Dou zoom out e vejo o planeta inteiro girando devagar; dou zoom in até o meu personagem.
3. Ando com WASD por cima da esfera, com a gravidade puxando para o centro do planeta, e consigo dar a volta ao mundo andando.
4. Não consigo andar no oceano (por enquanto).
5. Um HUD mostra em qual país estou e as coordenadas (latitude/longitude) do hexágono embaixo do personagem.

## Arquitetura

Monorepo com duas partes:

```
/
├── client/        # Godot 4 (versão estável mais recente), GDScript
├── server/        # Go (versão estável mais recente), módulo próprio
├── docs/
│   ├── ARQUITETURA.md
│   ├── briefing-fase-1.md
│   └── decisoes/  # ADRs curtos: 0001-godot.md, 0002-go.md, 0003-grade-geodesica.md ...
├── CLAUDE.md      # guia para o Claude Code: comandos, convenções, onde fica cada coisa
└── README.md      # em português, no mesmo estilo dos meus outros projetos
```

**Princípio central desde o dia 1: o servidor é a fonte da verdade do mundo.** O cliente não gera o mundo; ele baixa a definição do mundo do servidor e só desenha. Isso prepara o terreno para o multiplayer.

### Servidor (Go)

Estrutura sugerida:

```
server/
├── cmd/server/main.go
├── internal/world/
│   ├── geodesic.go      # gera a grade de hexágonos na esfera
│   ├── terrain.go       # marca cada célula como terra/oceano e atribui o país
│   └── world.go         # tipo World, montagem e cache
├── internal/httpapi/    # rotas HTTP
└── data/naturalearth/   # dados geográficos (domínio público)
```

**Grade do globo:** poliedro de Goldberg (o "dual" de um icosaedro subdividido). Tem hexágonos e exatamente 12 pentágonos, o que é normal e esperado. A quantidade de células é `10·n² + 2`, onde `n` é a frequência de subdivisão. Comece com `n = 20` (4.002 células) e deixe configurável. A geração tem que ser determinística: mesma frequência, mesmo mundo.

Cada célula tem:

- `id` (inteiro estável);
- centro em latitude/longitude e em vetor unitário 3D;
- vértices do polígono (vetores unitários, em ordem consistente);
- `neighbors` (ids das células vizinhas);
- `terrain`: `"land"` ou `"ocean"`;
- `country`: código ISO A3 do país (ou vazio no oceano).

**Terra, oceano e países:** use os shapefiles ou GeoJSON do **Natural Earth** em escala 1:110m (domínio público): `land` e `admin_0_countries`. Para cada célula, teste se o centro cai dentro de um polígono (point-in-polygon). Uma biblioteca como `github.com/paulmach/orb` ajuda. Faça um script para baixar os dados e documente a fonte e a licença em `docs/`.

**API:**

- `GET /health` → `{"status":"ok"}`;
- `GET /world` → JSON com a frequência, o raio sugerido e a lista de células. Pode ser grande; gere uma vez na inicialização e sirva do cache (com gzip).

**Testes em Go (obrigatórios):**

- número de células = `10·n² + 2`;
- exatamente 12 células com 5 vizinhos e o resto com 6;
- vizinhança simétrica (se A é vizinho de B, B é vizinho de A);
- determinismo (duas gerações iguais);
- a célula que contém São Paulo (-23.55, -46.63) é terra e país `BRA`;
- uma célula no meio do Atlântico (0, -30) é oceano;
- a proporção de oceano fica entre 60% e 80%.

### Cliente (Godot 4)

**Ao iniciar:** busca `GET /world` no servidor (URL configurável) e monta o globo.

**Malha do globo:**

- uma única `ArrayMesh` com cores por vértice (desempenho);
- células de terra levemente elevadas em relação ao oceano, criando um "degrau" fofo entre os hexágonos;
- sombreamento flat, low-poly, paleta pastel (oceano azul-claro, terra verde suave, bordas dos hexágonos sutis);
- colisão gerada a partir da malha.

**Escala:** raio do planeta de cerca de 100 unidades e personagem de cerca de 1 unidade. Dar a volta ao mundo andando deve levar alguns minutos. Deixe a escala fácil de ajustar.

**Personagem:**

- placeholder simples e fofo (uma cápsula com olhinhos já serve; nada de assets pesados);
- `CharacterBody3D` com gravidade apontando para o centro do planeta;
- `up_direction` atualizado a cada frame para `position.normalized()`, e a orientação do corpo alinhada à superfície;
- WASD move no plano tangente à esfera, relativo à câmera;
- bloqueio de oceano: o personagem não entra em célula de oceano (descubra a célula pela direção do personagem e consulte o terreno).

**Câmera:**

- terceira pessoa, orbitando o personagem, com o "para cima" alinhado à superfície;
- scroll do mouse faz zoom contínuo, do personagem até a visão do planeta inteiro;
- na visão afastada, o globo gira devagar sozinho.

**HUD mínimo:** nome ou código do país e lat/lon da célula atual. Destacar levemente a célula embaixo do personagem.

## Fora do escopo agora (não implementar)

Construção, multiplayer, Nakama, contas, banco de dados, moeda, fronteiras jogáveis, NPCs, áudio, arte final. Registre em `docs/decisoes/` que o Nakama será avaliado na fase de multiplayer.

## Qualidade

- `go test ./...` e `go vet ./...` passando.
- GitHub Actions rodando testes e vet do servidor a cada push.
- `README.md` com: o que é o jogo, screenshots/GIF (quando possível), arquitetura (diagrama Mermaid), como rodar servidor e cliente, roadmap das fases e uma seção "Sobre mim" igual à dos meus outros projetos.
- `CLAUDE.md` com comandos e convenções para as próximas fases.

## Forma de trabalho

- Execute a fase inteira de uma vez e me entregue tudo pronto para revisar.
- Se precisar tomar uma decisão que não está aqui, escolha a opção mais simples, registre num ADR curto em `docs/decisoes/` e siga em frente.
- No final, me diga exatamente como rodar o servidor e abrir o cliente no Godot, e liste o que ficou pendente.

## Roadmap (para referência, não implementar)

1. **Fase 1:** globo, personagem andando, servidor do mundo. ← agora
2. **Fase 2:** construir: pegar um terreno perto de uma cidade real e colocar casa, árvore e cerca.
3. **Fase 3:** multiplayer: ver outros jogadores em tempo real, com o servidor mandando para cada um só quem está perto.
4. **Fase 4:** fronteiras (países com "passaporte") e moeda (loja e troca entre jogadores).
