# 0017 — O "pacote de Halloween" é o Graveyard Kit

**Status:** substituída na fase 2 (a vegetação agora é do Ultimate Nature Pack, [ADR 0020](0020-objetos-interativos-no-servidor.md))

## Contexto
O briefing cita pacotes de natureza e "um pacote com tema de Halloween que também tem grama e pedras". No repositório havia só um pacote novo, o **Mini Forest**; o de Halloween é o **Graveyard Kit**, que já estava em `client/assets/kenney/graveyard-kit/` desde o complemento da fase 1.

## Decisão
Usar o Mini Forest (árvores, plantas, grama, pedras) e, do Graveyard Kit, **só itens neutros**: `pine`, `pine-crooked`, `pine-fall`, `rocks`, `rocks-tall` e `trunk-long`. Nenhuma abóbora, lápide, cruz, caixão ou caveira. O Graveyard Kit não tem grama; a grama vem do Mini Forest.

## Consequências
Se chegar outro pacote de natureza, basta acrescentar os modelos em `BiomeStyle.MODELS` e nas listas por bioma.

## Atualização (fase 2)
Os biomas passaram a usar o **Ultimate Nature Pack** (Quaternius), que cobre melhor árvores, pedras, arbustos e grama de todos os biomas, inclusive versões com neve. Os modelos do Mini Forest e do Graveyard Kit saíram dos biomas, mas os pacotes continuam em `client/assets/kenney/` para uso futuro. Continua valendo: nada de abóboras, lápides, cruzes, caixões ou caveiras no mundo.
