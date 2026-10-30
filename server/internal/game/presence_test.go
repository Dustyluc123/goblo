package game_test

import (
	"errors"
	"math"
	"testing"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

// fakePresence faz o papel da camada em tempo real nos testes.
type fakePresence struct {
	pos    map[int64]world.Vec3
	facing world.Vec3
}

func (f *fakePresence) Where(id int64) (world.Vec3, int, world.Vec3, bool) {
	p, ok := f.pos[id]
	return p, -1, f.facing, ok
}

// Com a camada em tempo real ligada, o servidor confere a distância (ADR 0040): coleta,
// caixa de vendas, frutinha, Goblopédia e balcão do aeroporto.
func TestServerChecksReach(t *testing.T) {
	f := newFixture(t)
	pres := &fakePresence{pos: map[int64]world.Vec3{}}
	f.svc.SetPresence(pres)
	p, me := f.player(t, "Alcance", "BRA")
	lot := me.Lot

	// Sem conexão em tempo real: nada de coletar.
	cells := []int{lot.Cell}
	objs, _, err := f.svc.Objects(f.ctx, p, cells)
	if err != nil || len(objs) == 0 {
		t.Fatalf("sem objetos no hexágono de casa: %v", err)
	}
	var tree *game.Object
	for i := range objs {
		if objs[i].Kind == game.KindTree && objs[i].Drop != "" {
			tree = &objs[i].Object
			break
		}
	}
	if tree == nil {
		t.Skip("hexágono sem árvore para sacudir")
	}
	if _, err := f.svc.Interact(f.ctx, p, tree.ID, "shake"); !errors.Is(err, game.ErrOffline) {
		t.Fatalf("sem tempo real, coleta deu %v", err)
	}
	// Longe da árvore: "chegue mais perto". Perto: funciona.
	tp := f.svc.ObjectPoint(tree)
	east := world.Vec3{Y: 1}.Cross(tp.Normalize()).Normalize()
	pres.pos[p.ID] = tp.Add(east.Scale(20))
	if _, err := f.svc.Interact(f.ctx, p, tree.ID, "shake"); !errors.Is(err, game.ErrTooFar) {
		t.Fatalf("a 20 unidades da árvore, coleta deu %v", err)
	}
	pres.pos[p.ID] = tp.Add(east.Scale(1.2))
	if _, err := f.svc.Interact(f.ctx, p, tree.ID, "shake"); err != nil {
		t.Fatalf("pertinho da árvore: %v", err)
	}

	// Caixa de vendas: só perto da do próprio lote.
	f.give(t, p, "wood", 3)
	pres.pos[p.ID] = tp.Add(east.Scale(60))
	if _, err := f.svc.Sell(f.ctx, p, []game.StackView{{Item: "wood", Count: 1}}); !errors.Is(err, game.ErrTooFar) {
		t.Fatalf("longe da caixa de vendas, venda deu %v", err)
	}
	fr := game.CellFrame(f.world, lot.Cell)
	box := fr.Point(lot.X0+(8+0.5)*game.TileSize, lot.Y0+(1+0.5)*game.TileSize)
	pres.pos[p.ID] = box
	if _, err := f.svc.Sell(f.ctx, p, []game.StackView{{Item: "wood", Count: 1}}); err != nil {
		t.Fatalf("na caixa de vendas: %v", err)
	}

	// Bancada: fabricar só perto da do próprio lote (canto 11, 1).
	f.give(t, p, "wood", 10)
	recipe := f.svc.Content().Recipes[0].ID
	pres.pos[p.ID] = tp.Add(east.Scale(60))
	if _, err := f.svc.Craft(f.ctx, p, recipe, 1); !errors.Is(err, game.ErrTooFar) {
		t.Fatalf("longe da bancada, fabricar deu %v", err)
	}
	pres.pos[p.ID] = fr.Point(lot.X0+12*game.TileSize, lot.Y0+2*game.TileSize)
	if _, err := f.svc.Craft(f.ctx, p, recipe, 1); errors.Is(err, game.ErrTooFar) || errors.Is(err, game.ErrOffline) {
		t.Fatalf("na bancada, fabricar deu %v", err)
	}

	// Frutinha: o animal precisa estar perto (com a folga das reações locais).
	animals, err := f.svc.Animals(f.ctx, f.svc.World().Cells[lot.Cell].Neighbors)
	if err != nil || len(animals) == 0 {
		t.Skip("sem animais em volta da casa")
	}
	a := animals[0]
	f.give(t, p, "berries", 2)
	ap := f.svc.AnimalPoint(&a, f.clock.Now())
	pres.pos[p.ID] = ap.Add(east.Scale(40))
	if _, err := f.svc.FeedAnimal(f.ctx, p, a.ID); !errors.Is(err, game.ErrTooFar) {
		t.Fatalf("a 40 unidades do animal, frutinha deu %v", err)
	}
	pres.pos[p.ID] = f.svc.AnimalPoint(&a, f.clock.Now()).Add(east.Scale(1))
	if _, err := f.svc.FeedAnimal(f.ctx, p, a.ID); err != nil {
		t.Fatalf("pertinho do animal: %v", err)
	}

	// Goblopédia: o animal precisa estar perto e na direção da câmera.
	ap = f.svc.AnimalPoint(&a, f.clock.Now())
	cam := ap.Add(east.Scale(-12))
	pres.pos[p.ID] = cam
	look := ap.Sub(cam).Normalize()
	// Uma direção sem nenhum animal da espécie na frente (pode haver outro atrás).
	up := cam.Normalize()
	var empty world.Vec3
	for k := 0; k < 12 && empty.Len() == 0; k++ {
		ang := float64(k) * math.Pi / 6
		d := look.Scale(math.Cos(ang)).Add(up.Cross(look).Scale(math.Sin(ang)))
		clear := true
		near, _ := f.svc.Animals(f.ctx, append(f.svc.World().Cells[lot.Cell].Neighbors, lot.Cell))
		for i := range near {
			if near[i].Species != a.Species {
				continue
			}
			to := f.svc.AnimalPoint(&near[i], f.clock.Now()).Sub(cam)
			if to.Len() < 70 && to.Normalize().Dot(d) > 0.3 {
				clear = false
			}
		}
		if clear {
			empty = d
		}
	}
	if empty.Len() > 0 {
		if _, err := f.svc.RegisterPedia(f.ctx, p, a.Species, "BRA", "forest", empty); !errors.Is(err, game.ErrTooFar) {
			t.Fatalf("câmera virada para onde não há %s registrou: %v", a.Species, err)
		}
	}
	if _, err := f.svc.RegisterPedia(f.ctx, p, a.Species, "BRA", "forest", look); err != nil {
		t.Fatalf("animal na frente da câmera: %v", err)
	}
	pres.pos[p.ID] = ap.Add(east.Scale(400))
	if _, err := f.svc.RegisterPedia(f.ctx, p, a.Species, "BRA", "forest", world.Vec3{}); !errors.Is(err, game.ErrTooFar) {
		t.Fatalf("animal a 400 unidades registrou: %v", err)
	}

	// Balcão do aeroporto: viajar só de perto dele.
	f.svc.DevCoins(f.ctx, p, 500)
	counter, _ := f.svc.ArrivalPoint("BRA")
	pres.pos[p.ID] = counter.Add(east.Scale(50))
	if _, err := f.svc.Travel(f.ctx, p, "BRA", "ARG", true, false); !errors.Is(err, game.ErrTooFar) {
		t.Fatalf("longe do balcão, viagem deu %v", err)
	}
	pres.pos[p.ID] = counter
	if _, err := f.svc.Travel(f.ctx, p, "BRA", "ARG", true, false); err != nil {
		t.Fatalf("no balcão: %v", err)
	}
	arrival, ok := f.svc.ConsumeArrival(p.ID)
	if want, _ := f.svc.ArrivalPoint("ARG"); !ok || arrival != want {
		t.Fatal("o voo pago não liberou a chegada na Argentina")
	}
	if _, ok := f.svc.ConsumeArrival(p.ID); ok {
		t.Fatal("a chegada vale uma vez só")
	}
	_ = time.Second
}
