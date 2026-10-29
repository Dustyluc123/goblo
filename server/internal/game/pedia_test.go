package game_test

import (
	"errors"
	"testing"

	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

func TestPediaRewardOnlyOnce(t *testing.T) {
	f := newFixture(t)
	p, me := f.player(t, "Fotógrafa", "BRA")
	reward := f.svc.Content().Economy.Rewards.PediaFirst
	r1, err := f.svc.RegisterPedia(f.ctx, p, "cow", "ARG", "grassland")
	if err != nil {
		t.Fatal(err)
	}
	if !r1.First || r1.Reward != reward || r1.Coins != me.Coins+reward || r1.Sightings != 1 {
		t.Fatalf("primeira foto: %+v", r1)
	}
	r2, err := f.svc.RegisterPedia(f.ctx, p, "cow", "BRA", "forest")
	if err != nil {
		t.Fatal(err)
	}
	if r2.First || r2.Reward != 0 || r2.Coins != r1.Coins || r2.Sightings != 2 {
		t.Fatalf("segunda foto não pode pagar de novo: %+v", r2)
	}
	if _, err := f.svc.RegisterPedia(f.ctx, p, "dragao", "BRA", "forest"); !errors.Is(err, game.ErrNotFound) {
		t.Fatalf("espécie inventada: %v", err)
	}
	list, err := f.svc.Pedia(f.ctx, p)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, e := range list {
		if e.ID == "cow" {
			found = true
			// A primeira foto foi na Argentina, no campo: isso não muda com as próximas.
			if !e.Discovered || e.Country != "ARG" || e.CountryName != "Argentina" || e.Biome != "grassland" || e.Sightings != 2 {
				t.Fatalf("página da vaca: %+v", e)
			}
		} else if e.Discovered {
			t.Fatalf("%s descoberto sem foto", e.ID)
		}
	}
	if !found || len(list) != len(f.svc.Content().Animals.Species)+3 {
		t.Fatalf("%d páginas", len(list))
	}
}

func TestFeedingMakesFriendsAndSpendsOneBerry(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Amiga", "BRA")
	_, animals := cellWithAnimals(t, f, world.BiomeGrassland)
	a := animals[0]
	if _, err := f.svc.FeedAnimal(f.ctx, p, a.ID); !errors.Is(err, game.ErrMissingMaterials) {
		t.Fatalf("sem frutinha: %v", err)
	}
	if _, err := f.svc.DevGive(f.ctx, p, "berries", 2); err != nil {
		t.Fatal(err)
	}
	res, err := f.svc.FeedAnimal(f.ctx, p, a.ID)
	if err != nil {
		t.Fatal(err)
	}
	if res.Species != a.Species || count(res.Inventory, "berries") != 1 {
		t.Fatalf("frutinha: %+v", res)
	}
	list, _ := f.svc.Pedia(f.ctx, p)
	for _, e := range list {
		if e.ID == a.Species && (!e.Friend || e.Discovered) {
			t.Fatalf("amigo sem foto: %+v", e)
		}
	}
	if _, err := f.svc.FeedAnimal(f.ctx, p, game.AnimalID(0, 15)); !errors.Is(err, game.ErrNotFound) {
		t.Fatalf("animal que não existe: %v", err)
	}
}

func TestDevPediaCompleteAndReset(t *testing.T) {
	f := newFixture(t)
	p, me := f.player(t, "Colecionadora", "BRA")
	list, err := f.svc.DevPedia(f.ctx, p, "complete")
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range list {
		if !e.Discovered {
			t.Fatalf("%s não ficou descoberto", e.ID)
		}
	}
	after, _ := f.svc.Me(f.ctx, p)
	if after.Coins != me.Coins {
		t.Fatalf("completar pelo modo dev não paga moedas: %d → %d", me.Coins, after.Coins)
	}
	list, _ = f.svc.DevPedia(f.ctx, p, "reset")
	for _, e := range list {
		if e.Discovered || e.Friend {
			t.Fatalf("%s continua depois do reset", e.ID)
		}
	}
}

// A flor azul rara aparece pouco e não muda nenhum outro objeto (ids e posições iguais).
func TestRareFlowerDoesNotMoveObjects(t *testing.T) {
	w, c := sharedWorld(t)
	plain := *c
	plain.Objects = map[string][]game.ObjectRule{}
	for b, rules := range c.Objects {
		cp := append([]game.ObjectRule(nil), rules...)
		for i := range cp {
			cp[i].RareColor = ""
		}
		plain.Objects[b] = cp
	}
	flowers, blue := 0, 0
	for cell := 0; cell < len(w.Cells) && flowers < 4000; cell++ {
		a := game.GenerateObjects(w, c, cell)
		b := game.GenerateObjects(w, &plain, cell)
		if len(a) != len(b) {
			t.Fatalf("célula %d: %d objetos com a flor rara, %d sem", cell, len(a), len(b))
		}
		for i := range a {
			if a[i].ID != b[i].ID || a[i].X != b[i].X || a[i].Y != b[i].Y || a[i].Model != b[i].Model {
				t.Fatalf("célula %d: objeto %d mudou", cell, a[i].ID)
			}
			if a[i].Kind == game.KindFlower {
				flowers++
				if a[i].Item == "flower_blue" {
					blue++
				}
			}
		}
	}
	if share := float64(blue) / float64(flowers); blue == 0 || share > 0.1 {
		t.Fatalf("%d flores azuis em %d (precisa ser rara, mas existir)", blue, flowers)
	}
}
