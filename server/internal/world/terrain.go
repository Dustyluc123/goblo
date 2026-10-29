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
	countriesFile = "naturalearth/ne_110m_admin_0_countries.geojson"
)

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

// Geography responde se um ponto (lat/lon) é terra e a qual país pertence.
type Geography struct {
	land      []shape
	regions   []region
	Countries []Country
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
	for _, f := range countries {
		s, ok := toShape(f.Geometry)
		if !ok {
			continue
		}
		code := countryCode(f.Properties)
		if code == "" {
			return nil, fmt.Errorf("%s: país sem código (%v)", countriesFile, f.Properties["NAME"])
		}
		name := f.Properties.MustString("NAME_PT", "")
		if name == "" {
			name = f.Properties.MustString("NAME", code)
		}
		g.Countries = append(g.Countries, Country{Code: code, A2: countryA2(f.Properties), Name: name, shape: s})
	}
	if g.regions, err = loadRegions(fsys); err != nil {
		return nil, err
	}
	if len(g.land) == 0 || len(g.Countries) == 0 || len(g.regions) == 0 {
		return nil, fmt.Errorf("dados geográficos vazios")
	}
	return g, nil
}

// countryCode escolhe o código ISO A3. O Natural Earth usa "-99" em alguns países
// (França e Noruega, por exemplo); nesse caso tenta ISO_A3_EH e depois ADM0_A3.
func countryCode(p geojson.Properties) string {
	for _, k := range []string{"ISO_A3", "ISO_A3_EH", "ADM0_A3"} {
		if v := p.MustString(k, ""); v != "" && v != "-99" {
			return v
		}
	}
	return ""
}

// countryA2 escolhe o código ISO A2, com a mesma regra do "-99" de countryCode.
func countryA2(p geojson.Properties) string {
	for _, k := range []string{"ISO_A2", "ISO_A2_EH", "WB_A2"} {
		if v := p.MustString(k, ""); v != "" && v != "-99" {
			return v
		}
	}
	return ""
}

// Classify diz se o ponto é terra e, se for, o código do país ("" no oceano ou em terra
// fora de qualquer país, o que é raro na escala 1:110m).
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
	for _, c := range g.Countries {
		if c.contains(p) {
			return Land, c.Code
		}
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
