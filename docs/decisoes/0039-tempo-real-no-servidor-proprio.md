# 0039 — Tempo real no nosso servidor (e não no Nakama)

## Contexto

A fase 3 traz os outros jogadores em tempo real e passa para o servidor as validações que o cliente fazia. O ADR 0005 deixou para esta fase a escolha entre o servidor próprio em Go e o [Nakama](https://heroiclabs.com/nakama/), um servidor de jogos de código aberto, também em Go, com partidas autoritativas, chat, contas e cliente para Godot.

## Opções

**(a) Camada em tempo real no nosso servidor.**

- O mundo, as regras, o banco e os testes já estão aqui. A validação do movimento usa direto `Service.CanWalk`, `World.FindCell`, as fronteiras exatas (ADR 0031) e os lotes (ADR 0037), sem copiar nada.
- Continua um binário só, com um SQLite. Hospedar fica barato (`docs/DEPLOY.md`).
- Dá mais trabalho: WebSocket, área de interesse, chat, reconexão e testes ficam por nossa conta.
- É um ótimo exemplo para o portfólio: o autor mostra como uma camada dessas funciona por dentro.

**(b) Nakama.**

- Traz pronto: contas, chat com canais, grupos, partidas autoritativas, armazenamento e um cliente oficial para Godot.
- Exige um segundo serviço com PostgreSQL ou CockroachDB, ou reescrever as regras e o mundo como módulo dentro dele.
- As regras passariam a viver em dois lugares: o HTTP atual e o módulo do Nakama.
- A área de interesse por posição no globo teria de ser feita dentro de uma "partida" do Nakama do mesmo jeito.
- O cliente ganharia uma dependência (o SDK) e outro jeito de autenticar.

## Decisão

**(a).** O motivo forte que justificaria o Nakama seria precisar de recursos que ele traz e que demoram a fazer, como contas com e-mail, amigos, grupos, ranking e matchmaking. Nada disso está nas próximas fases. O custo de manter dois servidores, e as regras divididas entre eles, é maior que o ganho.

**Como ficou** (`server/internal/realtime`, `docs/PROTOCOLO.md`):

- **WebSocket** com `github.com/coder/websocket` (pequena, sem dependências). Uma conexão por jogador, com o token que já existe no `Authorization`. Uma conexão nova do mesmo jogador derruba a antiga. O servidor lembra a última posição para a reconexão.
- **Mensagens.** Movimento em binário: 19 bytes a posição, 20 bytes por jogador na foto do mundo. O resto vai em JSON enxuto. Há limite de tamanho, de posições e de chat por jogador.
- **Validação do movimento:**
  - velocidade, com uma folga acumulada para a rede tremendo;
  - altura;
  - oceano;
  - regra do passaporte (a mesma função do cliente);
  - teleportes só por casa (H), chegada de voo pago (`Service.ConsumeArrival`) ou modo dev.

  Se algo der errado, o servidor manda uma correção e o cliente desliza até a posição válida.
- **Área de interesse.** Uma grade espacial de cubos do tamanho do raio (80 unidades): cada jogador recebe os até 40 mais perto, com `enter`/`leave` quando a lista muda. As fotos saem 15 vezes por segundo, e o cliente interpola com 110 ms de atraso.
- **Previsão no cliente.** O personagem do próprio jogador responde na hora; o servidor só corrige.
- **Chat e emotes.**
  - O chat passa pelo filtro de palavrões do apelido, que troca o palavrão por ♡.
  - Os bloqueios ficam no banco (migração 0006).
  - Silenciar é só no cliente.
- **Eventos do mundo** (`Service.SetEvents`). Árvore sacudida e lote mudado vão para quem está perto. Mudança de passaporte faz o hub reler o estado do jogador.
- **Bots do modo dev**, dentro do servidor, para ver outros jogadores sem abrir vários jogos.
- **Bots externos** (`cmd/bots`) e `scripts/teste-de-carga.sh` para medir a carga.
- **Personagem.** Um dos 12 do Mini Characters, guardado no servidor (migração 0006): no primeiro acesso, no F6 e visto pelos outros.

## Consequências

- **Teste de carga** (README): 100 bots na mesma região usaram ~75% de um núcleo do i7 do autor e ~135 MB de memória, quase toda do mundo. Os bots rodavam na mesma máquina, então o número é pessimista. O perfil de CPU mostra que o custo é quase todo de rede (acordar goroutines e escrever no socket, 1.500 fotos por segundo); a lógica do jogo fica em ~10%. Se precisar de mais, o primeiro passo é baixar `snapshot_hz` ou juntar as mensagens de um tick num quadro só.
- Um processo só guarda o estado em tempo real na memória. Para mais de um servidor, seria preciso dividir o mundo por região. Não é o caso agora.
- O ADR 0005 fica respondido.
