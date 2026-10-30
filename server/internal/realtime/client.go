package realtime

import (
	"context"
	"encoding/json"
	"math"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/coder/websocket"

	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

// client é um jogador conectado (ou um bot do modo dev, com conn nil). Os campos de estado
// só são lidos e escritos com Hub.mu travado.
type client struct {
	hub    *Hub
	conn   *websocket.Conn
	id     int64
	player *game.Player
	state  *game.MovementState
	send   chan outMsg
	done   chan struct{}
	closed bool
	// replaced: outra conexão do mesmo jogador entrou no lugar desta.
	replaced bool

	spawned   bool
	lastKnown *lastKnown
	pos       world.Vec3
	cell      int
	yaw       float64
	anim      uint8
	flags     uint8
	seq       uint16
	country   string
	allow     float64   // distância que ainda pode andar agora (folga acumulada)
	lastMove  time.Time // última posição aceita (ou recusada)
	moveTimes []time.Time

	visible   map[int64]bool
	sentEmpty bool
	blocked   map[int64]bool // quem este jogador bloqueou
	blockedBy map[int64]bool // quem bloqueou este jogador

	chatTokens  float64
	chatAt      time.Time
	emoteTokens float64
	emoteAt     time.Time
	actTokens   float64
	actAt       time.Time

	bot *botState
}

type outMsg struct {
	typ  websocket.MessageType
	data []byte
}

func newClient(h *Hub, conn *websocket.Conn, p *game.Player, st *game.MovementState) *client {
	return &client{hub: h, conn: conn, id: p.ID, player: p, state: st, send: make(chan outMsg, 256),
		done: make(chan struct{}), cell: -1, visible: map[int64]bool{}, blocked: map[int64]bool{},
		blockedBy: map[int64]bool{}, chatTokens: float64(h.rules.Chat.Burst), emoteTokens: 2, actTokens: 4,
		chatAt: time.Now(), emoteAt: time.Now(), actAt: time.Now()}
}

// enterMsg apresenta o jogador para quem passa a vê-lo.
func (c *client) enterMsg() map[string]any {
	return map[string]any{"t": "enter", "id": c.id, "nick": c.player.Nickname, "country": c.player.Country,
		"char": c.player.Character, "bot": c.conn == nil, "pos": [3]float64{c.pos.X, c.pos.Y, c.pos.Z}}
}

func (c *client) sendJSON(v any) { c.enqueue(outMsg{websocket.MessageText, marshal(v)}) }

func (c *client) sendBinary(b []byte) { c.enqueue(outMsg{websocket.MessageBinary, b}) }

// enqueue não trava: se a fila encheu (conexão lenta demais), a conexão cai e o cliente
// reconecta.
func (c *client) enqueue(m outMsg) {
	if c.conn == nil || c.closed {
		return
	}
	select {
	case c.send <- m:
	default:
		c.close(websocket.StatusPolicyViolation, "fila cheia")
	}
}

// kick avisa o cliente e fecha a conexão depois que o aviso sai (até 1 s).
func (c *client) kick(reason string) {
	c.sendJSON(map[string]any{"t": "kick", "reason": reason})
	go func() {
		end := time.Now().Add(time.Second)
		for len(c.send) > 0 && time.Now().Before(end) {
			time.Sleep(10 * time.Millisecond)
		}
		time.Sleep(50 * time.Millisecond)
		c.hub.mu.Lock()
		c.close(websocket.StatusPolicyViolation, "conexão duplicada")
		c.hub.mu.Unlock()
	}()
}

func (c *client) close(code websocket.StatusCode, reason string) {
	if c.closed {
		return
	}
	c.closed = true
	close(c.done)
	if c.conn != nil {
		go c.conn.Close(code, reason)
	}
}

func (c *client) writeLoop() {
	for {
		select {
		case <-c.done:
			return
		case m := <-c.send:
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			err := c.conn.Write(ctx, m.typ, m.data)
			cancel()
			if err != nil {
				return
			}
			c.hub.bytesOut.Add(int64(len(m.data)))
			c.hub.msgsOut.Add(1)
		}
	}
}

func (c *client) readLoop(ctx context.Context) {
	for {
		typ, data, err := c.conn.Read(ctx)
		if err != nil {
			return
		}
		c.hub.bytesIn.Add(int64(len(data)))
		c.hub.msgsIn.Add(1)
		now := time.Now()
		if typ == websocket.MessageBinary {
			if m, err := DecodeMove(data); err == nil {
				c.hub.mu.Lock()
				c.onMove(m, now)
				c.hub.mu.Unlock()
			}
			continue
		}
		var msg map[string]any
		if json.Unmarshal(data, &msg) != nil {
			continue
		}
		c.onText(ctx, msg, now)
	}
}

// --- Movimento ------------------------------------------------------------------------------

// rateOK: no máximo max_moves_per_sec posições por segundo.
func (c *client) rateOK(now time.Time) bool {
	cut := now.Add(-time.Second)
	k := 0
	for _, t := range c.moveTimes {
		if t.After(cut) {
			c.moveTimes[k] = t
			k++
		}
	}
	c.moveTimes = c.moveTimes[:k]
	if len(c.moveTimes) >= c.hub.rules.Network.MaxMovesPerSec {
		return false
	}
	c.moveTimes = append(c.moveTimes, now)
	return true
}

// onMove valida a posição (ADR 0039). Sem posição ainda (acabou de entrar), vale como o
// teleporte de nascimento.
func (c *client) onMove(m Move, now time.Time) {
	if !c.rateOK(now) {
		return
	}
	if !c.spawned {
		c.teleport("spawn", m.Pos, now)
		return
	}
	reason := c.hub.validateMove(c, m.Pos, m.Flags, now)
	c.seq = m.Seq
	if reason != 0 {
		c.sendBinary(EncodeCorrection(m.Seq, c.pos, reason))
		return
	}
	c.yaw, c.anim, c.flags = m.Yaw, m.Anim, m.Flags
	c.afterMove()
}

// afterMove: carimbo a pé quando entra num país de que tem passaporte (ADR 0040).
func (c *client) afterMove() {
	country := c.hub.svc.CountryAtPoint(c.pos)
	if country == c.country {
		return
	}
	c.country = country
	if country == "" || c.state == nil || !c.state.Passports[country] || c.state.Stamped[country] {
		return
	}
	c.state.Stamped[country] = true
	p := c.player
	go func() {
		res, err := c.hub.svc.Stamp(context.Background(), p, country)
		if err != nil || res == nil || res.Stamp == nil {
			return
		}
		c.hub.mu.Lock()
		c.sendJSON(map[string]any{"t": "stamp", "result": res})
		c.hub.mu.Unlock()
	}()
}

// validateMove devolve 0 se o passo de c.pos para to é válido, ou o motivo da correção.
func (h *Hub) validateMove(c *client, to world.Vec3, flags uint8, now time.Time) byte {
	mv := h.rules.Movement
	dt := now.Sub(c.lastMove).Seconds()
	c.lastMove = now
	limit := mv.Burst + mv.MaxSpeed*0.25
	c.allow = math.Min(c.allow+mv.MaxSpeed*dt, limit)
	noclip := flags&FlagNoclip != 0 && h.dev
	d := groundDistance(h.world, c.pos, to)
	if !noclip && d > c.allow+0.05 {
		return ReasonSpeed
	}
	cell := h.world.FindCell(to, c.cell)
	top := h.world.Radius + h.world.Cells[cell].Height
	if h.world.Cells[cell].Terrain != world.Land {
		top = h.world.Radius
	}
	if r := to.Len(); !noclip && (r > top+mv.MaxAbove || r < top-mv.MaxBelow) {
		return ReasonHeight
	}
	if !noclip && h.world.Cells[cell].Terrain != world.Land && h.world.Cells[c.cell].Terrain == world.Land {
		return ReasonOcean
	}
	if !noclip && c.state != nil && !h.svc.CanWalk(c.player, c.state.Lot, c.state.Passports, c.pos, to, cell) {
		return ReasonBorder
	}
	c.allow -= d
	c.pos, c.cell = to, cell
	return 0
}

func groundDistance(w *world.World, a, b world.Vec3) float64 {
	d := a.Normalize().Dot(b.Normalize())
	return math.Acos(math.Max(-1, math.Min(1, d))) * w.Radius
}

// teleport: nascimento, casa (H), chegada do voo e modo dev passam pelo servidor.
func (c *client) teleport(why string, to world.Vec3, now time.Time) {
	h := c.hub
	mv := h.rules.Movement
	ok := false
	if finite(to) {
		cell := h.world.FindCell(to, c.cell)
		land := h.world.Cells[cell].Terrain == world.Land
		home := c.state != nil && c.state.Lot != nil && groundDistance(h.world, to, c.state.Home) <= mv.HomeRadius
		switch why {
		case "spawn":
			// Primeira posição: em casa, onde estava antes (reconexão) ou qualquer lugar no
			// modo dev (testes nascem em qualquer canto).
			back := c.lastKnown != nil && groundDistance(h.world, to, c.lastKnown.pos) <= 60
			ok = land && (h.dev || home || back || c.state == nil || c.state.Lot == nil)
		case "home":
			ok = home
		case "travel":
			if p, has := h.svc.ConsumeArrival(c.id); has {
				ok = groundDistance(h.world, to, p) <= mv.TravelRadius
			}
		case "dev":
			ok = h.dev
		}
		if ok {
			if !land {
				ok = false
			}
		}
		if ok {
			c.pos, c.cell, c.spawned = to, cell, true
			c.allow = mv.Burst
			c.lastMove = now
			c.country = ""
			c.afterMove()
			c.sendJSON(map[string]any{"t": "tp", "ok": true, "why": why})
			return
		}
	}
	h.log.Info("tempo real: teleporte recusado", "jogador", c.player.Nickname, "motivo", why)
	c.sendJSON(map[string]any{"t": "tp", "ok": false, "why": why})
	if c.spawned {
		c.sendBinary(EncodeCorrection(c.seq, c.pos, ReasonTeleport))
	}
}

// --- Texto (chat, emotes, ações, teleporte, bloqueio, ping) -------------------------------

func str(m map[string]any, k string) string {
	s, _ := m[k].(string)
	return s
}

func num(m map[string]any, k string) float64 {
	f, _ := m[k].(float64)
	return f
}

func vec(m map[string]any, k string) world.Vec3 {
	a, _ := m[k].([]any)
	if len(a) != 3 {
		return world.Vec3{X: math.NaN()}
	}
	f := func(i int) float64 { x, _ := a[i].(float64); return x }
	return world.Vec3{X: f(0), Y: f(1), Z: f(2)}
}

// Emotes que existem (animações do Mini Characters, no cliente).
var emotes = map[string]bool{"wave": true, "yes": true, "no": true, "sit": true, "cheer": true}

// Ações que os outros veem (animação de coletar, carinho, foto…).
var actions = map[string]bool{"shake": true, "chop": true, "mine": true, "pick": true, "pet": true, "feed": true, "photo": true}

// bucket: quantas mensagens de um tipo ainda pode mandar agora.
func bucket(tokens *float64, at *time.Time, now time.Time, perSec, burst float64) bool {
	*tokens = math.Min(burst, *tokens+now.Sub(*at).Seconds()*perSec)
	*at = now
	if *tokens < 1 {
		return false
	}
	*tokens--
	return true
}

func (c *client) onText(ctx context.Context, m map[string]any, now time.Time) {
	h := c.hub
	switch str(m, "t") {
	case "ping":
		h.mu.Lock()
		c.sendJSON(map[string]any{"t": "pong", "c": m["c"], "s": h.serverMs(now)})
		h.mu.Unlock()
	case "tp":
		h.mu.Lock()
		c.teleport(str(m, "why"), vec(m, "pos"), now)
		h.mu.Unlock()
	case "chat":
		h.mu.Lock()
		c.chat(str(m, "text"), now)
		h.mu.Unlock()
	case "emote":
		e := str(m, "e")
		h.mu.Lock()
		if emotes[e] && c.spawned && bucket(&c.emoteTokens, &c.emoteAt, now, h.rules.Chat.EmotePerSec, 2) {
			h.toWatchers(c, map[string]any{"t": "emote", "id": c.id, "e": e})
		}
		h.mu.Unlock()
	case "act":
		a := str(m, "a")
		h.mu.Lock()
		if actions[a] && c.spawned && bucket(&c.actTokens, &c.actAt, now, 3, 4) && c.actNear(a, int64(num(m, "animal")), now) {
			h.toWatchers(c, map[string]any{"t": "act", "id": c.id, "a": a, "animal": int64(num(m, "animal"))})
		}
		h.mu.Unlock()
	case "block":
		other := int64(num(m, "id"))
		on, _ := m["on"].(bool)
		if err := h.svc.SetBlock(ctx, c.player, other, on); err != nil {
			h.mu.Lock()
			c.sendJSON(map[string]any{"t": "info", "text": err.Error()})
			h.mu.Unlock()
			return
		}
		h.mu.Lock()
		c.setBlocked(other, on)
		h.mu.Unlock()
	case "char":
		ch := str(m, "c")
		if err := h.svc.SetCharacter(ctx, c.player, ch); err != nil {
			return
		}
		h.mu.Lock()
		h.toWatchers(c, map[string]any{"t": "char", "id": c.id, "c": ch})
		h.mu.Unlock()
	}
}

func (c *client) setBlocked(other int64, on bool) {
	if on {
		c.blocked[other] = true
	} else {
		delete(c.blocked, other)
	}
	if o := c.hub.clients[other]; o != nil {
		if on {
			o.blockedBy[c.id] = true
		} else {
			delete(o.blockedBy, c.id)
		}
	}
	c.sendJSON(map[string]any{"t": "blocked", "id": other, "on": on})
}

// actNear: carinho e frutinha só perto do animal (com a folga das reações locais).
func (c *client) actNear(a string, animal int64, now time.Time) bool {
	if a != "pet" && a != "feed" {
		return true
	}
	h := c.hub
	cell := game.AnimalCell(animal)
	if animal < 0 || cell < 0 || cell >= len(h.world.Cells) {
		return false
	}
	list, err := h.svc.Animals(context.Background(), []int{cell})
	if err != nil {
		return false
	}
	for i := range list {
		if list[i].ID == animal {
			r := h.rules.Reach.Animal + h.rules.Reach.AnimalDrift
			return groundDistance(h.world, c.pos, h.svc.AnimalPoint(&list[i], now)) <= r
		}
	}
	return false
}

// toWatchers manda para quem vê o jogador (e para ele mesmo), menos quem bloqueou ou foi
// bloqueado.
func (h *Hub) toWatchers(c *client, msg map[string]any) {
	data := marshal(msg)
	c.enqueue(outMsg{websocket.MessageText, data})
	for _, o := range h.clients {
		if o != c && o.visible[c.id] && !o.blocked[c.id] && !o.blockedBy[c.id] {
			o.enqueue(outMsg{websocket.MessageText, data})
		}
	}
}

// chat: filtro de palavrões (o mesmo do apelido), tamanho máximo e limite por segundo. O
// balão vai para quem está a até chat.radius.
func (c *client) chat(text string, now time.Time) {
	h := c.hub
	text = strings.TrimSpace(strings.ReplaceAll(text, "\n", " "))
	if text == "" || !c.spawned {
		return
	}
	if !bucket(&c.chatTokens, &c.chatAt, now, 1/h.rules.Chat.PerSeconds, float64(h.rules.Chat.Burst)) {
		c.sendJSON(map[string]any{"t": "info", "text": "Calma! Espere um pouquinho para mandar outra mensagem."})
		return
	}
	if utf8.RuneCountInString(text) > h.rules.Chat.MaxChars {
		text = string([]rune(text)[:h.rules.Chat.MaxChars])
	}
	text = CleanChat(text)
	msg := marshal(map[string]any{"t": "chat", "id": c.id, "nick": c.player.Nickname, "text": text})
	c.enqueue(outMsg{websocket.MessageText, msg})
	h.nearby(c.pos, h.rules.Chat.Radius, func(o *client) {
		if o != c && !o.blocked[c.id] && !o.blockedBy[c.id] {
			o.enqueue(outMsg{websocket.MessageText, msg})
		}
	})
}

// CleanChat troca palavrões por coraçõezinhos. Se a mensagem inteira, junta, formar um
// palavrão disfarçado ("m e r d a"), ela vira só coraçõezinhos.
func CleanChat(text string) string {
	words := strings.Fields(text)
	changed := false
	for i, w := range words {
		if game.IsProfane(w) {
			words[i] = strings.Repeat("♡", max(3, min(6, utf8.RuneCountInString(w))))
			changed = true
		}
	}
	out := strings.Join(words, " ")
	if !changed && game.IsProfane(text) {
		return "♡♡♡"
	}
	return out
}

const typText = websocket.MessageText
