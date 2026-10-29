# Briefing — Fase 2.5: explorar e colecionar

> Cole este arquivo inteiro no Claude Code. Salve uma cópia em `docs/briefing-fase-2-5.md` (não deixe na raiz).

## Contexto

As Fases 2, 2.1 e 2.2 estão impecáveis. **Não mexa no que funciona.** Esta fase dá motivos para sair do lote e rodar o globo: **animais, álbum de fotos, estações do ano reais, fronteiras mais precisas, dinheiro, aeroporto e passaportes.**

Regras de sempre (todas no `CLAUDE.md`): commits pequenos em português, testes passando, push no final, nenhuma menção a outros jogos, testes só em `--headless` e **perguntar antes de abrir o Godot com janela**, nada de `osascript`/permissões do Mac. Desempenho: não pode piorar de forma perceptível; meça o custo dos animais em `--headless` quando possível e deixe a medição com janela para eu rodar com `client/tools/medir_fps.sh`.

Tudo que for número de jogo (preços, recompensas, distâncias, quantidades) fica em **arquivos de dados no servidor** (`server/data/game/`), não no código.

## Ordem sugerida

1. Fronteiras mais precisas → 2. Dinheiro → 3. Animais → 4. Goblopédia e câmera → 5. Estações do ano → 6. Aeroporto, viagem e passaportes → 7. Modo dev, testes e documentação.

## 1. Fronteiras mais precisas (fazer primeiro)

Quando ando perto de uma fronteira, muitas vezes sinto que, na vida real, eu estaria no país X, mas o jogo diz Y.

**Causa provável:** o país é decidido **por hexágono**, e cada hexágono tem uns 20 a 25 unidades de largura, ou seja, **cerca de 140 km** na escala do jogo (1 unidade ≈ 6,4 km). Além disso, os dados são do Natural Earth 1:110m, que é bem grosseiro.

O que fazer:
- Trocar para dados mais detalhados do **Natural Earth (1:10m ou 1:50m)** para os países. Escolha pelo equilíbrio entre precisão e tamanho; documente num ADR.
- **O país passa a ser decidido pela posição exata do jogador** (latitude/longitude), por teste de ponto em polígono, e não mais pelo hexágono. O hexágono continua tendo um "país principal" (para o bioma, os lotes e o mini mapa), mas o HUD, os carimbos e a regra de passaporte usam a posição exata.
- O servidor monta um **índice espacial** dos polígonos para a consulta ser rápida, e envia ao cliente, por pedaços, as **linhas de fronteira simplificadas** perto do jogador.
- **Linha de fronteira visível no chão**: uma faixa discreta e fofa (tracejada, com pequenos marcos) onde a fronteira passa, e uma plaquinha "Bem-vindo à Argentina" ao cruzar.
- Países pequenos que hoje não aparecem (por exemplo, os que somem no 1:110m) passam a existir.
- **Testes em Go** com pontos uns 20 a 30 km dentro de cada lado de fronteiras conhecidas, por exemplo:
  - Foz do Iguaçu (BRA) × Ciudad del Este (PRY) × Puerto Iguazú (ARG);
  - Corumbá (BRA) × Puerto Quijarro (BOL);
  - Tabatinga (BRA) × Letícia (COL);
  - Strasbourg (FRA) × Kehl (DEU);
  - um ponto no interior de um país pequeno (ex.: Luxemburgo).
- Para áreas disputadas, use a versão padrão do Natural Earth e registre isso no README, sem tomar lado.

## 2. Dinheiro (versão inicial)

Viajar e comprar passaporte custam dinheiro, então precisamos de uma economia mínima agora. A loja completa e a troca entre jogadores continuam na Fase 4.

- Moeda com **nome provisório "moedas"**, configurável num arquivo de dados (vou escolher um nome depois). Ícone simples e fofo.
- Saldo guardado **no servidor** (fonte da verdade), mostrado no HUD.
- **Como ganhar:**
  - **Caixa de vendas** no lote (fabricada na bancada, ou já presente): coloco itens nela e recebo na hora. Preços por item no arquivo de dados (madeira, pedra, flor, fruta, coco etc.).
  - **Recompensa por registro novo na Goblopédia** (primeira foto de cada espécie).
  - **Primeiro carimbo** de cada país no passaporte dá uma pequena recompensa.
- Histórico de transações no servidor (para depurar e para a Fase 4).
- **Testes:** não dá para gastar o que não tem; venda credita o valor certo; recompensas não se repetem.

## 3. Animais

Use os 12 animais do **Ultimate Animated Animals** (já em `client/assets/`, convertidos para GLB), com as animações `Idle`, `Idle_2`, `Walk`, `Gallop`, `Eating`, `Jump` etc.

**Onde vivem** (num arquivo de dados para eu ajustar):

| Bioma | Animais |
|---|---|
| `grassland` | vaca, touro, cavalo, cavalo branco, burro |
| `forest` | cervo, alce-macho (*Stag*), raposa |
| `tropical_forest` | cervo, raposa (provisório, até termos animais tropicais) |
| `mountain` | alpaca |
| `tundra` | lobo, husky |
| perto dos bairros (qualquer bioma agradável) | shiba, husky |
| `desert`, `ice`, `beach` | raros ou nenhum por enquanto |

**Os mesmos para todos os jogadores:**
- O **servidor** define, de forma determinística por célula, quais animais existem ali (espécie, `id` estável, área de passeio).
- A **posição em cada instante** é calculada por uma função determinística do `id` do animal e do **horário do servidor** (caminhadas, pausas para pastar, voltas na área de passeio). Assim todos os jogadores veem o mesmo animal no mesmo lugar, **sem o servidor simular nada**. Registre num ADR.
- Reações locais (fugir, chegar perto) são um desvio temporário só para quem está ali; depois o animal volta suavemente ao trajeto comum. Documente como isso vai funcionar no multiplayer.

**Comportamento:**
- Andam pelo terreno (alinhados à superfície da esfera), evitam oceano, casas, lotes e árvores grandes, e não sobem montanhas íngremes.
- **Tímidos** (cervo, alce, raposa, lobo): fogem galopando se eu correr perto; deixam chegar se eu andar devagar ou ficar parado.
- **Mansos** (vaca, cavalo, burro, alpaca, shiba, husky): deixam chegar sempre.
- Transições suaves entre animações.

**Interação** (tecla E perto do animal):
- **Fazer carinho:** animação curta do personagem, coraçõezinhos e o animal reage (`Idle_2` ou um pulinho).
- **Dar frutinha** (se tiver no bolso): o animal come (`Eating`) e fica **amigo** por um tempo, seguindo o jogador por alguns segundos.
- Nunca há forma de machucar os animais. **Não use** as animações `Attack` e `Death`.

**Desempenho:**
- Carregar animais só perto do jogador (raio próprio), com LOD de animação (animais longe atualizam menos vezes por segundo) e limite de quantos animados ao mesmo tempo.
- Preferência por poucos animais bem posicionados em vez de muitos espalhados.

## 4. Goblopédia e câmera fotográfica

- **Câmera fotográfica:** item fabricado na bancada (receita no arquivo de dados), que vai para a barra rápida.
- Com a câmera na mão, **clique direito** entra no modo foto: visão por cima do ombro com moldura, zoom com a roda do mouse e o clique tira a foto. O cursor fica preso, como no jogo normal.
- A foto é salva em `user://fotos/` (com miniatura). Se tiver um animal enquadrado (perto do centro e visível), ele é **registrado** na Goblopédia.
- **Goblopédia** (tecla **G**): álbum bonito com uma página por espécie. Mostra a primeira foto que tirei, o bioma e o país onde fotografei, quantas vezes vi e se já somos amigos. Espécies não descobertas aparecem como silhueta com "???".
- Além dos animais: **flores raras** (uma cor rara de flor que aparece pouco) e **árvores em estação** (primeira foto de uma árvore de outono e de uma com neve).
- O progresso da Goblopédia fica no servidor; as imagens ficam só no meu computador.
- Recompensa em moedas pelo primeiro registro de cada coisa.

## 5. Estações do ano reais

- A estação vem da **data real (UTC)** e do **hemisfério**: hoje (fim de outubro) é **primavera no sul e outono no norte**.
- **Temperado e boreal** (`forest`, `grassland` fora dos trópicos, `tundra`, `mountain`):
  - primavera: mais flores e verde claro;
  - verão: verde pleno;
  - outono: árvores trocadas pelas versões `*_Autumn_*`, chão com tons dourados e folhas caídas;
  - inverno: árvores e pedras nas versões `*_Snow_*` ou `*_Dead_Snow_*`, **chão branco** e flocos de neve caindo (partículas leves, ligadas à qualidade).
- **Trópicos** (`tropical_forest`, `beach` e o que estiver entre os trópicos): quase não mudam.
- Transições graduais nas viradas de estação (não trocar tudo de um dia para o outro).
- As árvores interativas continuam com o mesmo `id`; só muda o modelo/visual.
- O mini mapa e a visão afastada do globo mostram a diferença entre hemisférios.
- **Testes:** dado uma data e uma latitude, a estação está certa (ex.: 15 de janeiro em Berlim = inverno; em São Paulo = verão; em Manaus = sem estação marcada).

## 6. Aeroporto, viagem e passaportes

**Aeroportos:**
- Um por país, perto da **capital** (use a camada de lugares povoados do Natural Earth para achar as capitais). Países muito pequenos podem compartilhar ou ter só um ponto de chegada simples.
- Prédio montado com o Fantasy Town Kit (terminal pequeno, pátio, uma pista feita com peças de caminho, biruta). Não temos avião; tudo bem.
- Marcador do aeroporto no mini mapa e no globo afastado.

**Viagem:**
- No balcão do aeroporto (E), abre o menu: lista de países pesquisável, **preço** (por distância, no arquivo de dados) e se eu tenho o passaporte de lá.
- Ao confirmar: tela escurece levemente, a câmera faz **zoom out** até o globo, desenha um **arco** do aeroporto de origem até o destino com um pontinho viajando (alguns segundos, com a hora do dia correta passando pelo globo), e faz **zoom in** no aeroporto do destino.
- **H** (voltar para casa) continua funcionando de qualquer lugar, **por enquanto**.

**Passaportes:**
- Para **entrar** em um país (a pé ou de avião), preciso do **passaporte daquele país**. O do meu país de residência é grátis e já vem comigo.
- Passaportes são comprados **no aeroporto** (preço no arquivo de dados). Ao comprar um passaporte do destino junto com a passagem, mostre o total.
- **A pé:** ao chegar na fronteira sem o passaporte daquele país, uma barreira suave me impede de passar e aparece uma mensagem fofa ("Para entrar no Paraguai você precisa do passaporte. Ele pode ser comprado em qualquer aeroporto.").
- **Livro de passaporte** (tecla **P**): uma página por país visitado, com um **carimbo** único gerado para cada país (cores e formas variadas, com o nome e a data da primeira visita). Também mostra os passaportes que tenho.
- Entrar a pé em outro país (com passaporte) **também conta carimbo**.
- O servidor valida tudo: saldo, passaporte, viagem. Como o servidor ainda não sabe a posição do jogador em tempo real, a barreira de fronteira fica no cliente por enquanto; documente no ADR que a validação no servidor entra no multiplayer.

## 7. Modo dev (F1), testes e documentação

Adicione ao painel dev:
- dar moedas;
- dar ou remover passaportes;
- **desligar a barreira de fronteira**;
- **forçar data/estação** (e voltar para a data real);
- mostrar/ocultar as linhas de fronteira e os polígonos de debug;
- criar animais perto de mim e listar os animais carregados;
- completar ou resetar a Goblopédia e o passaporte;
- viajar para qualquer aeroporto de graça.

**Testes em Go:** fronteiras (pontos acima), dinheiro, preço de viagem, passaporte obrigatório, carimbo único por país, animais determinísticos (mesmo `id` e mesma posição no mesmo horário), estações por data e latitude, recompensas sem repetição.

Atualize `README.md` (novas teclas: G Goblopédia, P passaporte, câmera), `docs/CONTEUDO.md` (preços, receitas, animais por bioma, recompensas), `docs/API.md` e os ADRs.

## Fora do escopo agora

Loja de itens e troca entre jogadores (Fase 4), multiplayer em tempo real (Fase 3), animais novos (vamos baixar mais pacotes depois), pesca, interior da casa, sons e música, redesenho geral da interface, carros e barcos.

## No final

Diga o que mudou, como testar cada parte pelo modo dev (passo a passo), o que precisa de assets novos, as decisões tomadas sozinho e o que ficou pendente. Liste também o que ficou **sem verificação visual** por não ter aberto o jogo com janela.
