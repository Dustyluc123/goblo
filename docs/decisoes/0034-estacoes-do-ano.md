# 0034 — Estações do ano pela data real

## Contexto

A fase 2.5 pede estações reais: a data (UTC) e o hemisfério decidem a estação (no fim de outubro, outono no norte e primavera no sul), com mudanças graduais e nada nos trópicos.

## Decisão

- **Regra (Go e GDScript iguais):** uma fase de 0 a 4 a partir do dia do ano (0 = primavera em 20/3, 1 = verão em 21/6, 2 = outono em 22/9, 3 = inverno em 21/12), interpolada entre as viradas; no sul, fase + 2. Entre os trópicos (|lat| < 23,44°) não há estação. Só mudam os biomas temperados e frios: floresta, campo, tundra e montanha (`SeasonFor`).
- **Transição gradual:** perto de cada virada, os pesos das duas estações se misturam por ±10 dias (`Seasons.weight`). O chão muda de cor aos poucos e cada objeto troca de modelo num dia diferente da transição (limiar sorteado pelo id), então a floresta vai amarelando ou embranquecendo devagar.
- **O que muda no visual:**
  - Outono: árvores nas versões `*_Autumn_*`, grama e chão dourados e folhas caindo.
  - Inverno: árvores, pedras, arbustos e troncos nas versões `*_Snow_*`, chão branco, grama rala e clara e flocos de neve.
  - Primavera: chão verde mais claro e florzinhas de enfeite na grama, com semente própria, então a grama de sempre não muda.
  - Verão: o visual de sempre.
- **Onde fica a conta:** o chão (shader do terreno) e o mini mapa calculam a estação por pixel, pela latitude. O alfa da cor do vértice marca os biomas que mudam. Então o globo afastado e o mini mapa mostram os dois hemisférios diferentes. Árvores e grama são remontadas quando a fase anda umas 4 horas (ou quando o modo dev força uma data).
- **Mesmo id:** as árvores interativas continuam com o mesmo id, a mesma colisão e as mesmas regras; só o modelo desenhado muda (`drawn_model`).
- **Sem carregar no meio do jogo:** na entrada, só as versões que valem hoje em algum hemisfério são pré-carregadas. Forçar outra estação no modo dev carrega o que faltar, com um aviso na tela.
- **Partículas:** folhas e neve em volta da câmera, ligadas à qualidade (nenhuma na baixa, 160 na média, 320 na alta).

## Consequências

- O relógio é o do servidor (o "dia seguinte" do modo dev também vale). A data forçada pelo modo dev vale só neste cliente.
- A tundra continua com as árvores de neve o ano todo (como era); o chão dela muda com as estações.
