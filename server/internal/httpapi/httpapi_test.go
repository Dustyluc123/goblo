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
	w := &world.World{Version: "abc123", Frequency: 1, Radius: 100, Countries: map[string]string{"BRA": "Brasil"},
		Cells: []world.Cell{{ID: 0, Terrain: world.Land, Country: "BRA", Biome: world.BiomeGrassland, Neighbors: []int{}}}}
	snap, err := w.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	return NewHandler(w, snap, slog.New(slog.NewTextHandler(io.Discard, nil))), snap
}

func get(h http.Handler, path string, headers ...string) *httptest.ResponseRecorder {
	req := httptest.NewRequest("GET", path, nil)
	for i := 0; i+1 < len(headers); i += 2 {
		req.Header.Set(headers[i], headers[i+1])
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestHealth(t *testing.T) {
	h, _ := testHandler(t)
	rec := get(h, "/health")
	if rec.Code != 200 || rec.Body.String() != `{"status":"ok"}` {
		t.Fatalf("status %d, corpo %q", rec.Code, rec.Body.String())
	}
}

func TestVersion(t *testing.T) {
	h, _ := testHandler(t)
	var v struct {
		Version string `json:"version"`
		Format  int    `json:"format"`
		Cells   int    `json:"cells"`
	}
	rec := get(h, "/world/version")
	if err := json.Unmarshal(rec.Body.Bytes(), &v); err != nil {
		t.Fatal(err)
	}
	if v.Version != "abc123" || v.Format != world.BinaryFormatVersion || v.Cells != 1 {
		t.Fatalf("versão inesperada: %+v", v)
	}
}

func TestWorldJSON(t *testing.T) {
	h, snap := testHandler(t)
	rec := get(h, "/world")
	if rec.Code != 200 || rec.Header().Get("Content-Encoding") != "" || rec.Header().Get("ETag") != `"abc123"` {
		t.Fatalf("status %d, encoding %q, etag %q", rec.Code, rec.Header().Get("Content-Encoding"), rec.Header().Get("ETag"))
	}
	if !bytes.Equal(rec.Body.Bytes(), snap.JSON) {
		t.Fatal("corpo diferente do snapshot")
	}
	var got world.World
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil || got.Cells[0].Biome != world.BiomeGrassland {
		t.Fatalf("JSON inválido: %v", err)
	}
}

func TestWorldBinaryGzip(t *testing.T) {
	h, snap := testHandler(t)
	rec := get(h, "/world.bin", "Accept-Encoding", "deflate, gzip;q=1.0")
	if rec.Header().Get("Content-Encoding") != "gzip" || rec.Header().Get("Content-Type") != "application/octet-stream" {
		t.Fatalf("cabeçalhos inesperados: %v", rec.Header())
	}
	zr, err := gzip.NewReader(rec.Body)
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := io.ReadAll(zr)
	if !bytes.Equal(raw, snap.Binary) {
		t.Fatal("gzip descompactado diferente do binário")
	}
}

func TestWorldNotModified(t *testing.T) {
	h, snap := testHandler(t)
	for _, path := range []string{"/world", "/world.bin"} {
		rec := get(h, path, "If-None-Match", snap.ETag())
		if rec.Code != http.StatusNotModified || rec.Body.Len() != 0 {
			t.Fatalf("%s: status %d, corpo de %d bytes", path, rec.Code, rec.Body.Len())
		}
	}
}

func TestUnknownRouteAndMethod(t *testing.T) {
	h, _ := testHandler(t)
	if rec := get(h, "/nada"); rec.Code != http.StatusNotFound {
		t.Errorf("rota desconhecida: status %d", rec.Code)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("POST", "/world", nil))
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("POST /world: status %d", rec.Code)
	}
}
