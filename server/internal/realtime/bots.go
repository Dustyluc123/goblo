package realtime

import (
	"context"
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
	// stay: bot parado do lado do jogador (troca do modo dev); sempre aceita trocas.
	stay bool
}

var botPhrases = []string{"Oi!", "Que lugar bonito!", "Alguém viu uma vaca por aqui?", "Bom dia!", "Vou colher umas flores.", "Olha o pôr do sol!"}

var botEmotes = []string{"wave", "yes", "cheer", "sit"}

// SpawnBots cria n bots perto de pos (modo dev). Cada bot é um jogador falso no banco,
// sem lote, com alguns itens e gobolares, para dar para trocar de verdade (ADR 0044): os
// de número par aceitam pedidos de troca sozinhos. Devolve quantos foram criados.
func (h *Hub) SpawnBots(pos world.Vec3, n int, country string) int {
	if !h.dev || n <= 0 {
		return 0
	}
	made := 0
	for i := 0; i < n && i < 200; i++ {
		h.mu.Lock()
		h.nextBot++
		k := h.nextBot
		h.mu.Unlock()
		rng := rand.New(rand.NewPCG(uint64(k), 7))
		chars := h.rules.Characters
		p, err := h.svc.DevCreateBot(context.Background(), fmt.Sprintf("Bot %d", k), country, chars[rng.IntN(len(chars))])
		if err != nil {
			h.log.Warn("bot do modo dev", "erro", err)
			continue
		}
		h.mu.Lock()
		start, ok := h.landNear(pos, 3+rng.Float64()*12, rng)
		if ok {
			c := &client{hub: h, id: p.ID, player: p, spawned: true, pos: start, cell: h.world.FindCell(start, -1),
				visible: map[int64]bool{}, blocked: map[int64]bool{}, blockedBy: map[int64]bool{}, done: make(chan struct{}),
				tradeReqs: map[int64]time.Time{}, bot: &botState{center: pos, target: start, rng: rng}}
			h.clients[p.ID] = c
			made++
		}
		h.mu.Unlock()
		if !ok {
			h.svc.DevDeleteBot(context.Background(), p.ID)
		}
	}
	return made
}

// DevTradeBot cria um bot parado do lado do jogador e já abre uma troca com ele (modo dev).
// Devolve o apelido do bot.
func (h *Hub) DevTradeBot(playerID int64) (string, error) {
	h.mu.Lock()
	me := h.clients[playerID]
	if !h.dev || me == nil || !me.spawned {
		h.mu.Unlock()
		return "", game.ErrOffline
	}
	pos, country := me.pos, me.player.Country
	h.nextBot++
	k := h.nextBot
	h.mu.Unlock()
	rng := rand.New(rand.NewPCG(uint64(k), 7))
	chars := h.rules.Characters
	p, err := h.svc.DevCreateBot(context.Background(), fmt.Sprintf("Bot %d", k), country, chars[rng.IntN(len(chars))])
	if err != nil {
		return "", err
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	start, ok := h.landNear(pos, 1.6, rng)
	if !ok {
		start = pos
	}
	c := &client{hub: h, id: p.ID, player: p, spawned: true, pos: start, cell: h.world.FindCell(start, -1),
		visible: map[int64]bool{}, blocked: map[int64]bool{}, blockedBy: map[int64]bool{}, done: make(chan struct{}),
		tradeReqs: map[int64]time.Time{}, bot: &botState{center: start, target: start, rng: rng, stay: true}}
	h.clients[p.ID] = c
	if me.trade != nil {
		return p.Nickname, nil
	}
	h.nextTrade++
	t := &trade{id: h.nextTrade, sides: [2]*client{me, c}}
	me.trade, c.trade = t, t
	h.sendTrade(t, "trade_open")
	return p.Nickname, nil
}

// RemoveBots tira todos os bots do modo dev (e apaga os jogadores falsos deles).
func (h *Hub) RemoveBots() int {
	h.mu.Lock()
	var ids []int64
	for id, c := range h.clients {
		if c.bot != nil {
			h.dropTrade(c)
			h.dropVisibility(c)
			delete(h.clients, id)
			ids = append(ids, id)
		}
	}
	h.mu.Unlock()
	for _, id := range ids {
		h.svc.DevDeleteBot(context.Background(), id)
	}
	return len(ids)
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
		if dist < 0.4 || b.stay {
			c.anim = 0
			if !b.stay && now.After(b.nextAt) {
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
