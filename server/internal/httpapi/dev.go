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
	mux.HandleFunc("POST /dev/coins", s.auth(s.devCoins))
	mux.HandleFunc("POST /dev/pedia", s.auth(s.devPedia))
	mux.HandleFunc("POST /dev/passport", s.auth(s.devPassport))
	mux.HandleFunc("POST /dev/travel", s.auth(s.travel(true)))
	mux.HandleFunc("GET /dev/border-lots", s.auth(s.devBorderLots))
	mux.HandleFunc("GET /dev/online", s.auth(s.devOnline))
	mux.HandleFunc("POST /dev/bots", s.auth(s.devBots))
	mux.HandleFunc("POST /dev/border-lots/move", s.auth(s.devMoveBorderLots))
}

// devBorderLots lista os lotes antigos que cruzam a fronteira ou ficam perto demais dela.
func (s *Server) devBorderLots(w http.ResponseWriter, r *http.Request, _ *game.Player) {
	list, err := s.Game.BorderLots(r.Context())
	if err != nil {
		writeError(w, s, err)
		return
	}
	crossing := 0
	for _, b := range list {
		if b.Crossing {
			crossing++
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"lots": list, "near": len(list) - crossing, "crossing": crossing})
}

// devMoveBorderLots muda esses lotes para um lugar válido no país do dono (ADR 0037).
func (s *Server) devMoveBorderLots(w http.ResponseWriter, r *http.Request, _ *game.Player) {
	moved, left, err := s.Game.DevMoveBorderLots(r.Context())
	if err != nil {
		writeError(w, s, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"moved": moved, "left": left})
}

func (s *Server) devPassport(w http.ResponseWriter, r *http.Request, p *game.Player) {
	var body struct {
		Action  string `json:"action"`
		Country string `json:"country"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, s, err)
		return
	}
	v, err := s.Game.DevPassport(r.Context(), p, body.Action, body.Country)
	if err != nil {
		writeError(w, s, err)
		return
	}
	writeJSON(w, http.StatusOK, v)
}

func (s *Server) devPedia(w http.ResponseWriter, r *http.Request, p *game.Player) {
	var body struct {
		Action string `json:"action"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, s, err)
		return
	}
	list, err := s.Game.DevPedia(r.Context(), p, body.Action)
	if err != nil {
		writeError(w, s, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"entries": list})
}

func (s *Server) devCoins(w http.ResponseWriter, r *http.Request, p *game.Player) {
	var body struct {
		Amount int64 `json:"amount"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, s, err)
		return
	}
	s.devMe(func(ctx context.Context, p *game.Player) (*game.MeView, error) {
		return s.Game.DevCoins(ctx, p, body.Amount)
	})(w, r, p)
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

// devOnline: quem está conectado em tempo real e os números da rede.
func (s *Server) devOnline(w http.ResponseWriter, _ *http.Request, _ *game.Player) {
	if s.Realtime == nil {
		writeJSON(w, http.StatusOK, map[string]any{"online": []any{}})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"online": s.Realtime.Online(), "stats": s.Realtime.Stats()})
}

// devBots cria bots perto do jogador (count > 0) ou tira todos (count = 0).
func (s *Server) devBots(w http.ResponseWriter, r *http.Request, p *game.Player) {
	var body struct {
		Count int `json:"count"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, s, err)
		return
	}
	if s.Realtime == nil {
		writeError(w, s, game.ErrOffline)
		return
	}
	if body.Count <= 0 {
		writeJSON(w, http.StatusOK, map[string]any{"removed": s.Realtime.RemoveBots()})
		return
	}
	pos, _, _, ok := s.Realtime.Where(p.ID)
	if !ok {
		writeError(w, s, game.ErrOffline)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"created": s.Realtime.SpawnBots(pos, body.Count, p.Country)})
}
