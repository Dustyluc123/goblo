package game_test

import (
	"fmt"
	"testing"

	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Lotes novos ficam inteiros no país do dono (e, havendo lugar, longe da fronteira).
func TestNewLotsNeverCrossBorder(t *testing.T) {
	f := newFixture(t)
	for _, code := range []string{"PRY", "URY", "BEL", "NLD", "AUT", "CHE", "ALB"} {
		// Lotes longe da fronteira que o país tem: os primeiros jogadores ficam com eles.
		clear := 0
		for cell, c := range f.world.Cells {
			if c.Country != code {
				continue
			}
			for _, slot := range game.LotSlots(f.world, cell) {
				if f.svc.LotTier(cell, slot.Slot, code) == game.LotTierClear {
					clear++
				}
			}
		}
		for i := 0; i < min(6, f.svc.UsableLots(code)); i++ {
			p, me := f.player(t, fmt.Sprintf("Fronteira %s %d", code, i), code)
			lot := me.Lot
			tier := f.svc.LotTier(lot.Cell, int(lot.ID%4), code)
			if tier >= game.LotTierUnusable {
				t.Fatalf("%s ganhou um lote fora do país (%d)", p.Nickname, lot.ID)
			}
			// Conferência independente: amostras dentro do lote.
			fr := game.CellFrame(f.world, lot.Cell)
			x0, y0, x1, y1 := game.SlotRect(int(lot.ID % 4))
			out := 0
			for x := x0; x <= x1; x += 0.5 {
				for y := y0; y <= y1; y += 0.5 {
					if f.svc.CountryAtPoint(fr.Point(x, y)) != code {
						out++
					}
				}
			}
			if tier <= game.LotTierInside && out > 0 {
				t.Fatalf("%s: lote %d (nível %d) com %d amostras fora do país", code, lot.ID, tier, out)
			}
			if i < clear-2 && tier != game.LotTierClear { // folga: hexágonos de aeroporto
				t.Fatalf("%s: lote %d perto da fronteira (nível %d) com lotes melhores sobrando", code, lot.ID, tier)
			}
		}
	}
}

// crossingLot acha um lote possível do país que cruza a fronteira, e um ponto dele que é
// de outro país.
func crossingLot(t *testing.T, f *fixture, country string) (*game.Lot, world.Vec3, string) {
	t.Helper()
	for cell, c := range f.world.Cells {
		if c.Country != country {
			continue
		}
		for _, slot := range game.LotSlots(f.world, cell) {
			fr := game.CellFrame(f.world, cell)
			x0, y0, x1, y1 := game.SlotRect(slot.Slot)
			for x := x0 + 0.25; x < x1; x += 0.5 {
				for y := y0 + 0.25; y < y1; y += 0.5 {
					p := fr.Point(x, y)
					if other := f.svc.CountryAtPoint(p); other != "" && other != country {
						return &game.Lot{ID: slot.ID, Cell: cell, Slot: slot.Slot}, p, other
					}
				}
			}
		}
	}
	t.Fatalf("nenhum lote de %s cruza fronteira", country)
	return nil, world.Vec3{}, ""
}

// Num lote antigo que cruza a fronteira, o lote conta como país do dono para ele (e só
// para ele): pode andar no lote inteiro, mas visitantes seguem a fronteira de verdade.
func TestOldLotCrossingBorderCountsAsOwnersCountry(t *testing.T) {
	f := newFixture(t)
	for _, country := range []string{"BRA", "FRA", "DEU"} {
		lot, p, other := crossingLot(t, f, country)
		owner := &game.Player{ID: 1, Country: country}
		visitor := &game.Player{ID: 2, Country: country}
		if got := f.svc.PassageCountry(owner, lot, p); got != country {
			t.Fatalf("%s: ponto do lote em %s conta como %s para o dono", country, other, got)
		}
		if got := f.svc.PassageCountry(visitor, nil, p); got != other {
			t.Fatalf("%s: para um visitante o ponto é %s, não %s", country, other, got)
		}
		fr := game.CellFrame(f.world, lot.Cell)
		x0, y0, _, _ := game.SlotRect(lot.Slot)
		inLot := fr.Point(x0+3.5, y0+3.5)
		mine := map[string]bool{country: true}
		if !f.svc.CanWalk(owner, lot, mine, inLot, p, lot.Cell) {
			t.Fatalf("%s: o dono não pode andar no próprio lote", country)
		}
	}
}

// Sem bolsões: perto de fronteiras, quem está num país chega a pé a todo ponto daquele
// país que a geografia liga ao ponto de partida (busca em largura numa grade de 0,5
// unidade). O dono de um lote que cruza a fronteira chega do lote ao resto do país.
func TestNoPocketsNearBorders(t *testing.T) {
	f := newFixture(t)
	cases := []struct {
		name     string
		lat, lon float64
	}{
		{"Foz do Iguaçu", -25.55, -54.55},
		{"Strasbourg", 48.57, 7.78},
		{"Tabatinga", -4.2, -69.94},
		{"Corumbá", -19.0, -57.7},
	}
	for _, c := range cases {
		cell := f.world.FindCell(world.LatLonToVec(c.lat, c.lon), -1)
		fr := game.CellFrame(f.world, cell)
		const half, step = 16.0, 0.5
		n := int(2*half/step) + 1
		pts := make([]world.Vec3, n*n)
		land := make([]string, n*n)
		for i := 0; i < n; i++ {
			for j := 0; j < n; j++ {
				p := fr.Point(-half+float64(i)*step, -half+float64(j)*step)
				pts[i*n+j] = p
				land[i*n+j] = f.svc.CountryAtPoint(p)
			}
		}
		flood := func(start int, ok func(a, b int) bool) map[int]bool {
			seen := map[int]bool{start: true}
			queue := []int{start}
			for len(queue) > 0 {
				k := queue[0]
				queue = queue[1:]
				i, j := k/n, k%n
				for _, d := range [][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}} {
					a, b := i+d[0], j+d[1]
					if a < 0 || b < 0 || a >= n || b >= n {
						continue
					}
					nk := a*n + b
					if !seen[nk] && land[nk] != "" && ok(k, nk) {
						seen[nk] = true
						queue = append(queue, nk)
					}
				}
			}
			return seen
		}
		// Visitante: para cada país da área, o alcance a pé é a componente geográfica.
		done := map[string]bool{}
		for k, code := range land {
			if code == "" || done[code] {
				continue
			}
			done[code] = true
			pl := &game.Player{ID: 9, Country: code}
			pass := map[string]bool{code: true}
			walk := flood(k, func(a, b int) bool { return f.svc.CanWalk(pl, nil, pass, pts[a], pts[b], cell) })
			geo := flood(k, func(a, b int) bool { return land[b] == code })
			for g := range geo {
				if !walk[g] {
					t.Fatalf("%s: ponto de %s inacessível a pé para quem está nele", c.name, code)
				}
			}
		}
		// Dono de um lote que cruza a fronteira, se houver um na área.
		owner := &game.Player{ID: 10, Country: f.world.Cells[cell].Country}
		mine := map[string]bool{owner.Country: true}
		for _, slot := range game.LotSlots(f.world, cell) {
			lot := &game.Lot{Cell: cell, Slot: slot.Slot}
			x0, y0, _, _ := game.SlotRect(slot.Slot)
			start := -1
			best := 1e9
			for k := range pts {
				x, y := fr.Coords(pts[k])
				if d := (x-x0-3.5)*(x-x0-3.5) + (y-y0-3.5)*(y-y0-3.5); d < best {
					best, start = d, k
				}
			}
			walk := flood(start, func(a, b int) bool { return f.svc.CanWalk(owner, lot, mine, pts[a], pts[b], cell) })
			for k := range pts {
				if f.svc.InLotArea(lot, pts[k]) && land[k] != "" && !walk[k] {
					t.Fatalf("%s: o dono não chega a um ponto do próprio lote %d", c.name, slot.Slot)
				}
			}
			// Do lote, chega ao resto do país (a pontos do país fora do hexágono de casa).
			reached := false
			for k := range walk {
				if land[k] == owner.Country && f.world.FindCell(pts[k], cell) != cell {
					reached = true
					break
				}
			}
			if !reached {
				t.Fatalf("%s: do lote %d o dono não chega ao resto de %s", c.name, slot.Slot, owner.Country)
			}
		}
	}
}
