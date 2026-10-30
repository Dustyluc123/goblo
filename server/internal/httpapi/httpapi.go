// Package httpapi expõe o mundo e o jogo por HTTP. A lista completa de rotas está em
// docs/API.md.
//
//	GET /health        → {"status":"ok"}
//	GET /world/version → {"version":"…","format":1,"frequency":50,"cells":25002}
//	GET /world.bin     → mundo no formato binário (o que o jogo usa), com gzip
//	GET /world         → mundo em JSON (para depuração), com gzip
//
// As duas rotas do mundo mandam ETag com a versão e respondem 304 a If-None-Match.
// As rotas do jogo (jogador, objetos, inventário, lote) estão em game.go e as do modo
// dev em dev.go.
package httpapi

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/geoip"
	"github.com/Dustyluc123/goblo/server/internal/realtime"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Server junta o que as rotas precisam. Game pode ser nil (só o mundo é servido).
type Server struct {
	World    *world.World
	Geo      *world.Geography // países pela posição exata e fronteiras (pode ser nil nos testes)
	Snapshot *world.Snapshot
	Game     *game.Service
	GeoIP    *geoip.DB         // pode ser nil: aí o país vem só do idioma do sistema
	A2ToA3   map[string]string // código ISO A2 → código do país no mundo
	Dev      bool              // GOBLO_DEV=1: libera as rotas /dev/…
	Log      *slog.Logger
	// Realtime é a camada em tempo real (GET /ws e rotas de rede do modo dev). Pode ser nil.
	Realtime *realtime.Hub
}

// NewHandler monta só as rotas do mundo (usado nos testes do mundo).
func NewHandler(w *world.World, snap *world.Snapshot, log *slog.Logger) http.Handler {
	return (&Server{World: w, Snapshot: snap, Log: log}).Handler()
}

// Handler monta as rotas. O snapshot é gerado uma vez na inicialização e servido do cache.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", health)
	mux.HandleFunc("GET /world/version", versionHandler(s.World, s.Snapshot))
	mux.HandleFunc("GET /world.bin", blob(s.Snapshot, "application/octet-stream", s.Snapshot.Binary, s.Snapshot.BinaryGzip))
	mux.HandleFunc("GET /world", blob(s.Snapshot, "application/json", s.Snapshot.JSON, s.Snapshot.JSONGzip))
	if s.Geo != nil {
		mux.HandleFunc("GET /borders", s.borders)
	}
	if s.Game != nil {
		s.gameRoutes(mux)
	}
	s.devRoutes(mux)
	logged := logRequests(s.Log, cors(mux))
	if s.Realtime == nil {
		return logged
	}
	// O WebSocket fica fora do registro de requisições (ele precisa da conexão crua).
	outer := http.NewServeMux()
	outer.HandleFunc("GET /ws", s.Realtime.ServeWS)
	outer.Handle("/", logged)
	return outer
}

func health(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}

func versionHandler(wd *world.World, snap *world.Snapshot) http.HandlerFunc {
	body, _ := json.Marshal(map[string]any{
		"version":   snap.Version,
		"format":    world.BinaryFormatVersion,
		"frequency": wd.Frequency,
		"cells":     len(wd.Cells),
	})
	return func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-cache")
		_, _ = w.Write(body)
	}
}

func blob(snap *world.Snapshot, contentType string, raw, gz []byte) http.HandlerFunc {
	etag := snap.ETag()
	return func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Content-Type", contentType)
		h.Set("Cache-Control", "no-cache")
		h.Set("ETag", etag)
		h.Set("X-World-Version", snap.Version)
		h.Set("Vary", "Accept-Encoding")
		if r.Header.Get("If-None-Match") == etag {
			w.WriteHeader(http.StatusNotModified)
			return
		}
		body := raw
		if acceptsGzip(r) {
			h.Set("Content-Encoding", "gzip")
			body = gz
		}
		h.Set("Content-Length", strconv.Itoa(len(body)))
		if r.Method == http.MethodHead {
			return
		}
		_, _ = w.Write(body)
	}
}

func acceptsGzip(r *http.Request) bool {
	for _, part := range strings.Split(r.Header.Get("Accept-Encoding"), ",") {
		enc, q, _ := strings.Cut(strings.TrimSpace(part), ";")
		if strings.EqualFold(strings.TrimSpace(enc), "gzip") && strings.TrimSpace(q) != "q=0" {
			return true
		}
	}
	return false
}

// cors libera leitura de qualquer origem (útil para um cliente web no futuro).
func cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

func logRequests(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		log.Info("requisição", "método", r.Method, "rota", r.URL.Path, "status", rec.status,
			"duração", time.Since(start).Round(time.Microsecond))
	})
}
