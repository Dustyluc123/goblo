package world

import (
	"fmt"
	"math"
	"sort"
)

// Grid é a geometria pura do globo: um poliedro de Goldberg, o dual de um icosaedro
// subdividido com frequência n. Tem 10·n²+2 células: 12 pentágonos (nos vértices do
// icosaedro original) e o resto hexágonos.
//
// Convenções:
//   - Vertices[i] lista os cantos da célula i em sentido anti-horário visto de fora do planeta.
//   - Neighbors[i][k] é a célula do outro lado da aresta Vertices[i][k] → Vertices[i][k+1].
//     Por isso len(Neighbors[i]) == len(Vertices[i]).
//   - Os ids vão de 0 a len(Centers)-1 e só dependem da frequência.
type Grid struct {
	Frequency int
	Centers   []Vec3
	Vertices  [][]Vec3
	Neighbors [][]int
}

// CellCount devolve quantas células uma grade de frequência n tem.
func CellCount(n int) int { return 10*n*n + 2 }

// Icosaedro regular com 12 vértices (±1, ±φ, 0), (0, ±1, ±φ), (±φ, 0, ±1).
var (
	phi         = (1 + math.Sqrt(5)) / 2
	icoVertices = [12]Vec3{
		{-1, phi, 0}, {1, phi, 0}, {-1, -phi, 0}, {1, -phi, 0},
		{0, -1, phi}, {0, 1, phi}, {0, -1, -phi}, {0, 1, -phi},
		{phi, 0, -1}, {phi, 0, 1}, {-phi, 0, -1}, {-phi, 0, 1},
	}
	icoFaces = [20][3]int{
		{0, 11, 5}, {0, 5, 1}, {0, 1, 7}, {0, 7, 10}, {0, 10, 11},
		{1, 5, 9}, {5, 11, 4}, {11, 10, 2}, {10, 7, 6}, {7, 1, 8},
		{3, 9, 4}, {3, 4, 2}, {3, 2, 6}, {3, 6, 8}, {3, 8, 9},
		{4, 9, 5}, {2, 4, 11}, {6, 2, 10}, {8, 6, 7}, {9, 8, 1},
	}
)

// pointKey identifica um ponto da subdivisão de forma exata: até três pares
// (vértice do icosaedro, peso inteiro), ordenados pelo vértice. Pontos em arestas e
// vértices compartilhados por faces diferentes geram a mesma chave.
type pointKey [6]int

func makeKey(idx [3]int, w [3]int) pointKey {
	type pair struct{ v, w int }
	ps := make([]pair, 0, 3)
	for k := 0; k < 3; k++ {
		if w[k] > 0 {
			ps = append(ps, pair{idx[k], w[k]})
		}
	}
	sort.Slice(ps, func(a, b int) bool { return ps[a].v < ps[b].v })
	key := pointKey{-1, 0, -1, 0, -1, 0}
	for k, p := range ps {
		key[2*k], key[2*k+1] = p.v, p.w
	}
	return key
}

// position calcula o ponto na esfera a partir da chave, sempre da mesma forma,
// para que o resultado não dependa de qual face o encontrou primeiro.
func (k pointKey) position(n int) Vec3 {
	var p Vec3
	for i := 0; i < 3; i++ {
		if k[2*i] >= 0 {
			p = p.Add(icoVertices[k[2*i]].Scale(float64(k[2*i+1]) / float64(n)))
		}
	}
	return p.Normalize()
}

// NewGrid gera a grade de frequência n (n ≥ 1). A geração é determinística.
func NewGrid(n int) (*Grid, error) {
	if n < 1 {
		return nil, fmt.Errorf("frequência inválida: %d (precisa ser ≥ 1)", n)
	}

	ids := make(map[pointKey]int, CellCount(n))
	var centers []Vec3
	pointID := func(idx [3]int, w [3]int) int {
		key := makeKey(idx, w)
		if id, ok := ids[key]; ok {
			return id
		}
		id := len(centers)
		ids[key] = id
		centers = append(centers, key.position(n))
		return id
	}

	// Triângulos da subdivisão, todos em sentido anti-horário visto de fora.
	tris := make([][3]int, 0, 20*n*n)
	for _, f := range icoFaces {
		a, b, c := icoVertices[f[0]], icoVertices[f[1]], icoVertices[f[2]]
		if b.Sub(a).Cross(c.Sub(a)).Dot(a.Add(b).Add(c)) < 0 {
			f[1], f[2] = f[2], f[1]
		}
		p := func(i, j int) int { return pointID(f, [3]int{n - i - j, i, j}) }
		for j := 0; j < n; j++ {
			for i := 0; i+j < n; i++ {
				tris = append(tris, [3]int{p(i, j), p(i+1, j), p(i, j+1)})
				if i+j < n-1 {
					tris = append(tris, [3]int{p(i+1, j), p(i+1, j+1), p(i, j+1)})
				}
			}
		}
	}
	if len(centers) != CellCount(n) {
		return nil, fmt.Errorf("grade inconsistente: %d pontos, esperado %d", len(centers), CellCount(n))
	}

	// Para cada ponto, os triângulos em volta dele. Um "fan" (p, q, t) diz que, andando no
	// sentido anti-horário em volta do ponto, o triângulo t vai da aresta até p à aresta até q.
	type fan struct{ p, q, t int }
	around := make([][]fan, len(centers))
	centroids := make([]Vec3, len(tris))
	for ti, t := range tris {
		centroids[ti] = centers[t[0]].Add(centers[t[1]]).Add(centers[t[2]]).Normalize()
		for r := 0; r < 3; r++ {
			around[t[r]] = append(around[t[r]], fan{t[(r+1)%3], t[(r+2)%3], ti})
		}
	}

	g := &Grid{
		Frequency: n,
		Centers:   centers,
		Vertices:  make([][]Vec3, len(centers)),
		Neighbors: make([][]int, len(centers)),
	}
	for v, fans := range around {
		// Começa pelo fan cujo p tem o menor id (determinístico) e segue a corrente:
		// o próximo fan começa onde o anterior terminou. O centróide do fan k e o do fan k+1
		// ficam um de cada lado da aresta v→q, então o vizinho k é q.
		next := make(map[int]fan, len(fans))
		start := fans[0]
		for _, f := range fans {
			next[f.p] = f
			if f.p < start.p {
				start = f
			}
		}
		verts := make([]Vec3, 0, len(fans))
		neigh := make([]int, 0, len(fans))
		f := start
		for range fans {
			verts = append(verts, centroids[f.t])
			neigh = append(neigh, f.q)
			f = next[f.q]
		}
		if f != start {
			return nil, fmt.Errorf("célula %d: anel de triângulos não fecha", v)
		}
		g.Vertices[v] = verts
		g.Neighbors[v] = neigh
	}
	return g, nil
}
