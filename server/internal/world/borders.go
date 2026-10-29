package world

import (
	"math"
	"sort"
	"sync"

	"github.com/paulmach/orb"
)

// Fronteiras pela posição exata (ADR 0031).
//
// Os países vêm do Natural Earth 1:50m (paises.geojson, gerado por cmd/filtra-paises). Cada
// anel de cada país vira uma lista de segmentos orientados de modo que o país fica sempre
// à ESQUERDA do segmento (anel externo no sentido anti-horário, buracos no horário). Os
// segmentos ficam num índice de quadrados de 1° × 1°, para achar rápido os que passam perto
// de um ponto ou de uma célula.
//
// O país de um ponto (CountryAt) é decidido por ponto em polígono. O cliente recebe, por
// célula, só os segmentos que passam nela (CellBorders) e decide o país pelo segmento mais
// perto: está à esquerda dele → é aquele país. Fronteiras compartilhadas aparecem duas vezes
// (uma por país, em sentidos opostos); "Shared" marca as que não são costa, as únicas que
// viram linha desenhada no chão.

// BorderSeg é um pedaço de fronteira: de A para B (lon, lat), com o país à esquerda.
type BorderSeg struct {
	A, B    orb.Point
	Country int  // índice em Geography.Countries
	Shared  bool // separa dois países (não é costa)
}

// CellBorder diz o que o cliente precisa para saber o país em qualquer ponto de uma célula:
// ou a célula inteira é de um país só (Country), ou a lista de segmentos que passam perto.
type CellBorder struct {
	Country string      // célula inteira num país só ("" = fora de qualquer país)
	Segs    []BorderSeg // vazio quando a célula é de um país só
}

// Margem em volta da célula (graus) para os segmentos: o cliente acha o segmento mais perto
// sem depender das células vizinhas.
const cellBorderMargin = 0.35

type borderIndex struct {
	segs    []BorderSeg
	buckets map[int][]int32

	mu    sync.Mutex
	cells map[int]*CellBorder
}

func bucketKey(lonCell, latCell int) int {
	lonCell = ((lonCell+180)%360+360)%360 - 180
	return (latCell+90)*360 + (lonCell + 180)
}

func newBorderIndex(countries []Country) *borderIndex {
	b := &borderIndex{buckets: map[int][]int32{}, cells: map[int]*CellBorder{}}
	type edge struct{ a, b orb.Point }
	seen := map[edge]int{} // segmento → índice (para achar o mesmo segmento no outro sentido)
	for ci, c := range countries {
		for _, poly := range c.geom {
			for ri, ring := range poly {
				ccw := ringArea(ring) > 0
				reverse := (ri == 0) != ccw // externo anti-horário, buracos horário
				n := len(ring)
				for k := 0; k+1 < n; k++ {
					a, p := ring[k], ring[k+1]
					if reverse {
						a, p = ring[n-1-k], ring[n-2-k]
					}
					if a == p {
						continue
					}
					seg := BorderSeg{A: a, B: p, Country: ci}
					if j, ok := seen[edge{p, a}]; ok && b.segs[j].Country != ci {
						seg.Shared = true
						b.segs[j].Shared = true
					}
					seen[edge{a, p}] = len(b.segs)
					b.add(seg)
				}
			}
		}
	}
	return b
}

func (b *borderIndex) add(s BorderSeg) {
	idx := int32(len(b.segs))
	b.segs = append(b.segs, s)
	x0, x1 := math.Floor(math.Min(s.A[0], s.B[0])), math.Floor(math.Max(s.A[0], s.B[0]))
	y0, y1 := math.Floor(math.Min(s.A[1], s.B[1])), math.Floor(math.Max(s.A[1], s.B[1]))
	for y := int(y0); y <= int(y1); y++ {
		for x := int(x0); x <= int(x1); x++ {
			k := bucketKey(x, y)
			b.buckets[k] = append(b.buckets[k], idx)
		}
	}
}

func ringArea(r orb.Ring) float64 {
	a := 0.0
	for k := 0; k+1 < len(r); k++ {
		a += r[k][0]*r[k+1][1] - r[k+1][0]*r[k][1]
	}
	return a / 2
}

// near devolve os segmentos com algum pedaço no retângulo [lon0, lon1] × [lat0, lat1]
// (lon pode passar de ±180: o índice dá a volta).
func (b *borderIndex) near(lon0, lat0, lon1, lat1 float64) []int32 {
	var out []int32
	seen := map[int32]bool{}
	for y := int(math.Floor(lat0)); y <= int(math.Floor(lat1)); y++ {
		if y < -90 || y > 89 {
			continue
		}
		for x := int(math.Floor(lon0)); x <= int(math.Floor(lon1)); x++ {
			for _, i := range b.buckets[bucketKey(x, y)] {
				if !seen[i] {
					seen[i] = true
					out = append(out, i)
				}
			}
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i] < out[j] })
	return out
}

// local projeta (lon, lat) num plano em volta de (lon0, lat0), em graus de latitude: o
// leste é encolhido por cos(lat0) e a longitude dá a volta em ±180.
func local(p orb.Point, lon0, lat0 float64) (float64, float64) {
	dl := p[0] - lon0
	for dl > 180 {
		dl -= 360
	}
	for dl < -180 {
		dl += 360
	}
	return dl * math.Cos(lat0*math.Pi/180), p[1] - lat0
}

// segDist é a distância (graus) do ponto (0, 0) ao segmento a→b e o lado: > 0 se o ponto
// está à esquerda.
func segDist(ax, ay, bx, by float64) (dist, side float64) {
	ex, ey := bx-ax, by-ay
	l2 := ex*ex + ey*ey
	t := 0.0
	if l2 > 0 {
		t = math.Max(0, math.Min(1, -(ax*ex+ay*ey)/l2))
	}
	cx, cy := ax+ex*t, ay+ey*t
	return math.Hypot(cx, cy), ex*(-ay) - ey*(-ax)
}

// nearestCountry é o país do segmento mais perto do ponto (até maxDeg graus), sem olhar o
// lado: serve para pôr num país as células que o 1:110m chama de terra e o 1:50m de mar.
func (b *borderIndex) nearestCountry(lat, lon, maxDeg float64) int {
	pad := maxDeg / math.Max(0.2, math.Cos(lat*math.Pi/180))
	best, bestD := -1, maxDeg
	for _, i := range b.near(lon-pad, lat-maxDeg, lon+pad, lat+maxDeg) {
		s := b.segs[i]
		ax, ay := local(s.A, lon, lat)
		bx, by := local(s.B, lon, lat)
		if d, _ := segDist(ax, ay, bx, by); d < bestD {
			best, bestD = s.Country, d
		}
	}
	return best
}

// CountryAt é o país (código) que contém o ponto exato, pelo 1:50m. "" no mar ou fora de
// qualquer país.
func (g *Geography) CountryAt(lat, lon float64) string {
	p := orb.Point{lon, lat}
	for _, c := range g.Countries {
		if c.contains(p) {
			return c.Code
		}
	}
	return ""
}

// CountryIndex devolve a posição do país em Countries.
func (g *Geography) CountryIndex(code string) (int, bool) {
	i, ok := g.byCode[code]
	return i, ok
}

// CountryName devolve o nome do país pelo código ("" se não existe).
func (g *Geography) CountryName(code string) string {
	if i, ok := g.byCode[code]; ok {
		return g.Countries[i].Name
	}
	return ""
}

// CellBorders devolve o que passa pela célula (calculado na primeira vez e guardado).
func (g *Geography) CellBorders(w *World, cell int) *CellBorder {
	b := g.borders
	b.mu.Lock()
	cb := b.cells[cell]
	b.mu.Unlock()
	if cb != nil {
		return cb
	}
	cb = g.cellBorders(w, cell)
	b.mu.Lock()
	b.cells[cell] = cb
	b.mu.Unlock()
	return cb
}

func (g *Geography) cellBorders(w *World, cell int) *CellBorder {
	c := &w.Cells[cell]
	lon0, lat0 := c.Lon, c.Lat
	minX, minY, maxX, maxY := math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
	for _, v := range c.Vertices {
		lat, lon := VecToLatLon(Vec3{v[0], v[1], v[2]})
		dl := lon - lon0
		for dl > 180 {
			dl -= 360
		}
		for dl < -180 {
			dl += 360
		}
		minX, maxX = math.Min(minX, lon0+dl), math.Max(maxX, lon0+dl)
		minY, maxY = math.Min(minY, lat), math.Max(maxY, lat)
	}
	pad := cellBorderMargin / math.Max(0.1, math.Cos(lat0*math.Pi/180))
	if math.Abs(lat0) > 80 { // perto do polo: a célula dá a volta em longitude
		minX, maxX, pad = -180, 180, 0
	}
	minX, maxX = minX-pad, maxX+pad
	minY, maxY = minY-cellBorderMargin, maxY+cellBorderMargin
	out := &CellBorder{}
	for _, i := range g.borders.near(minX, minY, maxX, maxY) {
		s := g.borders.segs[i]
		if segTouchesBox(s, minX, minY, maxX, maxY) {
			out.Segs = append(out.Segs, s)
		}
	}
	if len(out.Segs) == 0 {
		out.Country = g.CountryAt(lat0, lon0)
	}
	return out
}

// segTouchesBox confere (por amostras, o que basta para segmentos curtos e para os longos
// retos do 1:50m) se o segmento passa pelo retângulo, já com a longitude desembrulhada.
func segTouchesBox(s BorderSeg, minX, minY, maxX, maxY float64) bool {
	center := (minX + maxX) / 2
	unwrap := func(lon float64) float64 {
		for lon-center > 180 {
			lon -= 360
		}
		for lon-center < -180 {
			lon += 360
		}
		return lon
	}
	ax, bx := unwrap(s.A[0]), unwrap(s.B[0])
	if math.Max(ax, bx) < minX || math.Min(ax, bx) > maxX || math.Max(s.A[1], s.B[1]) < minY || math.Min(s.A[1], s.B[1]) > maxY {
		return false
	}
	steps := int(math.Max(math.Abs(bx-ax), math.Abs(s.B[1]-s.A[1]))/0.1) + 1
	for k := 0; k <= steps; k++ {
		t := float64(k) / float64(steps)
		x, y := ax+(bx-ax)*t, s.A[1]+(s.B[1]-s.A[1])*t
		if x >= minX && x <= maxX && y >= minY && y <= maxY {
			return true
		}
	}
	return false
}

// CountryByNearestSegment é a regra que o cliente usa (o país do segmento mais perto, se o
// ponto estiver à esquerda dele). Fica aqui para os testes garantirem que ela concorda com
// o ponto em polígono. Devolve "" se o ponto não está em país nenhum.
func (cb *CellBorder) CountryByNearestSegment(countries []Country, lat, lon float64) string {
	if len(cb.Segs) == 0 {
		return cb.Country
	}
	const tie = 1e-7
	bestD := math.Inf(1)
	for _, s := range cb.Segs {
		ax, ay := local(s.A, lon, lat)
		bx, by := local(s.B, lon, lat)
		if d, _ := segDist(ax, ay, bx, by); d < bestD {
			bestD = d
		}
	}
	// Entre os segmentos empatados (fronteira compartilhada aparece duas vezes, e num canto
	// dois segmentos do mesmo anel empatam), vale o primeiro em que o ponto está à esquerda.
	// No canto, a regra é: ponto à esquerda do segmento mais "virado" para ele.
	best, bestScore := "", math.Inf(-1)
	for _, s := range cb.Segs {
		ax, ay := local(s.A, lon, lat)
		bx, by := local(s.B, lon, lat)
		d, side := segDist(ax, ay, bx, by)
		if d > bestD+tie {
			continue
		}
		l := math.Hypot(bx-ax, by-ay)
		if l == 0 {
			continue
		}
		score := side / l
		if score > bestScore {
			bestScore = score
			if side > 0 {
				best = countries[s.Country].Code
			} else {
				best = ""
			}
		}
	}
	return best
}
