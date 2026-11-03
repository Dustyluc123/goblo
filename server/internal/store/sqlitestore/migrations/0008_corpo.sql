-- Fase 4.0: corpo do jogador (necessidades, bônus, modo tranquilo, visual e roupas), como
-- JSON (game.bodyRecord). Só muda com o jogador conectado.
CREATE TABLE player_body (
    player_id  INTEGER PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
    data       TEXT    NOT NULL,
    updated_at INTEGER NOT NULL
);
