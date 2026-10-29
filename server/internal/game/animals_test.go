package game_test

import (
	"encoding/json"
	"math"
	"os"
	"reflect"
	"testing"

	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

// cellWithAnimals acha uma célula do bioma com animais (procurando em ordem, determinístico).
func cellWithAnimals(t *testing.T, f *fixture, biome world.Biome) (int, []game.Animal) {
	t.Helper()
	for i, c := range f.world.Cells {
		if c.Biome != biome {
			continue
		}
		objs := game.FilterLots(game.GenerateObjects(f.world, f.svc.Content(), i), nil)
		if a := game.GenerateAnimals(f.world, f.svc.Content(), i, objs, nil); len(a) > 0 {
			return i, a
		}
	}
	t.Fatalf("nenhuma célula de %s com animais", biome)
	return 0, nil
}

func TestAnimalsAreDeterministic(t *testing.T) {
	f := newFixture(t)
	cell, first := cellWithAnimals(t, f, world.BiomeGrassland)
	objs := game.GenerateObjects(f.world, f.svc.Content(), cell)
	again := game.GenerateAnimals(f.world, f.svc.Content(), cell, objs, nil)
	if !reflect.DeepEqual(first, again) {
		t.Fatalf("mesma célula, animais diferentes")
	}
	for _, a := range first {
		if game.AnimalCell(a.ID) != cell {
			t.Fatalf("id %d fora da célula %d", a.ID, cell)
		}
		sp := f.svc.Content().Animals.Species[a.Species]
		if sp.Name == "" {
			t.Fatalf("espécie desconhecida %q", a.Species)
		}
		// Mesmo id e mesmo horário → mesma posição (é o que deixa todo mundo ver o mesmo).
		for _, tt := range []float64{1.8e9, 1.8e9 + 3.3, 1.8e9 + 77.7} {
			p1, p2 := game.AnimalAt(&a, tt), game.AnimalAt(&a, tt)
			if p1 != p2 {
				t.Fatalf("posição muda para o mesmo horário: %+v %+v", p1, p2)
			}
		}
	}
}

func TestAnimalsStayInsideTheCellAndOutOfLots(t *testing.T) {
	f := newFixture(t)
	_, me := f.player(t, "Pastora", "BRA")
	cell := me.Lot.Cell
	w := f.world
	content := f.svc.Content()
	lots := []game.Lot{{ID: me.Lot.ID, Cell: cell, Slot: me.Lot.Slot}}
	objs := game.FilterLots(game.GenerateObjects(w, content, cell), []int{me.Lot.Slot})
	animals := game.GenerateAnimals(w, content, cell, objs, lots)
	fr := game.CellFrame(w, cell)
	x0, y0, x1, y1 := game.SlotRect(me.Lot.Slot)
	for _, a := range animals {
		for s := 0.0; s < 600; s += 0.7 {
			p := game.AnimalAt(&a, 1.8e9+s)
			if !fr.Inside(p.X, p.Y, 0.5) {
				t.Fatalf("%s saiu da célula em (%.2f, %.2f)", a.Species, p.X, p.Y)
			}
			if p.X > x0 && p.X < x1 && p.Y > y0 && p.Y < y1 {
				t.Fatalf("%s entrou no lote em (%.2f, %.2f)", a.Species, p.X, p.Y)
			}
		}
	}
	// Nenhum animal em bioma sem animais (deserto, gelo).
	for i, c := range w.Cells {
		if c.Biome == world.BiomeDesert || c.Biome == world.BiomeIce {
			if a := game.GenerateAnimals(w, content, i, nil, nil); len(a) > 0 {
				t.Fatalf("animais no %s (célula %d)", c.Biome, i)
			}
			break
		}
	}
}

func TestAnimalWalksAndRests(t *testing.T) {
	f := newFixture(t)
	_, animals := cellWithAnimals(t, f, world.BiomeForest)
	a := animals[0]
	states := map[string]int{}
	var last game.AnimalPose
	for s := 0.0; s < a.Leg*20; s += 0.5 {
		p := game.AnimalAt(&a, 1.8e9+s)
		states[p.State]++
		if s > 0 && math.Hypot(p.X-last.X, p.Y-last.Y) > a.Speed*0.5*1.6+1e-9 {
			t.Fatalf("pulo de posição em %.1f s: (%.2f, %.2f) → (%.2f, %.2f)", s, last.X, last.Y, p.X, p.Y)
		}
		last = p
	}
	if states["walk"] == 0 || states["walk"] == len(states) {
		t.Fatalf("o animal precisa andar e parar: %v", states)
	}
}

// O cliente (client/scripts/animal_path.gd) faz a mesma conta que AnimalAt. Este arquivo
// guarda poses de referência; client/tests/test_animais.gd confere contra ele. Para gerar
// de novo: GOBLO_GOLDEN=1 go test ./internal/game -run AnimalGolden
func TestAnimalGolden(t *testing.T) {
	type pose struct {
		T       float64 `json:"t"`
		X       float64 `json:"x"`
		Y       float64 `json:"y"`
		Heading float64 `json:"heading"`
		State   string  `json:"state"`
	}
	type golden struct {
		Animal game.Animal `json:"animal"`
		Poses  []pose      `json:"poses"`
	}
	a := game.Animal{ID: 123456789, Cell: 7716049, Species: "cow", Speed: 0.8, Leg: 16,
		Points: [][2]float64{{1.5, 2}, {-3.25, 4.5}, {0.75, -5}, {6.5, 1.25}, {-2, -2.5}}}
	var g golden
	g.Animal = a
	for _, tt := range []float64{1.7e9, 1.7e9 + 1.25, 1.7e9 + 9.5, 1.7e9 + 15.9, 1.7e9 + 16.2, 1761750000.75, 1799999999.5, 2.1e9 + 0.125} {
		p := game.AnimalAt(&a, tt)
		g.Poses = append(g.Poses, pose{tt, p.X, p.Y, p.Heading, p.State})
	}
	path := "testdata/animal_paths.json"
	if os.Getenv("GOBLO_GOLDEN") == "1" {
		b, _ := json.MarshalIndent(g, "", " ")
		if err := os.WriteFile(path, b, 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile("../../../client/tests/animal_paths.json", b, 0o644); err != nil {
			t.Fatal(err)
		}
		return
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("%v (gere com GOBLO_GOLDEN=1)", err)
	}
	var want golden
	if err := json.Unmarshal(raw, &want); err != nil {
		t.Fatal(err)
	}
	for i, p := range g.Poses {
		w := want.Poses[i]
		if math.Abs(p.X-w.X) > 1e-9 || math.Abs(p.Y-w.Y) > 1e-9 || p.State != w.State || math.Abs(p.Heading-w.Heading) > 1e-9 {
			t.Errorf("t=%.3f: %+v, referência %+v", p.T, p, w)
		}
	}
}
