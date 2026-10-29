-- Posição da casa em obra: na melhoria a casa cresce e pode se deslocar, mas a casa
-- atual continua no lugar dela até a obra ficar pronta.
ALTER TABLE lots ADD COLUMN pending_x INTEGER NOT NULL DEFAULT 0;
ALTER TABLE lots ADD COLUMN pending_y INTEGER NOT NULL DEFAULT 0;
UPDATE lots SET pending_x = house_x, pending_y = house_y;
