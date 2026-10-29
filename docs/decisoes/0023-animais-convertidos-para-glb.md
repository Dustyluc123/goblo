# 0023 — Animais do Quaternius convertidos para GLB

**Status:** aceita (fase 2)

## Contexto
O pacote Ultimate Animated Animals (Quaternius, CC0) vem em glTF com os dados embutidos em base64: 36 MB, que o Godot importa devagar. O briefing pede só o glTF e autoriza converter para `.glb` se o import ficar pesado.

## Decisão
Converter cada `.gltf` para `.glb` binário com `tools/gltf_para_glb.py` (Python puro, sem dependências): decodifica os buffers base64, junta num só e grava o contêiner GLB. Os 12 animais caem de 36 MB para 22 MB, com as mesmas animações (`Idle`, `Walk`, `Gallop`, `Eating`, `Jump_ToIdle`…).

## Consequências
- Os animais ficam guardados em `client/assets/quaternius/ultimate-animated-animals/` para a fase 2.5; ainda não aparecem no mundo.
- Para atualizar o pacote, rode o script de novo sobre os `.gltf` originais.
