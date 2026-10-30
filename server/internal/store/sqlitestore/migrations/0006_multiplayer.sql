-- Fase 3 (multiplayer): o personagem escolhido (um dos 12 do Mini Characters; vazio = o
-- padrão do cliente) e os bloqueios entre jogadores (quem bloqueou não vê o chat nem os
-- emotes do outro, e o outro não vê os dele).
ALTER TABLE players ADD COLUMN character TEXT NOT NULL DEFAULT '';

CREATE TABLE blocks (
    player_id  INTEGER NOT NULL REFERENCES players (id) ON DELETE CASCADE,
    blocked_id INTEGER NOT NULL REFERENCES players (id) ON DELETE CASCADE,
    created_at INTEGER NOT NULL, -- unix
    PRIMARY KEY (player_id, blocked_id)
);
CREATE INDEX blocks_blocked ON blocks (blocked_id);
