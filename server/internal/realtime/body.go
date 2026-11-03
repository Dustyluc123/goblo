package realtime

import (
	"context"
	"math"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Corpo em tempo real (fase 4.0, ADR 0050): uma vez por segundo, as necessidades de quem
// está conectado avançam (game.Service.BodyTick) e o cliente recebe a mensagem body quando
// algo muda. O multiplicador de velocidade (nível das necessidades e bônus) entra na
// validação do movimento, com a folga dos últimos segundos. Com o jogo fechado, nada cai.

const (
	bodyEvery     = time.Second
	bodySaveEvery = 30 * time.Second
	bodySendEvery = 5 * time.Second // manda mesmo sem mudança, de tempos em tempos
)

// RunBody avança as necessidades até Close.
func (h *Hub) RunBody() {
	t := time.NewTicker(bodyEvery)
	defer t.Stop()
	last := time.Now()
	lastSave := time.Now()
	for {
		select {
		case <-h.stop:
			return
		case now := <-t.C:
			h.bodyTick(now, now.Sub(last).Seconds(), now.Sub(lastSave) > bodySaveEvery)
			last = now
			if now.Sub(lastSave) > bodySaveEvery {
				lastSave = now
			}
		}
	}
}

type bodyJob struct {
	c       *client
	pos     world.Vec3
	cell    int
	running bool
}

func (h *Hub) bodyTick(now time.Time, dt float64, save bool) {
	dt = math.Min(dt, 5) // depois de uma pausa longa do servidor, não desconta tudo de uma vez
	h.mu.Lock()
	jobs := make([]bodyJob, 0, len(h.clients))
	for _, c := range h.clients {
		if c.conn != nil && c.spawned {
			jobs = append(jobs, bodyJob{c: c, pos: c.pos, cell: c.cell, running: c.anim == 2})
		}
	}
	h.mu.Unlock()
	ctx := context.Background()
	for _, j := range jobs {
		v, err := h.svc.BodyTick(ctx, j.c.id, dt, j.pos, j.cell, j.running)
		if err != nil {
			continue
		}
		speed := h.svc.SpeedFactor(j.c.id)
		h.mu.Lock()
		j.c.speed = speed
		if changedBody(j.c.lastBody, v) || now.Sub(j.c.bodySentAt) > bodySendEvery {
			j.c.lastBody = v
			j.c.bodySentAt = now
			j.c.sendJSON(map[string]any{"t": "body", "body": v})
		}
		h.mu.Unlock()
		if save {
			_ = h.svc.SaveBody(ctx, j.c.id, false)
		}
	}
}

// changedBody: mudou o que o cliente mostra (valores inteiros, nível, sensação, fontes)?
func changedBody(a, b game.BodyView) bool {
	if math.Floor(a.Thirst) != math.Floor(b.Thirst) || math.Floor(a.Hunger) != math.Floor(b.Hunger) ||
		math.Floor(a.Comfort) != math.Floor(b.Comfort) || a.Level != b.Level || a.Speed != b.Speed ||
		math.Round(a.Felt) != math.Round(b.Felt) || a.Quiet != b.Quiet || a.Dizzy != b.Dizzy ||
		len(a.Buffs) != len(b.Buffs) || len(a.Sources) != len(b.Sources) || a.Cold != b.Cold || a.Hot != b.Hot {
		return true
	}
	for i := range a.Sources {
		if a.Sources[i] != b.Sources[i] {
			return true
		}
	}
	return false
}

// saveBodyOnExit grava e tira o corpo da memória quando o jogador sai.
func (h *Hub) saveBodyOnExit(id int64) {
	go func() { _ = h.svc.SaveBody(context.Background(), id, true) }()
}

// onLook: o visual de um jogador mudou (roupa, tinta, editor). Atualiza e manda para quem vê.
func (h *Hub) onLook(id int64, look any) {
	h.mu.Lock()
	defer h.mu.Unlock()
	c := h.clients[id]
	if c == nil {
		return
	}
	if lv, ok := look.(game.LookView); ok {
		c.look = &lv
	}
	h.toWatchers(c, map[string]any{"t": "look", "id": c.id, "look": c.look})
}
