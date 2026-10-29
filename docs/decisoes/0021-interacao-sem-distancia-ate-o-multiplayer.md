# 0021 — Interações sem conferir distância até o multiplayer

**Status:** aceita (fase 2), temporária

## Contexto
O servidor valida limites diários, ferramenta, inventário e dono do lote. O ideal seria conferir também se o jogador está perto do objeto (ou da bancada). Mas nesta fase o servidor não sabe onde o jogador está: a posição só passa a ser enviada no multiplayer (fase 3).

## Decisão
Aceitar `POST /interact` e `POST /craft` **sem conferir a distância**. Há `TODO(fase 3)` em `Service.Interact` e `Service.Craft`. O cliente só deixa interagir quem está perto (tecla E com alcance de 1 a 2 unidades; bancada a até 1,8).

## Consequências
- Um cliente modificado poderia coletar à distância. Como os limites são por jogador e por objeto, o estrago é pequeno: ele pegaria no máximo o que pegaria andando até lá.
- Na fase 3, com a posição do jogador no servidor (Nakama ou o próprio servidor), incluir a checagem: distância do jogador até o objeto ≤ alcance + folga de latência.
