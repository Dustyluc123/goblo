package world

import (
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math"
)

// Config define o mundo. Mesma Config + mesmos dados = mesmo mundo.
type Config struct {
	Frequency int     // frequência de subdivisão da grade (células = 10·n²+2)
	Radius    float64 // raio sugerido do planeta, em unidades do jogo
}

// DefaultConfig é o mundo da fase 1: 4.002 células e raio 100.
var DefaultConfig = Config{Frequency: 20, Radius: 100}

// Cell é uma célula do globo, no formato enviado ao cliente.
type Cell struct {
	ID        int          `json:"id"`
	Lat       float64      `json:"lat"`
	Lon       float64      `json:"lon"`
	Center    [3]float64   `json:"center"`
	Vertices  [][3]float64 `json:"vertices"`
	Neighbors []int        `json:"neighbors"`
	Terrain   Terrain      `json:"terrain"`
	Country   string       `json:"country"`
}

// World é a definição completa do mundo: a fonte da verdade que o cliente só desenha.
type World struct {
	Frequency int               `json:"frequency"`
	Radius    float64           `json:"radius"`
	Countries map[string]string `json:"countries"` // código ISO A3 → nome, só países com células
	Cells     []Cell            `json:"cells"`
}

// New monta o mundo: gera a grade e classifica cada célula pelo centro.
func New(cfg Config, geo *Geography) (*World, error) {
	if cfg.Radius <= 0 {
		return nil, fmt.Errorf("raio inválido: %v", cfg.Radius)
	}
	grid, err := NewGrid(cfg.Frequency)
	if err != nil {
		return nil, err
	}
	names := make(map[string]string, len(geo.Countries))
	for _, c := range geo.Countries {
		names[c.Code] = c.Name
	}

	w := &World{
		Frequency: cfg.Frequency,
		Radius:    cfg.Radius,
		Countries: map[string]string{},
		Cells:     make([]Cell, len(grid.Centers)),
	}
	for i, c := range grid.Centers {
		lat, lon := VecToLatLon(c)
		terrain, country := geo.Classify(lat, lon)
		verts := make([][3]float64, len(grid.Vertices[i]))
		for k, v := range grid.Vertices[i] {
			verts[k] = round3(v)
		}
		w.Cells[i] = Cell{
			ID:        i,
			Lat:       round(lat, 4),
			Lon:       round(lon, 4),
			Center:    round3(c),
			Vertices:  verts,
			Neighbors: append([]int(nil), grid.Neighbors[i]...),
			Terrain:   terrain,
			Country:   country,
		}
		if country != "" {
			w.Countries[country] = names[country]
		}
	}
	return w, nil
}

// CellAt devolve a célula que contém o ponto (lat/lon em graus): a de centro mais próximo.
func (w *World) CellAt(lat, lon float64) *Cell {
	p := LatLonToVec(lat, lon)
	best, bestDot := -1, math.Inf(-1)
	for i := range w.Cells {
		c := w.Cells[i].Center
		if d := p.Dot(Vec3{c[0], c[1], c[2]}); d > bestDot {
			best, bestDot = i, d
		}
	}
	return &w.Cells[best]
}

// OceanRatio é a fração de células de oceano.
func (w *World) OceanRatio() float64 {
	ocean := 0
	for _, c := range w.Cells {
		if c.Terrain == Ocean {
			ocean++
		}
	}
	return float64(ocean) / float64(len(w.Cells))
}

// Snapshot é o mundo já serializado, gerado uma vez na inicialização e servido do cache.
type Snapshot struct {
	JSON []byte
	Gzip []byte
	ETag string
}

// Snapshot serializa o mundo em JSON e em JSON+gzip.
func (w *World) Snapshot() (*Snapshot, error) {
	raw, err := json.Marshal(w)
	if err != nil {
		return nil, err
	}
	var buf bytes.Buffer
	zw, _ := gzip.NewWriterLevel(&buf, gzip.BestCompression)
	if _, err := zw.Write(raw); err != nil {
		return nil, err
	}
	if err := zw.Close(); err != nil {
		return nil, err
	}
	sum := sha256.Sum256(raw)
	return &Snapshot{JSON: raw, Gzip: buf.Bytes(), ETag: `"` + hex.EncodeToString(sum[:8]) + `"`}, nil
}

func round(x float64, digits int) float64 {
	p := math.Pow(10, float64(digits))
	return math.Round(x*p) / p
}

// round3 arredonda para 6 casas: precisão de ~6 m num planeta do tamanho da Terra e
// JSON bem menor.
func round3(v Vec3) [3]float64 {
	return [3]float64{round(v.X, 6), round(v.Y, 6), round(v.Z, 6)}
}
