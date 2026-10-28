package world

import (
	"io/fs"

	"github.com/paulmach/orb"
)

const regionsFile = "naturalearth/regioes.geojson"

// regionKind é o que uma região do Natural Earth diz sobre o bioma.
type regionKind uint8

const (
	regionNone regionKind = iota
	regionMountain
	regionHills
	regionDesert
	regionTundra
	regionTropical
	regionGrassland
)

type region struct {
	name string
	kind regionKind
	shape
}

// Exceções por nome às regras por classe (veja docs/BIOMAS.md).
var regionByName = map[string]regionKind{
	// Planaltos altos contam como montanha.
	"PLATEAU OF TIBET": regionMountain,
	"ALTIPLANO":        regionMountain,
	// Florestas tropicais.
	"AMAZON BASIN":  regionTropical,
	"CONGO BASIN":   regionTropical,
	"GUIANA SHIELD": regionTropical,
	"SELVAS":        regionTropical,
	"YUNGAS":        regionTropical,
	// Campos, savanas e cerrado.
	"BRAZILIAN HIGHLANDS":     regionGrassland,
	"PLANALTO CENTRAL":        regionGrassland,
	"PLANALTO DO MATO GROSSO": regionGrassland,
	"Campos Sertão":           regionGrassland,
	"MONGOLIAN PLATEAU":       regionGrassland,
	"KAZAKH UPLAND":           regionGrassland,
	"DECCAN PLATEAU":          regionGrassland,
	"Bié Plateau":             regionGrassland,
	"KATANGA PLATEAU":         regionGrassland,
	"ALTI-PLANICIE MEXICANA":  regionGrassland,
	"Edwards Plateau":         regionGrassland,
	"GREAT ARTESIAN BASIN":    regionGrassland,
	"MURRAY-DARLING BASIN":    regionGrassland,
	"CAATINGAS":               regionGrassland, // semiárido, mas não deserto
	"PUNJAB":                  regionGrassland,
	// Desertos que o Natural Earth chama de planalto, bacia ou península.
	"WESTERN PLATEAU":   regionDesert, // centro da Austrália
	"ARABIAN PENINSULA": regionDesert,
	"GREAT BASIN":       regionDesert,
	"TARIM BASIN":       regionDesert,
	"Junggar Basin":     regionDesert,
	"Qaidam Basin":      regionDesert,
	"COLORADO PLATEAU":  regionDesert,
	"Ustyurt Plateau":   regionDesert,
	// O Escudo Canadense vai até 50° N: é floresta boreal, não tundra.
	"CANADIAN SHIELD": regionNone,
}

// Planícies que são campos/estepes (as outras ficam com a regra de latitude).
var grasslandPlains = map[string]bool{
	"GREAT PLAINS": true, "CENTRAL LOWLAND": true, "PAMPAS": true, "KAZAKH STEPPE": true,
	"PONTIC STEPPE": true, "SAHEL": true, "LLANOS": true, "GRAN CHACO": true,
	"CHACO AUSTRAL": true, "CHACO BOREAL": true, "Iwembere Steppe": true,
	"NULLARBOR PLAIN": true, "TURAN LOWLAND": true,
}

func classifyRegion(class, name string, rank int) regionKind {
	if k, ok := regionByName[name]; ok {
		return k
	}
	switch class {
	case "Range/mtn":
		if rank <= 3 {
			return regionMountain
		}
		return regionHills
	case "Foothills":
		return regionHills
	case "Desert":
		return regionDesert
	case "Tundra":
		return regionTundra
	case "Plain":
		if grasslandPlains[name] {
			return regionGrassland
		}
	}
	return regionNone
}

func loadRegions(fsys fs.FS) ([]region, error) {
	features, err := readFeatures(fsys, regionsFile)
	if err != nil {
		return nil, err
	}
	var out []region
	for _, f := range features {
		s, ok := toShape(f.Geometry)
		if !ok {
			continue
		}
		name := f.Properties.MustString("NAME", "")
		kind := classifyRegion(f.Properties.MustString("FEATURECLA", ""), name, f.Properties.MustInt("SCALERANK", 9))
		if kind != regionNone {
			out = append(out, region{name: name, kind: kind, shape: s})
		}
	}
	return out, nil
}

// regionHits diz em quais tipos de região um ponto cai.
type regionHits [regionGrassland + 1]bool

func (g *Geography) regionsAt(lat, lon float64) regionHits {
	var h regionHits
	p := orb.Point{lon, lat}
	for _, r := range g.regions {
		if !h[r.kind] && r.contains(p) {
			h[r.kind] = true
		}
	}
	for _, r := range handRegions {
		if !h[r.kind] && r.contains(p) {
			h[r.kind] = true
		}
	}
	return h
}

// handRegions são polígonos aproximados, desenhados à mão (lon, lat), para regiões
// que o Natural Earth não traz como polígono. Precisão de centenas de km: só para o
// bioma ficar reconhecível.
var handRegions = func() []region {
	mk := func(name string, kind regionKind, pts ...float64) region {
		ring := make(orb.Ring, 0, len(pts)/2+1)
		for i := 0; i+1 < len(pts); i += 2 {
			ring = append(ring, orb.Point{pts[i], pts[i+1]})
		}
		ring = append(ring, ring[0])
		mp := orb.MultiPolygon{orb.Polygon{ring}}
		return region{name: name, kind: kind, shape: shape{geom: mp, bound: mp.Bound()}}
	}
	return []region{
		mk("Mata Atlântica", regionTropical,
			-35, -5, -34.5, -8, -37.5, -13, -39, -18, -40.5, -22, -43.5, -23.3, -47.5, -25.5,
			-48.5, -28.5, -50.5, -30, -53, -28, -51, -25, -48, -23, -46, -21.5, -43, -19.5,
			-41, -16, -39.5, -12, -37, -8),
		mk("Sudeste Asiático", regionTropical,
			92, 21, 100, 21, 110, 22, 122, 19, 128, 10, 155, 0, 155, -11, 105, -11, 94, 5),
		mk("América Central", regionTropical,
			-92.5, 18.5, -86, 21.5, -82, 14, -77, 9, -79, 7, -86, 10, -92.5, 14),
		mk("Floresta da África Ocidental", regionTropical,
			-13, 11, -5, 9, 10, 7, 18, 6, 18, -6, 8, -2, -8, 4, -15, 9),
		mk("Savana da África Oriental", regionGrassland,
			29.5, 12, 52, 12, 52, -2, 41, -12, 29.5, -12),
		mk("Savana do Norte da Austrália", regionGrassland,
			113, -12, 145, -10, 146, -19, 135, -21, 113, -21),
	}
}()
