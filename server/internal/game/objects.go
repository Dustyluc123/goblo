package game

import (
	"math"
	"sort"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// MaxObjectsPerCell limita os objetos de uma célula; o id do objeto é célula × 64 + índice.
const MaxObjectsPerCell = 64

// objectInset mantém os objetos no topo plano da célula, longe da borda e dos degraus.
const objectInset = 0.85

// Object é um objeto interativo (ou enfeite grande) do mundo, gerado pelo servidor.
// A posição é (X, Y) no plano da célula (veja Frame).
type Object struct {
	ID    int64   `json:"id"`
	Cell  int     `json:"cell"`
	Kind  string  `json:"kind"`
	Model string  `json:"model"`
	X     float64 `json:"x"`
	Y     float64 `json:"y"`
	Yaw   float64 `json:"yaw"`
	Scale float64 `json:"scale"`
	Drop  string  `json:"drop,omitempty"` // árvore: o que cai ao sacudir
	Chop  bool    `json:"chop,omitempty"` // árvore: dá madeira com o machado
	Item  string  `json:"item,omitempty"` // flor: o item que ela vira
	Solid bool    `json:"solid,omitempty"`
}

// ObjectID monta o id estável de um objeto.
func ObjectID(cell, index int) int64 { return int64(cell)*MaxObjectsPerCell + int64(index) }

// ObjectCell devolve a célula de um id de objeto.
func ObjectCell(id int64) int { return int(id / MaxObjectsPerCell) }

// GenerateObjects gera os objetos de uma célula. É determinístico: depende só do id da
// célula, do bioma, da geometria e de objects.json. Não olha os lotes; quem chama filtra
// os objetos que caem em lotes ocupados (FilterLots), para os ids não mudarem.
func GenerateObjects(w *world.World, content *Content, cell int) []Object {
	if cell < 0 || cell >= len(w.Cells) || w.Cells[cell].Terrain != world.Land {
		return nil
	}
	rules := content.Objects[w.Cells[cell].Biome.String()]
	if len(rules) == 0 {
		return nil
	}
	f := CellFrame(w, cell)
	nearWater := false
	for _, nb := range w.Cells[cell].Neighbors {
		if w.Cells[nb].Terrain == world.Ocean {
			nearWater = true
			break
		}
	}
	// Triângulos do leque (centro + cantos encolhidos), para sortear pontos por área.
	n := len(f.Poly)
	areas := make([]float64, n)
	total := 0.0
	for k := 0; k < n; k++ {
		a, b := f.Poly[k], f.Poly[(k+1)%n]
		areas[k] = math.Abs(a[0]*b[1]-b[0]*a[1]) / 2
		total += areas[k]
	}

	r := newRNG(mix(uint64(cell), 0x0B1EC75))
	var out []Object
	spacing := []float64{}
	for _, rule := range rules {
		if rule.NearWater && !nearWater {
			continue
		}
		count := int(rule.PerCell)
		if r.float() < rule.PerCell-float64(count) {
			count++
		}
		placed := 0
		for try := 0; try < count*6 && placed < count && len(out) < MaxObjectsPerCell; try++ {
			// Ponto uniforme no triângulo escolhido pela área.
			pick := r.float() * total
			k := 0
			for k < n-1 && pick > areas[k] {
				pick -= areas[k]
				k++
			}
			u, v := r.float(), r.float()
			if u+v > 1 {
				u, v = 1-u, 1-v
			}
			a, b := f.Poly[k], f.Poly[(k+1)%n]
			x := (a[0]*u + b[0]*v) * objectInset
			y := (a[1]*u + b[1]*v) * objectInset
			yaw := r.float() * 2 * math.Pi
			scale := rule.Scale[0] + (rule.Scale[1]-rule.Scale[0])*r.float()
			model := rule.Models[r.intn(len(rule.Models))]
			color := ""
			if len(rule.Colors) > 0 {
				color = rule.Colors[r.intn(len(rule.Colors))]
			}
			ok := true
			for i, o := range out {
				min := (spacing[i] + rule.Spacing) / 2
				if (o.X-x)*(o.X-x)+(o.Y-y)*(o.Y-y) < min*min {
					ok = false
					break
				}
			}
			if !ok {
				continue
			}
			o := Object{
				ID: ObjectID(cell, len(out)), Cell: cell, Kind: rule.Kind, Model: model,
				X: round2(x), Y: round2(y), Yaw: round2(yaw), Scale: round2(scale), Solid: rule.Solid,
			}
			if rule.Kind == KindTree {
				o.Drop = rule.Drop
				if o.Drop == "" {
					o.Drop = "branch"
				}
				o.Chop = rule.Chop
			}
			if rule.Kind == KindFlower && color != "" {
				o.Item = "flower_" + color
				// Cor rara: sorteio à parte pelo id da flor, que não mexe na sequência dos
				// outros objetos (ids e posições continuam os mesmos).
				if rule.RareColor != "" && newRNG(mix(uint64(o.ID), 0xF10E5)).float() < rule.RareP {
					o.Item = "flower_" + rule.RareColor
				}
			}
			out = append(out, o)
			spacing = append(spacing, rule.Spacing)
			placed++
		}
	}
	return out
}

// objectLotMargin afasta os objetos da borda dos lotes ocupados (copas de árvore não
// invadem o terreno de ninguém).
const objectLotMargin = 1.0

// FilterLots tira os objetos que caem dentro (ou perto) dos lotes ocupados da célula.
func FilterLots(objs []Object, occupiedSlots []int) []Object {
	if len(occupiedSlots) == 0 {
		return objs
	}
	out := objs[:0:0]
	for _, o := range objs {
		if !insideAnySlot(o.X, o.Y, occupiedSlots, objectLotMargin) {
			out = append(out, o)
		}
	}
	return out
}

func insideAnySlot(x, y float64, slots []int, margin float64) bool {
	for _, s := range slots {
		x0, y0, x1, y1 := SlotRect(s)
		if x >= x0-margin && x <= x1+margin && y >= y0-margin && y <= y1+margin {
			return true
		}
	}
	return false
}

func round2(x float64) float64 { return math.Round(x*100) / 100 }

// sortedCells devolve as células sem repetição, em ordem.
func sortedCells(cells []int) []int {
	seen := map[int]bool{}
	out := make([]int, 0, len(cells))
	for _, c := range cells {
		if !seen[c] {
			seen[c] = true
			out = append(out, c)
		}
	}
	sort.Ints(out)
	return out
}
