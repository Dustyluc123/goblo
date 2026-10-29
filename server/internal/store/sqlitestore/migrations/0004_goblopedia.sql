-- Fase 2.5: Goblopédia. Uma linha por jogador e coisa registrada (espécie de animal, flor
-- rara, árvore em estação). first_at = 0 enquanto não houver foto (dá para ser amigo de
-- uma espécie antes de fotografá-la). As fotos ficam só no computador do jogador.
CREATE TABLE pedia (
    player_id INTEGER NOT NULL REFERENCES players (id) ON DELETE CASCADE,
    entry     TEXT    NOT NULL,
    first_at  INTEGER NOT NULL DEFAULT 0,     -- unix da primeira foto (0 = ainda não)
    country   TEXT    NOT NULL DEFAULT '',    -- país da primeira foto (ISO A3)
    biome     TEXT    NOT NULL DEFAULT '',    -- bioma da primeira foto
    sightings INTEGER NOT NULL DEFAULT 0,     -- quantas fotos registraram essa coisa
    friend    INTEGER NOT NULL DEFAULT 0,     -- 1 = já deu frutinha (animais)
    PRIMARY KEY (player_id, entry)
);
