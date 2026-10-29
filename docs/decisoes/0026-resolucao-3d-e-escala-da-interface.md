# 0026 — Resolução do 3D separada da interface

## Contexto

Na tela Retina do Mac do autor, a janela maximizada tem quase 3000 × 1800 pixels. Renderizar o 3D nessa resolução derruba o fps numa placa integrada, e a interface feita para 1280 × 720 ficava pequena demais.

## Decisão

- A janela abre maximizada (`window/size/mode=2`), com `stretch/mode = canvas_items` e `aspect = expand`: a interface cresce com a janela.
- O 3D é renderizado numa fração da janela (`scaling_3d_scale`) e ampliado com FSR 1; a interface continua na resolução cheia. A fração vem do preset de qualidade (`scale_3d`: baixa 50%, média 67%, alta 85%), mas nunca abaixo de 1080 linhas e só vale em janelas com mais de 1080 de altura (`Quality.render_scale`).
- Tamanho da interface (80%, 100%, 125%, 150%) e tela cheia (F11) ficam na janela de configurações (F6), salvos em `user://settings.cfg`.
- O mini mapa renderiza o globinho na resolução real da tela, para não ficar borrado.

## Consequências

- Em telas pequenas nada muda (3D em 100%).
- Medições de desempenho precisam informar o tamanho da janela e a resolução do 3D (o `--perf-test` imprime).
