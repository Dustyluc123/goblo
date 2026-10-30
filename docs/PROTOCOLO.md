# Protocolo em tempo real

Conexão WebSocket em `GET /ws` (fase 3, ADR 0039). Código: `server/internal/realtime/` e `client/scripts/net.gd`. Todos os números (frequências, raios, limites) ficam em `server/data/game/rules.json`.

## Conexão

- **Autenticação:** o token do jogador (o mesmo da API) vai em `Authorization: Bearer <token>`, ou em `?token=` para clientes que não mandam cabeçalho. Token errado: `401` antes do WebSocket abrir.
- **Conexão duplicada:** se o mesmo jogador conectar de novo, a conexão antiga recebe `kick` e é fechada. A nova continua de onde a antiga estava.
- **Reconexão:** o cliente tenta de novo sozinho (espera 1, 2, 4… até 8 s). O servidor lembra a última posição de quem saiu, e o `welcome` diz `"resumed": true`. Voltar para perto dela (até 60 unidades) é aceito como nascimento.
- **Limites:**
  - mensagens de até `network.max_message_bytes` (1 KB), senão a conexão fecha;
  - posições: até `max_moves_per_sec` (30) por segundo, o resto é ignorado;
  - chat: rajada de `chat.burst` (3) e depois uma a cada `chat.per_seconds` (2 s), até `chat.max_chars` (120) letras;
  - emotes: até `chat.emote_per_sec` (1,5) por segundo;
  - ações: 3 por segundo;
  - se o cliente não der conta de ler (fila de 256 mensagens cheia), a conexão cai e ele reconecta.

## Coordenadas

Posições em coordenadas do mundo (planeta na origem, raio 1000, `+Y` = norte), como `float32`. O **yaw** (para onde o personagem olha) é o ângulo no chão, medido no leste e norte locais da posição:

```
up = normalize(pos); ref = (0,1,0) (ou (0,0,1) perto dos polos)
leste = normalize(ref × up); norte = up × leste
yaw = atan2(dir·norte, dir·leste)
```

`realtime.Tangent` (Go) e `Net.tangent` (GDScript) fazem a mesma conta. O yaw vai como `int16` = `round(yaw × 10000)`.

## Mensagens binárias (little-endian)

### Cliente → servidor: posição (`1`, 19 bytes), `send_hz` (15) vezes por segundo

| Bytes | Campo |
| --- | --- |
| 0 | `1` |
| 1–2 | sequência (`uint16`) |
| 3–14 | posição x, y, z (`float32`) |
| 15–16 | yaw (`int16`) |
| 17 | animação: 0 parado, 1 andando, 2 correndo, 3 no ar, 4 ação, 5 pegando, 6 pose de foto, 7 sentado |
| 18 | bits: 1 no chão, 2 correndo, 4 voo do modo dev, 8 modo foto |

Parado, o cliente manda uma vez por segundo.

### Servidor → cliente: foto dos outros (`2`, 6 + 20 × n bytes), `snapshot_hz` (15) vezes por segundo

| Bytes | Campo |
| --- | --- |
| 0 | `2` |
| 1–4 | tempo do servidor (ms desde que subiu, `uint32`) |
| 5 | n (até 255; na prática até `max_visible`, 40) |
| por jogador | id (`int32`; bots do modo dev são negativos), posição (3 × `float32`), yaw (`int16`), animação (`uint8`), bits (`uint8`) |

Só vem quem está na **área de interesse**: os jogadores a até `interest_radius` (80 unidades), no máximo `max_visible` (40), os mais perto primeiro. O servidor acha esses jogadores com uma grade espacial de cubos de 80 unidades. O cliente desenha cada um `interp_delay_ms` (110 ms) atrás do relógio do servidor, entre as duas fotos em volta desse instante. Sem foto nova, continua o movimento por até 250 ms e depois espera.

### Servidor → cliente: correção (`3`, 16 bytes)

| Bytes | Campo |
| --- | --- |
| 0 | `3` |
| 1–2 | sequência da posição recusada |
| 3–14 | posição válida (`float32`) |
| 15 | motivo: 1 velocidade, 2 oceano, 3 fronteira, 4 altura, 5 teleporte recusado |

O cliente desliza até a posição válida em 6 quadros de física, ou vai direto se ela estiver a mais de 4 unidades.

## Validação do movimento

Cada posição nova é conferida contra a última aceita:

- **Velocidade.** A distância no chão não pode passar da folga acumulada. A folga cresce `max_speed` (15 unidades/s: correr dá 12,2) por segundo, até `burst + max_speed × 0,25`, para aguentar a rede tremendo.
- **Altura.** Entre `max_below` (1,5) abaixo e `max_above` (6) acima do topo da célula.
- **Oceano.** Não dá para entrar numa célula de oceano vindo da terra.
- **Fronteira.** `Service.CanWalk`, a mesma regra do cliente (ADR 0035 e 0037). Sem passaporte, não entra no país. O hexágono de casa, o lote e a margem do dono são livres, e quem já está dentro do país anda livre.
- **Voo do modo dev.** Com o bit 4 e o servidor em modo dev, nada é conferido.

Ao entrar num país de que tem passaporte e ainda não tem o carimbo, o servidor carimba e manda `stamp`.

## Mensagens em JSON

Todas têm `"t"` com o tipo.

### Cliente → servidor

| `t` | Campos | Faz |
| --- | --- | --- |
| `tp` | `why`, `pos: [x,y,z]` | pede um teleporte. `spawn`: nascer, em casa, onde estava antes ou (modo dev) em qualquer lugar. `home`: tecla H, perto do lote (`home_radius`). `travel`: chegada de um voo pago há pouco, perto do aeroporto de destino (`travel_radius`). `dev`: só no modo dev. Resposta: `tp` |
| `chat` | `text` | fala; quem está a até `chat.radius` (40) vê. Palavrões viram ♡ (o mesmo filtro do apelido) |
| `emote` | `e`: `wave`, `yes`, `no`, `sit`, `cheer` | emote para quem te vê |
| `act` | `a`: `shake`, `chop`, `mine`, `pick`, `pet`, `feed`, `photo`; `animal` (no carinho e na frutinha) | animação que os outros veem. Carinho e frutinha só valem perto do animal |
| `block` | `id`, `on` | bloqueia ou desbloqueia: nenhum dos dois vê mais o chat e os emotes do outro (guardado no banco) |
| `char` | `c` | troca o personagem (também por `POST /player/character`) |
| `ping` | `c` (relógio do cliente) | resposta `pong` |

### Servidor → cliente

| `t` | Campos | Quando |
| --- | --- | --- |
| `welcome` | `id`, `server_ms`, `send_hz`, `interp_delay_ms`, `animated_near`, `anim_lod_distance`, `chat_max`, `resumed` | ao conectar |
| `tp` | `why`, `ok` | resposta do teleporte (recusado: vem também uma correção) |
| `enter` | `id`, `nick`, `country`, `char`, `bot`, `pos` | alguém entrou na sua área de interesse |
| `leave` | `id` | saiu (ou desconectou) |
| `chat` | `id`, `nick`, `text` | mensagem de alguém perto (ou a sua, de volta) |
| `emote` / `act` / `char` | `id` e o resto como acima | de quem você vê |
| `obj` | `by`, `data: {id, action}` | alguém perto sacudiu, cortou ou quebrou um objeto (o estado de coleta continua de cada um; aqui é só a animação) |
| `lot` | `by`, `lot` (igual ao `GET /lots`) | um lote perto mudou: decoração, obra, casa |
| `stamp` | `result` (igual ao `POST /passport/stamp`) | carimbo novo ao entrar a pé num país |
| `blocked` | `id`, `on` | confirmação do bloqueio |
| `info` | `text` | aviso (chat rápido demais, erro) |
| `pong` | `c`, `s` (relógio do servidor) | resposta do `ping` (o cliente acerta o relógio e mede o atraso) |
| `kick` | `reason` | outra conexão do mesmo jogador entrou; esta vai fechar |
