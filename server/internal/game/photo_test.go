package game_test

import (
	"encoding/json"
	"errors"
	"math"
	"os"
	"testing"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Fase 4.2 (ADR 0053): a foto registra o que está centralizado e perto, e só isso.

// shotAt monta uma foto tirada a `dist` unidades (no chão) da coisa em `target`, com a câmera
// nos olhos e virada `turn` radianos para o lado. Devolve a posição do personagem e a foto.
func shotAt(target world.Vec3, dist, turn float64) (world.Vec3, game.PhotoShot) {
	up := target.Normalize()
	east := up.Cross(world.Vec3{Y: 1}).Normalize()
	pos := target.Add(east.Scale(dist))
	cam := pos.Add(pos.Normalize().Scale(0.78))
	look := target.Sub(cam).Normalize()
	if turn != 0 {
		side := look.Cross(cam.Normalize()).Normalize()
		look = look.Scale(math.Cos(turn)).Add(side.Scale(math.Sin(turn)))
	}
	return pos, game.PhotoShot{Look: look, Cam: cam, At: target}
}

// at muda o relógio para o instante t (a partir do começo dos testes).
func (f *fixture) at(t time.Time) {
	f.clock.Reset()
	f.clock.Advance(t.Sub(f.clock.Now()))
}

func TestPhotoRegistersEveryFlower(t *testing.T) {
	f := newFixture(t)
	pres := &fakePresence{pos: map[int64]world.Vec3{}}
	f.svc.SetPresence(pres)
	p, _ := f.player(t, "Fotografa", "BRA")
	c := f.svc.Content()
	// Uma flor de cada espécie: procura no mundo e numa data em que ela aparece.
	found := map[string]bool{}
	negatives := 0
	var flowers []game.PediaEntry
	for _, e := range c.PediaEntries() {
		if e.Kind == "flower" {
			flowers = append(flowers, e)
		}
	}
	dates := []time.Time{time.Date(2027, 1, 15, 15, 0, 0, 0, time.UTC), time.Date(2027, 4, 20, 15, 0, 0, 0, time.UTC),
		time.Date(2027, 7, 15, 15, 0, 0, 0, time.UTC), time.Date(2027, 10, 20, 15, 0, 0, 0, time.UTC)}
	w := f.svc.World()
	for cell := 0; cell < len(w.Cells) && len(found) < len(flowers); cell += 7 {
		if w.Cells[cell].Terrain != world.Land {
			continue
		}
		for _, o := range game.GenerateObjects(w, c, cell) {
			if o.Kind != game.KindFlower || found[o.Item] {
				continue
			}
			target := f.svc.ObjectPoint(&o)
			for _, d := range dates {
				f.at(d)
				pos, shot := shotAt(target, 5, 0)
				pres.pos[p.ID] = pos
				shot.At = world.Vec3{} // só a flor do servidor (sem o ponto enquadrado)
				if _, err := f.svc.RegisterPedia(f.ctx, p, o.Item, "BRA", "forest", shot); err == nil {
					found[o.Item] = true
					if !isolated(f, &o, 80) {
						break // outra flor igual por perto poderia estar no enquadramento
					}
					negatives++
					// Fora do centro (40°) e longe (60 unidades): não registra.
					_, off := shotAt(target, 5, 40*math.Pi/180)
					if _, err := f.svc.RegisterPedia(f.ctx, p, o.Item, "BRA", "forest", off); !errors.Is(err, game.ErrTooFar) {
						t.Errorf("%s fora do centro registrou: %v", o.Item, err)
					}
					far, farShot := shotAt(target, 60, 0)
					pres.pos[p.ID] = far
					if _, err := f.svc.RegisterPedia(f.ctx, p, o.Item, "BRA", "forest", farShot); !errors.Is(err, game.ErrTooFar) {
						t.Errorf("%s a 60 unidades registrou: %v", o.Item, err)
					}
					break
				}
			}
		}
	}
	for _, e := range flowers {
		if !found[e.ID] {
			t.Errorf("não consegui fotografar %s (%s)", e.ID, e.Name)
		}
	}
	if negatives < 2 {
		t.Errorf("só %d flores isoladas para conferir fora do centro e longe", negatives)
	}
}

// isolated: nenhuma outra flor do mesmo item a até r unidades (na célula e nas vizinhas).
func isolated(f *fixture, o *game.Object, r float64) bool {
	w := f.svc.World()
	at := f.svc.ObjectPoint(o)
	cells := append([]int{o.Cell}, w.Cells[o.Cell].Neighbors...)
	for _, nb := range w.Cells[o.Cell].Neighbors {
		cells = append(cells, w.Cells[nb].Neighbors...)
	}
	for _, c := range cells {
		for _, x := range game.GenerateObjects(w, f.svc.Content(), c) {
			if x.ID != o.ID && x.Item == o.Item && f.svc.ObjectPoint(&x).Sub(at).Len() < r {
				return false
			}
		}
	}
	return true
}

// Flor decorativa (só no cliente): vale a espécie que cresce ali, no ponto enquadrado.
func TestPhotoDecorativeFlower(t *testing.T) {
	f := newFixture(t)
	pres := &fakePresence{pos: map[int64]world.Vec3{}}
	f.svc.SetPresence(pres)
	p, _ := f.player(t, "Jardim", "BRA")
	w := f.svc.World()
	f.at(time.Date(2027, 7, 15, 15, 0, 0, 0, time.UTC)) // verão no norte
	cell := -1
	for i, cl := range w.Cells {
		if cl.Terrain == world.Land && cl.Biome == world.BiomeGrassland && cl.Lat > 35 && cl.Lat < 50 {
			cell = i
			break
		}
	}
	if cell < 0 {
		t.Fatal("sem campo temperado no norte")
	}
	frame := game.CellFrame(w, cell)
	target := frame.Point(1.3, -2.1)
	pos, shot := shotAt(target, 4, 0)
	pres.pos[p.ID] = pos
	if _, err := f.svc.RegisterPedia(f.ctx, p, "flower_sunflower", "BRA", "grassland", shot); err != nil {
		t.Errorf("girassol decorativo no campo, no verão: %v", err)
	}
	if _, err := f.svc.RegisterPedia(f.ctx, p, "flower_lotus", "BRA", "grassland", shot); !errors.Is(err, game.ErrTooFar) {
		t.Errorf("lótus (não nasce no campo) registrou: %v", err)
	}
	_, off := shotAt(target, 4, 45*math.Pi/180)
	if _, err := f.svc.RegisterPedia(f.ctx, p, "flower_sunflower", "BRA", "grassland", off); !errors.Is(err, game.ErrTooFar) {
		t.Errorf("girassol fora do centro registrou: %v", err)
	}
	f.at(time.Date(2027, 1, 15, 15, 0, 0, 0, time.UTC)) // inverno no norte: sem girassol
	if _, err := f.svc.RegisterPedia(f.ctx, p, "flower_sunflower", "BRA", "grassland", shot); !errors.Is(err, game.ErrTooFar) {
		t.Errorf("girassol no inverno registrou: %v", err)
	}
}

// Árvores de outono e com neve: o servidor sabe qual versão o cliente desenha (TreeVariant).
func TestPhotoSeasonTrees(t *testing.T) {
	f := newFixture(t)
	pres := &fakePresence{pos: map[int64]world.Vec3{}}
	f.svc.SetPresence(pres)
	p, _ := f.player(t, "Outonal", "BRA")
	w := f.svc.World()
	c := f.svc.Content()
	// Dias do outono e do inverno no norte, inclusive na virada (a árvore troca num dia
	// diferente de cada uma).
	days := []time.Time{}
	for d := 0; d < 200; d += 3 {
		days = append(days, time.Date(2027, 9, 10, 15, 0, 0, 0, time.UTC).AddDate(0, 0, d))
	}
	want := map[string]string{"autumn": "tree_autumn", "snow": "tree_snow"}
	done := map[string]bool{}
	refused := false
	for cell := 0; cell < len(w.Cells) && len(done) < 2; cell += 5 {
		cl := w.Cells[cell]
		if cl.Terrain != world.Land || cl.Lat < 35 || (cl.Biome != world.BiomeForest && cl.Biome != world.BiomeGrassland) {
			continue
		}
		for _, o := range game.GenerateObjects(w, c, cell) {
			if o.Kind != game.KindTree {
				continue
			}
			top := f.svc.ObjectPoint(&o)
			top = top.Add(top.Normalize().Scale(2))
			for _, d := range days {
				v := game.TreeVariant(&o, d, cl.Lat, cl.Biome)
				entry, ok := want[v]
				if v == "" && !refused && game.TreeVariant(&o, d.Add(24*time.Hour), cl.Lat, cl.Biome) == "" &&
					game.TreeVariant(&o, d.Add(-24*time.Hour), cl.Lat, cl.Biome) == "" {
					// Árvore de sempre: não é árvore de outono.
					f.at(d)
					pos, shot := shotAt(top, 8, 0)
					pres.pos[p.ID] = pos
					if _, err := f.svc.RegisterPedia(f.ctx, p, "tree_autumn", "BRA", "forest", shot); err == nil {
						// Pode haver outra árvore de outono enquadrada atrás; só conta se não houver.
						continue
					}
					refused = true
				}
				if !ok || done[v] {
					continue
				}
				f.at(d)
				pos, shot := shotAt(top, 8, 0)
				pres.pos[p.ID] = pos
				if _, err := f.svc.RegisterPedia(f.ctx, p, entry, "BRA", "forest", shot); err != nil {
					t.Errorf("%s em %s: %v", entry, d.Format("2006-01-02"), err)
				}
				done[v] = true
			}
			if len(done) == 2 {
				break
			}
		}
	}
	if !done["autumn"] || !done["snow"] {
		t.Errorf("não achei árvores das duas estações: %v", done)
	}
	if !refused {
		t.Error("nenhuma árvore de sempre foi recusada como árvore de outono")
	}
}

// As flores decorativas do cliente (client/data/decoracao.json) são de espécies que crescem
// naquele bioma e estação para o servidor (senão a foto delas não registraria).
func TestDecorFlowersAreRegistrable(t *testing.T) {
	raw, err := os.ReadFile("../../../client/data/decoracao.json")
	if err != nil {
		t.Skip("sem o cliente ao lado")
	}
	var dec struct {
		Flowers map[string][]struct {
			Models  []string `json:"models"`
			Seasons []string `json:"seasons"`
		} `json:"flowers"`
	}
	if err := json.Unmarshal(raw, &dec); err != nil {
		t.Fatal(err)
	}
	c := newFixture(t).svc.Content()
	byModel := map[string]string{}
	for _, it := range c.Items {
		if it.HasTag("flower") {
			byModel[it.Model] = it.ID
		}
	}
	seasonal := map[string]bool{"forest": true, "grassland": true, "tundra": true, "mountain": true}
	for biome, rules := range dec.Flowers {
		for _, r := range rules {
			for _, m := range r.Models {
				item, ok := byModel[m]
				if !ok {
					t.Errorf("%s: flor decorativa %s não é item", biome, m)
					continue
				}
				for _, se := range r.Seasons {
					if !seasonal[biome] {
						se = "none" // bioma sem estação
					}
					if !c.FlowerGrows(biome, item, []string{se}) {
						t.Errorf("%s: %s aparece em %s no cliente, mas não nasce ali para o servidor", biome, item, se)
					}
				}
			}
		}
	}
}

// Os mesmos casos de client/tests/test_estacoes.gd: a árvore de estação é igual nos dois
// lados (o servidor confere a foto pelo que o cliente desenha).
func TestTreeVariantCases(t *testing.T) {
	cases := []struct {
		id   int64
		unix int64
		lat  float64
		want string
	}{{1001, 1821268800, 48.0, ""}, {1001, 1821268800, -40.0, "snow"}, {1001, 1822132800, 48.0, "autumn"}, {1001, 1822132800, -40.0, ""}, {1001, 1825070400, 48.0, "autumn"}, {1001, 1825070400, -40.0, ""}, {1001, 1829131200, 48.0, "autumn"}, {1001, 1829131200, -40.0, ""}, {1001, 1829822400, 48.0, "snow"}, {1001, 1829822400, -40.0, ""}, {77777, 1821268800, 48.0, ""}, {77777, 1821268800, -40.0, ""}, {77777, 1822132800, 48.0, "autumn"}, {77777, 1822132800, -40.0, ""}, {77777, 1825070400, 48.0, "autumn"}, {77777, 1825070400, -40.0, ""}, {77777, 1829131200, 48.0, ""}, {77777, 1829131200, -40.0, ""}, {77777, 1829822400, 48.0, "snow"}, {77777, 1829822400, -40.0, ""}, {123456, 1821268800, 48.0, ""}, {123456, 1821268800, -40.0, "snow"}, {123456, 1822132800, 48.0, "autumn"}, {123456, 1822132800, -40.0, ""}, {123456, 1825070400, 48.0, "autumn"}, {123456, 1825070400, -40.0, ""}, {123456, 1829131200, 48.0, ""}, {123456, 1829131200, -40.0, ""}, {123456, 1829822400, 48.0, "snow"}, {123456, 1829822400, -40.0, ""}, {9999999, 1821268800, 48.0, ""}, {9999999, 1821268800, -40.0, "snow"}, {9999999, 1822132800, 48.0, "autumn"}, {9999999, 1822132800, -40.0, ""}, {9999999, 1825070400, 48.0, "autumn"}, {9999999, 1825070400, -40.0, ""}, {9999999, 1829131200, 48.0, "autumn"}, {9999999, 1829131200, -40.0, ""}, {9999999, 1829822400, 48.0, "snow"}, {9999999, 1829822400, -40.0, ""}, {640, 1821268800, 48.0, ""}, {640, 1821268800, -40.0, ""}, {640, 1822132800, 48.0, "autumn"}, {640, 1822132800, -40.0, ""}, {640, 1825070400, 48.0, "autumn"}, {640, 1825070400, -40.0, ""}, {640, 1829131200, 48.0, ""}, {640, 1829131200, -40.0, ""}, {640, 1829822400, 48.0, "snow"}, {640, 1829822400, -40.0, ""}, {1600000, 1821268800, 48.0, ""}, {1600000, 1821268800, -40.0, "snow"}, {1600000, 1822132800, 48.0, "autumn"}, {1600000, 1822132800, -40.0, ""}, {1600000, 1825070400, 48.0, "autumn"}, {1600000, 1825070400, -40.0, ""}, {1600000, 1829131200, 48.0, "autumn"}, {1600000, 1829131200, -40.0, ""}, {1600000, 1829822400, 48.0, "snow"}, {1600000, 1829822400, -40.0, ""}}
	for _, c := range cases {
		o := game.Object{ID: c.id, Kind: game.KindTree, Model: "CommonTree_2"}
		if got := game.TreeVariant(&o, time.Unix(c.unix, 0), c.lat, world.BiomeForest); got != c.want {
			t.Errorf("árvore %d em %d (lat %.0f): %q, esperava %q", c.id, c.unix, c.lat, got, c.want)
		}
	}
}

// Modo dev: com a data das estações forçada (como o cliente desenha), a árvore com neve
// daquela data registra, mesmo fora do inverno de verdade.
func TestPhotoDevSeason(t *testing.T) {
	f := newFixture(t)
	pres := &fakePresence{pos: map[int64]world.Vec3{}}
	f.svc.SetPresence(pres)
	p, _ := f.player(t, "Neve", "BRA")
	w := f.svc.World()
	winter := time.Date(2027, 1, 25, 12, 0, 0, 0, time.UTC)
	f.at(time.Date(2027, 7, 15, 15, 0, 0, 0, time.UTC)) // verão no norte, de verdade
	for cell := 0; cell < len(w.Cells); cell += 3 {
		cl := w.Cells[cell]
		if cl.Terrain != world.Land || cl.Lat < 40 || cl.Biome != world.BiomeForest {
			continue
		}
		for _, o := range game.GenerateObjects(w, f.svc.Content(), cell) {
			if game.TreeVariant(&o, winter, cl.Lat, cl.Biome) != "snow" {
				continue
			}
			top := f.svc.ObjectPoint(&o)
			top = top.Add(top.Normalize().Scale(2))
			pos, shot := shotAt(top, 8, 0)
			pres.pos[p.ID] = pos
			if _, err := f.svc.RegisterPedia(f.ctx, p, "tree_snow", "DEU", "forest", shot); !errors.Is(err, game.ErrTooFar) {
				t.Fatalf("árvore com neve no verão registrou: %v", err)
			}
			f.svc.DevSeason(p, winter)
			if _, err := f.svc.RegisterPedia(f.ctx, p, "tree_snow", "DEU", "forest", shot); err != nil {
				t.Fatalf("com o inverno forçado no modo dev: %v", err)
			}
			return
		}
	}
	t.Fatal("sem árvore com neve no inverno")
}
