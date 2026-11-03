# 0048 — Bandeiras nos marcos da fronteira

**Fase 3.6.** Contexto: só dava para saber o país do outro lado chegando perto (nome no HUD). O autor quer ver de longe.

## Decisão

- **Fonte:** [flag-icons](https://github.com/lipis/flag-icons) 7.6.0 (MIT), SVG 4:3. Cobre os 237 países do jogo que têm código ISO de duas letras. O Godot desenha os SVG (`Image.load_svg_from_buffer`) numa ferramenta (`client/tools/montar_bandeiras.gd`) que gera um atlas só (`bandeiras.png`, 1024 × 720, quadrinhos de 64 × 48 com margem repetida de 3 px para os mipmaps) e o índice (`bandeiras.json`, código A3 do jogo → posição). Os SVG ficam fora do Git.
- **Regra neutra:** a mesma das fronteiras (padrão do Natural Earth). Cada área usa a bandeira do seu código ISO 3166-1; Chipre do Norte, Somalilândia e o Glaciar de Siachen, sem código, ganham uma bandeirinha neutra (creme, faixa verde do Goblo e o código em letras de pixel). Taiwan vem como `CN-TW` do Natural Earth e usa o código ISO `TW`.
- **Nos marcos:** cada marco ganha um mastro e uma bandeirinha acima da cortina. O pano é um quadrilátero só, com uma bandeira em cada face (`FRONT_FACING` no `border_flag.gdshader`): quem está de um lado vê a bandeira do país do outro lado. O país de cada lado sai da orientação dos segmentos (o país do segmento fica à esquerda de a → b), na mesma thread que monta a cortina. Um MultiMesh por par de países, com os dois índices e a fase da onda no `INSTANCE_CUSTOM`; o pano tremula no shader.
- **Reaproveitável:** `FlagAtlas` (`index_of`, `uv_rect`, `texture`) serve para a capa da fase 4.0.

## Consequências

- Um draw call a mais por par de países perto (o MultiMesh das bandeiras) e um a mais para os mastros.
- `--border-test` confere que cada face mostra o país do outro lado (pelo `BorderMap`, a 1,5 unidade de cada lado do marco).
- Um aviso "material is null" aparece só no renderizador falso do modo headless; com janela, não.
