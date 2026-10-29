# 0010 — Formato binário do mundo, com versão e cache no cliente

**Status:** aceita (fase 1.5)

## Contexto
Com 25.002 células, o JSON da fase 1 passaria de 9 MB (1,6 MB com gzip) e levaria segundos para o GDScript ler.

## Decisão
- `GET /world.bin`: formato binário próprio (`server/internal/world/binary.go`), little-endian, com assinatura `GOBW` e número de versão do formato. As células vão em blocos (um array por campo: centros, vizinhos, bioma, país, altura), que comprimem melhor e o cliente lê cada um de uma vez (`to_float32_array`, `to_int32_array`). Cantos e lat/lon não vão no arquivo: o cliente calcula (um teste em Go garante que bate).
- Resultado: 1.076 KB, **353 KB com gzip**; leitura em ~0,5 s no cliente.
- **Versão do mundo** = os 8 primeiros bytes do SHA-256 do binário, em hexadecimal. Vai no `ETag`, no cabeçalho `X-World-Version` e em `GET /world/version`.
- O cliente guarda o binário e a versão em `user://cache/` e pede com `If-None-Match`; se a versão não mudou, o servidor responde **304** e o cliente lê o arquivo local. Se o servidor estiver fora do ar e houver cache, o jogo abre com o mundo guardado.
- `GET /world` continua em JSON para depuração.

## Consequências
- Qualquer campo novo exige subir `BinaryFormatVersion` e atualizar `WorldData.from_binary` (o cliente recusa versões que não conhece e apaga o cache).
- Os valores numéricos dos biomas fazem parte do formato: só acrescente no fim.
