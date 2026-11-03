# Briefing — Fase 4.0: clima, necessidades, roupas, personagem e flores

> Cole este arquivo inteiro no Claude Code. Salve uma cópia em `docs/briefing-fase-4-0.md` (não deixe na raiz).

## Contexto

As Fases 3.5 e 3.6 estão encerradas e muito boas. **Não mexa no que funciona.**

Esta fase deixa o mundo mais vivo e o personagem mais seu: **temperatura real, necessidades gentis (sede, calor, frio e fome), comidas, roupas com proteção térmica, editor de personagem, capa de bandeiras e muito mais flores para o álbum.**

Regras de sempre do `CLAUDE.md`: commits pequenos em português, testes passando, push no final, nenhuma menção a outros jogos, nada de `osascript`/permissões do Mac, **todos os números de jogo em arquivos de dados**, textos visíveis passando por `tr()`. Pode usar `tools/sem_foco.sh` para capturas; para outras formas de abrir o Godot com janela, pergunte antes.

**Princípio desta fase:** o Goblo é um jogo para relaxar. As necessidades existem para dar **vantagens** a quem cuida do personagem, nunca para castigar. Ninguém morre, perde itens ou fica impedido de jogar.

## 0. Pequenas pendências (fazer primeiro)

- Escreva os ADRs **0043, 0044 e 0045**, que estão linkados no README e no `CLAUDE.md` mas não existem.
- Revise se **todo** texto visível montado na interface passa por `tr()` (pendência da 3.5).
- Investigue a travada que às vezes aparece **andando perto dos animais** (o `--border-test` falha por isso de vez em quando) e corrija.
- Os executáveis em `client/export/` ficam para o fim da fase: regenere-os por último, se os modelos de exportação estiverem instalados.

## 1. Temperatura do mundo

- O **servidor** calcula a temperatura de qualquer ponto a partir de: **latitude** (equador quente, polos frios), **estação** do hemisfério, **altitude/bioma** (montanha mais fria, deserto quente de dia e frio à noite) e **hora do dia** local.
- Valores plausíveis e fofos, não precisam ser científicos, mas coerentes: Manaus quente o ano todo; Patagônia fria; Saara muito quente de dia; Antártida sempre gelada.
- Fontes locais de calor e frio: **fogueira** (nova receita na bancada, pode ser colocada no lote e em qualquer lugar por um tempo) aquece quem está perto; **sombra de árvore** refresca um pouco no calor; entrar na água/oceano refresca.
- **HUD:** um termômetro pequeno com a temperatura sentida e um ícone (sol, nuvem, floco) quando estiver muito quente ou muito frio.
- O personagem reage visualmente: **treme** de frio, **abana-se/sua** no calor, solta vapor da respiração em lugares gelados.
- **Testes em Go:** dado lugar, data e hora, a temperatura cai na faixa esperada (Manaus quente, Ushuaia fria em julho, Saara quente ao meio-dia e frio à meia-noite, montanha mais fria que a planície vizinha).

## 2. Necessidades gentis: sede, temperatura e fome

Três indicadores (com ícones bonitos no HUD, discretos quando estão bem):

- **Sede:** cai devagar com o tempo, mais rápido no calor.
- **Conforto térmico:** depende da temperatura sentida, já descontada a proteção das roupas e das fontes de calor/frio.
- **Fome:** cai devagar com o tempo e mais rápido correndo ou coletando muito.

**Efeito na velocidade de movimento** (três níveis, números no arquivo de dados):

| Estado | Quando | Efeito |
|---|---|---|
| **Ótimo** | todos os indicadores **no máximo** (ou quase) | **bônus leve**: anda e corre um pouco mais rápido que hoje |
| **Neutro** | nenhum indicador no mínimo, mas nem todos no máximo | velocidade **igual à de hoje** |
| **Crítico** | **qualquer** indicador no mínimo | **cansaço**: anda mais devagar. Com fome no mínimo, a tela fica levemente zonza (efeito suave, sem enjoar) |

- Nada além disso: **sem dano, sem morte, sem perder itens**. As necessidades **não caem com o jogo fechado**.
- **Modo tranquilo** nas configurações (F6): desliga as necessidades por completo (sem bônus e sem penalidade). Fica salvo no servidor.
- **O servidor é a fonte da verdade** das necessidades e do multiplicador de velocidade, porque já valida a velocidade do movimento. O cliente só mostra.
- No modo dev: encher/zerar cada indicador, congelar as necessidades, forçar temperatura.

### Como beber
- **Água de coco** (o coco que já existe passa a matar a sede).
- **Cantil** (receita na bancada): enche numa **fonte**, num **poço** (nova decoração fabricável) ou na água doce, e pode ser bebido em qualquer lugar algumas vezes.
- Frutinhas matam um pouco a sede.
- Água do oceano **não** mata a sede.

### Comida
- Comer usa o item direto do bolso (E ou clique).
- **Comidas cruas** já existentes (frutinhas, coco) matam pouco a fome.
- **Cozinhar na fogueira:** perto de uma fogueira, abre um menu de receitas simples (por exemplo, frutinhas assadas, espetinho de cogumelo se houver, sopa, suco). Receitas no arquivo de dados.
- Comidas melhores dão, além de matar a fome, um **bônus temporário** (por exemplo, correr mais rápido, as necessidades caírem mais devagar, aguentar mais frio ou calor por alguns minutos). Ícone do bônus com tempo restante no HUD.
- Se precisar de ingredientes novos (cogumelos, ervas, grãos), crie-os como objetos coletáveis em biomas que fazem sentido, gerados pelo servidor como as flores.

## 3. Roupas (por espaço, substituição direta)

- O personagem tem **espaços de roupa**: **cabeça**, **corpo**, **pernas**, **pés** e **costas**. Cada espaço tem **uma** peça; colocar uma nova **substitui** a anterior, que volta para o bolso.
- Janela de **guarda-roupa** (tecla **C**, ou dentro do bolso), com o personagem girando e prévia antes de vestir.
- Cada peça tem, no arquivo de dados: espaço, **proteção contra frio**, **proteção contra calor**, preço, receita (se fabricável) e cores disponíveis.
- **Como conseguir:** fabricando na bancada (receitas com materiais, flores e lã/couro, se fizer sentido) ou **comprando na loja** do país (com algumas peças típicas de cada região do mundo).
- Exemplos para começar (ajuste ao que der para fazer bem): gorro, chapéu de palha, boné, cachecol, casaco, regata, calça, bermuda, botas, sandálias.
- **Tinta de flores:** flores podem virar **tinta** na bancada, e a tinta muda a cor de uma peça de roupa. É mais um uso para as flores novas.
- **Visual:** as peças precisam aparecer no personagem para todo mundo (multiplayer). Como o pacote não tem roupas, crie-as **no mesmo estilo** dos personagens da Kenney (formas simples, cantos chanfrados, proporções fofas): acessórios como malhas encaixadas (chapéus, cachecol, botas, capa) e, para camisas, casacos e calças, troca de cor/região do corpo por shader ou malhas levemente maiores sobre o corpo. Registre a abordagem num ADR.
- O que cada jogador veste vai pelo servidor e aparece para os outros.

### Capa de bandeiras
- Peça do espaço **costas**, **vendida na loja de cada país**.
- Mostra, como retalhos, as **bandeiras dos países em que o jogador já esteve** (dos carimbos), usando o atlas de bandeiras da 3.6. Cresce conforme ele viaja. Os outros jogadores veem.
- Leve tremulação ao andar.

## 4. Editor de personagem

Quero montar o personagem escolhendo partes: **cabeça, cabelo, pernas** e o que mais fizer sentido.

- **Primeiro, investigue** como os modelos do **Mini Characters** são feitos: se cabeça, cabelo, tronco, braços e pernas são nós/malhas separados dentro do `.glb`, ou se cada personagem é uma malha única. Me diga o resultado no final.
- **Se as partes forem separáveis:** permita misturar partes dos 12 personagens (cabeça de um, cabelo de outro, pernas de outro), mantendo o esqueleto e as animações funcionando.
- **Se não forem:** monte o editor com o que dá para fazer bem: corpo base (os 12 atuais), **cor da pele**, **penteados** (crie malhas de cabelo no mesmo estilo, encaixadas na cabeça), **cor do cabelo**, rosto/olhos se der, e acessórios (óculos do pacote e outros). Registre num ADR.
- O editor aparece no **primeiro acesso** (no lugar da escolha de personagem atual) e pode ser reaberto num **espelho** fabricável no lote e nas configurações.
- O visual é salvo no servidor e todos os outros jogadores veem.
- **Desempenho:** personagens customizados de outros jogadores não podem pesar mais que hoje (junte as partes num só objeto por personagem quando possível).

## 5. Mais flores e o álbum

- Hoje há praticamente um modelo de flor recolorido. Crie **várias espécies novas** no mesmo estilo low-poly do Nature Pack (pelo menos 10 a 15), algumas inspiradas em flores reais de cada região (por exemplo, girassol, ipê-amarelo como arbusto/árvore florida, lavanda, cacto florido, flor de lótus na água, flores alpinas, flores do campo), com cores próprias.
- Cada bioma e **cada estação** têm suas flores (primavera com mais flores, inverno quase sem). Algumas são **raras**.
- **Densidade:** bem mais flores pelo cenário, sem perder desempenho (MultiMesh, como a grama).
- As flores colhíveis continuam vindo do servidor; as decorativas, do cliente.
- **Goblopédia:** nova seção de **flores**, com silhueta "???" para as não descobertas, a primeira foto, onde e quando foi encontrada e a raridade. Recompensa em gobolares pelo primeiro registro.

## 6. Modo dev, testes e documentação

- Painel dev: aba **Corpo** (necessidades, temperatura, modo tranquilo, bônus de comida) e aba **Visual** (dar roupas, abrir editor, mostrar todas as flores do bioma).
- **Testes em Go:** temperatura por lugar e hora; necessidades caindo no ritmo certo e paradas com o jogo fechado; níveis de velocidade (ótimo, neutro, crítico) e o servidor aceitando o bônus de velocidade sem acusar movimento inválido; modo tranquilo; roupas substituindo por espaço; proteção térmica somando certo; capa com os países visitados; receitas de comida e bônus temporários.
- Atualize README (teclas novas: C guarda-roupa), `docs/CONTEUDO.md` (temperaturas, necessidades, roupas, comidas, flores), `docs/API.md`, `docs/PROTOCOLO.md` e ADRs.
- Meça (sem janela) o custo de personagens customizados e das flores, e deixe a medição com janela para eu rodar com `client/tools/medir_fps.sh`.

## Fora do escopo

Itens do `BACKLOG.md` não citados aqui, cavernas, baú, limite por item, ferramentas novas, folclore, animais novos, pesca, barcos, Atlântida, veículos, petróleo, interior da casa, interface nova, música e sons.

## No final

O que mudou, como testar cada parte pelo modo dev (passo a passo), **o que você descobriu sobre os modelos dos personagens** (partes separáveis ou não), decisões tomadas sozinho, o que ficou pendente e o que ficou sem verificação visual.
