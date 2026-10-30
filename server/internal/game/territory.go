package game

import (
	"context"
	"fmt"
	"math"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Rules são as regras de fronteira e de multiplayer (rules.json).
type Rules struct {
	Borders BorderRules `json:"borders"`
}

// BorderRules: lotes e fronteiras (fase 3, ADR 0037).
type BorderRules struct {
	// Distância mínima entre um lote novo e qualquer fronteira com outro país.
	LotMargin float64 `json:"lot_margin"`
	// Espaçamento das amostras que conferem o lote.
	SampleStep float64 `json:"sample_step"`
}

func (r *Rules) check() error {
	if r.Borders.LotMargin < 0 || r.Borders.SampleStep <= 0 {
		return fmt.Errorf("rules.json: borders.lot_margin >= 0 e borders.sample_step > 0")
	}
	return nil
}

// Point é o ponto (x, y) do plano da célula em coordenadas do mundo.
func (f *Frame) Point(x, y float64) world.Vec3 {
	return f.Center.Scale(f.Top).Add(f.East.Scale(x)).Add(f.North.Scale(y))
}

// Coords são as coordenadas (x, y) de um ponto do mundo no plano da célula.
func (f *Frame) Coords(p world.Vec3) (x, y float64) {
	return p.Dot(f.East), p.Dot(f.North)
}

// CountryAtPoint é o país exato de um ponto do mundo ("" = mar ou fora de qualquer país).
// Sem geografia carregada, vale o país principal da célula.
func (s *Service) CountryAtPoint(p world.Vec3) string {
	if s.geo == nil {
		return s.world.Cells[s.world.FindCell(p, -1)].Country
	}
	lat, lon := world.VecToLatLon(p)
	return s.geo.CountryAt(lat, lon)
}

// Níveis de encaixe de um lote no país (ADR 0037). O jogador novo ganha um lote do melhor
// nível que ainda tiver vaga: países grandes sempre têm do nível 0; países pequenos, que
// cabem num hexágono cortado por fronteiras (Albânia), ficam com o 1 ou o 2.
const (
	LotTierClear    = 0 // inteiro no país e longe da fronteira (margem de rules.json)
	LotTierInside   = 1 // inteiro no país, mas perto da fronteira
	LotTierMostly   = 2 // a maior parte no país (o resto conta como do dono, PassageCountry)
	LotTierUnusable = 3
)

// LotTier é o nível de encaixe do lote (célula, posição) no país. Fica em cache.
func (s *Service) LotTier(cell, slot int, country string) int {
	key := fmt.Sprintf("%d:%s", LotID(cell, slot), country)
	if v, ok := s.tiers.Load(key); ok {
		return v.(int)
	}
	t := s.lotTier(cell, slot, country)
	s.tiers.Store(key, t)
	return t
}

func (s *Service) lotTier(cell, slot int, country string) int {
	if s.geo == nil {
		if s.world.Cells[cell].Country == country {
			return LotTierClear
		}
		return LotTierUnusable
	}
	f := CellFrame(s.world, cell)
	x0, y0, x1, y1 := SlotRect(slot)
	m := s.content.Rules.Borders.LotMargin
	step := s.content.Rules.Borders.SampleStep
	in, total := 0, 0
	marginOK := true
	for x := x0 - m; x <= x1+m+1e-9; x += step {
		for y := y0 - m; y <= y1+m+1e-9; y += step {
			c := s.CountryAtPoint(f.Point(x, y))
			if x >= x0 && x <= x1 && y >= y0 && y <= y1 {
				total++
				if c == country {
					in++
				}
			} else if c != country && c != "" {
				marginOK = false // outro país na margem (mar pode, pela costa)
			}
		}
	}
	switch {
	case in == total && marginOK:
		return LotTierClear
	case in == total:
		return LotTierInside
	case 2*in >= total:
		return LotTierMostly
	}
	return LotTierUnusable
}

// LotFitsCountry diz se o lote fica inteiro no país, longe da fronteira (o nível normal).
func (s *Service) LotFitsCountry(cell, slot int, country string) bool {
	return s.LotTier(cell, slot, country) == LotTierClear
}

// UsableLots conta os lotes que um jogador do país pode ganhar (testes e modo dev).
func (s *Service) UsableLots(country string) int {
	n := 0
	for _, cell := range s.byCountry[country] {
		if s.airportCells[cell] {
			continue
		}
		for _, slot := range LotSlots(s.world, cell) {
			if s.LotTier(cell, slot.Slot, country) < LotTierUnusable {
				n++
			}
		}
	}
	return n
}

// InLotArea diz se o ponto do mundo está no lote ou na margem em volta dele.
func (s *Service) InLotArea(l *Lot, p world.Vec3) bool {
	f := CellFrame(s.world, l.Cell)
	if p.Normalize().Dot(f.Center) < 0.99 { // longe da célula (mais de ~140 unidades)
		return false
	}
	x, y := f.Coords(p)
	x0, y0, x1, y1 := SlotRect(l.Slot)
	m := s.content.Rules.Borders.LotMargin
	return x >= x0-m && x <= x1+m && y >= y0-m && y <= y1+m
}

// PassageCountry é o país que vale para a regra de passagem do jogador no ponto: o lote
// dele e a margem em volta contam como o país dele (lotes antigos que cruzam fronteira);
// fora disso, o país exato. lot pode ser nil.
func (s *Service) PassageCountry(p *Player, lot *Lot, pos world.Vec3) string {
	if lot != nil && s.InLotArea(lot, pos) {
		return p.Country
	}
	return s.CountryAtPoint(pos)
}

// CanWalk diz se o jogador pode dar o passo de from para to pela regra do passaporte
// (ADR 0035 e 0037). Pode sempre: no hexágono de casa, para dentro de um país de que tem
// passaporte (ou para fora de qualquer país) e dentro do país em que já está (chegou de
// avião ou por teleporte). passports inclui o país do jogador.
func (s *Service) CanWalk(p *Player, lot *Lot, passports map[string]bool, from, to world.Vec3, hint int) bool {
	if lot != nil && s.world.FindCell(to, hint) == lot.Cell {
		return true
	}
	target := s.PassageCountry(p, lot, to)
	if target == "" || passports[target] {
		return true
	}
	return s.PassageCountry(p, lot, from) == target
}

// BorderLot é um lote antigo que cruza fronteira (ou fica perto demais dela).
type BorderLot struct {
	LotID    int64  `json:"lot_id"`
	Cell     int    `json:"cell"`
	Owner    string `json:"owner"`
	Country  string `json:"country"`
	Fake     bool   `json:"fake"`
	Crossing bool   `json:"crossing"` // true: parte do lote é de outro país; false: só a margem
}

// BorderLots lista os lotes ocupados que não cabem mais na regra de lote novo.
func (s *Service) BorderLots(ctx context.Context) ([]BorderLot, error) {
	lots, err := s.store.AllLots(ctx)
	if err != nil {
		return nil, err
	}
	ids := make([]int64, len(lots))
	for i, l := range lots {
		ids[i] = l.OwnerID
	}
	owners, err := s.store.PlayersByIDs(ctx, ids)
	if err != nil {
		return nil, err
	}
	out := []BorderLot{}
	for _, l := range lots {
		o := owners[l.OwnerID]
		if o == nil || s.LotFitsCountry(l.Cell, l.Slot, o.Country) {
			continue
		}
		out = append(out, BorderLot{LotID: l.ID, Cell: l.Cell, Owner: o.Nickname, Country: o.Country, Fake: o.Fake,
			Crossing: s.LotTier(l.Cell, l.Slot, o.Country) >= LotTierMostly})
	}
	return out, nil
}

// DevMoveBorderLots muda os lotes de BorderLots para um lugar válido no país do dono,
// com a casa, a obra e os objetos colocados (as posições dentro do lote não mudam).
// Devolve quantos foram movidos e quantos ficaram (país sem lote livre válido).
func (s *Service) DevMoveBorderLots(ctx context.Context) (moved, left int, err error) {
	list, err := s.BorderLots(ctx)
	if err != nil {
		return 0, 0, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, b := range list {
		err := s.store.InTx(ctx, func(tx Store) error {
			cells := s.byCountry[b.Country]
			lots, err := tx.LotsByCells(ctx, cells)
			if err != nil {
				return err
			}
			taken := map[int64]bool{}
			for _, l := range lots {
				taken[l.ID] = true
			}
			for _, cell := range cells {
				if s.airportCells[cell] {
					continue
				}
				for _, slot := range LotSlots(s.world, cell) {
					if taken[slot.ID] || !s.LotFitsCountry(cell, slot.Slot, b.Country) {
						continue
					}
					return tx.MoveLot(ctx, b.LotID, slot.ID, cell, slot.Slot)
				}
			}
			return errNoValidLot
		})
		switch {
		case err == errNoValidLot:
			left++
		case err != nil:
			return moved, left, err
		default:
			moved++
		}
	}
	return moved, left, nil
}

var errNoValidLot = fmt.Errorf("sem lote livre válido")

// angularUnits é a distância (unidades do mundo, no chão) entre dois pontos.
func (s *Service) angularUnits(a, b world.Vec3) float64 {
	d := a.Normalize().Dot(b.Normalize())
	return math.Acos(math.Max(-1, math.Min(1, d))) * s.world.Radius
}
