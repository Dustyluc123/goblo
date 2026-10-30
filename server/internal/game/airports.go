package game

import (
	"context"
	"fmt"
	"math"
	"sort"
	"strings"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Aeroportos, viagem e passaportes (fase 2.5, ADR 0035).
//
// Cada país com hexágono tem um aeroporto no hexágono de terra dele mais perto da capital
// (capitais.json; sem capital, o "centro" do país). O aeroporto ocupa o hexágono inteiro:
// ali não há lotes novos, objetos nem animais. País com menos de minAirportCells hexágonos
// ganha só um ponto de chegada (um balcão na beirada do hexágono, fora dos lotes), para
// não perder lugar de lote. Países sem hexágono (Vaticano, Mônaco…) não têm aeroporto:
// chega-se a pé, pelo vizinho.

// EarthRadiusKm é o raio da Terra, para a distância das passagens.
const EarthRadiusKm = 6371.0

// Onde fica o balcão no plano da célula do aeroporto (o cliente monta o prédio em volta).
const airportCounterX, airportCounterY = 0.0, 1.5

// País com menos hexágonos que isso ganha só um ponto de chegada, sem ocupar o hexágono.
const minAirportCells = 3

// Distância do centro do ponto de chegada (no corredor entre os lotes e a borda).
const kioskRadius = 8.6

// Raio em volta do ponto de chegada sem árvores nem pedras.
const kioskClear = 2.2

// Airport é o aeroporto de um país.
type Airport struct {
	Country     string  `json:"country"`
	CountryName string  `json:"country_name"`
	Name        string  `json:"name"`
	City        string  `json:"city"`
	Cell        int     `json:"cell"`
	Lat         float64 `json:"lat"`
	Lon         float64 `json:"lon"`
	X           float64 `json:"x"` // balcão, no plano da célula
	Y           float64 `json:"y"`
	Small       bool    `json:"small"` // só um ponto de chegada (país pequeno)
}

// buildAirports escolhe o hexágono de cada aeroporto. Pula hexágonos que já têm lote (de
// um banco antigo); assim o mesmo banco sempre dá os mesmos aeroportos.
func (s *Service) buildAirports() {
	s.airports = nil
	s.airportBy = map[string]*Airport{}
	s.airportCells = map[int]bool{}
	s.kiosks = map[int][2]float64{}
	taken := map[int]bool{}
	if lots, err := s.store.LotsByCells(context.Background(), allLandCells(s.world)); err == nil {
		for _, l := range lots {
			taken[l.Cell] = true
		}
	}
	codes := make([]string, 0, len(s.byCountry))
	for code := range s.byCountry {
		codes = append(codes, code)
	}
	sort.Strings(codes)
	for _, code := range codes {
		cells := s.byCountry[code]
		city := ""
		var target world.Vec3
		if c, ok := s.geo.Capitals[code]; ok {
			city = c.Name
			target = world.LatLonToVec(c.Lat, c.Lon)
		} else {
			target = cellVec(&s.world.Cells[cells[0]])
		}
		best, bestDot := -1, -2.0
		for _, cell := range cells {
			if taken[cell] {
				continue
			}
			if d := cellVec(&s.world.Cells[cell]).Normalize().Dot(target); d > bestDot {
				best, bestDot = cell, d
			}
		}
		if best < 0 {
			continue
		}
		c := &s.world.Cells[best]
		name := s.CountryName(code)
		label := "Aeroporto de " + name
		if city != "" {
			label = "Aeroporto de " + city
		}
		a := Airport{Country: code, CountryName: name, Name: label, City: city,
			Cell: best, Lat: c.Lat, Lon: c.Lon, X: airportCounterX, Y: airportCounterY}
		if len(cells) < minAirportCells {
			a.Small = true
			a.Name = "Ponto de chegada de " + name
			a.X, a.Y = s.kioskSpot(best)
			s.kiosks[best] = [2]float64{a.X, a.Y}
		} else {
			s.airportCells[best] = true
		}
		s.airports = append(s.airports, a)
	}
	for i := range s.airports {
		s.airportBy[s.airports[i].Country] = &s.airports[i]
	}
}

// kioskSpot é um lugar na beirada do hexágono, fora dos lotes (no corredor entre eles).
func (s *Service) kioskSpot(cell int) (float64, float64) {
	f := CellFrame(s.world, cell)
	for _, p := range [][2]float64{{0, -kioskRadius}, {0, kioskRadius}, {kioskRadius, 0}, {-kioskRadius, 0}} {
		if f.Inside(p[0], p[1], 1.0) {
			return p[0], p[1]
		}
	}
	return 0, -kioskRadius
}

func allLandCells(w *world.World) []int {
	var out []int
	for i, c := range w.Cells {
		if c.Terrain == world.Land {
			out = append(out, i)
		}
	}
	return out
}

// Airports lista os aeroportos (por nome do país).
func (s *Service) Airports() []Airport {
	out := append([]Airport(nil), s.airports...)
	sort.Slice(out, func(a, b int) bool { return out[a].CountryName < out[b].CountryName })
	return out
}

// IsAirportCell diz se o hexágono é de um aeroporto (sem lotes, objetos nem animais).
func (s *Service) IsAirportCell(cell int) bool { return s.airportCells[cell] }

// distanceKm entre dois aeroportos, pela superfície da Terra.
func distanceKm(a, b *Airport) float64 {
	va, vb := world.LatLonToVec(a.Lat, a.Lon), world.LatLonToVec(b.Lat, b.Lon)
	return math.Acos(math.Max(-1, math.Min(1, va.Dot(vb)))) * EarthRadiusKm
}

// TravelPrice é o preço da passagem entre dois aeroportos (economy.json, travel).
func (s *Service) TravelPrice(from, to string) int64 {
	a, b := s.airportBy[from], s.airportBy[to]
	if a == nil || b == nil {
		return 0
	}
	t := s.content.Economy.Travel
	price := int64(math.Round(t.Base + t.Per1000K*distanceKm(a, b)/1000))
	return max(price, t.Min)
}

// --- Passaportes ----------------------------------------------------------------------------

// PassportView é o livro de passaporte: os passaportes (o do país de residência primeiro) e
// os carimbos dos países visitados.
type PassportView struct {
	Passports []string    `json:"passports"`
	Stamps    []StampView `json:"stamps"`
	Coins     int64       `json:"coins"`
}

// StampView é um carimbo.
type StampView struct {
	Country string `json:"country"`
	Name    string `json:"name"`
	FirstAt int64  `json:"first_at"`
}

func (s *Service) passportsOf(ctx context.Context, st Store, p *Player) ([]string, error) {
	list, err := st.Passports(ctx, p.ID)
	if err != nil {
		return nil, err
	}
	out := []string{p.Country}
	for _, c := range list {
		if c != p.Country {
			out = append(out, c)
		}
	}
	return out, nil
}

func (s *Service) hasPassport(ctx context.Context, st Store, p *Player, country string) (bool, error) {
	list, err := s.passportsOf(ctx, st, p)
	for _, c := range list {
		if c == country {
			return true, err
		}
	}
	return false, err
}

// Passport devolve o livro de passaporte do jogador.
func (s *Service) Passport(ctx context.Context, p *Player) (*PassportView, error) {
	return s.passportView(ctx, s.store, p)
}

func (s *Service) passportView(ctx context.Context, st Store, p *Player) (*PassportView, error) {
	v := &PassportView{Stamps: []StampView{}}
	var err error
	if v.Passports, err = s.passportsOf(ctx, st, p); err != nil {
		return nil, err
	}
	stamps, err := st.Stamps(ctx, p.ID)
	if err != nil {
		return nil, err
	}
	for _, sp := range stamps {
		v.Stamps = append(v.Stamps, StampView{Country: sp.Country, Name: s.CountryName(sp.Country), FirstAt: sp.FirstAt.Unix()})
	}
	v.Coins, err = st.Coins(ctx, p.ID)
	return v, err
}

// PassportResult é a resposta de comprar passaporte, carimbar ou viajar.
type PassportResult struct {
	Passport *PassportView `json:"passport"`
	Stamp    *StampView    `json:"stamp,omitempty"` // carimbo novo (nil se já tinha)
	Reward   int64         `json:"reward"`
	Price    int64         `json:"price"`
	Airport  *Airport      `json:"airport,omitempty"`
	Message  string        `json:"message"`
}

func (s *Service) validCountry(code string) bool { return s.CountryName(code) != "" }

// buyPassport cobra e guarda o passaporte (dentro de uma transação).
func (s *Service) buyPassport(ctx context.Context, tx Store, p *Player, country string) (int64, error) {
	if country == p.Country {
		return 0, ErrInvalid.with("O passaporte de %s você já tem: é o seu país.", s.CountryName(country))
	}
	if ok, err := s.hasPassport(ctx, tx, p, country); err != nil || ok {
		if ok {
			return 0, ErrInvalid.with("Você já tem o passaporte de %s.", s.CountryName(country))
		}
		return 0, err
	}
	price := s.content.PassportPrice(country)
	if _, err := s.grant(ctx, tx, p, -price, "passport", country); err != nil {
		return 0, err
	}
	_, err := tx.AddPassport(ctx, p.ID, country, s.clock.Now())
	return price, err
}

// stamp carimba o país (se for a primeira visita) e paga a recompensa.
func (s *Service) stamp(ctx context.Context, tx Store, p *Player, country string) (*StampView, int64, error) {
	added, err := tx.AddStamp(ctx, p.ID, country, s.clock.Now())
	if err != nil || !added {
		return nil, 0, err
	}
	reward := s.content.Economy.Rewards.StampFirst
	if _, err := s.grant(ctx, tx, p, reward, "stamp", country); err != nil {
		return nil, 0, err
	}
	return &StampView{Country: country, Name: s.CountryName(country), FirstAt: s.clock.Now().Unix()}, reward, nil
}

// BuyPassport compra o passaporte de um país (no aeroporto).
//
// Com o tempo real ligado, a distância é conferida no servidor (ADR 0040).
func (s *Service) BuyPassport(ctx context.Context, p *Player, country string) (*PassportResult, error) {
	if !s.validCountry(country) {
		return nil, ErrCountry
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *PassportResult
	err := s.store.InTx(ctx, func(tx Store) error {
		price, err := s.buyPassport(ctx, tx, p, country)
		if err != nil {
			return err
		}
		res = &PassportResult{Price: price, Message: fmt.Sprintf("Passaporte de %s comprado!", s.CountryName(country))}
		res.Passport, err = s.passportView(ctx, tx, p)
		return err
	})
	if err == nil {
		s.emit(Event{Kind: "passports", PlayerID: p.ID})
	}
	return res, err
}

// Stamp carimba a entrada a pé num país. Precisa do passaporte dele (ou ser o país de
// residência). Só a primeira visita a cada país dá carimbo e recompensa.
//
// Com o tempo real ligado, a distância é conferida no servidor (ADR 0040).
func (s *Service) Stamp(ctx context.Context, p *Player, country string) (*PassportResult, error) {
	if !s.validCountry(country) {
		return nil, ErrCountry
	}
	// Carimbo a pé: o jogador precisa estar mesmo no país (ou a um passo dele).
	if pos, _, _, checked, err := s.where(p); err != nil {
		return nil, err
	} else if checked && !s.nearCountry(pos, country, 2.0) {
		return nil, ErrInvalid.with("Você não está em %s.", s.CountryName(country))
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *PassportResult
	err := s.store.InTx(ctx, func(tx Store) error {
		ok, err := s.hasPassport(ctx, tx, p, country)
		if err != nil {
			return err
		}
		if !ok {
			return ErrNoPassport.with("Para entrar aqui, você precisa do passaporte deste país: %s. Ele pode ser comprado em qualquer aeroporto.", s.CountryName(country))
		}
		res = &PassportResult{}
		if res.Stamp, res.Reward, err = s.stamp(ctx, tx, p, country); err != nil {
			return err
		}
		if res.Stamp != nil {
			res.Message = fmt.Sprintf("Carimbo novo no passaporte: %s!", s.CountryName(country))
		}
		res.Passport, err = s.passportView(ctx, tx, p)
		return err
	})
	return res, err
}

// Travel compra a passagem de `from` para `to` (e, com buyPassport, o passaporte do destino
// junto) e carimba a chegada. Sem o passaporte do destino, não dá para viajar.
//
// O jogador precisa estar no balcão do aeroporto `from` (ADR 0040).
func (s *Service) Travel(ctx context.Context, p *Player, from, to string, buyPassport, free bool) (*PassportResult, error) {
	dest := s.airportBy[to]
	if dest == nil {
		return nil, ErrNotFound.with("%s não tem aeroporto.", s.CountryName(to))
	}
	if s.airportBy[from] == nil {
		from = p.Country
	}
	if from == to {
		return nil, ErrInvalid.with("Você já está em %s.", s.CountryName(to))
	}
	// No balcão do aeroporto de saída (o voo de graça do modo dev sai de qualquer lugar).
	if !free {
		counter, _ := s.ArrivalPoint(from)
		if err := s.requireNear(p, counter, s.content.Rules.Reach.Airport, "do balcão do aeroporto"); err != nil {
			return nil, err
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *PassportResult
	err := s.store.InTx(ctx, func(tx Store) error {
		ok, err := s.hasPassport(ctx, tx, p, to)
		if err != nil {
			return err
		}
		res = &PassportResult{}
		if !ok && !free {
			if !buyPassport {
				return ErrNoPassport.with("Para viajar para %s, você precisa do passaporte de lá (%s).", s.CountryName(to), s.CoinsText(s.content.PassportPrice(to)))
			}
			if res.Price, err = s.buyPassport(ctx, tx, p, to); err != nil {
				return err
			}
		}
		if !free {
			fare := s.TravelPrice(from, to)
			if _, err := s.grant(ctx, tx, p, -fare, "travel", from+">"+to); err != nil {
				if res.Price > 0 {
					have, _ := tx.Coins(ctx, p.ID)
					return ErrNoCoins.with("A passagem e o passaporte custam %s; você tem %s.", s.CoinsText(fare+res.Price), s.CoinsText(have+res.Price))
				}
				return err
			}
			res.Price += fare
		}
		if res.Stamp, res.Reward, err = s.stamp(ctx, tx, p, to); err != nil {
			return err
		}
		res.Airport = dest
		res.Message = fmt.Sprintf("Boa viagem para %s!", s.CountryName(to))
		res.Passport, err = s.passportView(ctx, tx, p)
		return err
	})
	if err == nil {
		s.allowArrival(p.ID, to)
	}
	if err == nil {
		s.emit(Event{Kind: "passports", PlayerID: p.ID})
	}
	return res, err
}

// AirportQuote é um destino com o preço a partir de um aeroporto.
type AirportQuote struct {
	Airport
	Fare          int64 `json:"fare"`
	PassportPrice int64 `json:"passport_price"`
	HasPassport   bool  `json:"has_passport"`
}

// Quotes lista os destinos a partir do aeroporto `from`, com passagem e passaporte.
func (s *Service) Quotes(ctx context.Context, p *Player, from string) ([]AirportQuote, error) {
	have, err := s.passportsOf(ctx, s.store, p)
	if err != nil {
		return nil, err
	}
	owned := map[string]bool{}
	for _, c := range have {
		owned[c] = true
	}
	if s.airportBy[from] == nil {
		from = p.Country
	}
	var out []AirportQuote
	for _, a := range s.Airports() {
		if a.Country == from {
			continue
		}
		out = append(out, AirportQuote{Airport: a, Fare: s.TravelPrice(from, a.Country),
			PassportPrice: s.content.PassportPrice(a.Country), HasPassport: owned[a.Country]})
	}
	return out, nil
}

// PassportPrices lista todos os países (com ou sem aeroporto) com o preço do passaporte.
func (s *Service) PassportPrices() []map[string]any {
	var out []map[string]any
	if s.geo == nil {
		return out
	}
	for _, c := range s.geo.Countries {
		out = append(out, map[string]any{"country": c.Code, "name": c.Name, "price": s.content.PassportPrice(c.Code)})
	}
	sort.Slice(out, func(a, b int) bool { return strings.Compare(out[a]["name"].(string), out[b]["name"].(string)) < 0 })
	return out
}

// DevPassport: "give" ou "remove" um passaporte; "complete" (todos os passaportes e um
// carimbo de cada país com aeroporto, sem moedas) ou "reset" (sem passaportes nem carimbos).
func (s *Service) DevPassport(ctx context.Context, p *Player, action, country string) (*PassportView, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var v *PassportView
	err := s.store.InTx(ctx, func(tx Store) error {
		now := s.clock.Now()
		switch action {
		case "give":
			if !s.validCountry(country) {
				return ErrCountry
			}
			if _, err := tx.AddPassport(ctx, p.ID, country, now); err != nil {
				return err
			}
		case "remove":
			if err := tx.RemovePassport(ctx, p.ID, country); err != nil {
				return err
			}
		case "complete":
			if s.geo == nil {
				return ErrInvalid
			}
			for _, c := range s.geo.Countries {
				if _, err := tx.AddPassport(ctx, p.ID, c.Code, now); err != nil {
					return err
				}
			}
			for _, a := range s.airports {
				if _, err := tx.AddStamp(ctx, p.ID, a.Country, now); err != nil {
					return err
				}
			}
		case "reset":
			if err := tx.ClearPassports(ctx, p.ID); err != nil {
				return err
			}
		default:
			return ErrInvalid.with("Use give, remove, complete ou reset.")
		}
		var err error
		v, err = s.passportView(ctx, tx, p)
		return err
	})
	if err == nil {
		s.emit(Event{Kind: "passports", PlayerID: p.ID})
	}
	return v, err
}
