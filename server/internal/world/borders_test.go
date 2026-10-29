package world

import (
	"math"
	"math/rand"
	"testing"
)

// Pontos uns 20 a 30 km para dentro de cada lado de fronteiras conhecidas (o país vem da
// posição exata, não do hexágono, que tem ~140 km).
var borderPoints = []struct {
	name     string
	lat, lon float64
	code     string
}{
	// Tríplice fronteira: Foz do Iguaçu × Ciudad del Este × Puerto Iguazú.
	{"Foz do Iguaçu (lado brasileiro)", -25.50, -54.35, "BRA"},
	{"Ciudad del Este (lado paraguaio)", -25.45, -54.85, "PRY"},
	{"Puerto Iguazú (lado argentino)", -25.85, -54.40, "ARG"},
	// Corumbá × Puerto Quijarro.
	{"Corumbá (lado brasileiro)", -19.05, -57.40, "BRA"},
	{"Puerto Quijarro (lado boliviano)", -18.95, -57.95, "BOL"},
	// Tabatinga × Letícia.
	{"Tabatinga (lado brasileiro)", -4.30, -69.70, "BRA"},
	{"Letícia (lado colombiano)", -4.00, -69.95, "COL"},
	// Strasbourg × Kehl.
	{"Strasbourg (lado francês)", 48.55, 7.45, "FRA"},
	{"Kehl (lado alemão)", 48.55, 8.10, "DEU"},
	// Países pequenos que somem no 1:110m.
	{"Luxemburgo", 49.70, 6.10, "LUX"},
	{"Andorra", 42.55, 1.57, "AND"},
	{"Liechtenstein", 47.14, 9.55, "LIE"},
}

func TestCountryAtKnownBorders(t *testing.T) {
	g := testGeography(t)
	for _, tc := range borderPoints {
		if got := g.CountryAt(tc.lat, tc.lon); got != tc.code {
			t.Errorf("%s (%.2f, %.2f): país %q, esperado %q", tc.name, tc.lat, tc.lon, got, tc.code)
		}
	}
	if g.CountryAt(0, -30) != "" {
		t.Errorf("meio do Atlântico com país")
	}
}

// O cliente decide o país pelo segmento mais perto (CellBorders). Precisa concordar com o
// ponto em polígono nos pontos conhecidos e em pontos sorteados perto de fronteiras.
func TestCellBordersAgreeWithPointInPolygon(t *testing.T) {
	g := testGeography(t)
	w := testWorld(t)
	for _, tc := range borderPoints {
		c := w.CellAt(tc.lat, tc.lon)
		cb := g.CellBorders(w, c.ID)
		if got := cb.CountryByNearestSegment(g.Countries, tc.lat, tc.lon); got != tc.code {
			t.Errorf("%s: regra do cliente deu %q, esperado %q (%d segmentos)", tc.name, got, tc.code, len(cb.Segs))
		}
	}
	r := rand.New(rand.NewSource(7))
	checked, wrong := 0, 0
	for _, tc := range borderPoints {
		for k := 0; k < 150; k++ {
			lat := tc.lat + (r.Float64()-0.5)*1.2
			lon := tc.lon + (r.Float64()-0.5)*1.2
			c := w.CellAt(lat, lon)
			cb := g.CellBorders(w, c.ID)
			want := g.CountryAt(lat, lon)
			if got := cb.CountryByNearestSegment(g.Countries, lat, lon); got != want {
				wrong++
				if wrong <= 5 {
					t.Logf("(%.4f, %.4f): cliente %q, polígono %q", lat, lon, got, want)
				}
			}
			checked++
		}
	}
	if wrong > checked/200 {
		t.Errorf("%d de %d pontos discordam", wrong, checked)
	}
}

func TestCellBordersUniformCells(t *testing.T) {
	g := testGeography(t)
	w := testWorld(t)
	// Interior do Brasil, longe de qualquer fronteira e da costa: célula de um país só.
	c := w.CellAt(-10, -55)
	cb := g.CellBorders(w, c.ID)
	if len(cb.Segs) != 0 || cb.Country != "BRA" {
		t.Errorf("Mato Grosso: %d segmentos, país %q", len(cb.Segs), cb.Country)
	}
	// Foz do Iguaçu: tem fronteira compartilhada (linha no chão), não só costa.
	cb = g.CellBorders(w, w.CellAt(-25.55, -54.58).ID)
	shared := 0
	for _, s := range cb.Segs {
		if s.Shared {
			shared++
		}
	}
	if shared == 0 {
		t.Errorf("Foz do Iguaçu sem fronteira compartilhada (%d segmentos)", len(cb.Segs))
	}
}

func TestSmallCountriesExist(t *testing.T) {
	g := testGeography(t)
	for _, code := range []string{"LUX", "AND", "MCO", "LIE", "SMR", "VAT", "SGP", "MLT"} {
		if g.CountryName(code) == "" {
			t.Errorf("país pequeno %s não existe", code)
		}
	}
	if n := g.CountryName("LUX"); n != "Luxemburgo" {
		t.Errorf("nome de LUX: %q", n)
	}
}

func TestBorderSegmentsKeepCountryOnTheLeft(t *testing.T) {
	g := testGeography(t)
	// Um ponto logo à esquerda do meio de cada segmento compartilhado tem de cair no país dele.
	bad, n := 0, 0
	for i, s := range g.borders.segs {
		if !s.Shared || i%37 != 0 {
			continue
		}
		mx, my := (s.A[0]+s.B[0])/2, (s.A[1]+s.B[1])/2
		ex, ey := s.B[0]-s.A[0], s.B[1]-s.A[1]
		l := math.Hypot(ex, ey)
		px, py := mx-ey/l*0.002, my+ex/l*0.002
		if g.CountryAt(py, px) != g.Countries[s.Country].Code {
			bad++
		}
		n++
	}
	if bad > n/50 {
		t.Errorf("%d de %d segmentos com o país do lado errado", bad, n)
	}
}
