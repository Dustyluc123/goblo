# 0051 — Visual do personagem: partes misturadas, roupas e capa numa malha só

**Fase 4.0.**

## O que os modelos do Mini Characters são

Investigado no começo da fase: cada personagem do pacote tem **um esqueleto de 7 ossos** (root, perna esquerda, perna direita, tronco, braço esquerdo, braço direito, cabeça), igual nos 12 (a diferença é de 2 mm num osso), e **duas malhas com pele (skin)**: `body-mesh` (tronco, braços e pernas) e `head-mesh` (cabeça **com o cabelo junto**). As cores vêm de uma textura de paleta 4 × 4 (cada quadrado é um degradê de uma cor).

## Decisão

- **Partes separáveis:** o editor mistura a cabeça (com o cabelo) de um personagem, o tronco e os braços de outro e as pernas de um terceiro. As pernas saem dos triângulos do `body-mesh` cujo osso dominante é uma perna. As animações são as do personagem do tronco (o esqueleto é o mesmo).
- **Pele e cabelo:** cada vértice é marcado pelo quadrado da paleta (pele: quadrados com tom de pele; cabelo: o mais usado no alto da cabeça, fora do rosto) e guarda o brilho dele em relação ao quadrado. O shader troca pela cor escolhida mantendo o sombreado. As cores são **parâmetros de instância**: um material só para todos os personagens.
- **Roupas** (`items.json → wear`, um item por espaço: cabeça, corpo, pernas, pés, costas): casaco, regata, poncho, calça, bermuda e botas são **cascas** copiadas dos triângulos do corpo, empurradas pela normal, com os mesmos pesos dos ossos (acompanham as animações); chapéus, cachecol, sandálias, penteados extras e óculos do pacote são formas simples presas a um osso.
- **Capa de bandeiras** (costas, vendida em todas as lojas): pano preso ao tronco com os retalhos das bandeiras dos carimbos (atlas da fase 3.6, até 12, os mais recentes), balançando mais quando o personagem anda.
- **Uma malha por personagem** (uma superfície; duas com a capa), montada numa thread (10 a 23 ms) e guardada pela combinação de partes, roupas e cores das roupas: jogadores iguais dividem a malha. Na thread principal fica menos de 1 ms. Antes eram duas malhas por personagem; agora é uma (menos chamadas de desenho).
- **Servidor:** guarda o visual e as roupas (`/look`, `/wear`, `/wear/remove`, `/wear/dye`) no corpo do jogador e manda a mensagem `look` para quem vê (também na entrada, `enter.look`). Vestir outra peça devolve a antiga ao bolso; a tinta (feita de flores) gasta uma unidade.

## Consequências

- Personagem novo do pacote entra sozinho, se tiver o mesmo esqueleto.
- Peça nova de roupa: item em `items.json` com `wear` e a forma em `CharacterLook` (casca pelo filtro de ossos ou forma presa a um osso).
- Algumas cabeças com boné ou cabelo do mesmo tom da pele recolorem menos exatamente (a classificação é pela paleta).
