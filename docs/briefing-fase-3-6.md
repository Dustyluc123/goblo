# Briefing — Fase 3.6: polimento (aeroporto, frestas entre hexágonos e bandeiras)

> Cole este arquivo inteiro no Claude Code. Salve uma cópia em `docs/briefing-fase-3-6.md` (não deixe na raiz).

## 0. Encerrar a Fase 3.5 do jeito que está

Você parou no meio da Fase 3.5, mas quase tudo ficou pronto e eu testei. **Não continue nada do que ficou faltando da 3.5.**

- Faça commit e push de qualquer coisa que esteja pronta e sem commit, desde que os testes passem. Se houver algo **pela metade e quebrado**, não commite: desfaça essa parte e me diga o que era.
- Atualize `docs/progresso-fase-3-5.md` (crie se não existir) marcando a fase como **encerrada** e listando o que ficou de fora, como **"adiado"**.
- Crie (ou atualize) `docs/BACKLOG.md` e mova para lá os itens adiados da 3.5, cada um com uma linha explicando o que é. Eu decido depois em qual fase eles entram.
- Me diga no final, em poucas linhas, o que ficou de fora da 3.5.

## Contexto

O jogo está muito bom. Esta fase é **pequena**: só corrige o aeroporto, um bug de queda entre hexágonos e coloca bandeiras nas fronteiras. **Não mexa no que funciona e não adicione conteúdo além do que está aqui.**

Regras de sempre do `CLAUDE.md`: commits pequenos em português, testes passando, push no final, nenhuma menção a outros jogos, nada de `osascript`/permissões do Mac, números em arquivos de dados. **Pode usar `tools/sem_foco.sh` para capturas**; para qualquer outra forma de abrir o Godot com janela, pergunte antes.

## 1. Aeroporto na escala certa

Hoje até o personagem é maior que o avião.

- **Avião:** aumente para cerca de **10 vezes** o tamanho atual. A referência: a porta do avião tem pelo menos a altura do personagem e a asa é bem maior que uma casa grande. Ajuste o tamanho no voo sobre o globo para continuar bonito lá também.
- **Pista:** mais larga e mais comprida, proporcional ao avião novo. Se não couber no hexágono, ajuste a montagem do aeroporto (pista na diagonal do hexágono, terminal mais compacto) e registre num ADR.
- **Faces piscando na pista:** há o mesmo bug de *z-fighting* que já existiu na casa: duas superfícies no mesmo plano brigando (marcações da pista contra o asfalto, ou a pista contra o chão do hexágono). Corrija com um pequeno deslocamento de altura, ou desenhando as marcações como decalque/textura em vez de malha sobreposta. Confira também o pátio e as calçadas.
- **Carros do pátio:** na escala em que o personagem **caberia dentro** (a porta do carro com a altura do personagem). Revise todos os veículos usados no aeroporto.
- **Terminal com cara de aeroporto:** paleta mais **cinza e neutra** (concreto, vidro azulado, detalhes em branco e um toque de cor da identidade do Goblo), menos parecido com casa de vila. Torre de controle coerente com o terminal.
- Confira que nada disso piora o desempenho (o aeroporto continua juntado numa malha por material).
- Capturas com `sem_foco.sh`: aeroporto de longe, personagem ao lado do avião, carros e pista de perto.

## 2. Bug: cair na fresta entre dois hexágonos

Mandei uma captura: no Chile (célula 20575, por volta de 52,19° S, 72,99° O, bioma montanha), o personagem **ficou preso/caindo numa fresta entre dois hexágonos de alturas diferentes**, com o céu aparecendo por baixo. Parece que o degrau entre hexágonos vizinhos não está fechado, nem no visual nem na colisão.

- Garanta que, entre **qualquer** par de hexágonos vizinhos, o degrau tenha uma **parede lateral fechada** (do mais alto até o mais baixo), tanto na malha visual quanto na **colisão**. Isso vale para terra com terra, terra com oceano e nos 12 pentágonos.
- Confira também a colisão gerada **por pedaços em thread**: as bordas entre pedaços precisam se encontrar sem frestas.
- Depois de corrigido, se o personagem ainda assim cair abaixo do terreno por qualquer motivo, ele é **reposicionado** em cima do hexágono mais próximo (proteção de segurança, sem tirar a causa).
- **Teste automático:** percorra um conjunto grande de bordas de hexágonos (incluindo montanhas, litoral e pentágonos) jogando raios de colisão de cima para baixo nas bordas e nos cantos, e garanta que **todo raio acerta o chão**. Inclua a célula 20575.

## 3. Bandeiras nas fronteiras

Hoje só dá para saber qual país está do outro lado chegando perto. Quero ver **de longe**.

- Nos **marcos** da cortina de fronteira, coloque **bandeirinhas tremulando** com a bandeira do país do outro lado (de cada lado, a bandeira do país vizinho). Elas são visíveis de longe, inclusive quando a cortina está fechada.
- Use um conjunto de bandeiras **com licença livre** (há bibliotecas abertas com as bandeiras de todos os países). Confira a licença, registre a fonte em `client/assets/CREDITOS.md` e no README, e cubra **todos** os países que existem no jogo. Se algum país não tiver bandeira na biblioteca, use uma bandeirinha neutra com o código do país.
- Bandeiras como texturas pequenas, num atlas, para não pesar.
- Ao chegar perto, continua aparecendo o nome do país como hoje.
- Para territórios e áreas disputadas, siga a mesma regra neutra das fronteiras (padrão do Natural Earth), documentada no README.

> A **capa com as bandeiras dos países visitados** fica para a Fase 4.0 (roupas). Mas deixe o atlas de bandeiras fácil de reaproveitar para isso.

## Fora do escopo

Qualquer item adiado da 3.5, roupas e capa, fome e comida, clima, cavernas, baú, limite por item, veículos, petróleo, pesca, Atlântida, interface nova, sons.

## No final

- O que ficou de fora da 3.5 (resumo) e onde está o `BACKLOG.md`.
- O que mudou em cada item, como testar (incluindo como ir até a célula 20575 pelo modo dev) e as capturas.
- O que ficou sem verificação visual.
