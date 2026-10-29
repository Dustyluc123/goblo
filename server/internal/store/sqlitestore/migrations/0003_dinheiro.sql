-- Fase 2.5: dinheiro. O saldo fica no jogador; cada mudança vira uma linha do histórico
-- (para depurar e para a loja e a troca da fase 4).
ALTER TABLE players ADD COLUMN coins INTEGER NOT NULL DEFAULT 0 CHECK (coins >= 0);

CREATE TABLE transactions (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    player_id  INTEGER NOT NULL REFERENCES players (id) ON DELETE CASCADE,
    delta      INTEGER NOT NULL,              -- positivo = ganhou, negativo = gastou
    balance    INTEGER NOT NULL,              -- saldo depois da transação
    reason     TEXT    NOT NULL,              -- sell, travel, passport, pedia, stamp, start, dev
    ref        TEXT    NOT NULL DEFAULT '',   -- o que foi vendido, o país, a espécie…
    created_at INTEGER NOT NULL               -- unix
);
CREATE INDEX transactions_player ON transactions (player_id, id);
