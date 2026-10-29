package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"sync"
	"testing"

	"github.com/Dustyluc123/goblo/server/data"
	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/geoip"
	"github.com/Dustyluc123/goblo/server/internal/store/sqlitestore"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

var (
	gameOnce  sync.Once
	gameWorld *world.World
	gameSnap  *world.Snapshot
	gameData  *game.Content
	gameGeo   *world.Geography
	a2        map[string]string
)

// gameServer monta o servidor completo com um mundo menor (n = 20) para os testes de HTTP.
func gameServer(t *testing.T, dev bool) http.Handler {
	t.Helper()
	gameOnce.Do(func() {
		geo, err := world.LoadGeography(data.NaturalEarth)
		if err != nil {
			panic(err)
		}
		gameGeo = geo
		if gameWorld, err = world.New(world.Config{Frequency: 20, Radius: 1000}, geo); err != nil {
			panic(err)
		}
		if gameSnap, err = gameWorld.Snapshot(); err != nil {
			panic(err)
		}
		if gameData, err = game.LoadContent(data.Game); err != nil {
			panic(err)
		}
		a2 = map[string]string{}
		for _, c := range geo.Countries {
			a2[c.A2] = c.Code
		}
	})
	store, err := sqlitestore.Open(context.Background(), filepath.Join(t.TempDir(), "api.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	db, err := geoip.LoadFile("../geoip/testdata/amostra.csv")
	if err != nil {
		t.Fatal(err)
	}
	s := &Server{
		World: gameWorld, Geo: gameGeo, Snapshot: gameSnap, Game: game.NewService(gameWorld, gameData, store, game.NewOffsetClock(nil)),
		GeoIP: db, A2ToA3: a2, Dev: dev, Log: slog.New(slog.NewTextHandler(io.Discard, nil)),
	}
	return s.Handler()
}

func call(t *testing.T, h http.Handler, method, path, token string, body any, remote ...string) (*httptest.ResponseRecorder, map[string]any) {
	t.Helper()
	var buf bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buf).Encode(body)
	}
	req := httptest.NewRequest(method, path, &buf)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if len(remote) > 0 {
		req.RemoteAddr = remote[0]
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	var out map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	return rec, out
}

func newPlayer(t *testing.T, h http.Handler, nick string) string {
	t.Helper()
	rec, out := call(t, h, "POST", "/players", "", map[string]string{"nickname": nick, "country": "BRA"})
	if rec.Code != http.StatusCreated {
		t.Fatalf("criar jogador: %d %s", rec.Code, rec.Body.String())
	}
	return out["token"].(string)
}

func TestDevRoutesBlockedWithoutDevMode(t *testing.T) {
	h := gameServer(t, false)
	token := newPlayer(t, h, "Curiosa")
	for _, r := range []struct{ method, path string }{
		{"GET", "/dev/status"}, {"POST", "/dev/give"}, {"POST", "/dev/finish-house"}, {"POST", "/dev/next-day"},
		{"POST", "/dev/country"}, {"POST", "/dev/reset"}, {"POST", "/dev/fake-neighbors"}, {"GET", "/dev/qualquer-coisa"},
	} {
		rec, out := call(t, h, r.method, r.path, token, map[string]any{"item": "wood", "count": 99})
		if rec.Code != http.StatusForbidden || out["error"] != "dev_only" {
			t.Errorf("%s %s sem GOBLO_DEV: %d %v", r.method, r.path, rec.Code, out)
		}
	}
	_, me := call(t, h, "GET", "/me", token, nil)
	if inv := me["inventory"].([]any); len(inv) != 0 {
		t.Fatalf("/dev/give bloqueado não pode dar itens: %v", inv)
	}
}

func TestDevRoutesWorkInDevMode(t *testing.T) {
	h := gameServer(t, true)
	token := newPlayer(t, h, "Dev")
	if rec, _ := call(t, h, "GET", "/dev/status", "", nil); rec.Code != http.StatusOK {
		t.Fatalf("/dev/status: %d", rec.Code)
	}
	rec, me := call(t, h, "POST", "/dev/give", token, map[string]any{"item": "wood", "count": 12})
	if rec.Code != http.StatusOK || me["inventory"].([]any)[0].(map[string]any)["count"].(float64) != 12 {
		t.Fatalf("/dev/give: %d %s", rec.Code, rec.Body.String())
	}
	if rec, _ := call(t, h, "POST", "/dev/give", "", map[string]any{"item": "wood", "count": 1}); rec.Code != http.StatusUnauthorized {
		t.Fatalf("dev sem token: %d", rec.Code)
	}
	cell := int(me["lot"].(map[string]any)["cell"].(float64))
	rec, out := call(t, h, "POST", "/dev/fake-neighbors", token, map[string]any{"cell": cell, "count": 5})
	if rec.Code != http.StatusOK || out["created"].(float64) != 5 {
		t.Fatalf("vizinhos falsos: %d %s", rec.Code, rec.Body.String())
	}
	rec, _ = call(t, h, "POST", "/dev/reset", token, map[string]any{"what": "player"})
	if rec.Code != http.StatusOK {
		t.Fatalf("reset do jogador: %d", rec.Code)
	}
	if rec, _ := call(t, h, "GET", "/me", token, nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("depois de apagar, o token não vale mais: %d", rec.Code)
	}
}

func TestGeoDetection(t *testing.T) {
	h := gameServer(t, false)
	// IP local (rodando na máquina): cai no idioma do sistema.
	_, out := call(t, h, "GET", "/geo?locale=pt_BR", "", nil, "127.0.0.1:5000")
	if out["country"] != "BRA" || out["source"] != "locale" {
		t.Fatalf("local + pt_BR: %v", out)
	}
	_, out = call(t, h, "GET", "/geo?locale=fr", "", nil, "[::1]:5000")
	if out["country"] != "" || out["source"] != "none" {
		t.Fatalf("local sem região: %v", out)
	}
	// IP conhecido: o IP manda, mesmo com outro idioma.
	_, out = call(t, h, "GET", "/geo?locale=en_US", "", nil, "200.147.67.142:443")
	if out["country"] != "BRA" || out["source"] != "ip" {
		t.Fatalf("IP brasileiro: %v", out)
	}
	_, out = call(t, h, "GET", "/geo", "", nil, "81.2.69.160:443")
	if out["country"] != "GBR" || out["source"] != "ip" {
		t.Fatalf("IP britânico: %v", out)
	}
}

func TestGameFlowOverHTTP(t *testing.T) {
	h := gameServer(t, true)
	rec, out := call(t, h, "POST", "/players", "", map[string]string{"nickname": "P0rr4", "country": "BRA"})
	if rec.Code != http.StatusBadRequest || out["error"] != "nickname_invalid" {
		t.Fatalf("palavrão: %d %v", rec.Code, out)
	}
	token := newPlayer(t, h, "Fluxo")
	if rec, _ := call(t, h, "GET", "/me", "token-errado", nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("token errado: %d", rec.Code)
	}
	_, me := call(t, h, "GET", "/me", token, nil)
	lot := me["lot"].(map[string]any)
	cell := int(lot["cell"].(float64))
	rec, objs := call(t, h, "GET", "/objects?cells="+itoa(cell), token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("/objects: %d", rec.Code)
	}
	var tree float64 = -1
	for _, o := range objs["objects"].([]any) {
		if m := o.(map[string]any); m["kind"] == "tree" && m["drop"] == "branch" {
			tree = m["id"].(float64)
			break
		}
	}
	if tree >= 0 {
		rec, res := call(t, h, "POST", "/interact", token, map[string]any{"object": tree, "action": "shake"})
		if rec.Code != http.StatusOK || len(res["gained"].([]any)) != 1 {
			t.Fatalf("/interact: %d %s", rec.Code, rec.Body.String())
		}
		rec, res = call(t, h, "POST", "/interact", token, map[string]any{"object": tree, "action": "shake"})
		if rec.Code != http.StatusConflict || res["error"] != "daily_limit" {
			t.Fatalf("segunda sacudida: %d %v", rec.Code, res)
		}
	}
	call(t, h, "POST", "/dev/give", token, map[string]any{"item": "wood", "count": 10})
	rec, _ = call(t, h, "POST", "/craft", token, map[string]any{"recipe": "fence"})
	if rec.Code != http.StatusOK {
		t.Fatalf("/craft: %d %s", rec.Code, rec.Body.String())
	}
	rec, _ = call(t, h, "POST", "/lot/place", token, map[string]any{"lot": lot["id"], "item": "fence", "x": 0, "y": 0, "rot": 0})
	if rec.Code != http.StatusOK {
		t.Fatalf("/lot/place: %d %s", rec.Code, rec.Body.String())
	}
	rec, lots := call(t, h, "GET", "/lots?cells="+itoa(cell), token, nil)
	if rec.Code != http.StatusOK || len(lots["lots"].([]any)) != 1 {
		t.Fatalf("/lots: %d %s", rec.Code, rec.Body.String())
	}
	if rec, _ := call(t, h, "GET", "/content", "", nil); rec.Code != http.StatusOK {
		t.Fatalf("/content: %d", rec.Code)
	}
	if rec, _ := call(t, h, "GET", "/objects?cells=a,b", token, nil); rec.Code != http.StatusBadRequest {
		t.Fatalf("células inválidas: %d", rec.Code)
	}
}

func itoa(n int) string { return fmtInt(n) }

func fmtInt(n int) string {
	b, _ := json.Marshal(n)
	return string(b)
}

func TestBordersRoute(t *testing.T) {
	h := gameServer(t, false)
	foz := gameWorld.CellAt(-25.55, -54.58).ID
	inland := gameWorld.CellAt(-10, -55).ID
	rec, body := call(t, h, "GET", fmt.Sprintf("/borders?cells=%d,%d", foz, inland), "", nil)
	if rec.Code != 200 {
		t.Fatalf("status %d: %v", rec.Code, body)
	}
	cells := body["cells"].([]any)
	if len(cells) != 2 {
		t.Fatalf("%d células", len(cells))
	}
	countries := body["countries"].([]any)
	names := map[string]bool{}
	for _, c := range countries {
		names[c.(map[string]any)["code"].(string)] = true
	}
	for _, code := range []string{"BRA", "PRY", "ARG"} {
		if !names[code] {
			t.Errorf("Foz do Iguaçu sem %s nos países: %v", code, names)
		}
	}
	segs, _ := cells[0].(map[string]any)["segs"].([]any)
	if len(segs) == 0 || len(segs)%6 != 0 {
		t.Errorf("segmentos de Foz: %d números", len(segs))
	}
	if c := cells[1].(map[string]any)["country"]; c != "BRA" {
		t.Errorf("interior do Brasil: %v", cells[1])
	}
}
