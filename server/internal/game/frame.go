package game

import (
	"math"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Frame é o sistema de coordenadas plano do topo de uma célula. O topo de cada célula é um
// plano perpendicular ao centro c, a uma distância Top (raio + altura) da origem. Um ponto
// (x, y) desse plano fica em
//
//	P = c·Top + East·x + North·y
//
// com East = normalize(ref × c) e North = c × East, onde ref = (0, 1, 0), ou (0, 0, 1)
// se |c.y| > 0,999 (célula do polo). O cliente usa exatamente a mesma conta
// (WorldData.cell_frame), então objetos e lotes são enviados como (célula, x, y).
type Frame struct {
	Center, East, North world.Vec3
	Top                 float64
	// Poly são os cantos da célula projetados no plano, em sentido anti-horário.
	Poly [][2]float64
}

// CellFrame monta o sistema de coordenadas do topo da célula.
func CellFrame(w *world.World, cell int) Frame {
	c := w.Cells[cell]
	center := world.Vec3{X: c.Center[0], Y: c.Center[1], Z: c.Center[2]}.Normalize()
	ref := world.Vec3{Y: 1}
	if math.Abs(center.Y) > 0.999 {
		ref = world.Vec3{Z: 1}
	}
	east := ref.Cross(center).Normalize()
	north := center.Cross(east)
	f := Frame{Center: center, East: east, North: north, Top: w.Radius + c.Height}
	for _, v := range c.Vertices {
		p := world.Vec3{X: v[0], Y: v[1], Z: v[2]}
		p = p.Scale(f.Top / p.Dot(center))
		f.Poly = append(f.Poly, [2]float64{p.Dot(east), p.Dot(north)})
	}
	return f
}

// Inside diz se (x, y) está dentro do polígono da célula, a pelo menos margin da borda.
func (f *Frame) Inside(x, y, margin float64) bool {
	n := len(f.Poly)
	sign := 1.0
	if polygonArea(f.Poly) < 0 {
		sign = -1
	}
	for k := 0; k < n; k++ {
		a, b := f.Poly[k], f.Poly[(k+1)%n]
		ex, ey := b[0]-a[0], b[1]-a[1]
		l := math.Hypot(ex, ey)
		if l == 0 {
			continue
		}
		if sign*(ex*(y-a[1])-ey*(x-a[0]))/l < margin {
			return false
		}
	}
	return true
}

func polygonArea(p [][2]float64) float64 {
	a := 0.0
	for k := range p {
		b := p[(k+1)%len(p)]
		a += p[k][0]*b[1] - b[0]*p[k][1]
	}
	return a / 2
}
