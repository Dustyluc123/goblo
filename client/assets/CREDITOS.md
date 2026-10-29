# Créditos dos assets

Todos os pacotes abaixo estão sob licença **Creative Commons Zero (CC0)**: podem ser usados em projetos pessoais, educacionais e comerciais, sem obrigação de atribuição. Damos o crédito mesmo assim. Obrigado, Kenney e Quaternius!

## Kenney ([www.kenney.nl](https://www.kenney.nl))

| Pacote | Versão | Pasta | O que copiamos | Uso |
| --- | --- | --- | --- | --- |
| [Mini Characters](https://kenney.nl/assets/mini-characters) | 1.0 | `kenney/mini-characters/` | modelos GLB + `Textures/colormap.png` | personagem jogável (fase 1) |
| [Fantasy Town Kit](https://kenney.nl/assets/fantasy-town-kit) | 2.0 (03/08/2025) | `kenney/fantasy-town-kit/` | `GLB format/` + `Textures/` | casas montadas peça por peça e decorações do lote (fase 2) |
| [Mini Forest](https://kenney.nl/assets/mini-forest) | 1.0 | `kenney/mini-forest/` | modelos GLB + `Textures/colormap.png` | vegetação da fase 1.5; guardado desde a fase 2 |
| [Graveyard Kit](https://kenney.nl/assets/graveyard-kit) | 5.0 | `kenney/graveyard-kit/` | modelos GLB + `Textures/colormap.png` | pinheiros e pedras da fase 1.5; guardado desde a fase 2 |
| [Car Kit](https://kenney.nl/assets/car-kit) | 02/04/2026 | `kenney/car-kit/` | `GLB format/` + `Textures/` | guardado para o futuro (carros) |
| [Watercraft Pack](https://kenney.nl/assets/watercraft-pack) | 19/04/2024 | `kenney/watercraft-pack/` | `GLB format/` + `Textures/` | guardado para o futuro (barcos) |
| [Monster Builder Pack](https://kenney.nl/assets/monster-builder-pack) | 1.0 | `kenney/monster-builder/` | `PNG/` (2D) | guardado, ainda sem uso |

## Quaternius ([quaternius.com](https://quaternius.com), [patreon.com/quaternius](https://www.patreon.com/quaternius))

| Pacote | Versão | Pasta | O que copiamos | Uso |
| --- | --- | --- | --- | --- |
| [Ultimate Nature Pack](https://quaternius.com/packs/ultimatenature.html) | junho de 2019 | `quaternius/ultimate-nature/` | só `FBX/` (o Godot 4 importa FBX direto) | árvores, pedras, arbustos, flores, grama e enfeites de todos os biomas (fase 2); as versões de outono e neve ficam para as estações da fase 2.5 |
| [Ultimate Animated Animals](https://quaternius.com/packs/ultimateanimatedanimals.html) | julho de 2021 | `quaternius/ultimate-animated-animals/` | `glTF/` convertido para `.glb` ([ADR 0023](../../docs/decisoes/0023-animais-convertidos-para-glb.md)) | guardado para a fase 2.5 (animais andando pelos biomas) |

O `License.txt` original de cada pacote está na pasta dele. Licença CC0: <https://creativecommons.org/publicdomain/zero/1.0/>.

Do Graveyard Kit (tema de Halloween), nada de abóboras, lápides, cruzes, caixões ou caveiras no mundo por enquanto ([ADR 0017](../../docs/decisoes/0017-pacote-de-halloween.md)).

Não copiamos as versões FBX e OBJ da Kenney, os `OBJ/` e `Blends/` do Quaternius, as prévias (imagens e `Preview.mp4`) nem os arquivos de vetor e spritesheet. Os pacotes originais baixados (`kenney_*/`, `Ultimate */`) ficam fora do Git. Para atualizar um pacote, baixe de novo e copie só as mesmas pastas.

## Outros modelos

A bancada, o machado, a picareta e o coco não existem nos pacotes: são modelos low-poly simples feitos em código (caixas e cilindros), em `client/scripts/model_library.gd` (`primitive:…`).
