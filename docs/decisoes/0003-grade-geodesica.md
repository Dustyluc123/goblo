# 0003 — Grade geodésica (poliedro de Goldberg)

**Status:** aceita (fase 1)

## Contexto
O mundo precisa ser dividido em terrenos parecidos em tamanho e forma, sem as distorções de uma grade lat/lon (que espreme as células nos polos).

## Decisão
Poliedro de Goldberg: dual de um icosaedro subdividido com frequência `n`. `10·n² + 2` células, sendo 12 pentágonos. Fase 1: `n = 20` (4.002 células), configurável.

Detalhes de implementação:
- Pontos da subdivisão identificados por chave inteira exata (vértices do icosaedro + pesos), o que garante determinismo e ids estáveis.
- Cantos de cada célula = centróides (projetados na esfera) dos triângulos em volta, em sentido anti-horário visto de fora.
- `neighbors[k]` alinhado com a aresta `k` do polígono.
- Célula de um ponto = a de centro mais próximo.

## Consequências
- Os 12 pentágonos são normais e esperados; o jogo precisa tratá-los como células comuns.
- Mudar `n` muda todos os ids. Quando houver terrenos salvos (fase 2), a frequência vira parte do "formato do mundo" e só poderá mudar com migração.
