package realtime_test

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"

	"github.com/Dustyluc123/goblo/server/data"
	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/realtime"
	"github.com/Dustyluc123/goblo/server/internal/store/sqlitestore"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

var (
	once    sync.Once
	tWorld  *world.World
	tGeo    *world.Geography
	content *game.Content
)

func shared(t *testing.T) {
	t.Helper()
	once.Do(func() {
		var err error
		if tGeo, err = world.LoadGeography(data.NaturalEarth); err != nil {
			panic(err)
		}
		if tWorld, err = world.New(world.DefaultConfig, tGeo); err != nil {
			panic(err)
		}
		if content, err = game.LoadContent(data.Game); err != nil {
			panic(err)
		}
	})
}

type env struct {
	svc *game.Service
	hub *realtime.Hub
	srv *httptest.Server
	ctx context.Context
}

func newEnv(t *testing.T, dev bool) *env {
	t.Helper()
	shared(t)
	store, err := sqlitestore.Open(context.Background(), filepath.Join(t.TempDir(), "rt.db"))
	if err != nil {
		t.Fatal(err)
	}
	svc := game.NewService(tWorld, content, store, nil)
	svc.SetGeography(tGeo)
	hub := realtime.NewHub(svc, slog.New(slog.NewTextHandler(io.Discard, nil)), dev)
	svc.SetPresence(hub)
	svc.SetEvents(hub.OnEvent)
	go hub.Run()
	mux := http.NewServeMux()
	mux.HandleFunc("GET /ws", hub.ServeWS)
	srv := httptest.NewServer(mux)
	t.Cleanup(func() {
		srv.Close()
		hub.Close()
		store.Close()
	})
	return &env{svc: svc, hub: hub, srv: srv, ctx: context.Background()}
}

// conn é um jogador conectado nos testes: guarda tudo o que chega.
type conn struct {
	t      *testing.T
	ws     *websocket.Conn
	player *game.Player
	mu     sync.Mutex
	texts  []map[string]any
	snaps  [][]realtime.Entry
	corrs  []byte
	closed bool
	seq    uint16
}

func (e *env) join(t *testing.T, nick, country string) (*conn, string) {
	t.Helper()
	p, token, err := e.svc.CreatePlayer(e.ctx, nick, country)
	if err != nil {
		t.Fatal(err)
	}
	return e.connect(t, p, token), token
}

func (e *env) connect(t *testing.T, p *game.Player, token string) *conn {
	t.Helper()
	url := "ws" + strings.TrimPrefix(e.srv.URL, "http") + "/ws"
	ws, _, err := websocket.Dial(e.ctx, url, &websocket.DialOptions{HTTPHeader: http.Header{"Authorization": {"Bearer " + token}}})
	if err != nil {
		t.Fatal(err)
	}
	c := &conn{t: t, ws: ws, player: p}
	go func() {
		for {
			typ, b, err := ws.Read(context.Background())
			c.mu.Lock()
			if err != nil {
				c.closed = true
				c.mu.Unlock()
				return
			}
			if typ == websocket.MessageText {
				var m map[string]any
				json.Unmarshal(b, &m)
				c.texts = append(c.texts, m)
			} else if b[0] == realtime.MsgSnapshot {
				_, list, _ := realtime.DecodeSnapshot(b)
				c.snaps = append(c.snaps, list)
			} else if b[0] == realtime.MsgCorrection {
				_, _, reason, _ := realtime.DecodeCorrection(b)
				c.corrs = append(c.corrs, reason)
			}
			c.mu.Unlock()
		}
	}()
	t.Cleanup(func() { ws.Close(websocket.StatusNormalClosure, "") })
	c.waitText("welcome", time.Second)
	return c
}

func (c *conn) send(v any) {
	b, _ := json.Marshal(v)
	if err := c.ws.Write(context.Background(), websocket.MessageText, b); err != nil {
		c.t.Fatal(err)
	}
}

func (c *conn) tp(why string, p world.Vec3) bool {
	c.mu.Lock()
	n := len(c.texts)
	c.mu.Unlock()
	c.send(map[string]any{"t": "tp", "why": why, "pos": []float64{p.X, p.Y, p.Z}})
	m := c.waitTextAfter("tp", n, time.Second)
	ok, _ := m["ok"].(bool)
	return ok
}

func (c *conn) move(p world.Vec3) {
	c.seq++
	b := realtime.EncodeMove(realtime.Move{Seq: c.seq, Pos: p, Flags: realtime.FlagOnFloor})
	if err := c.ws.Write(context.Background(), websocket.MessageBinary, b); err != nil {
		c.t.Fatal(err)
	}
}

func (c *conn) waitText(kind string, d time.Duration) map[string]any {
	return c.waitTextAfter(kind, 0, d)
}

func (c *conn) waitTextAfter(kind string, from int, d time.Duration) map[string]any {
	c.t.Helper()
	end := time.Now().Add(d)
	for time.Now().Before(end) {
		c.mu.Lock()
		for i := from; i < len(c.texts); i++ {
			if c.texts[i]["t"] == kind {
				m := c.texts[i]
				c.mu.Unlock()
				return m
			}
		}
		c.mu.Unlock()
		time.Sleep(10 * time.Millisecond)
	}
	c.t.Fatalf("%s: não chegou %q", c.player.Nickname, kind)
	return nil
}

func (c *conn) count(kind string) int {
	c.mu.Lock()
	defer c.mu.Unlock()
	n := 0
	for _, m := range c.texts {
		if m["t"] == kind {
			n++
		}
	}
	return n
}

func (c *conn) corrections() []byte {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]byte(nil), c.corrs...)
}

// ground é o ponto no chão (topo da célula) em lat/lon.
func ground(lat, lon float64) world.Vec3 {
	v := world.LatLonToVec(lat, lon)
	c := tWorld.Cells[tWorld.FindCell(v, -1)]
	return v.Scale(tWorld.Radius + c.Height)
}

// step anda d unidades (no chão) de p para o leste (dir = 1) ou oeste (dir = -1).
func step(p world.Vec3, d, dir float64) world.Vec3 {
	east, _ := realtime.Tangent(p)
	return stepAlong(p, east.Scale(dir), d)
}

// stepAlong anda d unidades (no chão) na direção dada.
func stepAlong(p, dir world.Vec3, d float64) world.Vec3 {
	q := p.Add(dir.Scale(d))
	c := tWorld.Cells[tWorld.FindCell(q, -1)]
	h := tWorld.Radius + c.Height
	if c.Terrain != world.Land {
		h = tWorld.Radius
	}
	return q.Normalize().Scale(h)
}

func TestMovementValidation(t *testing.T) {
	e := newEnv(t, true)
	a, _ := e.join(t, "Andarilho", "BRA")
	start := ground(-23.55, -46.63)
	if !a.tp("dev", start) {
		t.Fatal("teleporte do modo dev recusado")
	}
	// Andando normal: 0,3 unidade a cada 60 ms (5 unidades/s) não é corrigido.
	p := start
	for i := 0; i < 15; i++ {
		time.Sleep(60 * time.Millisecond)
		p = step(p, 0.3, 1)
		a.move(p)
	}
	time.Sleep(150 * time.Millisecond)
	if c := a.corrections(); len(c) != 0 {
		t.Fatalf("andar normal foi corrigido: %v", c)
	}
	// Salto de 40 unidades: velocidade.
	a.move(step(p, 40, 1))
	time.Sleep(150 * time.Millisecond)
	if c := a.corrections(); len(c) != 1 || c[0] != realtime.ReasonSpeed {
		t.Fatalf("salto de 40 unidades: correções %v", c)
	}
	// Teleporte sem motivo válido (casa longe) é recusado.
	if a.tp("home", step(p, 200, 1)) {
		t.Fatal("teleporte para casa longe da casa foi aceito")
	}
}

func TestMovementOceanAndBorder(t *testing.T) {
	e := newEnv(t, true)
	a, _ := e.join(t, "Costeiro", "BRA")
	// Oceano: da praia do Rio para o mar, devagar.
	p := ground(-22.97, -43.18)
	if !a.tp("dev", p) {
		t.Fatal("teleporte recusado")
	}
	var reasons []byte
	for i := 0; i < 250 && len(reasons) == 0; i++ {
		time.Sleep(40 * time.Millisecond)
		_, north := realtime.Tangent(p)
		next := stepAlong(p, north.Scale(-1), 0.2) // a praia do Rio é virada para o sul
		a.move(next)
		time.Sleep(10 * time.Millisecond)
		reasons = a.corrections()
		if len(reasons) == 0 {
			p = next
		}
	}
	if len(reasons) == 0 || reasons[0] != realtime.ReasonOcean {
		t.Fatalf("andar para o mar: correções %v", reasons)
	}
	// Fronteira: de Foz do Iguaçu para o Paraguai, sem e depois com passaporte.
	b, _ := e.join(t, "Fronteirico", "BRA")
	walkWest := func(from world.Vec3, n int) (world.Vec3, []byte) {
		q := from
		for i := 0; i < n; i++ {
			time.Sleep(40 * time.Millisecond)
			next := step(q, 0.2, -1)
			b.move(next)
			time.Sleep(10 * time.Millisecond)
			if c := b.corrections(); len(c) > 0 {
				return q, c
			}
			q = next
		}
		return q, nil
	}
	q := ground(-25.50, -54.35)
	if !b.tp("dev", q) {
		t.Fatal("teleporte recusado")
	}
	stop, c := walkWest(q, 150)
	if len(c) == 0 || c[0] != realtime.ReasonBorder {
		t.Fatalf("sem passaporte, a fronteira não segurou: %v", c)
	}
	if got := e.svc.CountryAtPoint(stop); got != "BRA" {
		t.Fatalf("parou em %s, esperado BRA", got)
	}
	if _, err := e.svc.DevPassport(e.ctx, b.player, "give", "PRY"); err != nil {
		t.Fatal(err)
	}
	time.Sleep(200 * time.Millisecond) // o hub relê os passaportes
	b.mu.Lock()
	b.corrs = nil
	b.mu.Unlock()
	end, c := walkWest(stop, 40)
	if len(c) != 0 || e.svc.CountryAtPoint(end) != "PRY" {
		t.Fatalf("com passaporte não entrou no Paraguai (%s, correções %v)", e.svc.CountryAtPoint(end), c)
	}
	// Carimbo a pé, pelo servidor.
	b.waitText("stamp", 2*time.Second)
}

func TestInterestEnterAndLeave(t *testing.T) {
	e := newEnv(t, true)
	a, _ := e.join(t, "Anfitriao", "BRA")
	b, _ := e.join(t, "Visitante", "BRA")
	here := ground(-23.55, -46.63)
	far := ground(-3.0, -60.0)
	a.tp("dev", here)
	b.tp("dev", far)
	time.Sleep(300 * time.Millisecond)
	if a.count("enter") != 0 {
		t.Fatal("A vê B a milhares de unidades")
	}
	b.tp("dev", step(here, 6, 1))
	m := a.waitText("enter", time.Second)
	if int64(m["id"].(float64)) != b.player.ID || m["nick"] != "Visitante" {
		t.Fatalf("enter errado: %v", m)
	}
	time.Sleep(200 * time.Millisecond)
	a.mu.Lock()
	seen := false
	for _, s := range a.snaps {
		for _, en := range s {
			if int64(en.ID) == b.player.ID {
				seen = true
			}
		}
	}
	a.mu.Unlock()
	if !seen {
		t.Fatal("B não aparece nas fotos que A recebe")
	}
	b.tp("dev", far)
	a.waitText("leave", time.Second)
}

func TestChatFilterAndLimit(t *testing.T) {
	e := newEnv(t, true)
	a, _ := e.join(t, "Falante", "BRA")
	b, _ := e.join(t, "Ouvinte", "BRA")
	here := ground(-23.55, -46.63)
	a.tp("dev", here)
	b.tp("dev", step(here, 3, 1))
	time.Sleep(200 * time.Millisecond)
	a.send(map[string]any{"t": "chat", "text": "oi, que merda de chuva"})
	m := b.waitText("chat", time.Second)
	if txt := m["text"].(string); strings.Contains(txt, "merda") || !strings.Contains(txt, "♡") {
		t.Fatalf("palavrão passou: %q", txt)
	}
	long := strings.Repeat("a", 500)
	for i := 0; i < 5; i++ {
		a.send(map[string]any{"t": "chat", "text": fmt.Sprintf("%d %s", i, long)})
	}
	time.Sleep(300 * time.Millisecond)
	// A rajada é de 3: a primeira mensagem e mais 2 desta leva chegam; o resto vira aviso.
	if n := b.count("chat"); n != 3 {
		t.Fatalf("chegaram %d mensagens, esperado 3 (limite)", n)
	}
	if a.count("info") == 0 {
		t.Fatal("quem mandou rápido demais não foi avisado")
	}
	b.mu.Lock()
	last := b.texts[len(b.texts)-1]
	for i := len(b.texts) - 1; i >= 0; i-- {
		if b.texts[i]["t"] == "chat" {
			last = b.texts[i]
			break
		}
	}
	b.mu.Unlock()
	if n := len([]rune(last["text"].(string))); n > content.Rules.Chat.MaxChars {
		t.Fatalf("mensagem com %d caracteres passou", n)
	}
	// Bloqueio: B bloqueia A e não recebe mais o chat dele.
	b.send(map[string]any{"t": "block", "id": a.player.ID, "on": true})
	b.waitText("blocked", time.Second)
	before := b.count("chat")
	time.Sleep(2100 * time.Millisecond)
	a.send(map[string]any{"t": "chat", "text": "ainda me ouve?"})
	time.Sleep(300 * time.Millisecond)
	if b.count("chat") != before {
		t.Fatal("chat de quem foi bloqueado chegou")
	}
}

func TestReconnectAndDuplicate(t *testing.T) {
	e := newEnv(t, false) // sem o modo dev: o nascimento segue a regra de verdade
	p, token, err := e.svc.CreatePlayer(e.ctx, "Volta Sempre", "BRA")
	if err != nil {
		t.Fatal(err)
	}
	st, err := e.svc.MovementStateOf(e.ctx, p)
	if err != nil {
		t.Fatal(err)
	}
	a := e.connect(t, p, token)
	if !a.tp("spawn", st.Home) {
		t.Fatal("nascer em casa foi recusado")
	}
	q := st.Home
	for i := 0; i < 20; i++ {
		time.Sleep(50 * time.Millisecond)
		q = step(q, 0.3, 1)
		a.move(q)
	}
	time.Sleep(100 * time.Millisecond)
	// Conexão duplicada: a antiga recebe o aviso e cai.
	b := e.connect(t, p, token)
	a.waitText("kick", time.Second)
	time.Sleep(200 * time.Millisecond)
	a.mu.Lock()
	closed := a.closed
	a.mu.Unlock()
	if !closed {
		t.Fatal("a conexão antiga não foi encerrada")
	}
	// Nascer longe de casa e de onde estava: recusado. Perto de onde estava: aceito
	// (reconexão sem perder o estado).
	b.ws.Close(websocket.StatusNormalClosure, "")
	time.Sleep(200 * time.Millisecond)
	c := e.connect(t, p, token)
	w := c.waitText("welcome", time.Second)
	if resumed, _ := w["resumed"].(bool); !resumed {
		t.Fatal("reconexão não lembrou a posição")
	}
	if c.tp("spawn", ground(-3.0, -60.0)) {
		t.Fatal("nascer longe de casa foi aceito sem o modo dev")
	}
	if !c.tp("spawn", q) {
		t.Fatal("voltar para onde estava foi recusado")
	}
}

func TestCleanChat(t *testing.T) {
	for in, bad := range map[string]bool{"bom dia": false, "que m3rd4": true, "m e r d a": true, "computador": false} {
		out := realtime.CleanChat(in)
		if bad == (out == in) {
			t.Errorf("%q → %q", in, out)
		}
	}
}
