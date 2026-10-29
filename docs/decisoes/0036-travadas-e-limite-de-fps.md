# 0036 — Registro de travadas, trabalho espalhado entre quadros e limite de fps

## Contexto

Na fase 2.5, o fps caía de vez em quando sem padrão claro de lugar, clima, hora ou construção. Os fps médios estavam bons; o problema eram quadros isolados muito longos (travadas). Sem saber o que acontecia em cada um, não dava para corrigir.

## Decisão

- **Registro de travadas** (`HitchLog`): todo quadro com mais de 25 ms vira uma linha em `user://travadas.log`. A linha traz a hora, a duração e a posição (lat/lon, célula, bioma, país, fps, qualidade). Traz também o que foi anotado naquele quadro e no anterior: pedaços carregados e soltos, pedidos ao servidor, colisão, árvores e grama, lotes, animais, aeroportos, linhas de fronteira, troca de estação e modelos carregados na hora. Fecham a linha os shaders compilados (contadores de pipeline do Godot), o estado (voando, câmera afastada, modo foto, pedidos em andamento, janela sem foco) e os tempos de processo e física. O F2 mostra as últimas travadas na tela. Cada sessão começa com um cabeçalho com a qualidade, o tamanho da janela, o limite de fps e o V-Sync.
- **`--hitch-test`:** passeio automático pelos momentos suspeitos, com o registro ligado:
  - correr perto de casa e afastar a câmera até o globo;
  - a Alemanha no outono e o pampa com animais;
  - modo foto, voo, casa e troca de estação.
  No headless mede só a CPU. Com janela (`tools/sem_foco.sh`), entra também a compilação de shaders.
- **Correções, pelo que o registro mostrou** (headless, qualidade alta):
  - **Linhas de fronteira:** a busca da célula de cada amostra começava sem pista e varria as 25 mil células. Um pedaço perto de uma fronteira levava **230 a 320 ms** num quadro. Agora a busca começa na célula do segmento (~10 ms) e a conta toda roda numa thread. O nó entra no quadro seguinte.
  - **Pedaços do servidor:** o JSON grande das respostas (> 4 KB) é lido numa thread (chegava a 46 ms), e o preparo dos objetos também (até 9 ms para 700 objetos). Os pedaços prontos entram **um por quadro**. O `HTTPRequest` usa thread própria.
  - **Aeroportos:** montados um por quadro, o mais perto primeiro. Na Europa, uma dúzia entrava no mesmo quadro (200 ms).
  - **Colisão do chão:** os triângulos de cada pedaço novo são montados numa thread, e a forma entra um pedaço por quadro.
  - **Lotes de vizinhos:** entram aos poucos (até 4 ms por quadro, o mais perto primeiro). O do jogador entra na hora.
  - **Shaders:** pré-aquecidos na tela de carregamento ("Preparando os gráficos…"). Cada modelo carregado (malha comum, MultiMesh com e sem o material de folhagem, versão pontilhada da transparência da câmera), os animais com animação, os corações, as partículas de folhas e neve, a linha de fronteira, o arco do voo e o destaque da célula aparecem uma vez, pequenos, na frente da câmera, por 4 quadros. O Godot guarda o resultado no disco.
  - **Estações:** os modelos de outono e neve pré-carregados olham ~4,5 dias à frente, para a transição não carregar modelo no meio do jogo.
  - Resultado do `--hitch-test` headless: de 28 para 11 travadas. As que sobram são de teleporte (dezenas de pedaços entrando e saindo; é o momento esperado de espera) e da estação forçada pelo modo dev.
- **Limite de fps** nas configurações (F6): 30, 60 ou sem limite; padrão 60. O V-Sync fica sempre ligado (`project.godot` e `FpsLimit.apply`). Quando o limite é igual ou maior que a frequência da tela, quem segura é só o V-Sync, porque dois limitadores juntos fazem o ritmo dos quadros tremer. Com 30, a placa de vídeo trabalha metade e esquenta menos.

## Consequências

- O registro fica sempre ligado (custo: uma medida de tempo por quadro e uma escrita no disco por travada). O arquivo recomeça ao passar de 2 MB.
- Coisas que chegam do servidor aparecem um ou dois quadros depois. O nascimento e o teleporte continuam esperando tudo (`load_now`).
- Partes novas que façam trabalho pesado devem anotar no registro (`HitchLog.note`) e, se passarem de poucos ms, ir para uma thread ou ser espalhadas entre quadros.
- Pendente: medir com a janela na frente, porque os shaders e o aquecimento da GPU só aparecem assim. O autor joga 10 minutos e manda o `travadas.log`.
