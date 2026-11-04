package realtime

import (
	"time"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Cavernas no tempo real (fase 4.5, ADR 0056). Cada caverna fica num ponto próprio, longe
// do planeta: a área de interesse (por distância) já mostra só quem está na mesma caverna.
// Aqui ficam os teleportes de entrar, voltar ao começo e sair, as mensagens das cavernas
// (minério quebrado, tochas) e o chefe, que avança a cada foto do mundo.

// caveTeleport valida e aplica um teleporte de caverna. Devolve false se recusou.
func (h *Hub) caveTeleport(c *client, why string, to world.Vec3, now time.Time) bool {
	switch why {
	case "cave":
		cv, ok := h.svc.ConsumeCaveEntry(c.id)
		if !ok {
			return false
		}
		start, _ := h.svc.CaveStartPoint(cv)
		if to.Sub(start).Len() > 6 {
			return false
		}
		c.cave = cv
	case "cave_start":
		if c.cave < 0 {
			return false
		}
		start, _ := h.svc.CaveStartPoint(c.cave)
		if to.Sub(start).Len() > 6 {
			return false
		}
	case "cave_exit":
		if c.cave < 0 {
			return false
		}
		at, _ := h.svc.CaveEntrancePoint(c.cave)
		if groundDistance(h.world, to, at) > 10 {
			return false
		}
		cell := h.world.FindCell(to, -1)
		if h.world.Cells[cell].Terrain != world.Land {
			return false
		}
		c.cave = -1
		c.cell = cell
	default:
		return false
	}
	c.pos, c.spawned = to, true
	c.allow = h.rules.Movement.Burst
	c.lastMove = now
	c.country = ""
	c.afterMove()
	c.sendJSON(map[string]any{"t": "tp", "ok": true, "why": why})
	return true
}

// caveTick avança o chefe de cada caverna com gente e manda as mensagens (dentro de tick,
// com h.mu travado).
func (h *Hub) caveTick(now time.Time) {
	byCave := map[int][]*client{}
	for _, c := range h.clients {
		if c.spawned && c.cave >= 0 {
			byCave[c.cave] = append(byCave[c.cave], c)
		}
	}
	for cave, list := range byCave {
		l := h.svc.CaveLayoutOf(cave)
		if l == nil {
			continue
		}
		f := l.FrameOf()
		present := map[int64][3]float64{}
		for _, c := range list {
			x, y, z := f.Local(c.pos)
			present[c.id] = [3]float64{x, y, z}
		}
		for _, m := range h.svc.BossTick(cave, present, now) {
			for _, c := range list {
				if m.To == 0 || m.To == c.id {
					c.sendJSON(m.Data)
				}
			}
		}
	}
}

// onCaveEvent manda um evento de caverna (minério, tochas) para quem está nela.
func (h *Hub) onCaveEvent(by int64, data any) {
	d, ok := data.(map[string]any)
	if !ok {
		return
	}
	cave, ok := d["cave"].(int)
	if !ok {
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	msg := map[string]any{"t": "cave", "by": by, "data": d}
	for _, c := range h.clients {
		if c.conn != nil && c.cave == cave && c.id != by {
			c.sendJSON(msg)
		}
	}
}
