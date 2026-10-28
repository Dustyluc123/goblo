package world

import (
	"bytes"
	"compress/gzip"
	"io"
	"sync"
	"testing"

	"github.com/Dustyluc123/goblo/server/data"
)

var (
	geoOnce sync.Once
	geo     *Geography
	geoErr  error
)

func testGeography(t *testing.T) *Geography {
	t.Helper()
	geoOnce.Do(func() { geo, geoErr = LoadGeography(data.NaturalEarth) })
	if geoErr != nil {
		t.Fatal(geoErr)
	}
	return geo
}

func testWorld(t *testing.T) *World {
	t.Helper()
	w, err := New(DefaultConfig, testGeography(t))
	if err != nil {
		t.Fatal(err)
	}
	return w
}

func TestWorldCellCount(t *testing.T) {
	w := testWorld(t)
	if got, want := len(w.Cells), 4002; got != want {
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
}

func TestWorldMidAtlanticIsOcean(t *testing.T) {
	c := testWorld(t).CellAt(0, -30)
	if c.Terrain != Ocean || c.Country != "" {
		t.Fatalf("meio do Atlântico caiu na célula %d: terreno %q, país %q", c.ID, c.Terrain, c.Country)
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
	if noCountry > 10 {
		t.Errorf("%d células de terra sem país", noCountry)
	}
}

func TestWorldDeterministic(t *testing.T) {
	a, err := testWorld(t).Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	b, err := testWorld(t).Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(a.JSON, b.JSON) || a.ETag != b.ETag {
		t.Fatal("duas gerações do mundo deram JSON diferente")
	}
}

func TestSnapshotGzip(t *testing.T) {
	s, err := testWorld(t).Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	zr, err := gzip.NewReader(bytes.NewReader(s.Gzip))
	if err != nil {
		t.Fatal(err)
	}
	raw, err := io.ReadAll(zr)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(raw, s.JSON) {
		t.Fatal("gzip não corresponde ao JSON")
	}
	t.Logf("JSON: %d KB, gzip: %d KB", len(s.JSON)/1024, len(s.Gzip)/1024)
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
