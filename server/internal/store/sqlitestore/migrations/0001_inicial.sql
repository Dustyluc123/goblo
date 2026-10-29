-- Fase 2: jogadores, lotes (com a casa e a obra), inventário, coletas do dia e objetos
-- colocados nos lotes.

CREATE TABLE players (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    nickname   TEXT    NOT NULL UNIQUE COLLATE NOCASE,
    country    TEXT    NOT NULL,              -- ISO A3
    token_hash TEXT    NOT NULL UNIQUE,       -- sha256 do token; o token não é guardado
    created_at INTEGER NOT NULL,              -- unix
    fake       INTEGER NOT NULL DEFAULT 0     -- criado pelo modo dev
);

-- Um lote por jogador. id = célula × 4 + posição, então dois jogadores nunca têm o mesmo.
-- A casa e a obra em andamento ficam aqui: pending_level > 0 = obra até ready_at.
CREATE TABLE lots (
    id            INTEGER PRIMARY KEY,
    cell          INTEGER NOT NULL,
    slot          INTEGER NOT NULL,
    owner_id      INTEGER NOT NULL UNIQUE REFERENCES players (id) ON DELETE CASCADE,
    house_level   INTEGER NOT NULL DEFAULT 0,
    pending_level INTEGER NOT NULL DEFAULT 0,
    ready_at      INTEGER NOT NULL DEFAULT 0, -- unix
    house_x       INTEGER NOT NULL DEFAULT 0,
    house_y       INTEGER NOT NULL DEFAULT 0,
    house_rot     INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX lots_cell ON lots (cell);

CREATE TABLE inventory (
    player_id INTEGER NOT NULL REFERENCES players (id) ON DELETE CASCADE,
    item      TEXT    NOT NULL,
    count     INTEGER NOT NULL CHECK (count > 0),
    seq       INTEGER NOT NULL,               -- ordem de chegada (para a tela do inventário)
    PRIMARY KEY (player_id, item)
);

-- Quantas vezes o jogador fez uma ação num objeto num dia do jogo (vira às 5h locais).
CREATE TABLE collections (
    player_id INTEGER NOT NULL REFERENCES players (id) ON DELETE CASCADE,
    object_id INTEGER NOT NULL,
    cell      INTEGER NOT NULL,
    action    TEXT    NOT NULL,
    day       INTEGER NOT NULL,
    count     INTEGER NOT NULL,
    PRIMARY KEY (player_id, object_id, action, day)
);
CREATE INDEX collections_cell ON collections (player_id, day, cell);

-- Objetos colocados nos lotes (decoração e bancada), na grade de 16 × 16 quadradinhos.
CREATE TABLE placements (
    id     INTEGER PRIMARY KEY AUTOINCREMENT,
    lot_id INTEGER NOT NULL REFERENCES lots (id) ON DELETE CASCADE,
    item   TEXT    NOT NULL,
    x      INTEGER NOT NULL,
    y      INTEGER NOT NULL,
    rot    INTEGER NOT NULL
);
CREATE INDEX placements_lot ON placements (lot_id);
