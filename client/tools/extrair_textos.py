#!/usr/bin/env python3
"""Junta os textos do jogo num modelo de tradução (client/i18n/goblo.pot), fase 3.5, ADR 0045.

O português é o idioma de origem: cada texto em português é a própria chave (msgid). Entram:
- os textos da interface nos scripts do cliente (rótulos, botões, avisos, tr(...));
- os textos dos dados do servidor (nomes de itens, casas, animais, Goblopédia, NPCs e as
  falas dos diálogos), que o cliente passa por tr() antes de mostrar.

Uso (da raiz do repositório):  python3 client/tools/extrair_textos.py
Para traduzir: copie goblo.pot para <idioma>.po (ex.: en.po), preencha os msgstr e acrescente
o arquivo em Projeto → Localização → Traduções. Nada aqui muda o jogo em português.
"""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "client" / "scripts"
DATA = ROOT / "server" / "data" / "game"
OUT = ROOT / "client" / "i18n" / "goblo.pot"

# Linhas de log e de teste não são da interface.
SKIP_LINE = re.compile(r"print\(|push_warning|push_error|HitchLog\.note|check\.call|_fail\(|printerr")
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')
DATA_KEYS = {"name", "title", "text", "description", "hint", "singular", "plural", "slang", "label"}


def ui_text(s: str) -> bool:
    """Parece texto para pessoas (e não chave, caminho ou formato técnico)?"""
    if len(s) < 2 or s.startswith(("res://", "user://", "http", "/", "#", "Authorization")):
        return False
    if not re.search(r"[a-záéíóúâêôãõç]", s):
        return False
    return " " in s or re.search(r"[áéíóúâêôãõçÁÉÍÓÚ]", s) is not None or s[0].isupper()


def from_scripts(found: dict) -> None:
    for path in sorted(SCRIPTS.glob("*.gd")):
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            code = line.split("##", 1)[0]
            if code.lstrip().startswith("#") or SKIP_LINE.search(code):
                continue
            for m in STRING.finditer(code):
                s = m.group(1)  # já vem escapado como no código (igual ao formato .po)
                if ui_text(s):
                    found.setdefault(s, []).append(f"client/scripts/{path.name}:{n}")


def walk(v, where: str, found: dict, key: str = "") -> None:
    if isinstance(v, dict):
        for k in sorted(v):
            if not k.startswith("_"):
                walk(v[k], where, found, k)
    elif isinstance(v, list):
        for x in v:
            walk(x, where, found, key)
    elif isinstance(v, str) and key in DATA_KEYS and ui_text(v):
        found.setdefault(esc(v), []).append(where)


def from_data(found: dict) -> None:
    for path in sorted(DATA.glob("*.json")):
        walk(json.loads(path.read_text(encoding="utf-8")), f"server/data/game/{path.name}", found)


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main() -> None:
    found: dict = {}
    from_scripts(found)
    from_data(found)
    out = ['# Textos do Goblo para tradução (gerado por client/tools/extrair_textos.py).',
           '# O português é a chave; não edite este arquivo à mão.',
           'msgid ""', 'msgstr ""', '"Content-Type: text/plain; charset=UTF-8\\n"', '"Language: pt_BR\\n"', '']
    for s in sorted(found):
        refs = sorted(set(found[s]))
        out.append("#: " + " ".join(refs[:6]))
        out.append(f'msgid "{s}"')
        out.append('msgstr ""')
        out.append("")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(out), encoding="utf-8")
    print(f"{len(found)} textos em {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
