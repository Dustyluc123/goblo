package httpapi

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

func testHandler(t *testing.T) (http.Handler, *world.Snapshot) {
	t.Helper()
	w := &world.World{Frequency: 1, Radius: 100, Countries: map[string]string{},
		Cells: []world.Cell{{ID: 0, Terrain: world.Ocean, Neighbors: []int{}}}}
	snap, err := w.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	return NewHandler(snap, slog.New(slog.NewTextHandler(io.Discard, nil))), snap
}

func TestHealth(t *testing.T) {
	h, _ := testHandler(t)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/health", nil))
	if rec.Code != 200 || rec.Body.String() != `{"status":"ok"}` {
		t.Fatalf("status %d, corpo %q", rec.Code, rec.Body.String())
	}
}

func TestWorldPlain(t *testing.T) {
	h, snap := testHandler(t)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/world", nil))
	if rec.Code != 200 || rec.Header().Get("Content-Encoding") != "" {
		t.Fatalf("status %d, encoding %q", rec.Code, rec.Header().Get("Content-Encoding"))
	}
	if !bytes.Equal(rec.Body.Bytes(), snap.JSON) {
		t.Fatal("corpo diferente do snapshot")
	}
	var got world.World
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil || got.Radius != 100 {
		t.Fatalf("JSON inválido: %v", err)
	}
}

func TestWorldGzip(t *testing.T) {
	h, snap := testHandler(t)
	req := httptest.NewRequest("GET", "/world", nil)
	req.Header.Set("Accept-Encoding", "deflate, gzip;q=1.0")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Header().Get("Content-Encoding") != "gzip" {
		t.Fatalf("esperava gzip, veio %q", rec.Header().Get("Content-Encoding"))
	}
	zr, err := gzip.NewReader(rec.Body)
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := io.ReadAll(zr)
	if !bytes.Equal(raw, snap.JSON) {
		t.Fatal("gzip descompactado diferente do JSON")
	}
}

func TestWorldNotModified(t *testing.T) {
	h, snap := testHandler(t)
	req := httptest.NewRequest("GET", "/world", nil)
	req.Header.Set("If-None-Match", snap.ETag)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotModified || rec.Body.Len() != 0 {
		t.Fatalf("status %d, corpo de %d bytes", rec.Code, rec.Body.Len())
	}
}

func TestUnknownRouteAndMethod(t *testing.T) {
	h, _ := testHandler(t)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/nada", nil))
	if rec.Code != http.StatusNotFound {
		t.Errorf("rota desconhecida: status %d", rec.Code)
	}
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("POST", "/world", nil))
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("POST /world: status %d", rec.Code)
	}
}
