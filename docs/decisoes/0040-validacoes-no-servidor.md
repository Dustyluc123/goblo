# 0040 — O que passou do cliente para o servidor (e a amizade com os animais)

## Contexto

Os ADRs 0021, 0032, 0033 e 0035 deixaram no cliente o que dependia de saber onde o jogador está: a distância até o que ele usa, a barreira da fronteira, o carimbo a pé e o registro na Goblopédia. Com a camada em tempo real (ADR 0039), o servidor sabe a posição validada de cada jogador.

## Decisão

- **Presença** (`game.Presence`, implementada pelo hub). As regras perguntam a posição, a célula e a direção do jogador. Sem conexão em tempo real, a ação que precisa da posição responde `409 offline`. Longe demais, responde `403 too_far`. Os alcances ficam em `rules.json` (`reach`) e são um pouco maiores que os do cliente, para a rede não atrapalhar:

  | O quê | Rota | Até quanto |
  | --- | --- | --- |
  | Coleta | `/interact` | 4 unidades × a escala do objeto (árvore e pedra grande alcançam mais) |
  | Caixa de vendas | `/sell` | 4 unidades de uma caixa **do próprio lote** (ninguém usa a dos outros) |
  | Frutinha e carinho | `/animal/feed` e `act` | 5 unidades + 10 de folga (`animal_drift`), porque as reações locais (fugir, seguir o jogador) tiram o animal do trajeto comum em até 10 unidades |
  | Balcão do aeroporto | `/travel` | 8 unidades do balcão do aeroporto de saída. O voo pago libera a chegada no destino, uma vez só |
  | Foto na Goblopédia | `/pedia/register` | O cliente manda a direção da câmera (`look`). O servidor confere se havia, a até 45 unidades (mais a folga), um animal da espécie na posição do trajeto comum, a no máximo 60° da direção da câmera. Para a flor azul e as árvores de outono e com neve: um objeto desse tipo a até 34 unidades, com a estação de verdade na célula. Vale no selfie também, porque a câmera olha para o personagem e o animal fica atrás dele, na mesma direção |
- **Barreira da fronteira.** Agora no servidor: a posição que entraria num país sem passaporte é corrigida. A barreira do cliente continua, para a resposta ser imediata.
- **Carimbo a pé.** Quando a posição validada entra num país de que o jogador tem passaporte, o servidor carimba e manda `stamp`. O `POST /passport/stamp` continua existindo, mas confere se o jogador está no país (ou a até 2 unidades dele).
- **Amizade com animal: por jogador.** A frutinha marca a espécie como amiga na Goblopédia de quem deu, e o animal segue só quem deu. As reações de fugir, seguir e o carinho continuam locais, no cliente de cada um. Os outros veem a animação do carinho e os corações em cima do animal (mensagem `act`), mas a reação de cada animal continua sendo de cada jogador. Assim, um jogador não estraga a experiência do outro: um tímido que foge de quem corre não foge de quem está parado do lado.

## Consequências

- O que não pode ser feito pela rede (a posição exata de cada clique, o que aparece em cada foto) continua com alguma folga. Os alcances são generosos de propósito.
- Os testes antigos de regras rodam sem presença (não conferem distância). O `TestServerChecksReach` liga uma presença falsa e confere cada caso. Os testes do hub (`internal/realtime`) usam clientes WebSocket de verdade.
- Um jogador que abre o jogo sem conseguir a conexão em tempo real não coleta nem vende até reconectar. O HUD mostra "Sem conexão: tentando de novo…".
- Limitação: a direção da câmera vem do cliente. Dá para mentir sobre para onde a câmera apontava, mas não sobre o que estava perto.
