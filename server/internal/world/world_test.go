package world

import (
	"bytes"
	"compress/gzip"
	"io"
	"math"
	"sync"
	"testing"

	"github.com/Dustyluc123/goblo/server/data"
)

var (
	geoOnce   sync.Once
	geo       *Geography
	geoErr    error
	worldOnce sync.Once
	defWorld  *World
	worldErr  error
)

func testGeography(t *testing.T) *Geography {
	t.Helper()
	geoOnce.Do(func() { geo, geoErr = LoadGeography(data.NaturalEarth) })
	if geoErr != nil {
		t.Fatal(geoErr)
	}
	return geo
}

// testWorld devolve o mundo padrão (n = 50), gerado uma vez para todos os testes.
func testWorld(t *testing.T) *World {
	t.Helper()
	g := testGeography(t)
	worldOnce.Do(func() { defWorld, worldErr = New(DefaultConfig, g) })
	if worldErr != nil {
		t.Fatal(worldErr)
	}
	return defWorld
}

func TestWorldCellCount(t *testing.T) {
	w := testWorld(t)
	if w.Frequency != 50 {
		t.Fatalf("frequência padrão %d, esperado 50", w.Frequency)
	}
	if got, want := len(w.Cells), 10*50*50+2; got != want {
		t.Fatalf("%d células, esperado %d", got, want)
	}
	for i, c := range w.Cells {
		if c.ID != i {
			t.Fatalf("célula na posição %d tem id %d", i, c.ID)
		}
	}
}

func TestWorldSaoPauloIsBrazil(t *testing.T) {
	c := testWorld(t).CellAt(-23.55, -46.63)
	if c.Terrain != Land || c.Country != "BRA" {
		t.Fatalf("São Paulo caiu na célula %d: terreno %q, país %q", c.ID, c.Terrain, c.Country)
	}
	if c.Biome == BiomeDesert || c.Biome == BiomeIce || c.Biome == BiomeOcean {
		t.Fatalf("São Paulo com bioma %s", c.Biome)
	}
}

func TestWorldMidAtlanticIsOcean(t *testing.T) {
	c := testWorld(t).CellAt(0, -30)
	if c.Terrain != Ocean || c.Country != "" || c.Biome != BiomeOcean || c.Height != 0 {
		t.Fatalf("meio do Atlântico caiu na célula %d: %q, %q, %s, altura %v", c.ID, c.Terrain, c.Country, c.Biome, c.Height)
	}
}

func TestWorldBiomes(t *testing.T) {
	w := testWorld(t)
	for _, tc := range []struct {
		name     string
		lat, lon float64
		want     Biome
	}{
		{"Amazônia", -3, -60, BiomeTropicalForest},
		{"Saara", 23, 13, BiomeDesert},
		{"Himalaia", 28, 85, BiomeMountain},
		{"Antártida", -80, 0, BiomeIce},
		{"Congo", 0, 22, BiomeTropicalForest},
		{"Alpes", 46.5, 9.5, BiomeMountain},
		{"Grandes Planícies", 41, -100, BiomeGrassland},
		{"Sibéria norte", 70, 100, BiomeTundra},
		{"Europa central", 51, 15, BiomeForest},
		{"Arábia", 22, 48, BiomeDesert},
		{"Austrália central", -25, 130, BiomeDesert},
	} {
		if c := w.CellAt(tc.lat, tc.lon); c.Biome != tc.want {
			t.Errorf("%s (%v, %v): bioma %s, esperado %s", tc.name, tc.lat, tc.lon, c.Biome, tc.want)
		}
	}
}

func TestWorldHeights(t *testing.T) {
	w := testWorld(t)
	tibet := w.CellAt(33, 88).Height
	plain := w.CellAt(41, -100).Height
	if tibet < plain+4 {
		t.Errorf("montanha (%v) devia ser bem mais alta que o campo (%v)", tibet, plain)
	}
	maxH := 0.0
	for _, c := range w.Cells {
		maxH = math.Max(maxH, c.Height)
	}
	t.Logf("Tibete %.1f, campo %.1f, ponto mais alto %.1f", tibet, plain, maxH)
	for _, c := range w.Cells {
		switch {
		case c.Terrain == Ocean && (c.Height != 0 || c.Biome != BiomeOcean):
			t.Fatalf("oceano %d com altura %v e bioma %s", c.ID, c.Height, c.Biome)
		case c.Terrain == Land && (c.Height <= 0 || c.Biome == BiomeOcean):
			t.Fatalf("terra %d com altura %v e bioma %s", c.ID, c.Height, c.Biome)
		case c.Biome == BiomeBeach && c.Height >= plain:
			t.Fatalf("praia %d mais alta que o campo", c.ID)
		}
		// Fora das montanhas, vizinhos de terra diferem no máximo um pulo.
		if c.Terrain == Land && c.Biome != BiomeMountain {
			for _, nb := range c.Neighbors {
				o := w.Cells[nb]
				if o.Terrain == Land && o.Biome != BiomeMountain && math.Abs(o.Height-c.Height) > 1.25 {
					t.Fatalf("degrau de %.2f entre %d e %d", math.Abs(o.Height-c.Height), c.ID, nb)
				}
			}
		}
	}
	for b, n := range w.BiomeCounts() {
		t.Logf("%-16s %6d células", b, n)
	}
}

func TestWorldKnownCountries(t *testing.T) {
	w := testWorld(t)
	for _, tc := range []struct {
		name     string
		lat, lon float64
		code     string
	}{
		{"Paris", 48.85, 2.35, "FRA"}, // França usa -99 no ISO_A3 do Natural Earth
		{"Oslo", 59.91, 10.75, "NOR"},
		{"Cairo", 30.04, 31.24, "EGY"},
		{"Moscou", 55.75, 37.62, "RUS"},
		{"Pequim", 39.90, 116.40, "CHN"},
		{"Kansas", 39.0, -98.0, "USA"},
		{"Pacaraima", 4.0, -61.0, "BRA"},
	} {
		if c := w.CellAt(tc.lat, tc.lon); c.Country != tc.code {
			t.Errorf("%s: país %q, esperado %q", tc.name, c.Country, tc.code)
		}
	}
	if w.Countries["BRA"] != "Brasil" {
		t.Errorf("nome do Brasil: %q", w.Countries["BRA"])
	}
}

func TestWorldOceanRatio(t *testing.T) {
	if r := testWorld(t).OceanRatio(); r < 0.60 || r > 0.80 {
		t.Fatalf("proporção de oceano %.3f fora de [0.60, 0.80]", r)
	}
}

func TestWorldLandHasCountryAndOceanHasNot(t *testing.T) {
	w := testWorld(t)
	noCountry := 0
	for _, c := range w.Cells {
		if c.Terrain == Ocean && c.Country != "" {
			t.Fatalf("célula de oceano %d com país %q", c.ID, c.Country)
		}
		if c.Terrain == Land && c.Country == "" {
			noCountry++
		}
	}
	// Na escala 1:110m, terra e países não batem 100%; aceitamos poucas exceções.
	if limit := len(w.Cells) / 400; noCountry > limit {
		t.Errorf("%d células de terra sem país (limite %d)", noCountry, limit)
	}
}

// A meta da fase 1.5: SP → fronteira da Venezuela (Pacaraima) em 1min30–2min andando.
// O cliente anda a 5,3 u/s e corre a 12,19 u/s (client/scripts/game_config.gd). Em linha
// reta; o tempo real medido no cliente (com desvios) está no README.
func TestScaleSaoPauloToPacaraima(t *testing.T) {
	w := testWorld(t)
	a, b := LatLonToVec(-23.55, -46.63), LatLonToVec(4.5, -61.1)
	dist := math.Acos(a.Dot(b)) * w.Radius
	const walk, run = 5.3, 5.3 * 2.3
	t.Logf("SP → Pacaraima: %.0f unidades; %.0f s andando, %.0f s correndo", dist, dist/walk, dist/run)
	if dist/walk < 90 || dist/walk > 120 || dist/run >= 60 {
		t.Errorf("escala fora da meta: %.0f unidades", dist)
	}
	// Largura de um hexágono: distância entre centros vizinhos.
	c := w.CellAt(-23.55, -46.63)
	nb := w.Cells[c.Neighbors[0]]
	width := math.Acos(Vec3{c.Center[0], c.Center[1], c.Center[2]}.Dot(Vec3{nb.Center[0], nb.Center[1], nb.Center[2]})) * w.Radius
	t.Logf("largura de um hexágono: %.1f unidades", width)
	if width < 20 || width > 26 {
		t.Errorf("hexágono com %.1f unidades de largura", width)
	}
}

func TestWorldDeterministic(t *testing.T) {
	a := testWorld(t)
	b, err := New(DefaultConfig, testGeography(t))
	if err != nil {
		t.Fatal(err)
	}
	sa, _ := a.Snapshot()
	sb, _ := b.Snapshot()
	if !bytes.Equal(sa.JSON, sb.JSON) || !bytes.Equal(sa.Binary, sb.Binary) || a.Version != b.Version {
		t.Fatal("duas gerações do mundo deram resultados diferentes")
	}
}

func TestBinaryRoundTrip(t *testing.T) {
	w := testWorld(t)
	bin, err := w.MarshalBinary()
	if err != nil {
		t.Fatal(err)
	}
	freq, radius, cells, countries, err := UnmarshalBinaryCells(bin)
	if err != nil {
		t.Fatal(err)
	}
	if freq != w.Frequency || float64(radius) != w.Radius || len(cells) != len(w.Cells) || len(countries) != len(w.Countries) {
		t.Fatalf("cabeçalho errado: %d %v %d %d", freq, radius, len(cells), len(countries))
	}
	for i, c := range cells {
		o := w.Cells[i]
		if c.Biome != o.Biome || c.Country != o.Country || math.Abs(float64(c.Height)-o.Height) > 1e-6 ||
			len(c.Neighbors) != len(o.Neighbors) || math.Abs(float64(c.Center[1])-o.Center[1]) > 1e-6 {
			t.Fatalf("célula %d diferente depois de ida e volta", i)
		}
		for k := range c.Neighbors {
			if c.Neighbors[k] != o.Neighbors[k] {
				t.Fatalf("célula %d: vizinho %d diferente", i, k)
			}
		}
	}
}

// O cliente calcula os cantos a partir dos centros e vizinhos; confere que bate com o servidor.
func TestCornersFromNeighbors(t *testing.T) {
	w := testWorld(t)
	for _, c := range w.Cells[:2000] {
		n := len(c.Neighbors)
		for k := 0; k < n; k++ {
			p := w.Cells[c.Neighbors[(k+n-1)%n]].Center
			q := w.Cells[c.Neighbors[k]].Center
			v := Vec3{c.Center[0] + p[0] + q[0], c.Center[1] + p[1] + q[1], c.Center[2] + p[2] + q[2]}.Normalize()
			want := c.Vertices[k]
			if math.Abs(v.X-want[0]) > 1e-5 || math.Abs(v.Y-want[1]) > 1e-5 || math.Abs(v.Z-want[2]) > 1e-5 {
				t.Fatalf("célula %d, canto %d: calculado %v, servidor %v", c.ID, k, v, want)
			}
		}
	}
}

func TestSnapshotGzip(t *testing.T) {
	s, err := testWorld(t).Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	for _, pair := range [][2][]byte{{s.JSON, s.JSONGzip}, {s.Binary, s.BinaryGzip}} {
		zr, err := gzip.NewReader(bytes.NewReader(pair[1]))
		if err != nil {
			t.Fatal(err)
		}
		raw, _ := io.ReadAll(zr)
		if !bytes.Equal(raw, pair[0]) {
			t.Fatal("gzip não corresponde ao original")
		}
	}
	t.Logf("binário: %d KB (gzip %d KB); JSON: %d KB (gzip %d KB)",
		len(s.Binary)/1024, len(s.BinaryGzip)/1024, len(s.JSON)/1024, len(s.JSONGzip)/1024)
}

func TestNewRejectsInvalidConfig(t *testing.T) {
	g := testGeography(t)
	if _, err := New(Config{Frequency: 0, Radius: 100}, g); err == nil {
		t.Error("frequência 0 deveria falhar")
	}
	if _, err := New(Config{Frequency: 4, Radius: 0}, g); err == nil {
		t.Error("raio 0 deveria falhar")
	}
}

func TestNoiseDeterministicAndBounded(t *testing.T) {
	for i := 0; i < 1000; i++ {
		p := Vec3{float64(i) * 0.37, float64(i) * -0.11, float64(i) * 0.73}
		v := noise3(p)
		if v < 0 || v > 1 || v != noise3(p) {
			t.Fatalf("ruído inválido em %v: %v", p, v)
		}
	}
}
