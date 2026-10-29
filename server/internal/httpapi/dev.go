package httpapi

import (
	"context"
	"net/http"

	"github.com/Dustyluc123/goblo/server/internal/game"
)

// devRoutes registra /dev/…. Sem GOBLO_DEV=1 (ou sem o jogo), todas respondem 403.
func (s *Server) devRoutes(mux *http.ServeMux) {
	if !s.Dev || s.Game == nil {
		mux.HandleFunc("/dev/", func(w http.ResponseWriter, _ *http.Request) { writeError(w, s, game.ErrDevOnly) })
		return
	}
	mux.HandleFunc("GET /dev/status", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{"dev": true})
	})
	mux.HandleFunc("POST /dev/give", s.auth(s.devGive))
	mux.HandleFunc("POST /dev/finish-house", s.auth(s.devMe(s.Game.DevFinishHouse)))
	mux.HandleFunc("POST /dev/next-day", s.auth(s.devMe(s.Game.DevNextDay)))
	mux.HandleFunc("POST /dev/real-time", s.auth(s.devMe(s.Game.DevRealTime)))
	mux.HandleFunc("POST /dev/country", s.auth(s.devCountry))
	mux.HandleFunc("POST /dev/reset", s.auth(s.devReset))
	mux.HandleFunc("POST /dev/fake-neighbors", s.auth(s.devFakeNeighbors))
}

// devMe adapta uma ação dev que devolve o estado do jogador.
func (s *Server) devMe(fn func(context.Context, *game.Player) (*game.MeView, error)) authedHandler {
	return func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		me, err := fn(r.Context(), p)
		if err != nil {
			writeError(w, s, err)
			return
		}
		writeJSON(w, http.StatusOK, me)
	}
}

func (s *Server) devGive(w http.ResponseWriter, r *http.Request, p *game.Player) {
	var body struct {
		Item  string `json:"item"`
		Count int    `json:"count"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, s, err)
		return
	}
	s.devMe(func(ctx context.Context, p *game.Player) (*game.MeView, error) {
		return s.Game.DevGive(ctx, p, body.Item, body.Count)
	})(w, r, p)
}

func (s *Server) devCountry(w http.ResponseWriter, r *http.Request, p *game.Player) {
	var body struct {
		Country string `json:"country"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, s, err)
		return
	}
	s.devMe(func(ctx context.Context, p *game.Player) (*game.MeView, error) {
		return s.Game.DevSetCountry(ctx, p, body.Country)
	})(w, r, p)
}

func (s *Server) devReset(w http.ResponseWriter, r *http.Request, p *game.Player) {
	var body struct {
		What string `json:"what"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, s, err)
		return
	}
	me, err := s.Game.DevReset(r.Context(), p, body.What)
	if err != nil {
		writeError(w, s, err)
		return
	}
	if me == nil { // jogador apagado
		writeJSON(w, http.StatusOK, map[string]any{"deleted": true})
		return
	}
	writeJSON(w, http.StatusOK, me)
}

func (s *Server) devFakeNeighbors(w http.ResponseWriter, r *http.Request, p *game.Player) {
	var body struct {
		Cell  int `json:"cell"`
		Count int `json:"count"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, s, err)
		return
	}
	if body.Count == 0 {
		body.Count = 20
	}
	n, err := s.Game.DevFakeNeighbors(r.Context(), p, body.Cell, body.Count)
	if err != nil {
		writeError(w, s, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"created": n})
}
