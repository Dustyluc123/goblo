# Briefing — Fase 2.1: polimento da Fase 2

> Cole este arquivo inteiro no Claude Code, na pasta do projeto. Peça para ele salvar uma cópia em `docs/briefing-fase-2-1.md` antes de começar.

## Contexto

A Fase 2 (coletar e construir) está funcionando e eu testei. Esta fase **não adiciona conteúdo novo**: corrige os problemas que encontrei, melhora o desempenho e começa a deixar o jogo bonito. Só depois disso vamos para a Fase 2.5.

Regras de sempre: commits pequenos em português, `go test ./...` e `go vet ./...` passando, push no `main` no final, README, `CLAUDE.md` e ADRs atualizados.

## 0. Antes de tudo: conferir o trabalho interrompido

Eu pausei você no meio do último pedido (escala da interface, resolução 3D menor que a da tela e janela maximizada). A interface já está legível, mas **não sei se o resto foi concluído**. Rode `git status` e `git log`, veja o que ficou pela metade daquele pedido, termine e commite antes de começar esta fase. Me diga no final o que estava faltando.

## 1. Nenhuma menção a outros jogos

O jogo diz que "a casa fica pronta no dia seguinte, igual Animal Crossing". **O Goblo não pode citar nenhum outro jogo**: nem na interface, nem nos textos, nem no código (nomes de variáveis, funções, comentários, arquivos), nem no README, `CLAUDE.md`, ADRs, `docs/CONTEUDO.md` e briefings em `docs/`.

- Procure no repositório inteiro, sem diferenciar maiúsculas de minúsculas, por: `animal crossing`, `nook`, `stardew`, `minecraft`, `palia`, `zelda` e qualquer outro nome de jogo. Reescreva com termos próprios ("cozy", "aconchegante", "a obra fica pronta no dia seguinte").
- Adicione ao CI uma verificação que **falha** se algum desses nomes aparecer no código, nos textos do jogo ou na documentação (como a verificação de neutralidade que fiz em outro projeto).
- Registre isso no `CLAUDE.md` como regra permanente.

## 2. Câmera que não atravessa nada

Hoje a câmera entra nas casas e nos objetos. No meu teste, ela ficou **dentro da casa de outro jogador** com o meu personagem do lado de fora.

- A câmera nunca pode ficar dentro de uma malha. Use colisão da câmera (`SpringArm3D` ou um raio do personagem até a câmera), excluindo o próprio personagem: se algo bloquear, a câmera se aproxima do personagem com suavidade e volta para a distância normal quando o caminho fica livre.
- Objetos grandes entre a câmera e o personagem (casas, árvores grandes) ficam **semitransparentes** em vez de esconder o personagem. Grama e flores não bloqueiam a câmera.
- A câmera também não pode ficar abaixo do chão nem dentro do terreno ao girar perto de morros.
- Teste: andar encostado em casas, entrar no meio de uma floresta densa, girar a câmera com o personagem colado numa parede.

## 3. Texturas piscando nas casas (z-fighting)

Na casa, há partes em que duas faces ocupam o mesmo lugar e ficam "brigando": uma aparece e some enquanto a outra entra, principalmente nos cantos onde as paredes se encontram (madeira e pedra se alternando).

- Revise a montagem das três casas e de todas as decorações do Fantasy Town Kit: corrija peças sobrepostas nos cantos (use as peças de canto certas, `wall-*-corner*`, ou desloque/encurte as paredes para não haver faces coplanares).
- Confira também a borda do lote, os caminhos (`road*`) e o chão do lote contra o terreno.
- Capture a casa de cada nível de perto, de vários ângulos, e confira que não pisca.

## 4. Melhorar a casa diz que não há espaço

Construí a casa, ela ficou perfeita no lote, mas ao tentar melhorar aparece que **não há espaço**, mesmo sem nada atrapalhando.

- Provável causa: a verificação de espaço conta **a própria casa atual** como obstáculo. Na melhoria, a área da casa atual deve ser ignorada.
- Se a casa do próximo nível for maior, a área nova é calculada a partir da posição da casa atual (mantendo a porta no mesmo lado). Se não couber no lote por causa da borda, procure automaticamente a posição mais próxima que caiba.
- Se a área estiver ocupada por **decorações**, a mensagem diz **quais** objetos atrapalham, destaca-os em vermelho e oferece **guardá-los no bolso automaticamente** com um clique.
- Garanta que a casa grande caiba no lote 14 × 14 junto com algum espaço de quintal; se não couber, ajuste o tamanho do lote ou das casas e registre num ADR.
- **Testes em Go:** melhoria com a casa sozinha no lote funciona; melhoria com decoração no caminho falha com a lista dos objetos; melhoria perto da borda encontra posição válida.

## 5. Menus capturam o mouse e o teclado

Com a bancada aberta, rolar o mouse **mexe o zoom da câmera** em vez de rolar as receitas.

- Quando **qualquer** menu estiver aberto (bancada, bolso, modo construção com catálogo, painel dev, configurações, tela de primeiro acesso), a roda do mouse, os cliques e as teclas de movimento **não afetam o jogo**: a roda rola a lista do menu.
- Todo menu tem um **botão de fechar (X)** visível no canto superior direito, além do Esc. O texto "Esc fecha" vira uma dica pequena ao lado do botão, não a única forma de fechar.
- Centralize isso num lugar só (um gerenciador de interface que sabe se há menu aberto) em vez de corrigir menu por menu.

## 6. Desempenho (prioridade alta)

Meus números no Mac Intel (tela Retina, janela grande):
- **qualidade alta, no bairro:** 28 fps, 872 draw calls, 915 mil triângulos, 14.156 objetos;
- **qualidade média, perto das casas:** 47 fps, 299 draw calls, 282 mil triângulos.

Isso com **um jogador só** e o jogo ainda simples. O Goblo vai crescer (animais, mais construções, outros jogadores), então precisamos de folga. **Metas:** qualidade média com **60 fps estáveis** e qualidade alta com **no mínimo 45 fps**, ambas na janela grande do Mac Intel, no bairro com 20 vizinhos e na floresta tropical.

Antes de otimizar, **meça com o profiler do Godot** e me diga o que mais pesa (CPU ou placa de vídeo, sombras, vegetação, casas, transparência). Depois ataque, na ordem que o profiler indicar. Pontos que eu suspeito:

- **Casas montadas peça por peça:** cada casa do Fantasy Town Kit tem dezenas de peças, e cada peça é um draw call. Junte as peças de cada casa numa **malha única por material** (no carregamento ou pré-gerada por nível de casa). O mesmo vale para as decorações repetidas do lote: use `MultiMesh` quando houver várias iguais.
- **Distância de visão e LOD:** use `visibility_range` com *fade* (HLOD) para árvores, decorações e casas distantes, LOD automático de malha do Godot e, para árvores longe, versões simplificadas ou *impostors*.
- **Carregamento por pedaços (chunks):** revise o raio de carga de vegetação, objetos interativos e lotes. Hoje parece carregar coisas demais ao redor. Separe raios por tipo (grama perto, árvores médio, casas mais longe) e documente como isso vai funcionar no multiplayer (o servidor manda só os pedaços perto de cada jogador).
- **Sombras:** a sombra direcional costuma ser a coisa mais cara numa placa integrada. Ajuste a distância das sombras, o número de cascatas e quais objetos projetam sombra (grama nunca).
- **Occlusion culling:** avalie se compensa no bairro.
- **Resolução 3D:** confirme que a renderização 3D abaixo da resolução da tela (item 0) está ativa e ligada aos presets.

Atualize a tabela de desempenho do README com antes e depois, por qualidade e por lugar (floresta tropical, bairro com 20 vizinhos, visão afastada do globo).

## 7. Começar a deixar o jogo bonito

Hoje, mesmo na qualidade alta, tudo parece **chapado**. Sem trocar os modelos, o que mais muda a cara do jogo é **luz, atmosfera e movimento**. Implemente o que for barato primeiro, cada item ligado aos presets de qualidade:

- **Ambiente e luz:** `WorldEnvironment` com tonemapping (AgX ou Filmic), céu com gradiente bonito que muda com a hora do dia, luz do sol mais quente de manhã e no fim de tarde, luz ambiente vinda do céu e um leve *glow*.
- **Névoa de distância:** neblina suave que dá profundidade ao bairro e à floresta e esconde onde os pedaços terminam. É barata e muda muito o visual.
- **Oclusão de ambiente:** sombra suave onde os objetos encostam no chão e nos cantos. Pode ser SSAO na qualidade alta e algo mais barato (sombra falsa embaixo de árvores e casas, ou AO nos vértices) na média e na baixa.
- **Vento:** shader simples que balança a grama, as folhas das árvores e as flores. Quase de graça, e o mundo deixa de parecer parado.
- **Variação de cor:** pequenas variações de tom por instância de árvore, grama e pedra, e uma textura de ruído suave no chão, para quebrar as áreas lisas. A grama deve se misturar com a cor do chão.
- **Paleta:** revise as cores para ficarem harmônicas e pastel (o verde do chão, das árvores e da grama hoje não conversam bem).

Mande capturas de **antes e depois** do mesmo lugar e na mesma hora do dia (bairro de dia, floresta, fim de tarde e noite) e o custo de cada efeito em fps.

## 8. Minha casa no mini mapa

- O mini mapa (globinho no canto) mostra um **ícone de casinha** onde fica o meu lote, além do ponto do jogador.
- O ponto do jogador vira uma **setinha** que mostra para onde ele está virado.
- No zoom afastado do globo, um marcador discreto também mostra onde fica a minha casa.

## 9. Pendências da Fase 2

- **Relógio do modo dev:** depois de "avançar para o dia seguinte", deve haver um botão "voltar para a hora real" que funcione **sem reiniciar o servidor**.
- Remova o `briefing-fase-2.md` solto na raiz (a cópia está em `docs/`).

## 10. Testar sem roubar a minha tela (regra permanente)

Quando você abre o Godot para testar, a janela do jogo **vem para a frente e tira o foco do que eu estou fazendo** (por exemplo, um vídeo que estou assistindo). Isso precisa parar, nesta fase e em todas as próximas:

- **Prefira sempre testes sem janela:** `godot --headless` para testes automáticos, import de assets, validação de cenas e qualquer coisa que não precise de imagem.
- **Quando precisar de imagem** (capturas de tela, medição de fps), abra o jogo **sem tomar o foco**: no macOS, inicie com `open -g` (abre em segundo plano, sem ativar o app) ou use a flag de janela sem foco do Godot (`display/window/size/no_focus` ou o equivalente por linha de comando), **só nas execuções de teste**, sem mudar a configuração normal do jogo para mim. Se der, abra a janela minimizada ou fora da área visível.
- Lembre que o macOS pode reduzir o desempenho de janelas em segundo plano. Para as **medições de fps**, que precisam da janela na frente, **junte todas num momento só, no fim do trabalho**, e me avise antes no terminal, com uma linha clara tipo "vou abrir o jogo na frente por uns 2 minutos para medir o desempenho".
- Feche o jogo assim que o teste terminar.
- Registre essas regras no `CLAUDE.md`, numa seção "Testes sem atrapalhar o Lucas".

## Fora do escopo agora

Conteúdo novo (animais, estações, aeroporto, passaporte, colecionáveis), multiplayer, interior da casa, sons e **redesenho completo dos menus e das fontes** (vamos fazer uma fase só de interface depois; por enquanto, só não piore o que existe).

## Forma de trabalho

- Ordem: item 10 (vale desde o começo) → 0 → 1 → 5 → 4 → 3 → 2 → 8 → 9 → 6 → 7 (desempenho antes do visual, para o visual novo entrar já medido).
- Execute tudo de uma vez e me entregue pronto para revisar.
- No final: o que estava faltando do pedido interrompido, o que o profiler mostrou, a tabela de desempenho antes e depois, as capturas antes e depois do visual e como testar cada correção.
