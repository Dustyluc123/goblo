package game

import "github.com/Dustyluc123/goblo/server/internal/world"

// Lotes: cada célula de terra tem até 4 lotes quadrados, num quadriculado 2 × 2 em volta do
// centro, separados por um corredor. Cada lote é uma grade de LotTiles × LotTiles
// quadradinhos de TileSize unidades (ADR 0019).
const (
	TileSize    = 0.5
	LotTiles    = 14
	LotSize     = TileSize * LotTiles // 7 unidades
	LotsPerCell = 4
	lotGap      = 0.5 // corredor entre os lotes de uma célula
	lotMargin   = 0.3 // distância mínima até a borda da célula
)

// LotSlot é um lote possível (ocupado ou não). X0, Y0 é o canto mínimo no plano da célula
// (veja Frame); a grade cresce para East (x) e North (y).
type LotSlot struct {
	ID   int64   `json:"id"`
	Cell int     `json:"cell"`
	Slot int     `json:"slot"`
	X0   float64 `json:"x0"`
	Y0   float64 `json:"y0"`
}

// LotID é o id estável do lote: célula × 4 + posição.
func LotID(cell, slot int) int64 { return int64(cell)*LotsPerCell + int64(slot) }

// LotCell devolve a célula e a posição de um id de lote.
func LotCell(id int64) (cell, slot int) { return int(id / LotsPerCell), int(id % LotsPerCell) }

// LotSlots devolve os lotes que cabem na célula (nenhum no oceano).
func LotSlots(w *world.World, cell int) []LotSlot {
	if cell < 0 || cell >= len(w.Cells) || w.Cells[cell].Terrain != world.Land {
		return nil
	}
	f := CellFrame(w, cell)
	var out []LotSlot
	for s := 0; s < LotsPerCell; s++ {
		x0, y0 := slotOrigin(s)
		ok := true
		for _, c := range [][2]float64{{x0, y0}, {x0 + LotSize, y0}, {x0, y0 + LotSize}, {x0 + LotSize, y0 + LotSize}} {
			if !f.Inside(c[0], c[1], lotMargin) {
				ok = false
				break
			}
		}
		if ok {
			out = append(out, LotSlot{ID: LotID(cell, s), Cell: cell, Slot: s, X0: x0, Y0: y0})
		}
	}
	return out
}

func slotOrigin(s int) (float64, float64) {
	start := -LotSize - lotGap/2
	step := LotSize + lotGap
	return start + float64(s%2)*step, start + float64(s/2)*step
}

// SlotRect é o retângulo [x0, x0+LotSize] × [y0, y0+LotSize] de uma posição de lote.
func SlotRect(slot int) (x0, y0, x1, y1 float64) {
	x0, y0 = slotOrigin(slot)
	return x0, y0, x0 + LotSize, y0 + LotSize
}
