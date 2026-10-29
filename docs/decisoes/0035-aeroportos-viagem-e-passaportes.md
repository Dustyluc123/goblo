# 0035 — Aeroportos, viagem e passaportes

## Contexto

A fase 2.5 dá motivos para rodar o globo: aeroportos perto das capitais, viagens pagas em moedas, passaporte obrigatório para entrar em cada país (a pé ou de avião) e um livro com um carimbo por país visitado. O servidor ainda não sabe a posição do jogador em tempo real (fase 3).

## Decisão

- **Onde fica cada aeroporto:** no hexágono de terra do país mais perto da capital (`capitais.json`, camada de lugares povoados 1:50m; sem capital, o "centro" do país). O aeroporto **ocupa o hexágono inteiro**: ali não há lotes novos, objetos nem animais. Hexágonos que já têm lote (de um banco antigo) são pulados, então o mesmo banco sempre dá os mesmos aeroportos.
- **Países pequenos:** com menos de 3 hexágonos, o país ganha só um **ponto de chegada** (um balcão na beirada do hexágono, fora dos lotes), para não perder lugar de lote. Países sem hexágono (Vaticano, Mônaco…) não têm aeroporto; chega-se a pé pelo vizinho, e o passaporte deles é vendido em qualquer aeroporto.
- **Cenário:** montado no cliente com peças que o jogo já carrega: a casa grande como terminal, a barraquinha vermelha como balcão, uma pista de pedra com luzinhas, carrinho, lampiões e uma biruta feita em código. Ainda não há avião (o voo é um arco desenhado no globo).
- **Preços:** passagem = `base + per_1000_km × distância` entre os aeroportos (com mínimo), passaporte com preço padrão e exceções por país, tudo em `economy.json`. O servidor cobra tudo de uma vez numa transação (passagem + passaporte junto, se pedido); sem saldo, nada muda.
- **Passaporte obrigatório:** o do país de residência é implícito e grátis. Sem o passaporte do destino, o servidor recusa a viagem e o carimbo.
- **Carimbo:** um por país, na primeira visita (de avião ou a pé, com passaporte), com uma pequena recompensa uma vez só (chave primária jogador + país). Cada carimbo é desenhado em código a partir do código do país (forma, cor, borda, enfeite).
- **Barreira a pé (no cliente):** ao chegar na fronteira de um país sem passaporte, o personagem desliza ao longo da linha (a parte do passo que atravessaria é tirada; perto de uma tríplice fronteira, o que sobra é conferido de novo) e aparece um aviso. O hexágono de casa é sempre livre, e quem já está dentro de um país (por teleporte, H ou modo dev) anda livre. O modo dev pode desligar a barreira.
- **Viagem:** escurece um pouco, a câmera afasta até o globo, um arco pontilhado liga os aeroportos com um pontinho viajando (com o dia e a noite de agora) e a câmera aproxima no destino. `H` continua levando para casa de qualquer lugar.

## Consequências

- **Fase 3 (multiplayer):** com a posição do jogador no servidor, a barreira e o carimbo a pé passam a ser conferidos lá (`Geography.CountryAt` na posição enviada) e a viagem confere se o jogador está mesmo no balcão. Hoje o servidor valida saldo, passaporte e preços, mas confia no cliente sobre onde ele está (como na coleta, ADR 0021).
- Hexágonos de aeroporto não recebem lotes; um país grande perde um hexágono de lotes, um país pequeno não perde nenhum.
