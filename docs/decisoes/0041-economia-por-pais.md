# 0041 — Economia preparada para o governo de cada país

## Contexto

A visão do Goblo é que, no futuro, cada país tenha um **governo eleito pelos jogadores** que define impostos, o preço do passaporte do país e um mercado público. Nada disso entra agora, mas a fase 3.5 dá nome ao dinheiro (o **gobolar**, G$) e abre a economia (vender tudo, loja, troca). É o momento de organizar a economia para não fechar essa porta.

## Decisão

- **Uma função de preço só:** `Service.Price(contexto, item, país) → Quote{base, imposto, total}`. Os contextos são:
  - `sell_box`: o jogador vende na caixa de vendas;
  - `shop_sell`: o jogador vende na loja;
  - `shop_buy`: o jogador compra na loja;
  - `passport`: o item é o país do passaporte;
  - `travel`: o item é `ORIGEM>DESTINO`.

  Toda compra e venda do jogo passa por ela: caixa de vendas, loja, passaporte, passagem e a troca (que não tem preço, mas é registrada).
- **Modificadores por país** em `server/data/game/countries.json`:
  - imposto sobre itens, passaporte e viagem;
  - preço próprio do passaporte do país;
  - margem da loja.

  Hoje todos os países usam `default` (imposto zero, margem 1). O país que vale é o da transação: a loja onde se compra, o aeroporto de saída, a caixa de vendas no país do jogador.
- **Histórico:** cada transação grava o **país**, o **preço** e o **imposto** (migração 0007). Na venda, o jogador recebe o preço menos o imposto; na compra, paga o preço mais o imposto.
- **Cofre do país:** tabela `treasuries`, com saldo por país. O imposto de cada transação vai para lá (hoje sempre zero). Não há interface.
- **O nome do dinheiro** fica em `economy.json` (`currency`: singular, plural, símbolo e o apelido que os NPCs usam, "goblinhos").

## Como isso sustenta o governo de cada país

- Eleger um governo vira uma tabela de mandatos por país. O que ele decide (impostos, preço do passaporte, margem da loja) é escrito no lugar de `countries.json`, que passa a ser um padrão. A função de preço não muda.
- O cofre já recebe os impostos. Gastar o dinheiro do cofre (obras públicas, prêmios, o mercado público) é só mais um tipo de transação.
- O histórico por país permite mostrar a cada governo quanto o país arrecadou e com o quê.

## Consequências

- Preço que não passar por `Service.Price` é um erro de revisão: o teste de cada contexto confere país, imposto e cofre (`TestPriceUsesCountryModifiers`).
- Com imposto maior que zero, o total arredonda por item. Uma venda grande pode diferir de alguns gobolares da conta "total × taxa"; o histórico guarda o que de fato foi cobrado.
