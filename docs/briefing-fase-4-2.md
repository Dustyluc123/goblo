# Briefing — Fase 4.2: acertos no personagem, na Goblopédia e nas travadas

> Cole este arquivo inteiro no Claude Code. Salve uma cópia em `docs/briefing-fase-4-2.md` (não deixe na raiz).

## 0. Antes de tudo

Os 8 commits da Fase 4.1 **não foram enviados** para o GitHub. Rode os testes e faça **push** deles antes de começar.

## Contexto

A 4.1 resolveu bastante coisa (capa verde, roupa por cima da original, ícones, guarda-roupa), mas testei e alguns pontos precisam mudar. Esta fase continua **sem conteúdo novo**.

Regras de sempre do `CLAUDE.md`. Para medir fps com janela: **avise no terminal e espere eu responder "ok"**. Capturas pelo `tools/sem_foco.sh`.

## 1. Cabeça volta a ser uma peça só

Separar cabeça, cabelo e penteados extras gerou estranhezas. Decidi **simplificar**:

- No editor, **cabeça e cabelo voltam a ser uma coisa só**: a opção "Cabeça" escolhe uma das **12 cabeças originais completas** do pacote (rosto + cabelo, como vieram).
- **Remova** as opções separadas de **cabelo**, **penteados extras** e **cor do cabelo** do editor, do guarda-roupa, dos dados e do servidor. Jogadores que já salvaram essas escolhas passam a usar a cabeça original correspondente (faça a migração no banco).
- **Remova o acessório "Quepe azul"**. A cabeça que tinha o quepe (male-c) volta a ser a cabeça original do pacote.
- **Cor da pele continua** existindo, mas só se funcionar bem nas 12 cabeças (sem pintar cabelo, barba ou boné). Se alguma cabeça não aceitar bem, me diga qual.
- **Chapéus** continuam presos ao osso da cabeça, com o ajuste por cabeça em `cabecas.json`. Agora que o cabelo é parte da cabeça, ajuste posição e escala de cada chapéu para cada cabeça, para não flutuar nem atravessar demais o cabelo. Não deforme a cabeça. Atualize a grade cabeça × chapéu no README.
- Isso também elimina a "aba reta" do coque embaixo do chapéu.

## 2. Acessórios no lugar errado

- No editor, os **óculos escuros** e os **óculos** estão aparecendo **no pé** do personagem.
- Prenda todos os acessórios de rosto ao **osso da cabeça**, na altura dos olhos, com ajuste por cabeça.
- Revise **todos** os acessórios e roupas, em **todas as 12 cabeças e corpos**, no editor, no guarda-roupa, no jogo e nos outros jogadores (multiplayer). Adicione um teste automático que confere que cada acessório está preso ao osso certo e perto da posição esperada.
- O objeto que o tronco da "Personagem 1" segura (vem do pacote) deve manter a **cor original**, não a cor do casaco.

## 3. Pele que aparece por baixo da roupa

- Com a regata (e com o short e a sandália), a pele que fica à mostra **não é a cor de pele que eu escolhi** no editor.
- A região pintada pela peça precisa usar **a cor de pele do jogador**. Corrija e teste com todos os tons de pele disponíveis, em todas as peças que mostram pele, no meu personagem e nos outros jogadores.

## 4. Goblopédia: registro só com o assunto centralizado

**Bug:** na maior parte das **flores** e em algumas **árvores** (de outono e com neve), eu tirei foto e **não registrou** na Goblopédia. Descubra o motivo (detecção de objetos pequenos? flores decorativas versus colhíveis? árvores com modelo trocado pela estação? validação do servidor rígida demais?) e corrija.

**Nova regra de enquadramento** (para animais, flores e árvores):
- Só registra se o assunto estiver **centralizado** na foto (dentro de uma área central, por exemplo os 35% do meio da imagem), **visível** (não escondido atrás de outra coisa) e com um **tamanho mínimo** na tela (não um pontinho ao longe). Números no arquivo de dados.
- Se houver mais de um assunto, vale o **mais centralizado**.
- **Retorno visual no modo foto:** uma pequena mira no centro da moldura que **muda de cor** e mostra o **nome do assunto** (ou "???" se ainda não descoberto) quando há algo registrável bem enquadrado. Ao tirar a foto, uma mensagem confirma o registro ("Novo na Goblopédia: Ipê-amarelo!").
- O servidor aplica a mesma regra (cone de direção mais estreito e distância máxima), para não registrar algo que o cliente não mostrou centralizado.
- Funciona igual em primeira pessoa e no selfie (no selfie, vale o que está centralizado atrás do personagem).
- **Testes:** registrar cada espécie de flor e cada tipo de árvore de estação; não registrar assunto fora do centro, muito longe ou escondido.

## 5. Travadas ao carregar pedaços do mundo

Na 4.1, a média ficou perto de 60 fps mas não estável, por causa de **travadas quando o personagem anda e o jogo carrega pedaços novos** (você explicou que elas já existiam na Fase 3).

- Com a minha autorização (avise e espere o "ok"), rode o `--hitch-test` com janela e veja o que cada travada estava fazendo.
- Corrija espalhando o trabalho por mais quadros e threads (carga de pedaços, colisão, MultiMesh, objetos do servidor, animais, lotes).
- Meta: **média com 60 fps estáveis** nas cenas do `medir_fps.sh` e o **pior quadro abaixo de 33 ms** andando normalmente.
- Atualize a tabela do README.

## No final

O que mudou, como testar cada item, os resultados das travadas (antes e depois), quais cabeças aceitam bem a cor de pele, o que ficou pendente e o que ficou sem verificação visual. **Faça push no final.**
