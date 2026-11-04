-- Fase 4.5 (ADR 0056, 0057): conquistas, fornalha e baú.

-- Conquistas (uma vez só por jogador).
CREATE TABLE achievements (
    player_id INTEGER NOT NULL REFERENCES players (id) ON DELETE CASCADE,
    id        TEXT    NOT NULL,
    first_at  INTEGER NOT NULL,
    PRIMARY KEY (player_id, id)
);

-- Fornalha: o que está derretendo (ou pronto), por jogador. Fica até o jogador buscar.
CREATE TABLE furnace_jobs (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    player_id INTEGER NOT NULL REFERENCES players (id) ON DELETE CASCADE,
    item      TEXT    NOT NULL,
    count     INTEGER NOT NULL CHECK (count > 0),
    ready_at  INTEGER NOT NULL -- unix
);
CREATE INDEX furnace_jobs_player ON furnace_jobs (player_id);

-- Baú: o que está guardado em cada baú colocado num lote (some junto com a peça).
CREATE TABLE chest_items (
    placement_id INTEGER NOT NULL REFERENCES placements (id) ON DELETE CASCADE,
    item         TEXT    NOT NULL,
    count        INTEGER NOT NULL CHECK (count > 0),
    seq          INTEGER NOT NULL,
    PRIMARY KEY (placement_id, item)
);
