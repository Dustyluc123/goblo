package httpapi

import (
	"net/http"
	"strconv"

	"github.com/Dustyluc123/goblo/server/internal/game"
)

// Rotas do corpo, das roupas e do visual (fase 4.0; docs/API.md).
func (s *Server) bodyRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /body", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		reply(w, s)(s.Game.Body(r.Context(), p))
	}))
	mux.HandleFunc("POST /body/consume", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			Item string `json:"item"`
		}
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.Consume(r.Context(), p, body.Item))
		}
	}))
	mux.HandleFunc("POST /body/cook", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			Recipe string `json:"recipe"`
			Times  int    `json:"times"`
		}
		if readBody(w, r, s, &body) {
			if body.Times == 0 {
				body.Times = 1
			}
			reply(w, s)(s.Game.Cook(r.Context(), p, body.Recipe, body.Times))
		}
	}))
	mux.HandleFunc("POST /body/fill", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		reply(w, s)(s.Game.FillCanteen(r.Context(), p))
	}))
	mux.HandleFunc("POST /body/fire", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		reply(w, s)(s.Game.LightFire(r.Context(), p))
	}))
	mux.HandleFunc("GET /fires", s.auth(func(w http.ResponseWriter, r *http.Request, _ *game.Player) {
		cells, err := parseCells(r)
		if err != nil {
			writeError(w, s, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"fires": s.Game.Fires(cells)})
	}))
	mux.HandleFunc("POST /body/quiet", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			On bool `json:"on"`
		}
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.SetQuiet(r.Context(), p, body.On))
		}
	}))
	mux.HandleFunc("GET /temperature", func(w http.ResponseWriter, r *http.Request) {
		var lat, lon float64
		if err := parseFloats(r, &lat, &lon); err != nil {
			writeError(w, s, err)
			return
		}
		t, cell := s.Game.TemperatureAt(lat, lon, s.Game.Clock().Now())
		writeJSON(w, http.StatusOK, map[string]any{"temperature": t, "cell": cell})
	})
	mux.HandleFunc("GET /look", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		reply(w, s)(s.Game.LookOf(r.Context(), p))
	}))
	mux.HandleFunc("POST /look", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body game.Look
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.SetLook(r.Context(), p, body))
		}
	}))
	mux.HandleFunc("POST /wear", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			Item string `json:"item"`
		}
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.Wear(r.Context(), p, body.Item))
		}
	}))
	mux.HandleFunc("POST /wear/remove", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			Slot string `json:"slot"`
		}
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.Unwear(r.Context(), p, body.Slot))
		}
	}))
	mux.HandleFunc("POST /wear/dye", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body struct {
			Slot  string `json:"slot"`
			Paint string `json:"paint"`
		}
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.Dye(r.Context(), p, body.Slot, body.Paint))
		}
	}))
}

// Rotas do modo dev do corpo.
func (s *Server) devBodyRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /dev/body", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		var body game.DevBodyRequest
		if readBody(w, r, s, &body) {
			reply(w, s)(s.Game.DevBody(r.Context(), p, body))
		}
	}))
	mux.HandleFunc("POST /dev/wear", s.auth(func(w http.ResponseWriter, r *http.Request, p *game.Player) {
		if err := s.Game.DevWear(r.Context(), p); err != nil {
			writeError(w, s, err)
			return
		}
		reply(w, s)(s.Game.Me(r.Context(), p))
	}))
}

// reply responde o resultado (ou o erro) de uma regra.
func reply(w http.ResponseWriter, s *Server) func(any, error) {
	return func(v any, err error) {
		if err != nil {
			writeError(w, s, err)
			return
		}
		writeJSON(w, http.StatusOK, v)
	}
}

// readBody lê o JSON do pedido; false (e já respondeu) se não deu.
func readBody(w http.ResponseWriter, r *http.Request, s *Server, dst any) bool {
	if err := readJSON(r, dst); err != nil {
		writeError(w, s, err)
		return false
	}
	return true
}

// parseFloats lê ?lat=…&lon=….
func parseFloats(r *http.Request, lat, lon *float64) error {
	var err1, err2 error
	*lat, err1 = strconv.ParseFloat(r.URL.Query().Get("lat"), 64)
	*lon, err2 = strconv.ParseFloat(r.URL.Query().Get("lon"), 64)
	if err1 != nil || err2 != nil || *lat < -90 || *lat > 90 || *lon < -180 || *lon > 180 {
		return game.ErrInvalid.With("Use lat e lon em graus.")
	}
	return nil
}
