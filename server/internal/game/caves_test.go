package game_test

import (
	"encoding/json"
	"errors"
	"math"
	"slices"
	"testing"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Cavernas determinísticas: mesma boca, mesmo desenho, em dois serviços diferentes; bocas em
// terra, fora de aeroportos e dos lotes; cavernas longe umas das outras.
func TestCavesAreDeterministic(t *testing.T) {
	a, b := newFixture(t), newFixture(t)
	ca, cb := a.svc.Caves(), b.svc.Caves()
	if len(ca) < 100 {
		t.Fatalf("poucas cavernas: %d", len(ca))
	}
	ja, _ := json.Marshal(ca)
	jb, _ := json.Marshal(cb)
	if string(ja) != string(jb) {
		t.Fatal("bocas diferentes em dois serviços")
	}
	for _, id := range []int{0, len(ca) / 2, len(ca) - 1} {
		la, _ := json.Marshal(a.svc.CaveLayoutOf(id))
		lb, _ := json.Marshal(b.svc.CaveLayoutOf(id))
		if string(la) != string(lb) {
			t.Fatalf("caverna %d com desenho diferente", id)
		}
	}
	countries := map[string]int{}
	for _, cv := range ca {
		c := a.world.Cells[cv.Cell]
		if c.Terrain != world.Land || a.svc.IsAirportCell(cv.Cell) {
			t.Fatalf("boca %d fora da terra ou no aeroporto", cv.ID)
		}
		f := game.CellFrame(a.world, cv.Cell)
		if !f.Inside(cv.X, cv.Y, 1.5) {
			t.Fatalf("boca %d fora da célula", cv.ID)
		}
		for s := 0; s < game.LotsPerCell; s++ {
			x0, y0, x1, y1 := game.SlotRect(s)
			if cv.X > x0-1 && cv.X < x1+1 && cv.Y > y0-1 && cv.Y < y1+1 {
				t.Fatalf("boca %d em cima de um lote", cv.ID)
			}
		}
		countries[cv.Country]++
	}
	if countries["BRA"] < 2 || countries["USA"] < 2 {
		t.Errorf("poucas bocas nos países grandes: BRA %d, USA %d", countries["BRA"], countries["USA"])
	}
	// As cavernas ficam longe do planeta e umas das outras (a área de interesse não mistura).
	for i := 0; i < len(ca); i += 7 {
		for j := i + 1; j < len(ca); j += 5 {
			fi, fj := a.svc.CaveFrameOf(&ca[i]), a.svc.CaveFrameOf(&ca[j])
			if fi.Origin.Sub(fj.Origin).Len() < 600 {
				t.Fatalf("cavernas %d e %d perto demais", i, j)
			}
		}
	}
}

// O desenho: salões ligados, sala do chefe no fim, degrau menor que o pulo, minérios e
// enfeites no chão, minérios mais duros só no fundo.
func TestCaveLayoutIsWalkable(t *testing.T) {
	f := newFixture(t)
	cc := f.svc.Content().Caves
	minRule := map[string]game.OreRule{}
	for _, o := range cc.Ores {
		minRule[o.ID] = o
	}
	sizes := map[int]bool{}
	for id := range f.svc.Caves() {
		l := f.svc.CaveLayoutOf(id)
		sizes[len(l.Rooms)] = true
		if !l.Rooms[len(l.Rooms)-1].Boss && !anyBoss(l) {
			t.Fatalf("caverna %d sem sala do chefe", id)
		}
		seen := map[int]bool{0: true}
		for k := 0; k < len(l.Rooms); k++ {
			for _, tn := range l.Tunnels {
				if seen[tn.A] {
					seen[tn.B] = true
				}
			}
		}
		if len(seen) != len(l.Rooms) {
			t.Fatalf("caverna %d com salão sem caminho", id)
		}
		for _, tn := range l.Tunnels {
			dy := math.Abs(l.Rooms[tn.A].Y - l.Rooms[tn.B].Y)
			if tn.Ledge && dy > 1.05 {
				t.Fatalf("caverna %d: degrau de %.2f (o pulo é 1,3)", id, dy)
			}
		}
		for _, p := range [][3]float64{l.Start, l.Exit, l.Furnace, l.Boss} {
			if y, ok := l.FloorAt(p[0], p[2]); !ok || math.Abs(y-p[1]) > 0.01 {
				t.Fatalf("caverna %d: ponto %v fora do chão", id, p)
			}
		}
		for _, o := range l.Ores {
			y, ok := l.FloorAt(o.X, o.Z)
			if !ok || math.Abs(y-o.Y) > 0.01 {
				t.Fatalf("caverna %d: minério %d fora do chão", id, o.ID)
			}
			if o.MinTier != minRule[o.Ore].MinTier {
				t.Fatalf("minério %s com picareta errada", o.Ore)
			}
		}
		for _, g := range l.Glow {
			if _, ok := l.FloorAt(g.X, g.Z); !ok {
				t.Fatalf("caverna %d: enfeite fora do chão", id)
			}
		}
	}
	if len(sizes) < 3 {
		t.Errorf("as cavernas deveriam ter tamanhos variados: %v", sizes)
	}
}

func anyBoss(l *game.CaveLayout) bool {
	for _, r := range l.Rooms {
		if r.Boss {
			return true
		}
	}
	return false
}

// findOre acha, em alguma caverna, um minério do tipo pedido.
func findOre(t *testing.T, f *fixture, ore string) (int, game.CaveOre) {
	t.Helper()
	for id := range f.svc.Caves() {
		for _, o := range f.svc.CaveLayoutOf(id).Ores {
			if o.Ore == ore {
				return id, o
			}
		}
	}
	t.Fatalf("nenhum minério %s", ore)
	return 0, game.CaveOre{}
}

// Picareta mínima, golpes, quantidade, um por dia por jogador.
func TestMiningTiersAndDailyLimit(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Mineira", "BRA")
	q, _ := f.player(t, "Vizinho", "BRA")
	cave, dia := findOre(t, f, "diamond")
	if _, err := f.svc.MineOre(f.ctx, p, cave, dia.ID); !errors.Is(err, game.ErrNoTool) {
		t.Fatalf("sem picareta: %v", err)
	}
	f.give(t, p, "pickaxe", 1)
	if _, err := f.svc.MineOre(f.ctx, p, cave, dia.ID); !errors.Is(err, game.ErrNoTool) {
		t.Fatalf("diamante com picareta de pedra: %v", err)
	}
	f.give(t, p, "pickaxe_iron", 1)
	need := game.OreHits(dia.Hits, 2, dia.MinTier)
	var res *game.MineResult
	var err error
	for k := 1; k <= need; k++ {
		if res, err = f.svc.MineOre(f.ctx, p, cave, dia.ID); err != nil {
			t.Fatal(err)
		}
		if res.Broken != (k == need) || res.Need != need {
			t.Fatalf("golpe %d: %+v", k, res)
		}
	}
	if count(res.Inventory, "diamond") < 1 {
		t.Fatalf("quebrou e não deu diamante: %+v", res.Inventory)
	}
	if _, err := f.svc.MineOre(f.ctx, p, cave, dia.ID); !errors.Is(err, game.ErrLimit) {
		t.Fatalf("segunda vez no mesmo dia: %v", err)
	}
	// Outro jogador tem o próprio limite; uma picareta melhor precisa de menos golpes e dá mais.
	f.give(t, q, "pickaxe_goblita", 1)
	better := game.OreHits(dia.Hits, 4, dia.MinTier)
	if better >= need {
		t.Fatalf("picareta melhor não diminuiu os golpes (%d × %d)", better, need)
	}
	for k := 0; k < better; k++ {
		res, err = f.svc.MineOre(f.ctx, q, cave, dia.ID)
		if err != nil {
			t.Fatal(err)
		}
	}
	if !res.Broken || count(res.Inventory, "diamond") < 1+(4-dia.MinTier) {
		t.Fatalf("picareta de goblita: %+v", res)
	}
	// No dia seguinte, de novo.
	f.clock.Advance(24 * time.Hour)
	for k := 0; k < need; k++ {
		if _, err := f.svc.MineOre(f.ctx, p, cave, dia.ID); err != nil {
			t.Fatalf("dia seguinte: %v", err)
		}
	}
	info, err := f.svc.CaveInfo(f.ctx, p, cave)
	if err != nil || len(info.Mined) != 1 {
		t.Fatalf("estado do dia: %+v %v", info, err)
	}
}

// Machado melhor dá mais madeira.
func TestBetterAxeGivesMoreWood(t *testing.T) {
	f := newFixture(t)
	p, me := f.player(t, "Lenhadora", "BRA")
	tree := f.findObject(t, p, me, func(o game.ObjectView) bool { return o.Kind == game.KindTree && o.Chop })
	f.give(t, p, "axe_diamond", 1)
	res, err := f.svc.Interact(f.ctx, p, tree.ID, "chop")
	if err != nil {
		t.Fatal(err)
	}
	if res.Gained[0].Count != 3 {
		t.Fatalf("machado de diamante deu %d madeira", res.Gained[0].Count)
	}
}

// Limite por item em cada espaço do bolso.
func TestStackLimitPerSlot(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Arrumadinha", "BRA")
	bar := f.svc.Content().Item("iron_bar").Stack
	f.give(t, p, "iron_bar", bar)
	me, _ := f.svc.Me(f.ctx, p)
	used := me.SlotsUsed
	f.give(t, p, "iron_bar", 1)
	me, _ = f.svc.Me(f.ctx, p)
	if me.SlotsUsed != used+1 {
		t.Fatalf("%d barras deveriam ocupar mais um espaço (%d → %d)", bar+1, used, me.SlotsUsed)
	}
	for _, it := range f.svc.Content().Items {
		if (it.Category == game.CategoryTool && it.Tool != "torch") || it.Category == game.CategoryWear {
			if it.Stack != 1 {
				t.Errorf("%s: ferramentas e roupas ocupam um espaço cada", it.ID)
			}
		}
	}
	if f.svc.Content().Item("stone").Stack != 999 || f.svc.Content().Item("diamond").Stack >= 999 {
		t.Error("limites: 999 para os básicos, menos para os raros")
	}
}

// Fornalha: gasta o minério e o carvão, espera, entrega; a bancada não derrete.
func TestFurnaceSmeltsWithWait(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Ferreira", "BRA")
	f.give(t, p, "iron_ore", 4)
	f.give(t, p, "coal", 2)
	if _, err := f.svc.Craft(f.ctx, p, "iron_bar", 1); err == nil {
		t.Fatal("a bancada derreteu ferro")
	}
	v, err := f.svc.Smelt(f.ctx, p, "iron_bar", 2, -1)
	if err != nil {
		t.Fatal(err)
	}
	if count(v.Inventory, "iron_ore") != 0 || count(v.Inventory, "coal") != 0 || len(v.Jobs) != 1 || v.Jobs[0].Ready {
		t.Fatalf("fornalha: %+v", v)
	}
	v, _ = f.svc.CollectFurnace(f.ctx, p, -1)
	if count(v.Inventory, "iron_bar") != 0 {
		t.Fatal("pegou antes de ficar pronto")
	}
	f.clock.Advance(20 * time.Second)
	v, err = f.svc.CollectFurnace(f.ctx, p, 0) // a fornalha antiga de uma caverna também vale
	if err != nil {
		t.Fatal(err)
	}
	if count(v.Inventory, "iron_bar") != 2 || len(v.Jobs) != 0 {
		t.Fatalf("depois da espera: %+v", v)
	}
}

// Baú: só o dono abre, guarda e tira; com coisas dentro não sai do lote.
func TestChestOnlyOwner(t *testing.T) {
	f := newFixture(t)
	p, me := f.player(t, "Guardadora", "BRA")
	q, _ := f.player(t, "Curioso", "BRA")
	f.give(t, p, "chest", 1)
	f.give(t, p, "wood", 10)
	res, err := f.svc.Place(f.ctx, p, me.Lot.ID, "chest", 2, 2, 0)
	if err != nil {
		t.Fatal(err)
	}
	var chest int64
	for _, pl := range res.Lot.Placements {
		if pl.Item == "chest" {
			chest = pl.ID
		}
	}
	if _, err := f.svc.Chest(f.ctx, q, chest); !errors.Is(err, game.ErrNotOwner) {
		t.Fatalf("outro jogador abriu o baú: %v", err)
	}
	v, err := f.svc.MoveChest(f.ctx, p, chest, "wood", 7, true)
	if err != nil {
		t.Fatal(err)
	}
	if count(v.Items, "wood") != 7 || count(v.Inventory, "wood") != 3 {
		t.Fatalf("guardar: %+v", v)
	}
	if _, err := f.svc.MoveChest(f.ctx, q, chest, "wood", 1, false); !errors.Is(err, game.ErrNotOwner) {
		t.Fatalf("outro jogador tirou do baú: %v", err)
	}
	if _, err := f.svc.Remove(f.ctx, p, chest); err == nil {
		t.Fatal("guardou o baú cheio")
	}
	v, err = f.svc.MoveChest(f.ctx, p, chest, "wood", 7, false)
	if err != nil || count(v.Items, "wood") != 0 || count(v.Inventory, "wood") != 10 {
		t.Fatalf("tirar: %+v %v", v, err)
	}
	if _, err := f.svc.MoveChest(f.ctx, p, chest, "wood", 99, true); err == nil {
		t.Fatal("guardou mais do que tinha")
	}
	if _, err := f.svc.Remove(f.ctx, p, chest); err != nil {
		t.Fatalf("guardar o baú vazio: %v", err)
	}
}

// Chefe: ataques com aviso, três acertos voltam ao começo (sem perder nada), dorme depois
// das sequências e a recompensa sai uma vez por dia.
func TestBossHitsResetAndDailyReward(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Corajosa", "BRA")
	q, _ := f.player(t, "Saltitante", "BRA")
	b := f.svc.Content().Caves.Boss
	cave := 0
	l := f.svc.CaveLayoutOf(cave)
	var room game.CaveRoom
	for _, r := range l.Rooms {
		if r.Boss {
			room = r
		}
	}
	still := [3]float64{room.X + 2, room.Y, room.Z} // p fica parado (leva os acertos)
	now := f.svc.Clock().Now()
	hits, reset, attacks := 0, false, 0
	jumping := true
	for step := 0; step < 2000 && !reset; step++ {
		now = now.Add(100 * time.Millisecond)
		// q pula sempre (no ar no impacto não leva acerto).
		qpos := [3]float64{room.X - 3, room.Y + 1.0, room.Z}
		if !jumping {
			qpos[1] = room.Y
		}
		for _, m := range f.svc.BossTick(cave, map[int64][3]float64{p.ID: still, q.ID: qpos}, now) {
			switch m.Data["t"] {
			case "boss_attack":
				attacks++
			case "boss_hit":
				if m.To == q.ID {
					t.Fatal("acertou quem estava no ar")
				}
				hits = m.Data["hits"].(int)
				if r, _ := m.Data["reset"].(bool); r {
					reset = true
				}
			}
		}
	}
	if !reset || attacks < b.Hits {
		t.Fatalf("três acertos deveriam voltar ao começo (acertos %d, ataques %d)", hits, attacks)
	}
	// Rodada até ele dormir; q desviou de todos.
	asleep := false
	for step := 0; step < 3000 && !asleep; step++ {
		now = now.Add(100 * time.Millisecond)
		for _, m := range f.svc.BossTick(cave, map[int64][3]float64{q.ID: {room.X - 3, room.Y + 1.0, room.Z}}, now) {
			if m.Data["t"] == "boss" && m.Data["phase"] == game.BossAsleep {
				asleep = true
			}
		}
	}
	if !asleep {
		t.Fatal("o chefe não dormiu depois das sequências")
	}
	res, err := f.svc.WakeBoss(f.ctx, q, cave)
	if err != nil || !res.Won || count(res.Inventory, b.Reward.Item) != b.Reward.Count || res.Reward != b.Reward.Coins {
		t.Fatalf("vitória: %+v %v", res, err)
	}
	if res.Achievement != b.Reward.Achievement || !res.PediaFirst {
		t.Errorf("conquista e Goblopédia: %+v", res)
	}
	res, _ = f.svc.WakeBoss(f.ctx, q, cave)
	if res.Reward != 0 || count(res.Inventory, b.Reward.Item) != b.Reward.Count {
		t.Fatalf("recompensa duas vezes no mesmo dia: %+v", res)
	}
	// p (que levou os acertos e não desviou nesta rodada) não vence.
	if res, _ := f.svc.WakeBoss(f.ctx, p, cave); res.Won {
		t.Fatal("venceu sem desviar")
	}
}

// Folclore: toda lenda tem onde aparecer (só no país dela), e aparece de vez em quando.
func TestLegendsAppearOnlyInTheirCountry(t *testing.T) {
	f := newFixture(t)
	for _, l := range f.svc.Content().Folklore.Legends {
		cells := f.svc.LegendCells(l.ID)
		if len(cells) == 0 {
			t.Errorf("%s não tem onde aparecer (%s)", l.ID, l.Country)
			continue
		}
		for _, c := range cells {
			if f.world.Cells[c].Country != l.Country {
				t.Fatalf("%s fora do país: célula %d é %s", l.ID, c, f.world.Cells[c].Country)
			}
		}
		// Em alguns dias, aparece pelo menos uma vez em algum lugar do país.
		seen := 0
		at := time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC)
		for k := 0; k < 3*24*20 && seen == 0; k++ {
			for _, c := range cells[:min(len(cells), 40)] {
				for _, sg := range f.svc.LegendsNear(c, 0, at) {
					if sg.Legend == l.ID {
						seen++
					}
				}
			}
			at = at.Add(3 * time.Minute)
		}
		if seen == 0 {
			t.Errorf("%s não apareceu em três dias", l.ID)
		}
	}
	// Mesma hora, mesma resposta (todo mundo vê igual).
	c := f.svc.LegendCells("legend_saci")[0]
	at := time.Date(2026, 6, 2, 15, 0, 0, 0, time.UTC)
	a, _ := json.Marshal(f.svc.LegendsNear(c, 2, at))
	b, _ := json.Marshal(f.svc.LegendsNear(c, 2, at))
	if string(a) != string(b) {
		t.Fatal("lendas diferentes na mesma hora")
	}
}

// Animais do mundo (fase 4.5): cada espécie nova aparece na região de origem, e só nela.
func TestRegionalAnimalsLiveWhereTheyBelong(t *testing.T) {
	f := newFixture(t)
	c := f.svc.Content()
	where := map[string]map[string]int{}
	for cell := range f.world.Cells {
		for _, a := range game.GenerateAnimals(f.world, c, cell, nil, nil) {
			if where[a.Species] == nil {
				where[a.Species] = map[string]int{}
			}
			where[a.Species][f.world.Cells[cell].Country]++
		}
	}
	for _, r := range c.Animals.Regional {
		for _, sp := range r.Species {
			if len(where[sp]) == 0 {
				t.Errorf("%s não aparece em lugar nenhum", sp)
			}
			if len(r.Countries) > 0 {
				for country := range where[sp] {
					if !slices.Contains(r.Countries, country) {
						t.Errorf("%s apareceu em %s", sp, country)
					}
				}
			}
		}
	}
	if where["kangaroo"]["AUS"] == 0 || where["panda"]["CHN"] == 0 || where["capybara"]["BRA"] == 0 {
		t.Errorf("canguru, panda ou capivara fora de casa: %v %v %v", where["kangaroo"], where["panda"], where["capybara"])
	}
}
