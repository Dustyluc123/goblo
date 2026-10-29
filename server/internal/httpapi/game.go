package httpapi

import (
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/netip"
	"strconv"
	"strings"

	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/geoip"
)

// maxCells limita quantas células cabem num pedido de objetos ou lotes.
const maxCells = 512

func (s *Server) gameRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /content", s.content)
	mux.HandleFunc("GET /recipes", s.recipes)
	mux.HandleFunc("GET /geo", s.geo)
	mux.HandleFunc("POST /players", s.createPlayer)
	mux.HandleFunc("GET /me", s.auth(s.me))
	mux.HandleFunc("GET /objects", s.auth(s.objects))
	mux.HandleFunc("POST /interact", s.auth(s.interact))
	mux.HandleFunc("POST /craft", s.auth(s.craft))
	mux.HandleFunc("GET /lots", s.auth(s.lots))
	mux.HandleFunc("POST /lot/place", s.auth(s.place))
	mux.HandleFunc("POST /lot/remove", s.auth(s.remove))
	mux.HandleFunc("POST /lot/house", s.auth(s.house))
}

type authedHandler func(w http.ResponseWriter, r *http.Request, p *game.Player)

// auth exige o token no cabeçalho "Authorization: Bearer <token>".
func (s *Server) auth(next authedHandler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token, _ := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		p, err := s.Game.Authenticate(r.Context(), strings.TrimSpace(token))
		if err != nil {
			writeError(w, s, err)
			return
		}
		next(w, r, p)
	}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// writeError responde {"error": código, "message": texto}. Erros de regra usam o status
// deles; o resto vira 500 (e vai para o log).
func writeError(w http.ResponseWriter, s *Server, err error) {
	var ge *game.Error
	if errors.As(err, &ge) {
		writeJSON(w, ge.Status, map[string]string{"error": ge.Code, "message": ge.Message})
		return
	}
	if s != nil && s.Log != nil {
		s.Log.Error("erro interno", "erro", err)
	}
	writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal", "message": "Erro no servidor."})
}

// readJSON lê o corpo (até 64 KB) em v.
func readJSON(r *http.Request, v any) error {
	dec := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 64<<10))
	if err := dec.Decode(v); err != nil {
		return game.ErrInvalid
	}
	return nil
}

// parseCells lê "?cells=1,2,3".
func parseCells(r *http.Request) ([]int, error) {
	raw := r.URL.Query().Get("cells")
	if raw == "" {
		return nil, game.ErrInvalid
	}
	parts := strings.Split(raw, ",")
	if len(parts) > maxCells {
		return nil, game.ErrInvalid
	}
	out := make([]int, 0, len(parts))
	for _, p := range parts {
		n, err := strconv.Atoi(strings.TrimSpace(p))
		if err != nil || n < 0 {
			return nil, game.ErrInvalid
		}
		out = append(out, n)
	}
	return out, nil
}

// content manda tudo o que o cliente precisa saber do conteúdo do jogo.
func (s *Server) content(w http.ResponseWriter, _ *http.Request) {
	c := s.Game.Content()
	writeJSON(w, http.StatusOK, map[string]any{
		"items":           c.Items,
		"recipes":         c.Recipes,
		"houses":          c.Houses,
		"object_models":   c.ObjectModels(),
		"tile_size":       game.TileSize,
		"lot_tiles":       game.LotTiles,
		"inventory_slots": game.InventorySlots,
		"rollover_hour":   game.RolloverHour,
		"dev":             s.Dev,
	})
}

func (s *Server) recipes(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"recipes": s.Game.Content().Recipes})
}

// geo sugere o país do jogador: primeiro pelo IP da conexão (descartado logo depois),
// depois pelo idioma do sistema que o cliente manda em ?locale=pt_BR.
func (s *Server) geo(w http.ResponseWriter, r *http.Request) {
	country, source := s.detectCountry(r)
	writeJSON(w, http.StatusOK, map[string]string{
		"country": country, "country_name": s.World.Countries[country], "source": source,
	})
}

func (s *Server) detectCountry(r *http.Request) (country, source string) {
	if ip := remoteIP(r); s.GeoIP != nil {
		if c := s.Game.CountryForA2(s.GeoIP.Country(ip), s.A2ToA3); c != "" {
			return c, "ip"
		}
	}
	if c := s.Game.CountryForA2(geoip.RegionFromLocale(r.URL.Query().Get("locale")), s.A2ToA3); c != "" {
		return c, "locale"
	}
	return "", "none"
}

// remoteIP é o IP de quem conectou. Não é guardado nem vai para o log.
// TODO: atrás de um proxy reverso, ler X-Forwarded-For de um proxy confiável.
func remoteIP(r *http.Request) netip.Addr {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	ip, _ := netip.ParseAddr(host)
	return ip
}

func (s *Server) createPlayer(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Nickname string `json:"nickname"`
		Country  string `json:"country"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, s, err)
		return
	}
	p, token, err := s.Game.CreatePlayer(r.Context(), body.Nickname, body.Country)
	if err != nil {
		writeError(w, s, err)
		return
	}
	me, err := s.Game.Me(r.Context(), p)
	if err != nil {
		writeError(w, s, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"token": token, "me": me})
}

func (s *Server) me(w http.ResponseWriter, r *http.Request, p *game.Player) {
	me, err := s.Game.Me(r.Context(), p)
	if err != nil {
		writeError(w, s, err)
		return
	}
	writeJSON(w, http.StatusOK, me)
}

func (s *Server) objects(w http.ResponseWriter, r *http.Request, p *game.Player) {
	cells, err := parseCells(r)
	if err != nil {
		writeError(w, s, err)
		return
	}
	objs, day, err := s.Game.Objects(r.Context(), p, cells)
	if err != nil {
		writeError(w, s, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"day": day, "objects": objs})
}

func (s *Server) interact(w http.ResponseWriter, r *http.Request, p *game.Player) {
	var body struct {
		Object int64  `json:"object"`
		Action string `json:"action"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, s, err)
		return
	}
	res, err := s.Game.Interact(r.Context(), p, body.Object, body.Action)
	if err != nil {
		writeError(w, s, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) craft(w http.ResponseWriter, r *http.Request, p *game.Player) {
	var body struct {
		Recipe string `json:"recipe"`
		Times  int    `json:"times"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, s, err)
		return
	}
	if body.Times == 0 {
		body.Times = 1
	}
	res, err := s.Game.Craft(r.Context(), p, body.Recipe, body.Times)
	if err != nil {
		writeError(w, s, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) lots(w http.ResponseWriter, r *http.Request, _ *game.Player) {
	cells, err := parseCells(r)
	if err != nil {
		writeError(w, s, err)
		return
	}
	lots, err := s.Game.Lots(r.Context(), cells)
	if err != nil {
		writeError(w, s, err)
		return
	}
	if lots == nil {
		lots = []game.LotView{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"lots": lots})
}

type placeBody struct {
	Lot  int64  `json:"lot"`
	Item string `json:"item"`
	X    int    `json:"x"`
	Y    int    `json:"y"`
	Rot  int    `json:"rot"`
}

func (s *Server) place(w http.ResponseWriter, r *http.Request, p *game.Player) {
	var body placeBody
	if err := readJSON(r, &body); err != nil {
		writeError(w, s, err)
		return
	}
	res, err := s.Game.Place(r.Context(), p, body.Lot, body.Item, body.X, body.Y, body.Rot)
	if err != nil {
		writeError(w, s, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) remove(w http.ResponseWriter, r *http.Request, p *game.Player) {
	var body struct {
		Placement int64 `json:"placement"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, s, err)
		return
	}
	res, err := s.Game.Remove(r.Context(), p, body.Placement)
	if err != nil {
		writeError(w, s, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) house(w http.ResponseWriter, r *http.Request, p *game.Player) {
	var body placeBody
	if err := readJSON(r, &body); err != nil {
		writeError(w, s, err)
		return
	}
	res, err := s.Game.BuildHouse(r.Context(), p, body.Lot, body.X, body.Y, body.Rot)
	if err != nil {
		writeError(w, s, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}
