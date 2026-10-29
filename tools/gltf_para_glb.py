#!/usr/bin/env python3
"""Converte .gltf com buffers embutidos em base64 para .glb binário.

Uso: python3 tools/gltf_para_glb.py ENTRADA.gltf SAIDA.glb
Usado para os animais do Quaternius (ADR 0023): o glTF em base64 é ~35% maior e mais
lento de importar. Só aceita buffers embutidos (data URI) e junta todos num só.
"""
import base64
import json
import struct
import sys


def main(src: str, dst: str) -> None:
    with open(src, encoding="utf-8") as f:
        doc = json.load(f)
    blob = bytearray()
    offsets = []
    for buf in doc.get("buffers", []):
        uri = buf.get("uri", "")
        if not uri.startswith("data:"):
            sys.exit(f"{src}: buffer externo não suportado ({uri[:40]})")
        data = base64.b64decode(uri.split(",", 1)[1])
        while len(blob) % 4:
            blob.append(0)
        offsets.append(len(blob))
        blob.extend(data)
    for view in doc.get("bufferViews", []):
        view["byteOffset"] = view.get("byteOffset", 0) + offsets[view.get("buffer", 0)]
        view["buffer"] = 0
    for img in doc.get("images", []):
        if img.get("uri", "").startswith("data:"):
            sys.exit(f"{src}: imagem embutida não suportada")
    while len(blob) % 4:
        blob.append(0)
    doc["buffers"] = [{"byteLength": len(blob)}]
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(blob)
    with open(dst, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON"))
        f.write(js)
        f.write(struct.pack("<I4s", len(blob), b"BIN\0"))
        f.write(blob)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
