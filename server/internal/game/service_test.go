package game_test

import (
	"context"
	"errors"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/Dustyluc123/goblo/server/data"
	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/store/sqlitestore"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

var (
	worldOnce sync.Once
	testWorld *world.World
	testGeo   *world.Geography
	content   *game.Content
)

// sharedWorld gera o mundo de verdade (n = 50, raio 1000) uma vez para todos os testes.
func sharedWorld(t *testing.T) (*world.World, *game.Content) {
	t.Helper()
	worldOnce.Do(func() {
		geo, err := world.LoadGeography(data.NaturalEarth)
		if err != nil {
			panic(err)
		}
		testGeo = geo
		if testWorld, err = world.New(world.DefaultConfig, geo); err != nil {
			panic(err)
		}
		if content, err = game.LoadContent(data.Game); err != nil {
			panic(err)
		}
	})
	return testWorld, content
}

// start é uma quarta-feira às 15h UTC (12h em São Paulo pela longitude).
var start = time.Date(2026, 3, 4, 15, 0, 0, 0, time.UTC)

type fixture struct {
	svc   *game.Service
	clock *game.OffsetClock
	world *world.World
	ctx   context.Context
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	w, c := sharedWorld(t)
	store, err := sqlitestore.Open(context.Background(), filepath.Join(t.TempDir(), "teste.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	clock := game.NewOffsetClock(game.FixedClock{T: start})
	svc := game.NewService(w, c, store, clock)
	svc.SetGeography(testGeo)
	return &fixture{svc: svc, clock: clock, world: w, ctx: context.Background()}
}

func (f *fixture) player(t *testing.T, nick, country string) (*game.Player, *game.MeView) {
	t.Helper()
	p, token, err := f.svc.CreatePlayer(f.ctx, nick, country)
	if err != nil {
		t.Fatalf("criar %s: %v", nick, err)
	}
	if len(token) != 64 {
		t.Fatalf("token com tamanho %d", len(token))
	}
	if again, err := f.svc.Authenticate(f.ctx, token); err != nil || again.ID != p.ID {
		t.Fatalf("token não autentica: %v", err)
	}
	me, err := f.svc.Me(f.ctx, p)
	if err != nil {
		t.Fatal(err)
	}
	return p, me
}

func (f *fixture) give(t *testing.T, p *game.Player, item string, n int) {
	t.Helper()
	if _, err := f.svc.DevGive(f.ctx, p, item, n); err != nil {
		t.Fatalf("dar %s: %v", item, err)
	}
}

func count(me []game.StackView, item string) int {
	for _, s := range me {
		if s.Item == item {
			return s.Count
		}
	}
	return 0
}

func (f *fixture) inventory(t *testing.T, p *game.Player) []game.StackView {
	t.Helper()
	me, err := f.svc.Me(f.ctx, p)
	if err != nil {
		t.Fatal(err)
	}
	return me.Inventory
}

// findObject acha, perto do lote do jogador, um objeto que satisfaz ok.
func (f *fixture) findObject(t *testing.T, p *game.Player, me *game.MeView, ok func(o game.ObjectView) bool) game.ObjectView {
	t.Helper()
	cells := []int{me.Lot.Cell}
	cells = append(cells, f.world.Cells[me.Lot.Cell].Neighbors...)
	for _, nb := range f.world.Cells[me.Lot.Cell].Neighbors {
		cells = append(cells, f.world.Cells[nb].Neighbors...)
	}
	objs, _, err := f.svc.Objects(f.ctx, p, cells)
	if err != nil {
		t.Fatal(err)
	}
	for _, o := range objs {
		if ok(o) {
			return o
		}
	}
	t.Fatalf("nenhum objeto adequado perto da célula %d", me.Lot.Cell)
	return game.ObjectView{}
}

func TestCreatePlayerGetsLotInOwnCountry(t *testing.T) {
	f := newFixture(t)
	_, me := f.player(t, "Lucas", "BRA")
	if me.Lot == nil {
		t.Fatal("jogador sem lote")
	}
	cell := f.world.Cells[me.Lot.Cell]
	if cell.Country != "BRA" {
		t.Fatalf("lote no país %s, esperado BRA", cell.Country)
	}
	switch cell.Biome {
	case world.BiomeGrassland, world.BiomeForest, world.BiomeTropicalForest, world.BiomeBeach:
	default:
		t.Fatalf("lote em bioma %s; o Brasil tem biomas agradáveis de sobra", cell.Biome)
	}
	if len(me.Lot.Placements) != 2 || me.Lot.Placements[0].Item != "workbench" || me.Lot.Placements[1].Item != "sell_box" {
		t.Fatalf("o lote precisa começar com a bancada e a caixa de vendas: %+v", me.Lot.Placements)
	}
	if me.Lot.Owner != "Lucas" {
		t.Fatalf("dono %q", me.Lot.Owner)
	}
}

func TestLotPrefersPleasantBiomes(t *testing.T) {
	f := newFixture(t)
	// China e Austrália têm muito deserto e montanha, mas também campo e floresta.
	for _, country := range []string{"CHN", "AUS", "USA", "RUS"} {
		_, me := f.player(t, "Jogador "+country, country)
		b := f.world.Cells[me.Lot.Cell].Biome
		if b == world.BiomeDesert || b == world.BiomeIce || b == world.BiomeTundra || b == world.BiomeMountain {
			t.Errorf("%s: lote em %s, havendo opção melhor", country, b)
		}
	}
	// A Groenlândia só tem gelo e tundra: mesmo assim o jogador ganha lote lá.
	_, me := f.player(t, "Inuk", "GRL")
	if f.world.Cells[me.Lot.Cell].Country != "GRL" {
		t.Fatal("jogador da Groenlândia fora da Groenlândia")
	}
	if _, _, err := f.svc.CreatePlayer(f.ctx, "Ninguém", "XYZ"); !errors.Is(err, game.ErrCountry) {
		t.Fatalf("país inválido deveria falhar: %v", err)
	}
}

func TestTwoPlayersNeverShareALot(t *testing.T) {
	f := newFixture(t)
	// Um país pequeno, para esgotar os lotes: o de menos células.
	cells := map[string]int{}
	for _, c := range f.world.Cells {
		if c.Terrain == world.Land && c.Country != "" {
			cells[c.Country]++
		}
	}
	small, slots := "", 0
	for code, n := range cells {
		if n > 3 {
			continue // os pequenos bastam (e o teste fica rápido)
		}
		total := f.svc.UsableLots(code)
		if total >= 3 && (small == "" || total < slots || (total == slots && code < small)) {
			small, slots = code, total
		}
	}
	var mu sync.Mutex
	seen := map[int64]string{}
	var wg sync.WaitGroup
	errs := make(chan error, slots+5)
	for i := 0; i < slots+5; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			nick := "Vizinho " + string(rune('A'+i%26)) + string(rune('a'+i/26))
			p, _, err := f.svc.CreatePlayer(f.ctx, nick, small)
			if err != nil {
				errs <- err
				return
			}
			me, err := f.svc.Me(f.ctx, p)
			if err != nil {
				errs <- err
				return
			}
			mu.Lock()
			defer mu.Unlock()
			if other, dup := seen[me.Lot.ID]; dup {
				t.Errorf("lote %d dado para %s e %s", me.Lot.ID, other, nick)
			}
			seen[me.Lot.ID] = nick
		}(i)
	}
	wg.Wait()
	close(errs)
	noLot := 0
	for err := range errs {
		if !errors.Is(err, game.ErrNoLot) {
			t.Fatalf("erro inesperado: %v", err)
		}
		noLot++
	}
	if len(seen) != slots || noLot != 5 {
		t.Fatalf("%s tem %d lotes: %d jogadores ganharam lote, %d ficaram sem", small, slots, len(seen), noLot)
	}
}

func TestDailyLimitsAndRolloverAt5AM(t *testing.T) {
	f := newFixture(t)
	p, me := f.player(t, "Lenhador", "BRA")
	f.give(t, p, "axe", 1)
	f.give(t, p, "pickaxe", 1)
	tree := f.findObject(t, p, me, func(o game.ObjectView) bool { return o.Kind == game.KindTree && o.Chop && o.Drop == "branch" })
	rock := f.findObject(t, p, me, func(o game.ObjectView) bool { return o.Kind == game.KindRock })

	res, err := f.svc.Interact(f.ctx, p, tree.ID, "shake")
	if err != nil {
		t.Fatal(err)
	}
	if n := count(res.Gained, "branch"); n < 1 || n > 3 {
		t.Fatalf("sacudir deu %d galhos, esperado de 1 a 3", n)
	}
	if _, err := f.svc.Interact(f.ctx, p, tree.ID, "shake"); !errors.Is(err, game.ErrLimit) {
		t.Fatalf("segunda sacudida no dia deveria falhar: %v", err)
	}
	for i := 0; i < 3; i++ {
		res, err := f.svc.Interact(f.ctx, p, tree.ID, "chop")
		if err != nil || count(res.Gained, "wood") != 1 {
			t.Fatalf("golpe %d de machado: %v %+v", i+1, err, res)
		}
	}
	if _, err := f.svc.Interact(f.ctx, p, tree.ID, "chop"); !errors.Is(err, game.ErrLimit) {
		t.Fatalf("quarto golpe de machado deveria falhar: %v", err)
	}
	for i := 0; i < 3; i++ {
		if res, err := f.svc.Interact(f.ctx, p, rock.ID, "mine"); err != nil || count(res.Gained, "stone") != 1 {
			t.Fatalf("golpe %d de picareta: %v", i+1, err)
		}
	}
	if _, err := f.svc.Interact(f.ctx, p, rock.ID, "mine"); !errors.Is(err, game.ErrLimit) {
		t.Fatalf("quarto golpe de picareta deveria falhar: %v", err)
	}
	inv := f.inventory(t, p)
	if count(inv, "wood") != 3 || count(inv, "stone") != 3 {
		t.Fatalf("inventário: %+v", inv)
	}

	// Um minuto antes das 5h locais ainda é o mesmo dia; às 5h vira.
	lon := f.world.Cells[me.Lot.Cell].Lon
	next := game.NextRollover(f.clock.Now(), lon)
	f.clock.Advance(next.Sub(f.clock.Now()) - time.Minute)
	if _, err := f.svc.Interact(f.ctx, p, tree.ID, "shake"); !errors.Is(err, game.ErrLimit) {
		t.Fatalf("antes das 5h ainda deveria estar no limite: %v", err)
	}
	local := f.clock.Now().Add(time.Duration(lon*240) * time.Second)
	if local.Hour() != 4 || local.Minute() != 59 {
		t.Fatalf("hora local antes da virada: %s", local.Format("15:04"))
	}
	f.clock.Advance(time.Minute)
	if _, err := f.svc.Interact(f.ctx, p, tree.ID, "shake"); err != nil {
		t.Fatalf("depois das 5h a árvore deveria dar galhos de novo: %v", err)
	}
	for i := 0; i < 3; i++ {
		if _, err := f.svc.Interact(f.ctx, p, tree.ID, "chop"); err != nil {
			t.Fatalf("novo dia, golpe %d: %v", i+1, err)
		}
	}
}

func TestToolsAreRequired(t *testing.T) {
	f := newFixture(t)
	p, me := f.player(t, "Sem Ferramenta", "BRA")
	tree := f.findObject(t, p, me, func(o game.ObjectView) bool { return o.Kind == game.KindTree && o.Chop })
	rock := f.findObject(t, p, me, func(o game.ObjectView) bool { return o.Kind == game.KindRock })
	if _, err := f.svc.Interact(f.ctx, p, tree.ID, "chop"); !errors.Is(err, game.ErrNoTool) {
		t.Fatalf("cortar sem machado: %v", err)
	}
	if _, err := f.svc.Interact(f.ctx, p, rock.ID, "mine"); !errors.Is(err, game.ErrNoTool) {
		t.Fatalf("minerar sem picareta: %v", err)
	}
	if _, err := f.svc.Interact(f.ctx, p, rock.ID, "pick"); !errors.Is(err, game.ErrWrongAction) {
		t.Fatalf("pegar pedra grande: %v", err)
	}
}

func TestCollectionsArePerPlayer(t *testing.T) {
	f := newFixture(t)
	a, meA := f.player(t, "Ana", "BRA")
	b, _ := f.player(t, "Beto", "BRA")
	tree := f.findObject(t, a, meA, func(o game.ObjectView) bool { return o.Kind == game.KindTree && o.Drop == "branch" })
	flower := f.findObject(t, a, meA, func(o game.ObjectView) bool { return o.Kind == game.KindFlower })

	if _, err := f.svc.Interact(f.ctx, a, tree.ID, "shake"); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Interact(f.ctx, b, tree.ID, "shake"); err != nil {
		t.Fatalf("a sacudida da Ana não pode gastar a do Beto: %v", err)
	}
	res, err := f.svc.Interact(f.ctx, a, flower.ID, "pick")
	if err != nil || count(res.Gained, flower.Item) != 1 {
		t.Fatalf("colher flor: %v %+v", err, res)
	}
	stateOf := func(p *game.Player) map[string]int {
		objs, _, err := f.svc.Objects(f.ctx, p, []int{flower.Cell})
		if err != nil {
			t.Fatal(err)
		}
		for _, o := range objs {
			if o.ID == flower.ID {
				return o.State
			}
		}
		t.Fatal("flor sumiu da lista")
		return nil
	}
	if stateOf(a)["pick"] != 1 {
		t.Fatal("para a Ana, a flor deveria aparecer como colhida")
	}
	if len(stateOf(b)) != 0 {
		t.Fatal("para o Beto, a flor deveria continuar lá")
	}
	if _, err := f.svc.Interact(f.ctx, b, flower.ID, "pick"); err != nil {
		t.Fatalf("o Beto também pode colher: %v", err)
	}
}

func TestCraftConsumesMaterials(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Artesã", "BRA")
	if _, err := f.svc.Craft(f.ctx, p, "axe", 1); !errors.Is(err, game.ErrMissingMaterials) {
		t.Fatalf("fabricar sem nada: %v", err)
	}
	f.give(t, p, "branch", 4)
	f.give(t, p, "stone", 1)
	if _, err := f.svc.Craft(f.ctx, p, "axe", 1); !errors.Is(err, game.ErrMissingMaterials) {
		t.Fatalf("faltando 1 galho: %v", err)
	}
	if inv := f.inventory(t, p); count(inv, "branch") != 4 || count(inv, "stone") != 1 {
		t.Fatalf("fabricação que falhou não pode gastar nada: %+v", inv)
	}
	f.give(t, p, "branch", 3)
	res, err := f.svc.Craft(f.ctx, p, "axe", 1)
	if err != nil {
		t.Fatal(err)
	}
	if count(res.Inventory, "axe") != 1 || count(res.Inventory, "branch") != 2 || count(res.Inventory, "stone") != 0 {
		t.Fatalf("depois do machado: %+v", res.Inventory)
	}
	// Grupo "#flower": aceita cores misturadas.
	f.give(t, p, "flower_red", 2)
	f.give(t, p, "flower_white", 1)
	f.give(t, p, "branch", 1)
	res, err = f.svc.Craft(f.ctx, p, "hedge", 1)
	if err != nil {
		t.Fatal(err)
	}
	flowers := count(res.Inventory, "flower_red") + count(res.Inventory, "flower_white")
	if count(res.Inventory, "hedge") != 1 || flowers != 1 || count(res.Inventory, "branch") != 0 {
		t.Fatalf("depois da cerca viva: %+v", res.Inventory)
	}
	if _, err := f.svc.Craft(f.ctx, p, "nao-existe", 1); !errors.Is(err, game.ErrNotFound) {
		t.Fatalf("receita desconhecida: %v", err)
	}
}

func TestInventoryHas20Slots(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Acumulador", "BRA")
	f.give(t, p, "stone", 99*19)
	f.give(t, p, "wood", 99)
	if _, err := f.svc.DevGive(f.ctx, p, "branch", 1); !errors.Is(err, game.ErrInventoryFull) {
		t.Fatalf("21º espaço deveria falhar: %v", err)
	}
	f.give(t, p, "wood", -1)
	f.give(t, p, "wood", 1) // empilha no mesmo espaço
}

func TestPlacementRules(t *testing.T) {
	f := newFixture(t)
	a, meA := f.player(t, "Dona", "BRA")
	_, meB := f.player(t, "Vizinha", "BRA")
	f.give(t, a, "lantern", 2)
	f.give(t, a, "fountain", 1)

	if _, err := f.svc.Place(f.ctx, a, meB.Lot.ID, "lantern", 5, 5, 0); !errors.Is(err, game.ErrNotOwner) {
		t.Fatalf("colocar no lote dos outros: %v", err)
	}
	if _, err := f.svc.Place(f.ctx, a, meA.Lot.ID, "lantern", 16, 0, 0); !errors.Is(err, game.ErrOutOfLot) {
		t.Fatalf("fora da grade: %v", err)
	}
	if _, err := f.svc.Place(f.ctx, a, meA.Lot.ID, "fountain", 12, 3, 0); !errors.Is(err, game.ErrOutOfLot) {
		t.Fatalf("fonte 6×6 passando da borda: %v", err)
	}
	if _, err := f.svc.Place(f.ctx, a, meA.Lot.ID, "lantern", 12, 2, 0); !errors.Is(err, game.ErrOverlap) {
		t.Fatalf("em cima da bancada: %v", err)
	}
	if _, err := f.svc.Place(f.ctx, a, meA.Lot.ID, "lantern", 4, 4, 1); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Place(f.ctx, a, meA.Lot.ID, "fountain", 2, 2, 0); !errors.Is(err, game.ErrOverlap) {
		t.Fatalf("fonte em cima do lampião: %v", err)
	}
	if _, err := f.svc.Place(f.ctx, a, meA.Lot.ID, "fence", 0, 0, 0); !errors.Is(err, game.ErrMissingMaterials) {
		t.Fatalf("colocar o que não tem: %v", err)
	}
	res, err := f.svc.Place(f.ctx, a, meA.Lot.ID, "fountain", 6, 6, 0)
	if err != nil {
		t.Fatal(err)
	}
	if count(res.Inventory, "fountain") != 0 || count(res.Inventory, "lantern") != 1 || len(res.Lot.Placements) != 4 {
		t.Fatalf("depois de colocar: %+v", res)
	}
	// Guardar de volta.
	var lantern int64
	for _, pl := range res.Lot.Placements {
		if pl.Item == "lantern" {
			lantern = pl.ID
		}
	}
	if _, err := f.svc.Remove(f.ctx, a, meB.Lot.Placements[0].ID); !errors.Is(err, game.ErrNotOwner) {
		t.Fatalf("guardar a bancada da vizinha: %v", err)
	}
	res, err = f.svc.Remove(f.ctx, a, lantern)
	if err != nil || count(res.Inventory, "lantern") != 2 {
		t.Fatalf("guardar lampião: %v %+v", err, res)
	}
}

func TestHouseIsReadyOnlyAfterRollover(t *testing.T) {
	f := newFixture(t)
	p, me := f.player(t, "Construtora", "BRA")
	if _, err := f.svc.BuildHouse(f.ctx, p, me.Lot.ID, 5, 6, 0); !errors.Is(err, game.ErrMissingMaterials) {
		t.Fatalf("casa sem madeira: %v", err)
	}
	f.give(t, p, "wood", 10)
	if _, err := f.svc.BuildHouse(f.ctx, p, me.Lot.ID, 9, 0, 0); !errors.Is(err, game.ErrOutOfLot) {
		t.Fatalf("barraca passando da borda: %v", err)
	}
	if _, err := f.svc.BuildHouse(f.ctx, p, me.Lot.ID, 8, 0, 0); !errors.Is(err, game.ErrOverlap) {
		t.Fatalf("barraca em cima da bancada: %v", err)
	}
	res, err := f.svc.BuildHouse(f.ctx, p, me.Lot.ID, 5, 6, 0)
	if err != nil {
		t.Fatal(err)
	}
	if h := res.Lot.House; h == nil || h.Level != 0 || h.PendingLevel != 1 || count(res.Inventory, "wood") != 0 {
		t.Fatalf("obra recém-começada: %+v", res.Lot.House)
	}
	f.give(t, p, "wood", 30)
	f.give(t, p, "stone", 20)
	if _, err := f.svc.BuildHouse(f.ctx, p, me.Lot.ID, 0, 0, 0); !errors.Is(err, game.ErrBusy) {
		t.Fatalf("melhorar com obra em andamento: %v", err)
	}
	lon := f.world.Cells[me.Lot.Cell].Lon
	next := game.NextRollover(f.clock.Now(), lon)
	f.clock.Advance(next.Sub(f.clock.Now()) - time.Second)
	me, _ = f.svc.Me(f.ctx, p)
	if me.Lot.House.Level != 0 {
		t.Fatal("a casa ficou pronta antes da virada do dia")
	}
	f.clock.Advance(time.Second)
	me, _ = f.svc.Me(f.ctx, p)
	if me.Lot.House.Level != 1 || me.Lot.House.PendingLevel != 0 || me.Lot.House.Name != "Barraca" {
		t.Fatalf("depois da virada: %+v", me.Lot.House)
	}
	// Melhoria: cresce no mesmo lugar.
	res, err = f.svc.BuildHouse(f.ctx, p, me.Lot.ID, 0, 0, 0)
	if err != nil {
		t.Fatal(err)
	}
	// A barraca continua no lugar durante a obra; a casinha (9 × 7) cresce para os lados,
	// com a porta (sul) no mesmo lugar.
	if h := res.Lot.House; h.X != 5 || h.Y != 6 || h.PendingX != 4 || h.PendingY != 6 || h.PendingLevel != 2 || h.Level != 1 {
		t.Fatalf("melhoria: %+v", h)
	}
	if _, err := f.svc.DevFinishHouse(f.ctx, p); err != nil {
		t.Fatal(err)
	}
	me, _ = f.svc.Me(f.ctx, p)
	if h := me.Lot.House; h.Level != 2 || h.X != 4 || h.Y != 6 {
		t.Fatalf("dev deveria concluir a obra na hora, no lugar da obra: %+v", h)
	}
}

func TestNicknames(t *testing.T) {
	f := newFixture(t)
	for _, bad := range []string{"ab", "um apelido muito comprido", "P0RR4", "m.e.r.d.a", "Caralhoo", "fdp", "a<b>c"} {
		if _, _, err := f.svc.CreatePlayer(f.ctx, bad, "BRA"); !errors.Is(err, game.ErrNicknameInvalid) {
			t.Errorf("%q deveria ser recusado: %v", bad, err)
		}
	}
	for _, ok := range []string{"Curió", "Cuca", "Ana Paula", "Zé_123", "computador", "Pauline"} {
		if _, _, err := f.svc.CreatePlayer(f.ctx, ok, "BRA"); err != nil {
			t.Errorf("%q deveria ser aceito: %v", ok, err)
		}
	}
	if _, _, err := f.svc.CreatePlayer(f.ctx, "ana paula", "BRA"); !errors.Is(err, game.ErrNicknameTaken) {
		t.Fatalf("apelido repetido (sem diferenciar maiúsculas): %v", err)
	}
}

func TestObjectsAreDeterministic(t *testing.T) {
	w, c := sharedWorld(t)
	amazon := w.CellAt(-3, -60).ID
	a := game.GenerateObjects(w, c, amazon)
	b := game.GenerateObjects(w, c, amazon)
	if len(a) < 10 {
		t.Fatalf("Amazônia com só %d objetos", len(a))
	}
	trees := 0
	for i := range a {
		if a[i] != b[i] {
			t.Fatalf("objeto %d diferente entre duas gerações", i)
		}
		if a[i].ID != game.ObjectID(amazon, i) || game.ObjectCell(a[i].ID) != amazon {
			t.Fatalf("id instável: %d", a[i].ID)
		}
		if a[i].Kind == game.KindTree {
			trees++
		}
	}
	if trees < 6 {
		t.Fatalf("floresta tropical com só %d árvores", trees)
	}
	// Todos dentro da célula e sem objetos encavalados.
	frame := game.CellFrame(w, amazon)
	for i, o := range a {
		if !frame.Inside(o.X, o.Y, 0) {
			t.Fatalf("objeto %d fora da célula", i)
		}
		for j := i + 1; j < len(a); j++ {
			dx, dy := o.X-a[j].X, o.Y-a[j].Y
			if dx*dx+dy*dy < 0.25 {
				t.Fatalf("objetos %d e %d encavalados", i, j)
			}
		}
	}
	// Oceano não tem objetos; o deserto tem cactos e nenhuma flor.
	if n := len(game.GenerateObjects(w, c, w.CellAt(0, -30).ID)); n != 0 {
		t.Fatalf("oceano com %d objetos", n)
	}
	for _, o := range game.GenerateObjects(w, c, w.CellAt(23, 13).ID) {
		if o.Kind == game.KindFlower {
			t.Fatal("flor no Saara")
		}
	}
}

func TestObjectsDisappearUnderOccupiedLots(t *testing.T) {
	f := newFixture(t)
	p, me := f.player(t, "Moradora", "BRA")
	all := game.GenerateObjects(f.world, content, me.Lot.Cell)
	objs, _, err := f.svc.Objects(f.ctx, p, []int{me.Lot.Cell})
	if err != nil {
		t.Fatal(err)
	}
	x0, y0 := me.Lot.X0, me.Lot.Y0
	for _, o := range objs {
		if o.X > x0 && o.X < x0+game.LotSize && o.Y > y0 && o.Y < y0+game.LotSize {
			t.Fatalf("objeto %d dentro do lote ocupado", o.ID)
		}
	}
	if len(objs) >= len(all) {
		t.Fatalf("o lote deveria ter limpado algum objeto (%d de %d)", len(objs), len(all))
	}
}

func TestLotSlotsFitInsideCells(t *testing.T) {
	w, _ := sharedWorld(t)
	total, cells, four := 0, 0, 0
	for i, c := range w.Cells {
		if c.Terrain != world.Land {
			continue
		}
		slots := game.LotSlots(w, i)
		frame := game.CellFrame(w, i)
		for _, s := range slots {
			for _, p := range [][2]float64{{s.X0, s.Y0}, {s.X0 + game.LotSize, s.Y0 + game.LotSize}} {
				if !frame.Inside(p[0], p[1], 0) {
					t.Fatalf("lote %d sai da célula %d", s.ID, i)
				}
			}
		}
		total += len(slots)
		cells++
		if len(slots) == 4 {
			four++
		}
	}
	if float64(four)/float64(cells) < 0.85 {
		t.Fatalf("só %d de %d células de terra comportam 4 lotes", four, cells)
	}
	t.Logf("%d lotes em %d células de terra (%d com 4 lotes)", total, cells, four)
}
