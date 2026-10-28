// Comando filtra-regioes reduz o ne_50m_geography_regions_polys do Natural Earth ao que
// a classificação de biomas usa: só algumas classes (desertos, cordilheiras, planícies…),
// só as propriedades NAME, FEATURECLA e SCALERANK e coordenadas com 2 casas (~1 km).
//
// Uso: go run ./cmd/filtra-regioes ENTRADA.geojson SAIDA.geojson
package main

import (
	"fmt"
	"math"
	"os"

	"github.com/paulmach/orb"
	"github.com/paulmach/orb/geojson"
)

var keep = map[string]bool{
	"Desert": true, "Range/mtn": true, "Tundra": true, "Plateau": true,
	"Plain": true, "Basin": true, "Foothills": true, "Pen/cape": true,
}

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "uso: filtra-regioes ENTRADA.geojson SAIDA.geojson")
		os.Exit(2)
	}
	raw, err := os.ReadFile(os.Args[1])
	check(err)
	fc, err := geojson.UnmarshalFeatureCollection(raw)
	check(err)
	out := geojson.NewFeatureCollection()
	for _, f := range fc.Features {
		class := f.Properties.MustString("FEATURECLA", "")
		if !keep[class] {
			continue
		}
		g := roundGeometry(f.Geometry)
		if g == nil {
			continue
		}
		nf := geojson.NewFeature(g)
		nf.Properties = geojson.Properties{
			"NAME":       f.Properties.MustString("NAME", ""),
			"FEATURECLA": class,
			"SCALERANK":  f.Properties.MustInt("SCALERANK", 9),
		}
		out.Append(nf)
	}
	data, err := out.MarshalJSON()
	check(err)
	check(os.WriteFile(os.Args[2], data, 0o644))
	fmt.Printf("%d de %d regiões mantidas, %d KB\n", len(out.Features), len(fc.Features), len(data)/1024)
}

func roundGeometry(g orb.Geometry) orb.Geometry {
	r := func(ring orb.Ring) orb.Ring {
		res := make(orb.Ring, 0, len(ring))
		for _, p := range ring {
			q := orb.Point{math.Round(p[0]*100) / 100, math.Round(p[1]*100) / 100}
			if len(res) == 0 || res[len(res)-1] != q {
				res = append(res, q)
			}
		}
		return res
	}
	poly := func(p orb.Polygon) orb.Polygon {
		res := make(orb.Polygon, 0, len(p))
		for _, ring := range p {
			if rr := r(ring); len(rr) >= 4 {
				res = append(res, rr)
			}
		}
		return res
	}
	switch v := g.(type) {
	case orb.Polygon:
		return poly(v)
	case orb.MultiPolygon:
		var mp orb.MultiPolygon
		for _, p := range v {
			if pp := poly(p); len(pp) > 0 {
				mp = append(mp, pp)
			}
		}
		return mp
	}
	return nil
}

func check(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
