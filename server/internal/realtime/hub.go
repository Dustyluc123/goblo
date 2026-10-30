package realtime

import (
	"context"
	"encoding/json"
	"log/slog"
	"math"
	"net/http"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"

	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Hub guarda as conexões e o estado em tempo real de cada jogador. Um mutex só protege
// tudo: as mensagens são curtas e a foto do mundo (tick) leva poucos microssegundos por
// jogador.
type Hub struct {
	svc   *game.Service
	world *world.World
	rules game.Rules
	log   *slog.Logger
	dev   bool
	start time.Time

	mu      sync.Mutex
	clients map[int64]*client   // por jogador (bots do modo dev têm id negativo)
	last    map[int64]lastKnown // última posição de quem saiu (reconexão)
	nextBot int64

	// Estatísticas (painel dev e teste de carga).
	bytesIn, bytesOut, msgsIn, msgsOut atomic.Int64

	stop chan struct{}
}

type lastKnown struct {
	pos  world.Vec3
	cell int
	at   time.Time
}

// NewHub monta a camada em tempo real. Chame Run para começar a mandar as fotos.
func NewHub(svc *game.Service, log *slog.Logger, dev bool) *Hub {
	return &Hub{svc: svc, world: svc.World(), rules: svc.Content().Rules, log: log, dev: dev,
		start: time.Now(), clients: map[int64]*client{}, last: map[int64]lastKnown{}, stop: make(chan struct{})}
}

// Run manda as fotos do mundo snapshot_hz vezes por segundo até Close.
func (h *Hub) Run() {
	t := time.NewTicker(time.Second / time.Duration(h.rules.Network.SnapshotHz))
	defer t.Stop()
	for {
		select {
		case <-h.stop:
			return
		case <-t.C:
			h.tick(time.Now())
		}
	}
}

// Close para o hub e fecha as conexões.
func (h *Hub) Close() {
	close(h.stop)
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, c := range h.clients {
		c.close(websocket.StatusGoingAway, "servidor parando")
	}
}

func (h *Hub) serverMs(now time.Time) uint32 { return uint32(now.Sub(h.start).Milliseconds()) }

// Where implementa game.Presence: a posição validada do jogador conectado.
func (h *Hub) Where(player int64) (world.Vec3, int, world.Vec3, bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	c := h.clients[player]
	if c == nil || !c.spawned {
		return world.Vec3{}, -1, world.Vec3{}, false
	}
	return c.pos, c.cell, Facing(c.pos, c.yaw), true
}

// ServeWS aceita a conexão de um jogador (GET /ws, token no Authorization ou em ?token=).
func (h *Hub) ServeWS(w http.ResponseWriter, r *http.Request) {
	token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	if token == "" {
		token = r.URL.Query().Get("token")
	}
	p, err := h.svc.Authenticate(r.Context(), token)
	if err != nil {
		http.Error(w, "Jogador não identificado.", http.StatusUnauthorized)
		return
	}
	st, err := h.svc.MovementStateOf(r.Context(), p)
	if err != nil {
		http.Error(w, "erro", http.StatusInternalServerError)
		return
	}
	blocked, blockedBy, err := h.svc.Blocks(r.Context(), p)
	if err != nil {
		http.Error(w, "erro", http.StatusInternalServerError)
		return
	}
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true})
	if err != nil {
		return
	}
	conn.SetReadLimit(int64(h.rules.Network.MaxMessageBytes))
	c := newClient(h, conn, p, st)
	for _, id := range blocked {
		c.blocked[id] = true
	}
	for _, id := range blockedBy {
		c.blockedBy[id] = true
	}
	h.register(c)
	go c.writeLoop()
	c.readLoop(r.Context()) // até a conexão fechar
	h.unregister(c)
}

// register entra com o jogador; uma conexão antiga do mesmo jogador é encerrada.
func (h *Hub) register(c *client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if old := h.clients[c.id]; old != nil {
		old.replaced = true
		old.kick("Você entrou de outro lugar.")
		h.dropVisibility(old)
		if old.spawned { // a conexão nova continua de onde a antiga estava
			h.last[c.id] = lastKnown{pos: old.pos, cell: old.cell, at: time.Now()}
		}
	}
	h.clients[c.id] = c
	if lk, ok := h.last[c.id]; ok {
		c.lastKnown = &lk
	}
	c.sendJSON(map[string]any{"t": "welcome", "id": c.id, "server_ms": h.serverMs(time.Now()),
		"send_hz": h.rules.Network.SendHz, "interp_delay_ms": h.rules.Network.InterpDelayMs,
		"animated_near": h.rules.Network.AnimatedNear, "anim_lod_distance": h.rules.Network.AnimLodDistance,
		"chat_max": h.rules.Chat.MaxChars, "resumed": c.lastKnown != nil})
	h.log.Info("tempo real: entrou", "jogador", c.player.Nickname, "conectados", len(h.clients))
}

func (h *Hub) unregister(c *client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	c.close(websocket.StatusNormalClosure, "")
	if h.clients[c.id] != c {
		return // já foi trocada por uma conexão nova
	}
	delete(h.clients, c.id)
	if c.spawned {
		h.last[c.id] = lastKnown{pos: c.pos, cell: c.cell, at: time.Now()}
	} else if c.lastKnown != nil {
		h.last[c.id] = *c.lastKnown // saiu sem nascer: guarda a posição de antes
	}
	h.dropVisibility(c)
	h.log.Info("tempo real: saiu", "jogador", c.player.Nickname, "conectados", len(h.clients))
}

// dropVisibility tira o jogador da tela de quem o via.
func (h *Hub) dropVisibility(c *client) {
	for _, o := range h.clients {
		if o.visible[c.id] {
			delete(o.visible, c.id)
			o.sendJSON(map[string]any{"t": "leave", "id": c.id})
		}
	}
}

// --- Foto do mundo (área de interesse) -----------------------------------------------------

type bucketKey [3]int

func (h *Hub) bucketOf(p world.Vec3) bucketKey {
	r := h.rules.Network.InterestRadius
	return bucketKey{int(math.Floor(p.X / r)), int(math.Floor(p.Y / r)), int(math.Floor(p.Z / r))}
}

// tick: para cada jogador, quem está perto (até interest_radius, no máximo max_visible, os
// mais perto primeiro); avisa quem entrou e saiu e manda a foto com as posições.
func (h *Hub) tick(now time.Time) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.moveBots(now)
	buckets := map[bucketKey][]*client{}
	for _, c := range h.clients {
		if c.spawned {
			k := h.bucketOf(c.pos)
			buckets[k] = append(buckets[k], c)
		}
	}
	r := h.rules.Network.InterestRadius
	ms := h.serverMs(now)
	type near struct {
		c *client
		d float64
	}
	for _, c := range h.clients {
		if c.conn == nil || !c.spawned {
			continue
		}
		k := h.bucketOf(c.pos)
		var list []near
		for dx := -1; dx <= 1; dx++ {
			for dy := -1; dy <= 1; dy++ {
				for dz := -1; dz <= 1; dz++ {
					for _, o := range buckets[bucketKey{k[0] + dx, k[1] + dy, k[2] + dz}] {
						if o == c {
							continue
						}
						if d := o.pos.Sub(c.pos).Len(); d <= r {
							list = append(list, near{o, d})
						}
					}
				}
			}
		}
		sort.Slice(list, func(i, j int) bool {
			return list[i].d < list[j].d || (list[i].d == list[j].d && list[i].c.id < list[j].c.id)
		})
		if len(list) > h.rules.Network.MaxVisible {
			list = list[:h.rules.Network.MaxVisible]
		}
		seen := map[int64]bool{}
		entries := make([]Entry, 0, len(list))
		for _, n := range list {
			o := n.c
			seen[o.id] = true
			if !c.visible[o.id] {
				c.sendJSON(o.enterMsg())
			}
			entries = append(entries, Entry{ID: int32(o.id), Pos: o.pos, Yaw: o.yaw, Anim: o.anim, Flags: o.flags})
		}
		for id := range c.visible {
			if !seen[id] {
				c.sendJSON(map[string]any{"t": "leave", "id": id})
			}
		}
		c.visible = seen
		if len(entries) > 0 || !c.sentEmpty {
			c.sendBinary(EncodeSnapshot(ms, entries))
			c.sentEmpty = len(entries) == 0
		}
	}
}

// nearby chama fn para cada jogador conectado a até r unidades de pos.
func (h *Hub) nearby(pos world.Vec3, r float64, fn func(*client)) {
	for _, c := range h.clients {
		if c.conn != nil && c.spawned && c.pos.Sub(pos).Len() <= r {
			fn(c)
		}
	}
}

// --- Eventos do mundo (game.Service) --------------------------------------------------------

// OnEvent recebe os eventos das regras e manda para quem está perto.
func (h *Hub) OnEvent(e game.Event) {
	switch e.Kind {
	case "passports":
		go h.refreshState(e.PlayerID)
		return
	}
	if e.Cell < 0 || e.Cell >= len(h.world.Cells) {
		return
	}
	c := h.world.Cells[e.Cell].Center
	center := world.Vec3{X: c[0], Y: c[1], Z: c[2]}.Scale(h.world.Radius)
	var msg map[string]any
	switch e.Kind {
	case "object":
		msg = map[string]any{"t": "obj", "by": e.PlayerID, "data": e.Data}
	case "lot":
		msg = map[string]any{"t": "lot", "by": e.PlayerID, "lot": e.Data}
	default:
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	h.nearby(center, h.rules.Network.InterestRadius+40, func(o *client) {
		if o.id != e.PlayerID {
			o.sendJSON(msg)
		}
	})
}

// refreshState relê lote, passaportes e carimbos do jogador (comprou um passaporte).
func (h *Hub) refreshState(player int64) {
	h.mu.Lock()
	c := h.clients[player]
	h.mu.Unlock()
	if c == nil {
		return
	}
	st, err := h.svc.MovementStateOf(context.Background(), c.player)
	if err != nil {
		return
	}
	h.mu.Lock()
	c.state = st
	h.mu.Unlock()
}

// --- Modo dev ------------------------------------------------------------------------------

// OnlineView é um jogador conectado (painel dev).
type OnlineView struct {
	ID        int64   `json:"id"`
	Nickname  string  `json:"nickname"`
	Country   string  `json:"country"`
	Character string  `json:"character"`
	Bot       bool    `json:"bot"`
	Lat       float64 `json:"lat"`
	Lon       float64 `json:"lon"`
	Visible   int     `json:"visible"`
}

// Online lista quem está conectado.
func (h *Hub) Online() []OnlineView {
	h.mu.Lock()
	defer h.mu.Unlock()
	out := []OnlineView{}
	for _, c := range h.clients {
		lat, lon := world.VecToLatLon(c.pos)
		out = append(out, OnlineView{ID: c.id, Nickname: c.player.Nickname, Country: c.player.Country,
			Character: c.player.Character, Bot: c.conn == nil, Lat: lat, Lon: lon, Visible: len(c.visible)})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Nickname < out[j].Nickname })
	return out
}

// Stats são os números de rede (painel dev e teste de carga).
type Stats struct {
	Clients  int   `json:"clients"`
	Bots     int   `json:"bots"`
	BytesIn  int64 `json:"bytes_in"`
	BytesOut int64 `json:"bytes_out"`
	MsgsIn   int64 `json:"msgs_in"`
	MsgsOut  int64 `json:"msgs_out"`
	UptimeMs int64 `json:"uptime_ms"`
}

// Stats devolve os contadores desde que o servidor subiu.
func (h *Hub) Stats() Stats {
	h.mu.Lock()
	n, bots := 0, 0
	for _, c := range h.clients {
		if c.conn == nil {
			bots++
		} else {
			n++
		}
	}
	h.mu.Unlock()
	return Stats{Clients: n, Bots: bots, BytesIn: h.bytesIn.Load(), BytesOut: h.bytesOut.Load(),
		MsgsIn: h.msgsIn.Load(), MsgsOut: h.msgsOut.Load(), UptimeMs: time.Since(h.start).Milliseconds()}
}

func marshal(v any) []byte {
	b, _ := json.Marshal(v)
	return b
}
