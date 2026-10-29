# 0018 — SQLite em Go puro, atrás de repositórios

**Status:** aceita (fase 2)

## Contexto
A fase 2 precisa guardar jogadores, lotes, inventário, coletas do dia, objetos colocados e obras. O briefing pede SQLite sem cgo (no Mac Intel do autor, ferramentas que dependem do Xcode estão dando problema) e acesso atrás de interfaces, para trocar por PostgreSQL depois.

## Decisão
- Driver **`modernc.org/sqlite`** (SQLite traduzido para Go, sem cgo). O servidor continua sendo um binário só, que compila em qualquer máquina com Go.
- As regras (`internal/game`) só conhecem a interface **`game.Store`**, que junta `PlayerRepository`, `LotRepository`, `InventoryRepository`, `CollectionRepository` e `PlacementRepository`, mais `InTx` (transação). A implementação fica em `internal/store/sqlitestore`.
- **Migrações versionadas** em `internal/store/sqlitestore/migrations/NNNN_nome.sql`, embutidas no binário e aplicadas em ordem na abertura (tabela `schema_migrations`).
- A obra em andamento fica na própria tabela `lots` (`pending_level`, `ready_at`), em vez de uma tabela separada: um lote tem no máximo uma obra.
- Uma conexão só (`SetMaxOpenConns(1)`) e um mutex nas regras: SQLite tem um escritor por vez, e assim nada dá "database is locked".
- O arquivo do banco (`goblo.db`, configurável com `-db`) fica fora do Git (`*.db` no `.gitignore`).
- Os testes usam o SQLite de verdade num arquivo temporário (é Go puro, roda no CI).

## Consequências
- Trocar por PostgreSQL = escrever outro pacote que implemente `game.Store` e uma migração equivalente; as regras não mudam.
- O driver em Go puro é um pouco mais lento que o original em C, o que não importa nesta escala.
- Com uma conexão só, o servidor atende as escritas em fila. Para o multiplayer de verdade (fase 3), revisar (PostgreSQL ou SQLite com WAL e várias conexões de leitura).
