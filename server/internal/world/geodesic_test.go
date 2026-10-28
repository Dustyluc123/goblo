package world

import (
	"math"
	"reflect"
	"testing"
)

func TestGridCellCount(t *testing.T) {
	for _, n := range []int{1, 2, 5, 20, 33} {
		g, err := NewGrid(n)
		if err != nil {
			t.Fatalf("n=%d: %v", n, err)
		}
		if got, want := len(g.Centers), 10*n*n+2; got != want {
			t.Errorf("n=%d: %d células, esperado %d", n, got, want)
		}
	}
}

func TestGridRejectsInvalidFrequency(t *testing.T) {
	if _, err := NewGrid(0); err == nil {
		t.Fatal("frequência 0 deveria falhar")
	}
}

func TestGridTwelvePentagons(t *testing.T) {
	g := mustGrid(t, 20)
	pentagons := 0
	for i, nb := range g.Neighbors {
		switch len(nb) {
		case 5:
			pentagons++
		case 6:
		default:
			t.Fatalf("célula %d tem %d vizinhos", i, len(nb))
		}
		if len(g.Vertices[i]) != len(nb) {
			t.Fatalf("célula %d: %d vértices e %d vizinhos", i, len(g.Vertices[i]), len(nb))
		}
	}
	if pentagons != 12 {
		t.Errorf("%d pentágonos, esperado 12", pentagons)
	}
}

func TestGridNeighborsSymmetric(t *testing.T) {
	g := mustGrid(t, 20)
	for a, nb := range g.Neighbors {
		seen := map[int]bool{}
		for _, b := range nb {
			if b == a || seen[b] {
				t.Fatalf("célula %d: vizinho %d repetido ou ela mesma", a, b)
			}
			seen[b] = true
			if !contains(g.Neighbors[b], a) {
				t.Fatalf("%d é vizinho de %d, mas não o contrário", b, a)
			}
		}
	}
}

// Neighbors[i][k] precisa estar do outro lado da aresta Vertices[i][k] → Vertices[i][k+1]:
// os dois cantos dessa aresta também são cantos do vizinho.
func TestGridNeighborMatchesEdge(t *testing.T) {
	g := mustGrid(t, 8)
	for i := range g.Centers {
		vs := g.Vertices[i]
		for k, nb := range g.Neighbors[i] {
			a, b := vs[k], vs[(k+1)%len(vs)]
			if !hasVertex(g.Vertices[nb], a) || !hasVertex(g.Vertices[nb], b) {
				t.Fatalf("célula %d, aresta %d: vizinho %d não compartilha a aresta", i, k, nb)
			}
		}
	}
}

// Cantos em sentido anti-horário visto de fora: a normal do polígono aponta para fora.
func TestGridVerticesCounterClockwise(t *testing.T) {
	g := mustGrid(t, 8)
	for i, c := range g.Centers {
		vs := g.Vertices[i]
		for k := range vs {
			n := vs[k].Sub(c).Cross(vs[(k+1)%len(vs)].Sub(c))
			if n.Dot(c) <= 0 {
				t.Fatalf("célula %d: cantos fora de ordem na aresta %d", i, k)
			}
		}
	}
}

func TestGridUnitVectors(t *testing.T) {
	g := mustGrid(t, 8)
	for i, c := range g.Centers {
		if math.Abs(c.Len()-1) > 1e-9 {
			t.Fatalf("centro %d não é unitário: %v", i, c.Len())
		}
		for _, v := range g.Vertices[i] {
			if math.Abs(v.Len()-1) > 1e-9 {
				t.Fatalf("canto da célula %d não é unitário", i)
			}
		}
	}
}

func TestGridDeterministic(t *testing.T) {
	a, b := mustGrid(t, 20), mustGrid(t, 20)
	if !reflect.DeepEqual(a, b) {
		t.Fatal("duas gerações com a mesma frequência deram grades diferentes")
	}
}

func TestLatLonRoundTrip(t *testing.T) {
	for _, p := range [][2]float64{{0, 0}, {-23.55, -46.63}, {45, 170}, {-60, -179}, {89, 10}} {
		lat, lon := VecToLatLon(LatLonToVec(p[0], p[1]))
		if math.Abs(lat-p[0]) > 1e-9 || math.Abs(lon-p[1]) > 1e-9 {
			t.Errorf("%v virou (%v, %v)", p, lat, lon)
		}
	}
	if v := LatLonToVec(0, 90); math.Abs(v.X-1) > 1e-9 {
		t.Errorf("(0, 90°L) deveria ficar em +X, ficou em %v", v)
	}
	if v := LatLonToVec(90, 0); math.Abs(v.Y-1) > 1e-9 {
		t.Errorf("polo norte deveria ficar em +Y, ficou em %v", v)
	}
}

func mustGrid(t *testing.T, n int) *Grid {
	t.Helper()
	g, err := NewGrid(n)
	if err != nil {
		t.Fatal(err)
	}
	return g
}

func contains(xs []int, x int) bool {
	for _, y := range xs {
		if y == x {
			return true
		}
	}
	return false
}

func hasVertex(vs []Vec3, p Vec3) bool {
	for _, v := range vs {
		if v.Sub(p).Len() < 1e-9 {
			return true
		}
	}
	return false
}
