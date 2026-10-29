-- Fase 2.5: passaportes e carimbos. O passaporte do país de residência é implícito (grátis,
-- não fica aqui). Um carimbo por país, com a data da primeira visita.
CREATE TABLE passports (
    player_id  INTEGER NOT NULL REFERENCES players (id) ON DELETE CASCADE,
    country    TEXT    NOT NULL,              -- ISO A3
    created_at INTEGER NOT NULL,              -- unix
    PRIMARY KEY (player_id, country)
);

CREATE TABLE stamps (
    player_id INTEGER NOT NULL REFERENCES players (id) ON DELETE CASCADE,
    country   TEXT    NOT NULL,               -- ISO A3
    first_at  INTEGER NOT NULL,               -- unix da primeira visita
    PRIMARY KEY (player_id, country)
);
