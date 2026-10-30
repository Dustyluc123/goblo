package realtime

import (
	"fmt"
	"math"
	"math/rand/v2"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

// botState: bots do modo dev ("criar bots perto de mim"), dentro do próprio servidor. Andam
// devagar por perto (sempre em terra), mandam emotes e falam de vez em quando. Servem para
// ver outros jogadores e testar a interpolação sem abrir vários jogos.
type botState struct {
	center  world.Vec3
	target  world.Vec3
	rng     *rand.Rand
	nextAt  time.Time
	running bool
}

var botPhrases = []string{"Oi!", "Que lugar bonito!", "Alguém viu uma vaca por aqui?", "Bom dia!", "Vou colher umas flores.", "Olha o pôr do sol!"}

var botEmotes = []string{"wave", "yes", "cheer", "sit"}

// SpawnBots cria n bots perto de pos (modo dev). Devolve quantos foram criados.
func (h *Hub) SpawnBots(pos world.Vec3, n int, country string) int {
	if !h.dev || n <= 0 {
		return 0
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	made := 0
	for i := 0; i < n && i < 200; i++ {
		h.nextBot--
		id := h.nextBot
		rng := rand.New(rand.NewPCG(uint64(-id), 7))
		start, ok := h.landNear(pos, 3+rng.Float64()*12, rng)
		if !ok {
			continue
		}
		chars := h.rules.Characters
		p := &game.Player{ID: id, Nickname: fmt.Sprintf("Bot %d", -id), Country: country, Character: chars[rng.IntN(len(chars))]}
		c := &client{hub: h, id: id, player: p, spawned: true, pos: start, cell: h.world.FindCell(start, -1),
			visible: map[int64]bool{}, blocked: map[int64]bool{}, blockedBy: map[int64]bool{}, done: make(chan struct{}),
			bot: &botState{center: pos, target: start, rng: rng}}
		h.clients[id] = c
		made++
	}
	return made
}

// RemoveBots tira todos os bots do modo dev.
func (h *Hub) RemoveBots() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	n := 0
	for id, c := range h.clients {
		if c.bot != nil {
			h.dropVisibility(c)
			delete(h.clients, id)
			n++
		}
	}
	return n
}

// landNear sorteia um ponto em terra a até r unidades de pos.
func (h *Hub) landNear(pos world.Vec3, r float64, rng *rand.Rand) (world.Vec3, bool) {
	east, north := Tangent(pos)
	for try := 0; try < 12; try++ {
		a := rng.Float64() * 2 * math.Pi
		d := r * math.Sqrt(rng.Float64())
		p := pos.Add(east.Scale(d * math.Cos(a))).Add(north.Scale(d * math.Sin(a)))
		cell := h.world.FindCell(p, -1)
		c := h.world.Cells[cell]
		if c.Terrain != world.Land {
			continue
		}
		return p.Normalize().Scale(h.world.Radius + c.Height), true
	}
	return world.Vec3{}, false
}

// moveBots anda com os bots (no tick, com Hub.mu travado).
func (h *Hub) moveBots(now time.Time) {
	dt := 1 / float64(h.rules.Network.SnapshotHz)
	for _, c := range h.clients {
		b := c.bot
		if b == nil {
			continue
		}
		to := b.target.Sub(c.pos)
		up := c.pos.Normalize()
		to = to.Sub(up.Scale(to.Dot(up)))
		dist := to.Len()
		speed := 5.3
		if b.running {
			speed *= 2.3
		}
		if dist < 0.4 {
			c.anim = 0
			if now.After(b.nextAt) {
				if t, ok := h.landNear(b.center, 16, b.rng); ok {
					b.target = t
					b.running = b.rng.IntN(4) == 0
				}
				b.nextAt = now.Add(time.Duration(1+b.rng.IntN(5)) * time.Second)
				switch b.rng.IntN(10) {
				case 0:
					h.toWatchers(c, map[string]any{"t": "emote", "id": c.id, "e": botEmotes[b.rng.IntN(len(botEmotes))]})
				case 1:
					msg := marshal(map[string]any{"t": "chat", "id": c.id, "nick": c.player.Nickname, "text": botPhrases[b.rng.IntN(len(botPhrases))]})
					h.nearby(c.pos, h.rules.Chat.Radius, func(o *client) { o.enqueue(outMsg{typText, msg}) })
				}
			}
			continue
		}
		step := math.Min(dist, speed*dt)
		dir := to.Scale(1 / dist)
		p := c.pos.Add(dir.Scale(step))
		cell := h.world.FindCell(p, c.cell)
		if h.world.Cells[cell].Terrain != world.Land {
			b.target = c.pos
			continue
		}
		c.pos = p.Normalize().Scale(h.world.Radius + h.world.Cells[cell].Height)
		c.cell = cell
		e, n := Tangent(c.pos)
		c.yaw = math.Atan2(dir.Dot(n), dir.Dot(e))
		c.anim = 1
		if b.running {
			c.anim = 2
		}
		c.flags = FlagOnFloor
	}
}
