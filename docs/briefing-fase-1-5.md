# Briefing — Fase 1.5: um mundo de verdade

> Cole este arquivo inteiro no Claude Code, na pasta do projeto. Peça para ele salvar uma cópia em `docs/briefing-fase-1-5.md` antes de começar.

## Contexto

A Fase 1 está pronta e funcionando bem: globo de hexágonos gerado pelo servidor em Go, personagem da Kenney andando na esfera com animações, câmera com zoom, HUD. **Não refaça o que funciona.** Esta fase transforma o globo pequeno num mundo que dá vontade de explorar.

Feedback do teste da Fase 1:
- o movimento está fluido e gostoso; **mantenha a sensação**;
- falta **pulo**;
- o globo está **pequeno demais** em relação ao personagem: atravessar países é rápido demais para um MMO;
- o chão verde liso é sem graça; quero **grama, árvores e pedras em 3D** usando os pacotes da Kenney que estão no repositório.

Lembrete: meu Mac é **Intel** (provavelmente com GPU integrada). O jogo precisa rodar liso nele. Desempenho é requisito desta fase, não detalhe.

## Repositório e Git

Mesmas regras da Fase 1: commits pequenos, em português, um por etapa lógica; `go test ./...` e `go vet ./...` passando antes de cada commit; push no `main` no final. Atualize `README.md`, `CLAUDE.md` e os ADRs em `docs/decisoes/`.

## 1. Pulo

- Espaço pula. Use as animações `jump` e `fall` do personagem e volte para `idle`/`walk`/`sprint` ao pousar.
- O pulo é sempre na direção "para cima" local (para longe do centro do planeta), com a gravidade radial que já existe.
- Sem pulo duplo. Um pouco de *coyote time* (uns 0,1 s) e *jump buffer* para o pulo ficar responsivo.
- Altura do pulo suficiente para subir o degrau entre hexágonos de alturas diferentes, mas não para pular montanhas.

## 2. Escala: um globo maior

**Meta:** andar de São Paulo até a fronteira da Venezuela (perto de Pacaraima, 4,5° N, 61,1° O) deve levar **cerca de 1 min 30 s a 2 min andando** e menos de 1 min correndo. Isso dá um **raio de planeta em torno de 1.000 unidades** com o personagem de cerca de 1 unidade de altura (ajuste a velocidade e o raio para bater a meta).

- Raio e velocidades configuráveis num lugar só.
- **Meça** o tempo real do trajeto SP → Venezuela (pode ser um teste automatizado ou um cálculo documentado) e registre no README.
- Verifique a precisão de ponto flutuante nessa escala (não pode haver tremedeira no personagem nem na câmera).
- A câmera precisa continuar indo do personagem até a visão do planeta inteiro (ajuste `far`, a velocidade do zoom e a suavidade para a nova escala).

### Grade mais detalhada

Com o globo maior, os hexágonos ficariam enormes e o litoral viraria uma escadinha. Aumente a frequência da grade de `n = 20` para **`n = 50`** (25.002 células, com cada hexágono tendo umas 20 a 25 unidades de largura). Mantenha configurável.

- Cada hexágono passa a ser uma **"região"** (com país e bioma). Na Fase 2 haverá uma grade fina de construção dentro dele; **não implemente isso agora**, mas não feche essa porta.
- O formato atual do `/world` em JSON provavelmente fica grande demais. Crie um formato compacto (por exemplo binário, com gzip) para o cliente, mantendo um modo JSON para depuração. O mundo tem uma **versão/hash**; o cliente pode guardar em cache local e só baixar de novo quando a versão mudar.
- Meça e registre o tamanho do download e o tempo de geração no servidor e de carregamento no cliente.

## 3. Biomas (no servidor)

O servidor passa a atribuir um **bioma** a cada célula de terra, e uma **altura** coerente com ele. Biomas sugeridos:

| Bioma | Onde, aproximadamente |
|---|---|
| `ocean` | oceano (como hoje) |
| `beach` | terra vizinha de oceano em clima quente |
| `tropical_forest` | Amazônia, Congo, Sudeste Asiático |
| `forest` | florestas temperadas (Europa, leste dos EUA etc.) |
| `grassland` | campos, savanas, cerrado, pampas |
| `desert` | Saara, Arábia, Atacama, centro da Austrália etc. |
| `mountain` | Andes, Himalaia, Alpes, Rochosas |
| `tundra` | norte do Canadá, Sibéria |
| `ice` | Antártida, Groenlândia, polos |

Como decidir: comece por latitude, distância do litoral e regras simples, e refine com dados geográficos gratuitos. O Natural Earth tem polígonos de regiões geográficas (desertos, cordilheiras etc.) que podem ajudar; se não servirem, use regras e polígonos aproximados desenhados à mão para as regiões principais. Documente a fonte e o método em `docs/`. Não precisa ser perfeito, precisa ser **reconhecível e bonito**.

A altura das células varia por bioma (montanhas bem mais altas, praia quase no nível do mar), com degraus suaves entre vizinhos.

**Testes em Go (adicionar):**
- número de células = `10·n² + 2` para `n = 50`;
- São Paulo (-23,55, -46,63) é terra, `BRA`, e **não** é deserto nem gelo;
- Amazônia (-3, -60) é `tropical_forest`;
- Saara (23, 13) é `desert`;
- Himalaia (28, 85) é `mountain`;
- Antártida (-80, 0) é `ice`;
- determinismo continua valendo.

## 4. Vegetação e decoração 3D

Coloquei **mais pacotes da Kenney** na pasta do projeto, com natureza (grama, árvores, pedras e afins) e um pacote com tema de Halloween que também tem grama e pedras. **Procure-os no repositório**, organize como fizemos antes (só `GLB format/` + `Textures/` + `License.txt` em `client/assets/kenney/<nome-do-pacote>/`; nada de FBX, OBJ, Previews, `__MACOSX` ou `.DS_Store`; depois remova as pastas originais do Git) e atualize `client/assets/CREDITOS.md` e o README.

- Do pacote de Halloween, use **só itens neutros** (pedras, grama, troncos, arbustos). Nada de abóboras, lápides, caveiras etc. no mundo por enquanto.
- **Não substitua o chão pelos modelos.** O chão continua sendo a malha do globo, com cor por bioma (pode ganhar uma textura ou um ruído sutil para não ficar chapado). Os modelos são **espalhados por cima**, como decoração.
- Cada bioma tem sua lista de modelos e densidades: floresta tropical densa, deserto com pedras e quase nada verde, campo com grama e flores, montanha com pedras, tundra rala, gelo quase vazio.
- **Espalhamento determinístico:** a posição, rotação e escala de cada objeto vêm de uma semente baseada no `id` da célula, para que **todos os jogadores vejam exatamente as mesmas árvores** no futuro multiplayer. Documente isso num ADR.
- **Só perto do jogador:** carregue a vegetação por pedaços (as células num raio em volta do personagem) e descarregue o que fica longe. Use `MultiMeshInstance3D` (um por tipo de modelo e pedaço) para desempenho. Grama some mais cedo que árvores. No zoom afastado, nada de vegetação individual.
- Árvores grandes e pedras grandes têm colisão simples (cilindro ou caixa) perto do jogador; grama e flores não têm colisão.
- A colisão do chão também deve ser por pedaços perto do jogador, se a colisão do globo inteiro ficar pesada.
- Uma configuração de **qualidade** (baixa, média e alta) controla a densidade e a distância da vegetação. O padrão deve rodar liso no meu Mac Intel.

## 5. Dia e noite de verdade

- A posição do sol vem do **horário real (UTC)**: calcule o ponto subsolar (latitude pela declinação solar do dia do ano, longitude pela hora UTC) e aponte a `DirectionalLight3D` a partir dele.
- No zoom afastado, dá para ver a **linha entre o dia e a noite** cruzando o globo.
- A noite tem que ser **aconchegante, não escura demais**: céu azul-escuro, luz ambiente fria suave e estrelas. O jogador tem que conseguir andar e ver o caminho à noite.
- O HUD mostra o **horário local aproximado** onde o personagem está (pela longitude; fusos reais ficam para depois).
- Um atalho de depuração (por exemplo F3) acelera o tempo para testar o ciclo, e outro volta para o horário real.

## 6. Oceano, nuvens e navegação

- **Oceano animado:** shader com ondinhas suaves, cor mais clara perto do litoral e mais escura no oceano aberto, brilho do sol e, se ficar bonito, espuma leve na costa. Nada de cor chapada.
- **Nuvens:** algumas nuvens low-poly fofas orbitando devagar acima do globo. Aparecem bonitas no zoom afastado e somem suavemente quando a câmera está perto do personagem (para não atrapalhar a visão).
- **Bússola:** no topo da tela, mostrando norte, sul, leste e oeste em relação à direção da câmera.
- **Mini mapa:** um globinho no canto da tela, sempre virado para a posição do jogador, com um ponto marcando onde ele está e a linha dia/noite visível.

## HUD (resumo)

País, bioma, latitude/longitude, horário local, bússola, mini mapa e os controles (WASD andar, Shift correr, **Espaço pular**, botão direito gira a câmera, roda do mouse dá zoom, F3 acelera o tempo).

## Desempenho

- Meta: **60 fps estáveis** no meu Mac Intel na qualidade padrão, andando por uma floresta tropical.
- Mostre um contador de fps opcional (atalho F2).
- Registre no README o que foi medido e as decisões de otimização.

## Fora do escopo agora (não implementar)

Construção e grade de construção, multiplayer, contas, banco de dados, moeda, fronteiras jogáveis, NPCs, áudio, fusos horários reais, estações do ano, luzes de cidade à noite, objetos temáticos de Halloween.

## Forma de trabalho

- Execute a fase inteira de uma vez e me entregue tudo pronto para revisar.
- Sugestão de ordem: pulo → escala e grade `n = 50` com formato compacto → biomas no servidor → assets e vegetação por pedaços → dia e noite → oceano e nuvens → bússola, mini mapa e HUD → medição de desempenho e documentação.
- Decisões que não estão aqui: escolha a opção mais simples, registre num ADR curto e siga.
- No final, me diga o que mudou, como testar (lembrando que o servidor precisa estar rodando antes do Play no Godot), as medições de desempenho e o que ficou pendente.

## Roadmap (para referência)

1. Fase 1: globo, personagem, servidor do mundo. ✅
2. **Fase 1.5: um mundo de verdade (escala, pulo, biomas, vegetação, dia e noite, oceano, nuvens, navegação).** ← agora
3. Fase 2: construir (terreno do jogador com grade fina dentro de uma região, cidades reais no mapa, construções salvas no servidor).
4. Fase 3: multiplayer.
5. Fase 4: fronteiras e moeda.
