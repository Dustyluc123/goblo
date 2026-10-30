# Briefing — Fase 3: fronteiras vivas e multiplayer

> Cole este arquivo inteiro no Claude Code. Salve uma cópia em `docs/briefing-fase-3.md` (não deixe na raiz).
>
> Se você ainda estiver analisando o `travadas.log` que eu mandei, **termine e commite isso primeiro**, me diga o que encontrou e só depois comece esta fase.

## ⚠️ Regra desta fase: não abrir o Godot com janela

Vou estar assistindo vídeos e não quero ser interrompido. **Nesta fase, não abra o Godot com janela de jeito nenhum**, nem com `tools/sem_foco.sh`. A autorização que dei na 2.6 está suspensa até eu liberar de novo. Use só `--headless`. No final, liste tudo o que ficou **sem verificação visual** e eu confiro ou libero as capturas depois.

As demais regras do `CLAUDE.md` continuam valendo: commits pequenos em português, testes passando, push no final, nenhuma menção a outros jogos, nada de `osascript`/permissões do Mac, números de jogo em arquivos de dados.

## Contexto

As fases 2.5 e 2.6 ficaram ótimas. Esta fase tem duas partes:

- **Parte A (fronteiras vivas):** corrigir as fronteiras que passam por dentro dos lotes e transformar a fronteira num elemento visual bonito, que muda quando eu tenho o passaporte.
- **Parte B (multiplayer):** ver os outros jogadores em tempo real e passar para o servidor as validações que hoje o cliente faz.

Faça a Parte A primeiro, commite e só então comece a Parte B.

---

# Parte A — Fronteiras vivas

## A1. Fronteira não pode cortar lote

Agora que o país é decidido pela posição exata, a linha de fronteira às vezes passa **por dentro de um hexágono habitado e até de um lote**. Um morador pode ficar sem conseguir ir para um lado da própria casa porque aquele lado é de outro país e ele não tem o passaporte.

- **Lotes novos** só podem ser criados **inteiramente dentro do país do dono**, com uma margem da fronteira (por exemplo 2 unidades; no arquivo de dados).
- **Lotes existentes** que cruzam fronteira: liste quantos são no banco. A área inteira do lote (mais a margem) passa a contar como território do **país do dono** para a regra de passagem. Se for mais simples e seguro, ofereça no modo dev um comando para migrar esses lotes para um lugar válido no mesmo país, levando casa e decorações junto. Registre a decisão num ADR.
- O dono **nunca** é bloqueado dentro do próprio lote nem no caminho entre o lote e o resto do seu país.
- Visitantes andando perto de um lote que fica na beira da fronteira também não ficam presos em "bolsões": nenhum ponto de terra do país deve ficar inacessível a pé para quem está nele.
- **Testes em Go:** um lote novo nunca cruza a fronteira; um ponto dentro de um lote antigo que cruza fronteira conta como país do dono para ele; não existem bolsões inacessíveis num conjunto de casos de teste perto de fronteiras.

## A2. Fronteira visível de verdade (e que muda com o passaporte)

A linha tracejada no chão foi uma ótima ideia. Agora quero a fronteira **acima do chão**, com um visual bonito e fofo, mudando de estado conforme eu tenha ou não o passaporte do país do outro lado:

**Sem passaporte (fechada):**
- uma **cortina de luz** baixa e translúcida (por exemplo, até a altura do personagem), em tons pastel, ondulando devagar e com brilhinhos subindo;
- **marcos** a cada alguns metros: postes pequenos com uma fita ou bandeirola esticada entre eles, com um cadeadinho ou ícone de "fechado";
- ao encostar, a cortina reage (uma onda que se espalha a partir do ponto de contato) junto com a mensagem que já existe.

**Com passaporte (aberta):**
- a cortina fica **mais baixa e transparente**, a fita dos marcos fica **solta ou erguida como um arco**, e o ícone vira "aberto";
- ao atravessar, uma pequena **chuva de brilhos/confete** e a plaquinha "Bem-vindo!".

**Transição:** quando eu compro o passaporte de um país, a fronteira dele, se estiver por perto, **abre com uma animação** (a cortina desce, as fitas sobem). Quando olho de longe, as fronteiras abertas e fechadas são fáceis de distinguir.

**Regras visuais e de desempenho:**
- Só desenhar a cortina perto do jogador (fade com a distância), por pedaços, em thread, como já é feito com as linhas.
- O estado (aberta/fechada) é **por jogador**: cada um vê conforme os próprios passaportes.
- Nada assustador: tem que parecer um enfeite de festa, não uma cerca de prisão.
- No modo dev: alternar a visão "todas abertas"/"todas fechadas" para testar.
- Teste headless de desempenho: andar ao longo de uma fronteira não pode gerar travadas acima de 25 ms (use o registro de travadas).

---

# Parte B — Multiplayer em tempo real

## B1. Arquitetura

- Conexão em tempo real por **WebSocket** entre o Godot (`WebSocketPeer`) e o servidor em Go. Escreva um ADR comparando: (a) escrever a camada em tempo real no nosso servidor e (b) usar o Nakama, que tínhamos deixado para avaliar nesta fase. Minha preferência é (a), por já termos servidor, banco e regras prontos e por ser ótimo para o portfólio; só escolha (b) se houver um motivo forte.
- Autenticação pelo token que já existe. Se o mesmo jogador conectar duas vezes, a conexão antiga é encerrada.
- **Reconexão automática** se a internet cair, sem perder o estado.
- Mensagens compactas (binário ou JSON enxuto, documentado em `docs/PROTOCOLO.md`) com limite de tamanho e de frequência por jogador.

## B2. Movimento e presença

- O cliente manda a posição e o estado de animação de **10 a 20 vezes por segundo**.
- O servidor **valida**: velocidade máxima (correndo e pulando), sem teleporte (exceto H, voo e dev, que passam pelo servidor), sem oceano e **regra de passaporte nas fronteiras**. Se algo for inválido, corrige o jogador com suavidade.
- **Área de interesse:** o servidor só manda para cada jogador quem está nos pedaços ao redor dele (usando as células que já existem), e para de mandar quando o outro se afasta.
- Nos outros clientes: **interpolação** com um pequeno atraso (por volta de 100 ms) para o movimento ficar liso. O meu personagem continua respondendo na hora (previsão no cliente com correção do servidor).
- Outros jogadores aparecem com o **apelido em cima da cabeça** e as mesmas animações (andar, correr, pular, coletar, carinho, foto).
- **Escolha de personagem:** na tela de primeiro acesso e nas configurações, escolho um dos 12 personagens do Mini Characters. Fica salvo no servidor e os outros veem.
- Limite de quantos jogadores animados aparecem ao mesmo tempo, com LOD de animação para quem está longe.

## B3. Interação entre jogadores

- **Emotes** (roda de emotes numa tecla, por exemplo T): acenar, sim, não, sentar, comemorar (use as animações que existem no pacote).
- **Chat:** balão em cima da cabeça para quem está perto e uma janela de chat simples (Enter abre). Filtro de palavrões (o mesmo do apelido), limite de mensagens por segundo e tamanho máximo.
- **Silenciar e bloquear** um jogador (clicando no nome ou pela lista de jogadores próximos).
- As ações dos outros aparecem para mim: árvore balançando quando alguém sacode, decoração surgindo **na hora** quando um vizinho constrói, obra da casa mudando.
- Lista de **jogadores próximos** (Tab ou outra tecla livre) com país e apelido.
- Ninguém constrói, coleta a caixa de vendas ou mexe no lote dos outros (já é assim, mas confirme com o servidor em tempo real).

## B4. Passar para o servidor o que hoje é do cliente

Os ADRs da 2.5 registram o que ainda é decidido no cliente. Agora que o servidor sabe onde o jogador está:
- **Distância até o objeto** na coleta, carinho, frutinha e caixa de vendas.
- **Barreira de fronteira** e **carimbo a pé**.
- **Registro na Goblopédia:** o servidor confere se o animal (pela posição determinística) estava perto e à frente do jogador no momento da foto.
- **Amizade com animal:** compartilhada? Decida e registre (minha sugestão: a amizade é por jogador; a reação de fugir continua local).

## B5. Ferramentas de teste do multiplayer

- **Bots em Go** (`server/cmd/bots`): simulam N jogadores andando, coletando, mandando emotes e chat numa região. Use para teste de carga.
- **Meta:** **100 jogadores na mesma região** num servidor modesto, sem travar. Meça CPU, memória e banda por jogador e registre no README.
- **Modo dev (F1):** aba "Rede" com lista de conectados, criar bots perto de mim e **simular atraso e perda de pacotes** (por exemplo 0 a 300 ms e 0 a 10%) para testar a interpolação.
- **F2:** ping, pacotes por segundo e jogadores visíveis.
- **Testes:** validação de movimento (velocidade, oceano, fronteira), área de interesse (entra/sai), chat (filtro e limite), reconexão, conexão duplicada, e um teste de integração com **dois clientes headless** se vendo.

## B6. Preparar para jogar com amigos (sem publicar ainda)

- `Dockerfile` do servidor e um `docs/DEPLOY.md` com as opções de hospedagem barata que funcionam com WebSocket e banco persistente (SQLite com volume, ou PostgreSQL). **Não contrate nem publique nada**; eu decido depois.
- Configure as exportações do Godot para **macOS** e **Windows**, com a URL do servidor configurável, e documente como um amigo instala e abre (incluindo o aviso de segurança do macOS para apps sem assinatura).

---

## Fora do escopo agora

Vender todos os itens, loja, troca entre jogadores, NPCs, aeroporto novo e avião (Fase 3.5); temperatura, sede, roupas e mais flores (Fase 4.0); cavernas e folclore (Fase 4.5); redesenho da interface, música e sons (Fase 5.0); publicar o servidor de verdade.

## No final

- O que você encontrou no `travadas.log`, se ainda não tiver me dito.
- O que mudou nas partes A e B, como testar cada coisa (incluindo como rodar **dois jogos ao mesmo tempo** no meu Mac e como usar os bots) e as decisões que tomou sozinho.
- Os resultados do teste de carga.
- **Tudo o que ficou sem verificação visual.**
