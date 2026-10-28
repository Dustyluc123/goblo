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

// DefaultConfig é o mundo da fase 1.5: 25.002 células e raio 1000. Com isso cada
// hexágono tem ~22 unidades de largura e SP → Pacaraima tem ~549 unidades.
var DefaultConfig = Config{Frequency: 50, Radius: 1000}

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
	Biome     Biome        `json:"biome"`
	Height    float64      `json:"height"` // topo da célula acima do nível do mar
}

// World é a definição completa do mundo: a fonte da verdade que o cliente só desenha.
type World struct {
	Version   string            `json:"version"` // hash do formato binário; muda quando o mundo muda
	Frequency int               `json:"frequency"`
	Radius    float64           `json:"radius"`
	Countries map[string]string `json:"countries"` // código ISO A3 → nome, só países com células
	Cells     []Cell            `json:"cells"`
}

// New monta o mundo: gera a grade, classifica cada célula pelo centro (terra, país,
// bioma) e calcula as alturas.
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
	base := make([]Biome, len(grid.Centers))
	hills := make([]bool, len(grid.Centers))
	for i, c := range grid.Centers {
		lat, lon := VecToLatLon(c)
		terrain, country := geo.Classify(lat, lon)
		if terrain == Land {
			hits := geo.regionsAt(lat, lon)
			base[i] = baseBiome(lat, country, hits)
			hills[i] = isHilly(c, hits)
		}
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
	assignBiomes(w.Cells, base, hills)
	bin, err := w.MarshalBinary()
	if err != nil {
		return nil, err
	}
	sum := sha256.Sum256(bin)
	w.Version = hex.EncodeToString(sum[:8])
	return w, nil
}

// BiomeCounts conta as células de cada bioma.
func (w *World) BiomeCounts() map[Biome]int {
	counts := map[Biome]int{}
	for _, c := range w.Cells {
		counts[c.Biome]++
	}
	return counts
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
// O binário é o formato do jogo; o JSON é para depuração.
type Snapshot struct {
	Version    string
	JSON       []byte
	JSONGzip   []byte
	Binary     []byte
	BinaryGzip []byte
}

// ETag é a versão entre aspas, no formato do cabeçalho HTTP.
func (s *Snapshot) ETag() string { return `"` + s.Version + `"` }

// Snapshot serializa o mundo em JSON e binário, cada um também com gzip.
func (w *World) Snapshot() (*Snapshot, error) {
	raw, err := json.Marshal(w)
	if err != nil {
		return nil, err
	}
	bin, err := w.MarshalBinary()
	if err != nil {
		return nil, err
	}
	s := &Snapshot{Version: w.Version, JSON: raw, Binary: bin}
	if s.JSONGzip, err = gzipBytes(raw); err != nil {
		return nil, err
	}
	if s.BinaryGzip, err = gzipBytes(bin); err != nil {
		return nil, err
	}
	return s, nil
}

func gzipBytes(b []byte) ([]byte, error) {
	var buf bytes.Buffer
	zw, _ := gzip.NewWriterLevel(&buf, gzip.BestCompression)
	if _, err := zw.Write(b); err != nil {
		return nil, err
	}
	if err := zw.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
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
