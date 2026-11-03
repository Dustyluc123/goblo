package game_test

import (
	"math"
	"testing"
)

// A praça (pista na diagonal, terminal, loja, avião) cabe no hexágono de todos os aeroportos
// grandes, e o balcão e a loja ficam onde o cliente monta (fase 3.6, ADR 0047).
func TestPlazaFitsInEveryAirportCell(t *testing.T) {
	f := newFixture(t)
	big, worst, smaller := 0, math.Inf(1), 0
	for _, a := range f.svc.Airports() {
		if a.Small {
			continue
		}
		big++
		if a.Scale < 1 {
			smaller++
		}
		if a.Scale < 0.75 || a.Scale > 1 {
			t.Errorf("praça de %s com escala %.2f", a.Country, a.Scale)
		}
		m := f.svc.PlazaMargin(a)
		worst = math.Min(worst, m)
		if m < 0 {
			t.Errorf("praça de %s (célula %d) passa %.2f da borda do hexágono", a.Country, a.Cell, -m)
		}
		if math.Hypot(a.X, a.Y) < 2 || math.Hypot(a.ShopX, a.ShopY) < 5 {
			t.Errorf("praça de %s: balcão (%.1f, %.1f) ou loja (%.1f, %.1f) fora do lugar", a.Country, a.X, a.Y, a.ShopX, a.ShopY)
		}
	}
	t.Logf("%d praças (%d menores); menor folga até a borda: %.2f", big, smaller, worst)
}
