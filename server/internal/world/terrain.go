package world

import (
	"fmt"
	"io/fs"

	"github.com/paulmach/orb"
	"github.com/paulmach/orb/geojson"
	"github.com/paulmach/orb/planar"
)

// Terrain é o tipo de terreno de uma célula.
type Terrain string

const (
	Land  Terrain = "land"
	Ocean Terrain = "ocean"
)

const (
	landFile      = "naturalearth/ne_110m_land.geojson"
	countriesFile = "naturalearth/paises.geojson" // 1:50m, filtrado por cmd/filtra-paises
)

// Até onde (graus) procurar um país para uma célula que o 1:110m chama de terra e o 1:50m
// deixa fora de qualquer país (costas e ilhas pequenas).
const nearestCountryDeg = 2.0

type shape struct {
	geom  orb.MultiPolygon
	bound orb.Bound
}

func (s shape) contains(p orb.Point) bool {
	return s.bound.Contains(p) && planar.MultiPolygonContains(s.geom, p)
}

// Country é um país do Natural Earth.
type Country struct {
	Code string // ISO A3 (veja countryCode)
	A2   string // ISO A2 (ex.: "BR"), para ligar com bases de IP e o idioma do sistema
	Name string // nome em português
	shape
}

// Geography responde se um ponto (lat/lon) é terra e a qual país pertence. Terra e oceano
// vêm do 1:110m (a forma do globo); países, do 1:50m (veja borders.go e o ADR 0031).
type Geography struct {
	land      []shape
	regions   []region
	Countries []Country
	byCode    map[string]int
	borders   *borderIndex
}

// LoadGeography lê os GeoJSON do Natural Earth de fsys (normalmente data.NaturalEarth).
func LoadGeography(fsys fs.FS) (*Geography, error) {
	g := &Geography{}

	land, err := readFeatures(fsys, landFile)
	if err != nil {
		return nil, err
	}
	for _, f := range land {
		if s, ok := toShape(f.Geometry); ok {
			g.land = append(g.land, s)
		}
	}

	countries, err := readFeatures(fsys, countriesFile)
	if err != nil {
		return nil, err
	}
	g.byCode = map[string]int{}
	for _, f := range countries {
		s, ok := toShape(f.Geometry)
		if !ok {
			continue
		}
		code := f.Properties.MustString("CODE", "")
		if len(code) != 3 {
			return nil, fmt.Errorf("%s: país sem código (%v)", countriesFile, f.Properties["NAME"])
		}
		if _, dup := g.byCode[code]; dup {
			return nil, fmt.Errorf("%s: país %s repetido", countriesFile, code)
		}
		g.byCode[code] = len(g.Countries)
		g.Countries = append(g.Countries, Country{Code: code, A2: f.Properties.MustString("A2", ""),
			Name: f.Properties.MustString("NAME", code), shape: s})
	}
	g.borders = newBorderIndex(g.Countries)
	if g.regions, err = loadRegions(fsys); err != nil {
		return nil, err
	}
	if len(g.land) == 0 || len(g.Countries) == 0 || len(g.regions) == 0 {
		return nil, fmt.Errorf("dados geográficos vazios")
	}
	return g, nil
}

// Classify diz se o ponto é terra (1:110m) e, se for, o código do país (1:50m; se o ponto
// cair fora de qualquer país, o país mais perto até nearestCountryDeg). "" no oceano.
func (g *Geography) Classify(lat, lon float64) (Terrain, string) {
	p := orb.Point{lon, lat}
	isLand := false
	for _, s := range g.land {
		if s.contains(p) {
			isLand = true
			break
		}
	}
	if !isLand {
		return Ocean, ""
	}
	if code := g.CountryAt(lat, lon); code != "" {
		return Land, code
	}
	if i := g.borders.nearestCountry(lat, lon, nearestCountryDeg); i >= 0 {
		return Land, g.Countries[i].Code
	}
	return Land, ""
}

func readFeatures(fsys fs.FS, name string) ([]*geojson.Feature, error) {
	raw, err := fs.ReadFile(fsys, name)
	if err != nil {
		return nil, fmt.Errorf("lendo %s: %w (rode server/scripts/baixar-dados.sh)", name, err)
	}
	fc, err := geojson.UnmarshalFeatureCollection(raw)
	if err != nil {
		return nil, fmt.Errorf("lendo %s: %w", name, err)
	}
	return fc.Features, nil
}

func toShape(g orb.Geometry) (shape, bool) {
	var mp orb.MultiPolygon
	switch geom := g.(type) {
	case orb.Polygon:
		mp = orb.MultiPolygon{geom}
	case orb.MultiPolygon:
		mp = geom
	default:
		return shape{}, false
	}
	return shape{geom: mp, bound: mp.Bound()}, true
}
