# 0055 — Álbum de fotos por conta e galeria

**Fase 4.5.** Corrige a 0033/0053 (fotos da Goblopédia).

## O que estava errado

- Às vezes a página de um assunto mostrava a foto de outro (foto de flor na página da vaca) e, uma vez, a foto de um personagem antigo.
- O índice das fotos (`user://fotos/goblopedia_<perfil>.cfg`) era **só por perfil**. Outra conta no mesmo perfil (banco zerado, outro servidor, conta nova) herdava as fotos da antiga.
- Até a 4.1, uma foto registrava todos os assuntos enquadrados e a mesma imagem virava a "primeira foto" de cada um (a flor com uma vaca ao fundo ficava na página da vaca). A 4.2 passou a registrar só o centralizado, mas os índices errados continuavam guardados e valiam para sempre ("a primeira foto não muda").
- Nomes por data e hora até o segundo + milissegundo do relógio do jogo: improvável, mas possível de repetir.

## Decisão

- **Uma pasta por perfil e por conta:** `user://fotos/<perfil>/<id do jogador>_<10 letras do hash do token>/`. O token muda com a conta e com o servidor, então nada vaza de uma conta para outra (`Session.photo_account`).
- **Id único por foto** (data, hora, milissegundos, contador e sorteio; confere se o arquivo já existe). Arquivos `<id>.png` e `<id>_mini.png`.
- **Índice `album.cfg`:** por foto, data, lugar (país, bioma, lat/lon) e a página que ela registrou; por página, o id da foto que a representa (`pick`). A página aponta para a foto pelo id, nunca pela posição numa lista. Sem escolha, a primeira foto que registrou a página.
- **Cache de miniaturas** por caminho, que sai do cache quando a foto é apagada; escolher outra foto troca o id e, com ele, a miniatura.
- **Galeria** (aba "Fotos" da Goblopédia, G): todas as fotos da conta, mais recentes primeiro, com data e lugar; apagar (clique duas vezes) e "Usar na página" (só na página que a própria foto registrou, para nunca pôr a foto de uma coisa na página de outra). Apagar a foto escolhida volta para a mais antiga que sobrou daquela página.
- As fotos antigas (soltas em `user://fotos/`) ficam onde estão e não entram no álbum: não dá para saber de qual conta eram nem se o índice delas estava certo.

## Consequências

- `tests/test_fotos.gd` (sem servidor): quatro assuntos fotografados em sequência em três contas (dois perfis e duas contas no mesmo perfil), cada página com a foto certa pela cor, ids únicos, segunda foto não troca a primeira, escolher troca, apagar volta para a outra e não fica nada no cache, zerar a Goblopédia mantém as fotos.
- Captura: `--ui=pedia-photos`.
