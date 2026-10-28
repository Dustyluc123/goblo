# 0001 — Godot 4 no cliente

**Status:** aceita (fase 1)

## Contexto
O cliente precisa desenhar um globo 3D low-poly, ter física de personagem simples e, no futuro, exportar para desktop, web e celular. O projeto é solo e de portfólio.

## Decisão
Godot 4 (versão estável mais recente: 4.7) com GDScript.

## Por quê
- Código aberto, leve, sem royalties e com exportação para todas as plataformas que interessam.
- `ArrayMesh`, `CharacterBody3D` com `up_direction` configurável e colisão a partir da malha resolvem a fase 1 sem plugins.
- Cenas em texto (`.tscn`) e GDScript são fáceis de revisar no Git e de editar com o Claude Code.

## Consequências
- GDScript é mais lento que C#; por isso a malha é montada uma vez e a busca de célula anda pelos vizinhos em vez de varrer as 4.002 células.
