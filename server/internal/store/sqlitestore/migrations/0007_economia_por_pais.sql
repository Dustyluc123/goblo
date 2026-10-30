-- Fase 3.5: economia preparada para o governo de cada país (ADR 0041). Cada transação diz
-- em que país aconteceu e separa o preço e o imposto (hoje zero); o imposto vai para o cofre
-- do país. Também guarda se o jogador já viu a apresentação do guia.
ALTER TABLE transactions ADD COLUMN country TEXT    NOT NULL DEFAULT '';
ALTER TABLE transactions ADD COLUMN price   INTEGER NOT NULL DEFAULT 0;
ALTER TABLE transactions ADD COLUMN tax     INTEGER NOT NULL DEFAULT 0;

CREATE TABLE treasuries (
    country    TEXT    PRIMARY KEY,           -- ISO A3
    balance    INTEGER NOT NULL DEFAULT 0 CHECK (balance >= 0),
    updated_at INTEGER NOT NULL DEFAULT 0     -- unix
);

ALTER TABLE players ADD COLUMN intro_done  INTEGER NOT NULL DEFAULT 0;
-- Quem já jogava não vê a apresentação.
UPDATE players SET intro_done = 1;
-- Tarefas da apresentação já recompensadas (separadas por vírgula).
ALTER TABLE players ADD COLUMN intro_tasks TEXT    NOT NULL DEFAULT '';
