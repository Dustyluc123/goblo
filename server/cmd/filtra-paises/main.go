// Comando filtra-paises reduz o ne_50m_admin_0_countries do Natural Earth ao que o servidor
// usa: só as propriedades CODE (ISO A3, com a regra do "-99"), A2 e NAME (em português) e
// coordenadas com 4 casas (~11 m). Países que repetem o código (a Austrália e as ilhas
// Ashmore e Cartier, por exemplo) viram um só. Também tira as capitais da camada de
// lugares povoados (ne_50m_populated_places_simple) e grava capitais.json.
//
// Uso: go run ./cmd/filtra-paises PAISES.geojson LUGARES.geojson SAIDA_PAISES.geojson SAIDA_CAPITAIS.json
package main

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"sort"

	"github.com/paulmach/orb"
	"github.com/paulmach/orb/geojson"
	"github.com/paulmach/orb/planar"
)

type country struct {
	code, a2, name, adm0 string
	geom                 orb.MultiPolygon
	area                 float64 // da maior parte, para escolher o nome quando o código repete
}

// Capital é uma entrada de capitais.json.
type Capital struct {
	Name string  `json:"name"`
	Lat  float64 `json:"lat"`
	Lon  float64 `json:"lon"`
}

func main() {
	if len(os.Args) != 5 {
		fmt.Fprintln(os.Stderr, "uso: filtra-paises PAISES.geojson LUGARES.geojson SAIDA_PAISES.geojson SAIDA_CAPITAIS.json")
		os.Exit(2)
	}
	fc := read(os.Args[1])
	byCode := map[string]*country{}
	adm0ToCode := map[string]string{}
	var order []string
	for _, f := range fc.Features {
		p := f.Properties
		code := pick(p, "ISO_A3", "ISO_A3_EH", "ADM0_A3")
		if code == "" {
			fmt.Fprintf(os.Stderr, "país sem código: %v\n", p["NAME"])
			os.Exit(1)
		}
		adm0ToCode[p.MustString("ADM0_A3", "")] = code
		var mp orb.MultiPolygon
		switch g := f.Geometry.(type) {
		case orb.Polygon:
			mp = orb.MultiPolygon{g}
		case orb.MultiPolygon:
			mp = g
		default:
			continue
		}
		mp = roundMulti(mp)
		area := 0.0
		for _, poly := range mp {
			area = math.Max(area, math.Abs(planar.Area(poly)))
		}
		name := p.MustString("NAME_PT", "")
		if name == "" {
			name = p.MustString("NAME", code)
		}
		c := byCode[code]
		if c == nil {
			c = &country{code: code}
			byCode[code] = c
			order = append(order, code)
		}
		c.geom = append(c.geom, mp...)
		if area > c.area {
			c.area, c.name, c.adm0 = area, name, p.MustString("ADM0_A3", "")
			c.a2 = pick(p, "ISO_A2", "ISO_A2_EH", "WB_A2")
		}
	}
	sort.Strings(order)
	out := geojson.NewFeatureCollection()
	for _, code := range order {
		c := byCode[code]
		nf := geojson.NewFeature(c.geom)
		nf.Properties = geojson.Properties{"CODE": c.code, "A2": c.a2, "NAME": c.name}
		out.Append(nf)
	}
	data, err := out.MarshalJSON()
	check(err)
	check(os.WriteFile(os.Args[3], data, 0o644))
	fmt.Printf("%d países, %d KB\n", len(out.Features), len(data)/1024)

	// Capitais: "Admin-0 capital" primeiro (a "alt" só se não houver), depois a mais populosa.
	// Países sem capital na lista ficam com a maior cidade; sem nenhuma, o servidor usa o
	// centro do maior pedaço do país.
	places := read(os.Args[2])
	type cand struct {
		Capital
		rank int
		pop  float64
	}
	best := map[string]cand{}
	for _, f := range places.Features {
		p := f.Properties
		// Sem capital na lista (territórios, alguns países novos): fica a cidade mais populosa.
		rank := map[string]int{"Admin-0 capital": 2, "Admin-0 capital alt": 1}[p.MustString("featurecla", "")]
		code := adm0ToCode[p.MustString("adm0_a3", "")]
		if code == "" {
			continue
		}
		pt, ok := f.Geometry.(orb.Point)
		if !ok {
			continue
		}
		c := cand{Capital{p.MustString("name", ""), round4(pt[1]), round4(pt[0])}, rank, p.MustFloat64("pop_max", 0)}
		if b, ok := best[code]; !ok || c.rank > b.rank || (c.rank == b.rank && c.pop > b.pop) {
			best[code] = c
		}
	}
	caps := map[string]Capital{}
	for code, c := range best {
		caps[code] = c.Capital
	}
	capData, err := json.MarshalIndent(caps, "", " ")
	check(err)
	check(os.WriteFile(os.Args[4], capData, 0o644))
	fmt.Printf("%d capitais\n", len(caps))
}

func read(path string) *geojson.FeatureCollection {
	raw, err := os.ReadFile(path)
	check(err)
	fc, err := geojson.UnmarshalFeatureCollection(raw)
	check(err)
	return fc
}

// pick devolve a primeira propriedade que não é "-99" (o Natural Earth usa "-99" em alguns
// países, como França e Noruega).
func pick(p geojson.Properties, keys ...string) string {
	for _, k := range keys {
		if v := p.MustString(k, ""); v != "" && v != "-99" {
			return v
		}
	}
	return ""
}

func round4(x float64) float64 { return math.Round(x*1e4) / 1e4 }

func roundMulti(mp orb.MultiPolygon) orb.MultiPolygon {
	out := make(orb.MultiPolygon, 0, len(mp))
	for _, poly := range mp {
		np := make(orb.Polygon, 0, len(poly))
		for _, ring := range poly {
			r := make(orb.Ring, 0, len(ring))
			for _, p := range ring {
				q := orb.Point{round4(p[0]), round4(p[1])}
				if len(r) == 0 || r[len(r)-1] != q {
					r = append(r, q)
				}
			}
			if len(r) >= 4 {
				np = append(np, r)
			}
		}
		if len(np) > 0 {
			out = append(out, np)
		}
	}
	return out
}

func check(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
