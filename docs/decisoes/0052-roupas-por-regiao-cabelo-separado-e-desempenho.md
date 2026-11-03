# 0052 — Roupas que substituem a original, cabelo separado da cabeça e orçamento dos efeitos

**Fase 4.1.** Corrige a 0051 (visual do personagem) e acerta o custo das coisas da 4.0.

## O que estava errado

- **Paleta lida errado.** A 0051 tratava a textura do Mini Characters como uma grade 4 × 4. Ela tem **16 faixas × 4 linhas** (cada faixa, 32 px, é uma cor em degradê): um "quadrado" da 4.0 juntava quatro cores. Por isso a pele e a roupa caíam no mesmo quadrado, e o tom de pele e a cor do cabelo erravam em algumas cabeças.
- **Capa pintando o corpo inteiro.** O corpo (`character_look.gdshader`: `skin_color`, `hair_color`) e a capa (`character_cape.gdshader`: `wave`) são duas superfícies **da mesma instância**, e os parâmetros por instância dos dois usavam o índice 0. A capa escrevia por cima da cor da pele.
- **Roupa por cima da roupa.** As peças eram cascas por cima do corpo, que já vem vestido: a regata aparecia junto da camiseta original.

## Decisão

- **Paleta:** 16 × 4. As faixas de pele são as seis últimas da linha de baixo (fixas, sem adivinhar pelo tom).
- **Parâmetros por instância com índice fixo:** `skin_color` 0, `hair_color` 1, `wave` 2 (`instance_index`). O `tests/test_roupas.gd` confere que nenhum parâmetro por instância fica sem índice ou repete.
- **Roupa substitui a região (recolorir, sem malha a mais).** Escolhido entre máscara no shader, peça base neutra e recorte das malhas: recolorir os triângulos da região é o mais leve (a malha fica do mesmo tamanho; a 4.0 dobrava os vértices com as cascas) e fica igual ao estilo facetado do pacote. A cor é decidida **por triângulo** (pelo centro dele): as peças do Mini Characters são caixas com poucos vértices, e pintar por vértice virava degradê.
  - Corpo: casaco e poncho pintam tronco e braços (as mãos ficam); regata pinta o tronco e deixa os braços com a pele; o poncho ganha só uma aba (casca) no tronco. O **cachecol** é de pescoço: não esconde a camiseta.
  - Pernas: calça pinta a perna e a cintura (a parte do tronco abaixo do quadril, onde fica o calção ou a saia); short pinta a cintura e a coxa e deixa a canela com a pele.
  - Pés: bota pinta o pé e o cano; sandália deixa o pé com a pele e põe a sola.
  - Pele que aparece onde havia roupa usa um ponto de pele da própria parte: sem tom escolhido, fica com a pele original.
  - Espaço vazio: a roupa original continua.
  - As tampas de cima das pernas (escondidas no quadril do próprio personagem) ficam de fora: com o tronco de outro, apareciam como um aro escuro.
- **Cabelo separado pela forma, não pela cor.** As 12 cabeças têm o **mesmo crânio** (uma caixa chanfrada de x ±0,165, y 0,338–0,666, z −0,167–0,162; orelhas até ±0,232). Triângulo com algum vértice fora do crânio, do rosto (frente, abaixo da franja) e das orelhas é cabelo. A cabeça escolhida entra sem ele, com o alto, os lados e a nuca do crânio na cor da pele (a franja pintada na testa também). Funciona nas 12: `male-b` é careca (só barba, que fica no rosto) e o "cabelo" da `male-c` é um quepe, que vira o acessório `cap-male-c`. Visual novo: `Look.Haircut` (`""` = o da própria cabeça, `"none"` = sem cabelo, ou a cabeça de onde vem o cabelo).
- **Chapéus no osso da cabeça, no alto do crânio.** Ponto de encaixe e ajuste por cabeça (posição, escala, giro) em `client/data/cabecas.json`. Nada mexe nos vértices da cabeça. Com chapéu (ou quepe), o cabelo acima de `hair_cut` desce até essa altura e entra para dentro do chapéu (versão achatada); penteados extras, só o rabo de cavalo.
- **Primeiro acesso:** apelido e país, e logo depois o editor, obrigatório, antes de entrar no mundo. A lista de personagens prontos saiu (primeiro acesso e F6).
- **Orçamento dos efeitos (por qualidade, `quality.gd`):**
  - fogueiras: luz sem sombra, alcance 4, só as `fire_lights` mais perto da câmera acendem (0, 2, 3) e só as que estão a até `fx_radius` soltam fogo;
  - partículas (fogo, vapor, suor): quantidade × `particles`;
  - flores decorativas: densidade `flower_density` e distância `flower_radius` próprias, menores que as da grama;
  - objetos pequenos do servidor (flores para colher, galhos, pedrinhas, ingredientes, que a 4.0 dobrou): sem sombra e só até `small_objects_radius`;
  - tela zonza: não lê mais a tela (só cantos escuros), e só fica visível com fome no mínimo;
  - lugares do E (fogueira, fonte, espelho dos lotes): em cache por 0,5 s em vez de varrer todos os lotes a cada quadro;
  - prévia do personagem: a SubViewport para de desenhar quando a janela está fechada.

## Consequências

- Peça nova de roupa: item com `wear` em `items.json` e a regra da região em `CharacterLook` (`_body_color`, `_legs_color`) ou a forma presa a um osso (`_add_hat`, `_build`). O `tests/test_roupas.gd` garante que ela só muda as regiões do próprio espaço.
- Cabeça nova do pacote: se o crânio for o mesmo, o cabelo sai sozinho; se não, ajuste `SKULL_MIN`/`SKULL_MAX` (veja `tools/analisar_cabecas.gd`).
- Cabelos achatados embaixo do chapéu ficam com o alto reto (escondido pelo chapéu); um coque grande atrás aparece como uma aba reta na nuca.
- Os bots do modo dev ganham um visual sorteado com roupas (`DevRandomLook`), para o teste de multidão e o `--profile-scene --bots=N` medirem o custo real.
