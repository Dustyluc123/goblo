# 0012 — Biomas por regiões do Natural Earth, polígonos à mão e latitude

**Status:** aceita (fase 1.5)

## Contexto
O briefing pede biomas reconhecíveis (Amazônia, Saara, Himalaia, Antártida…), de preferência com dados gratuitos.

## Decisão
Usar as regiões geográficas do Natural Earth 1:50m (desertos, cordilheiras, planícies), alguns polígonos aproximados desenhados à mão e regras de latitude, nessa ordem de prioridade. As alturas saem do bioma e da distância até a borda (anéis de montanha). Detalhes em `docs/BIOMAS.md`.

## Alternativas consideradas
- **Mapas de ecorregiões** (RESOLVE 2017): mais precisos, mas grandes (centenas de MB) e com licença CC-BY. Ficam para uma fase futura.
- **Relevo real** (rasters de elevação): exigiria processar rasters no servidor. Não vale a pena para hexágonos de ~23 unidades.

## Consequências
Montanhas estreitas ficam baixas, e algumas regiões de transição (cerrado, caatinga) viram campo. Os testes garantem os casos principais.
