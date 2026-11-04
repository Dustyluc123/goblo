# Folclore do Goblo (fase 4.5)

Criaturas raras e fofas, inspiradas em **lendas populares de domínio público**, que aparecem de vez em quando no país de origem. Não atacam; somem se o jogador chega perto demais. O desafio é fotografar de longe para a seção **Lendas** da Goblopédia. Regras e números em `server/data/game/folklore.json`; decisão em [ADR 0058](decisoes/0058-folclore-animais-do-mundo-e-criaturas-em-codigo.md).

## Regras

- Só lendas e tradições populares de domínio público. **Nenhum personagem com direitos autorais** (de livros, filmes, desenhos, marcas).
- **Nada assustador:** todas são versões fofas e simpáticas.
- **Nada sagrado ou religioso** de nenhum povo (divindades, espíritos de cultos, figuras de religiões vivas).
- Sem estereótipos de povos e culturas: as criaturas são bichos e seres da história, não retratos de gente.

## As lendas

| Lenda | País | Origem | No Goblo |
| --- | --- | --- | --- |
| **Mula sem Cabeça** | Brasil | Lenda popular brasileira, contada no interior desde o período colonial: uma mula que galopa à noite, com fogo no lugar da cabeça. | Uma mulinha marrom com uma chama azul mansa no lugar da cabeça, nos campos e matas, à noite. |
| **Saci** | Brasil | Figura do folclore brasileiro (raízes tupi-guarani, com influências africanas e europeias): um menino travesso de uma perna só e gorro vermelho que vive nos redemoinhos. | Mostrado como um redemoinho de poeira com o gorro vermelho e olhinhos, à tarde. Sem cachimbo e sem retrato de pessoa. |
| **Pé-Grande** | Estados Unidos | Lenda moderna das florestas do noroeste da América do Norte: um gigante peludo e esquivo. | Um gigante peludo e tímido nas florestas e montanhas, de dia. |
| **Jackalope** | Estados Unidos | História popular do oeste americano (Wyoming): uma lebre com chifres de veado. | Uma lebre de chifrinhos nas pradarias e desertos, de manhãzinha. |
| **Wolpertinger** | Alemanha | Criatura do folclore da Baviera, misturando partes de vários bichos (coelho, chifres, asas). | Um coelhinho com asinhas e chifrinhos nos bosques, ao entardecer. |
| **Alebrije** | México | Tradição do artesanato popular mexicano (século XX): bichos fantásticos, coloridos e cheios de padrões. | Um bichinho de cores vivas, listras, espinhos e asinhas, de dia. |
| **Monstro do lago Ness** | Reino Unido (Escócia) | Lenda das terras altas da Escócia: uma criatura de pescoço comprido no lago Ness. | Só a cabeça e o pescoço aparecem na água, na costa da Escócia (latitude acima de 55° N). |
| **Leprechaun** | Irlanda | Ser do folclore irlandês: um sapateiro miudinho que guarda um pote de ouro. | Um sapateiro de casaco e cartola verdes com um pote de moedas, nos campos, de dia. |
| **Troll da montanha** | Noruega | Seres das histórias populares escandinavas que vivem nas montanhas. | Um troll grandalhão e musgoso, de bom humor, ao entardecer. |
| **Pássaro de fogo** | Rússia | Ave mágica dos contos populares russos, de penas que brilham como brasa. | Um pássaro laranja e dourado de cauda longa, nos bosques, ao entardecer (o mais raro). |
| **Tanuki** | Japão | Cão-guaxinim dos contos populares japoneses, brincalhão e mestre do disfarce (com uma folha na cabeça). | Um tanuki com a folhinha na cabeça, nas matas e montanhas, à tarde e à noite. |

## Ficaram de fora

- **Curupira** (Brasil): o briefing sugeria, mas ele vem da crença dos povos tupi como protetor da floresta, e isso se aproxima da regra "nada sagrado de nenhum povo". Melhor não usar sem consultar quem conhece a tradição.
- Lendas que são figuras de religiões ou espíritos de culto, criaturas assustadoras (fantasmas, assombrações) e personagens de livros ou filmes.

## Para acrescentar uma lenda

1. Uma entrada em `server/data/game/folklore.json` (id `legend_…`, nome, país, historinha, biomas, horas, chance, duração, cores).
2. O modelo em `client/scripts/creature_models.gd` (`IDS` e um caso em `_spec`) e a altura em `client/scripts/legends.gd`.
3. Uma linha nesta tabela, com a origem.
4. `go test ./internal/game -run Legend` confere que ela tem onde aparecer só no país dela.
