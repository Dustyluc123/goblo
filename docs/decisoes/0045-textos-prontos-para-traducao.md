# 0045 — Textos prontos para tradução, com o português como chave

**Fase 3.5** (escrito na 4.0, revisado na 4.0).

## Contexto

O jogo é em português, mas deve poder ser traduzido no futuro sem caçar texto pelo código.

## Decisão

- **O sistema de tradução do Godot com `.po`**, e o **texto em português é a chave** (`msgid`). Sem tabela de chaves artificiais: o código continua legível e o jogo em português não muda.
- Textos fixos de `Label`/`Button` são traduzidos sozinhos pelo Godot. Textos montados com `%` passam por `tr()` **no modelo, antes do `%`** (`tr("Comprar %d") % n`). Falas e nomes dos dados do servidor passam por `tr()` no cliente (`DialogUi`, `Session.item_name`).
- `client/tools/extrair_textos.py` junta os textos dos scripts e dos dados do servidor em `client/i18n/goblo.pot`. Para traduzir: copiar para `<idioma>.po`, preencher e acrescentar em Projeto → Localização.

## Consequências

- Mudou um texto em português? A tradução daquele texto volta a ficar pendente (é outra chave). Rode o extrator depois de mudar textos.
- Textos de log e de teste não entram.
