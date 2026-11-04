package httpapi

import (
	"net/http"
	"strconv"

	"github.com/Dustyluc123/goblo/server/internal/game"
)

// Rotas das cavernas, da fornalha, do baú, das conquistas e do folclore (fase 4.5;
// docs/API.md).
func (s *Server) caveRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /caves", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{"caves": s.Game.Caves()})
	})
	mux.HandleFunc("GET /cave/{id}", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		id, err := strconv.Atoi(r.PathValue("id"))
		if err != nil {
			writeError(w, s, game.ErrInvalid)
			return
		}
		reply(w, s)(s.Game.CaveInfo(r.Context(), p, id))
	}))
	mux.HandleFunc("POST /cave/enter", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			Cave int `json:"cave"`
		}
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.EnterCave(r.Context(), p, body.Cave))
		}
	}))
	mux.HandleFunc("POST /cave/mine", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			Cave int   `json:"cave"`
			Ore  int64 `json:"ore"`
		}
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.MineOre(r.Context(), p, body.Cave, body.Ore))
		}
	}))
	mux.HandleFunc("POST /cave/torch", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			Cave int        `json:"cave"`
			Pos  [3]float64 `json:"pos"`
		}
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.PlaceTorch(r.Context(), p, body.Cave, body.Pos))
		}
	}))
	mux.HandleFunc("POST /cave/torch/take", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			Cave int   `json:"cave"`
			ID   int64 `json:"id"`
		}
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.TakeTorch(r.Context(), p, body.Cave, body.ID))
		}
	}))
	mux.HandleFunc("POST /cave/boss", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			Cave int `json:"cave"`
		}
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.WakeBoss(r.Context(), p, body.Cave))
		}
	}))
	mux.HandleFunc("GET /furnace", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		reply(w, s)(s.Game.Furnace(r.Context(), p))
	}))
	mux.HandleFunc("POST /furnace/smelt", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			Recipe string `json:"recipe"`
			Times  int    `json:"times"`
			Cave   *int   `json:"cave"`
		}
		if readBody(w, r, s, &body) {
			if body.Times == 0 {
				body.Times = 1
			}
			reply(w, s)(s.Game.Smelt(r.Context(), p, body.Recipe, body.Times, caveOrLot(body.Cave)))
		}
	}))
	mux.HandleFunc("POST /furnace/collect", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			Cave *int `json:"cave"`
		}
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.CollectFurnace(r.Context(), p, caveOrLot(body.Cave)))
		}
	}))
	mux.HandleFunc("GET /chest/{id}", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			writeError(w, s, game.ErrInvalid)
			return
		}
		reply(w, s)(s.Game.Chest(r.Context(), p, id))
	}))
	mux.HandleFunc("POST /chest/{id}/{op}", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		op := r.PathValue("op")
		if err != nil || (op != "put" && op != "take") {
			writeError(w, s, game.ErrInvalid)
			return
		}
		var body struct {
			Item  string `json:"item"`
			Count int    `json:"count"`
		}
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.MoveChest(r.Context(), p, id, body.Item, body.Count, op == "put"))
		}
	}))
	mux.HandleFunc("GET /achievements", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		reply(w, s)(s.Game.AchievementsOf(r.Context(), p))
	}))
	mux.HandleFunc("GET /legends", s.auth(func(w http.ResponseWriter, r *http.Request, _ *game.Player) {
		cell, err := strconv.Atoi(r.URL.Query().Get("cell"))
		if err != nil {
			writeError(w, s, game.ErrInvalid)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"legends": s.Game.LegendsNear(cell, 2, s.Game.Clock().Now()),
			"now": s.Game.Clock().Now().Unix()})
	}))
}

// caveOrLot: sem "cave" no pedido, a fornalha é a do lote (-1).
func caveOrLot(c *int) int {
	if c == nil {
		return -1
	}
	return *c
}

// Rotas do modo dev das cavernas e do folclore.
func (s *Server) devCaveRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /dev/cave/enter", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			Cave int `json:"cave"`
		}
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.DevEnterCave(r.Context(), p, body.Cave))
		}
	}))
	mux.HandleFunc("POST /dev/cave/kit", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		if err := s.Game.DevCaveKit(r.Context(), p); err != nil {
			writeError(w, s, err)
			return
		}
		reply(w, s)(s.Game.Me(r.Context(), p))
	}))
	mux.HandleFunc("POST /dev/cave/god", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			On bool `json:"on"`
		}
		if readBody(w, r, s, &body) {
			s.Game.DevBossGod(p, body.On)
			writeJSON(w, http.StatusOK, map[string]any{"on": body.On})
		}
	}))
	mux.HandleFunc("POST /dev/cave/boss-sleep", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			Cave int `json:"cave"`
		}
		if readBody(w, r, s, &body) {
			s.Game.DevBossSleep(p, body.Cave)
			writeJSON(w, http.StatusOK, map[string]any{"ok": true})
		}
	}))
	mux.HandleFunc("POST /dev/chest/fill", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			ID int64 `json:"id"`
		}
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.DevFillChest(r.Context(), p, body.ID))
		}
	}))
	mux.HandleFunc("POST /dev/legend", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			ID string `json:"id"`
		}
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.DevLegend(p, body.ID))
		}
	}))
}
