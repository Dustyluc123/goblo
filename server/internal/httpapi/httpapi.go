// Package httpapi expõe o mundo por HTTP.
//
//	GET /health → {"status":"ok"}
//	GET /world  → definição completa do mundo (JSON, com gzip quando o cliente aceita)
package httpapi

import (
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// NewHandler monta as rotas. O snapshot é gerado uma vez na inicialização e servido do cache.
func NewHandler(snap *world.Snapshot, log *slog.Logger) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", health)
	mux.HandleFunc("GET /world", worldHandler(snap))
	return logRequests(log, cors(mux))
}

func health(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}

func worldHandler(snap *world.Snapshot) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Content-Type", "application/json")
		h.Set("Cache-Control", "no-cache")
		h.Set("ETag", snap.ETag)
		h.Set("Vary", "Accept-Encoding")
		if r.Header.Get("If-None-Match") == snap.ETag {
			w.WriteHeader(http.StatusNotModified)
			return
		}
		body := snap.JSON
		if acceptsGzip(r) {
			h.Set("Content-Encoding", "gzip")
			body = snap.Gzip
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
