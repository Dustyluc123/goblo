package game_test

import (
	"math"
	"testing"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Temperatura por lugar e hora (fase 4.0): Manaus quente, Ushuaia fria em julho, Saara
// quente ao meio-dia e frio de madrugada, Antártida gelada, montanha mais fria que a
// planície vizinha.
func TestTemperatureByPlaceAndTime(t *testing.T) {
	f := newFixture(t)
	at := func(lat, lon float64, utc time.Time) float64 {
		v, _ := f.svc.TemperatureAt(lat, lon, utc)
		return v
	}
	// Hora local ≈ UTC + lon/15.
	local := func(y int, m time.Month, d, hour int, lon float64) time.Time {
		return time.Date(y, m, d, hour, 0, 0, 0, time.UTC).Add(-time.Duration(lon / 15 * float64(time.Hour)))
	}
	for _, m := range []time.Month{time.January, time.July} {
		for _, h := range []int{3, 15} {
			if v := at(-3.1, -60.0, local(2026, m, 15, h, -60)); v < 22 || v > 36 {
				t.Errorf("Manaus em %s às %dh: %.1f °C (devia ser quente)", m, h, v)
			}
		}
	}
	if v := at(-54.8, -68.3, local(2026, time.July, 15, 15, -68.3)); v > 5 {
		t.Errorf("Ushuaia em julho à tarde: %.1f °C (devia ser fria)", v)
	}
	if v := at(23.0, 13.0, local(2026, time.January, 15, 12, 13)); v < 35 {
		t.Errorf("Saara ao meio-dia (janeiro): %.1f °C (devia ser muito quente)", v)
	}
	if v := at(23.0, 13.0, local(2026, time.January, 15, 0, 13)); v > 20 {
		t.Errorf("Saara à meia-noite (janeiro): %.1f °C (devia ser frio)", v)
	}
	if v := at(23.0, 13.0, local(2026, time.July, 15, 12, 13)); v < 40 {
		t.Errorf("Saara ao meio-dia (julho): %.1f °C", v)
	}
	for _, m := range []time.Month{time.January, time.July} {
		if v := at(-80, 30, local(2026, m, 15, 15, 30)); v > -5 {
			t.Errorf("Antártida em %s: %.1f °C (devia ser gelada)", m, v)
		}
	}
	// Montanha × planície vizinha: a mesma hora, a célula mais alta é mais fria.
	w := f.world
	checked := 0
	when := time.Date(2026, 1, 15, 15, 0, 0, 0, time.UTC)
	for i := range w.Cells {
		c := &w.Cells[i]
		if c.Terrain != world.Land || c.Biome != world.BiomeMountain || checked >= 20 {
			continue
		}
		for _, nb := range c.Neighbors {
			n := &w.Cells[nb]
			if n.Terrain == world.Land && n.Biome != world.BiomeMountain && n.Biome != world.BiomeDesert && n.Height < c.Height {
				if f.svc.CellTemperature(i, when) >= f.svc.CellTemperature(nb, when) {
					t.Errorf("montanha %d (%.1f °C) não é mais fria que a vizinha %d (%.1f °C)", i,
						f.svc.CellTemperature(i, when), nb, f.svc.CellTemperature(nb, when))
				}
				checked++
				break
			}
		}
	}
	if checked == 0 {
		t.Fatal("nenhuma montanha com planície vizinha")
	}
}

func ptr(v float64) *float64 { return &v }

// As necessidades caem no ritmo do body.json, mais rápido no calor e correndo, e não mudam
// com o jogo fechado.
func TestNeedsDecayAndStopWhenClosed(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Sedento", "BRA")
	n := f.svc.Content().Body.Needs
	pos := world.LatLonToVec(-15.8, -47.9).Scale(f.world.Radius)
	cell := f.world.FindCell(pos, -1)
	if _, err := f.svc.DevBody(f.ctx, p, game.DevBodyRequest{Temp: ptr(20)}); err != nil {
		t.Fatal(err)
	}
	v, err := f.svc.BodyTick(f.ctx, p.ID, 600, pos, cell, false) // 10 minutos, confortável
	if err != nil {
		t.Fatal(err)
	}
	if want := n.Max - n.ThirstPerMin*10; math.Abs(v.Thirst-want) > 0.11 {
		t.Errorf("sede depois de 10 min: %.1f, esperado %.1f", v.Thirst, want)
	}
	if want := n.Max - n.HungerPerMin*10; math.Abs(v.Hunger-want) > 0.11 {
		t.Errorf("fome depois de 10 min: %.1f, esperado %.1f", v.Hunger, want)
	}
	if v.Comfort != n.Max {
		t.Errorf("conforto com 20 °C: %.1f", v.Comfort)
	}
	// Calor: a sede cai mais rápido e o conforto cai.
	f.svc.DevBody(f.ctx, p, game.DevBodyRequest{Temp: ptr(38)})
	hot, _ := f.svc.BodyTick(f.ctx, p.ID, 60, pos, cell, false)
	if d := v.Thirst - hot.Thirst; math.Abs(d-(n.ThirstPerMin+n.ThirstHotExtra)) > 0.11 {
		t.Errorf("sede no calor caiu %.2f por minuto", d)
	}
	if hot.Comfort >= n.Max || !hot.Hot {
		t.Errorf("38 °C sem roupa de calor: conforto %.1f, hot %v", hot.Comfort, hot.Hot)
	}
	// Correndo: a fome cai mais rápido.
	run, _ := f.svc.BodyTick(f.ctx, p.ID, 60, pos, cell, true)
	if d := hot.Hunger - run.Hunger; math.Abs(d-(n.HungerPerMin+n.HungerRunExtra)) > 0.11 {
		t.Errorf("fome correndo caiu %.2f por minuto", d)
	}
	// Sai do jogo (grava e esquece), passa uma hora, volta: tudo igual.
	if err := f.svc.SaveBody(f.ctx, p.ID, true); err != nil {
		t.Fatal(err)
	}
	f.clock.Advance(time.Hour)
	back, err := f.svc.Body(f.ctx, p)
	if err != nil {
		t.Fatal(err)
	}
	if back.Thirst != run.Thirst || back.Hunger != run.Hunger || back.Comfort != run.Comfort {
		t.Errorf("com o jogo fechado mudou: antes %+v, depois %+v", run, back)
	}
}

// Níveis de velocidade: ótimo (tudo cheio) dá bônus, neutro igual, crítico (qualquer no
// mínimo) mais devagar e zonzo com fome. O modo tranquilo desliga tudo.
func TestSpeedLevelsAndQuietMode(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Corredor", "BRA")
	sp := f.svc.Content().Body.Speed
	check := func(level string, speed float64, what string) game.BodyView {
		t.Helper()
		v, err := f.svc.Body(f.ctx, p)
		if err != nil {
			t.Fatal(err)
		}
		if v.Level != level || math.Abs(v.Speed-speed) > 1e-9 {
			t.Fatalf("%s: nível %s, velocidade %.3f (esperado %s, %.3f)", what, v.Level, v.Speed, level, speed)
		}
		return *v
	}
	check(game.LevelOptimal, sp.Optimal, "tudo cheio")
	f.svc.DevBody(f.ctx, p, game.DevBodyRequest{Need: "thirst", Value: ptr(50)})
	check(game.LevelNeutral, sp.Neutral, "sede pela metade")
	f.svc.DevBody(f.ctx, p, game.DevBodyRequest{Need: "hunger", Value: ptr(0)})
	if v := check(game.LevelCritical, sp.Critical, "fome no mínimo"); !v.Dizzy {
		t.Error("fome no mínimo sem tontura")
	}
	if got := f.svc.SpeedFactor(p.ID); got < sp.Critical {
		t.Errorf("folga da velocidade %.2f", got)
	}
	// Bônus da comida multiplica.
	f.svc.DevBody(f.ctx, p, game.DevBodyRequest{Need: "all", Value: ptr(100), Buff: "fast", Minutes: 2})
	check(game.LevelOptimal, sp.Optimal*f.svc.Content().Body.Buffs["fast"].Speed, "ótimo com pernas leves")
	// Modo tranquilo: sem bônus, sem penalidade, nada cai.
	f.svc.DevBody(f.ctx, p, game.DevBodyRequest{Need: "all", Value: ptr(0), Buff: "fast"})
	if _, err := f.svc.SetQuiet(f.ctx, p, true); err != nil {
		t.Fatal(err)
	}
	v := check(game.LevelQuiet, sp.Neutral, "modo tranquilo")
	if v.Dizzy {
		t.Error("modo tranquilo zonzo")
	}
	pos := world.LatLonToVec(-15.8, -47.9).Scale(f.world.Radius)
	after, _ := f.svc.BodyTick(f.ctx, p.ID, 600, pos, f.world.FindCell(pos, -1), true)
	if after.Thirst != 0 || after.Hunger != 0 || after.Level != game.LevelQuiet {
		t.Errorf("modo tranquilo mudou as necessidades: %+v", after)
	}
	// Fica salvo.
	f.svc.SaveBody(f.ctx, p.ID, true)
	if v, _ := f.svc.Body(f.ctx, p); !v.Quiet {
		t.Error("modo tranquilo não ficou salvo")
	}
}

// Roupas: uma peça por espaço (a nova devolve a antiga ao bolso), a proteção soma e mexe na
// faixa de conforto; a tinta muda a cor.
func TestWearSlotsAndProtection(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Friorento", "BRA")
	c := f.svc.Content()
	for _, id := range []string{"beanie", "straw_hat", "coat", "boots", "paint_red"} {
		if _, err := f.svc.DevGive(f.ctx, p, id, 1); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := f.svc.Wear(f.ctx, p, "beanie"); err != nil {
		t.Fatal(err)
	}
	res, err := f.svc.Wear(f.ctx, p, "straw_hat")
	if err != nil {
		t.Fatal(err)
	}
	if res.Look.Wear["head"].Item != "straw_hat" || count(res.Inventory, "beanie") != 1 || count(res.Inventory, "straw_hat") != 0 {
		t.Fatalf("trocar o chapéu: %+v / %+v", res.Look.Wear, res.Inventory)
	}
	f.svc.Wear(f.ctx, p, "beanie") // o chapéu volta para o bolso
	f.svc.Wear(f.ctx, p, "coat")
	res, err = f.svc.Wear(f.ctx, p, "boots")
	if err != nil {
		t.Fatal(err)
	}
	want := c.Item("beanie").Wear.Cold + c.Item("coat").Wear.Cold + c.Item("boots").Wear.Cold
	if res.Body.ColdProt != want || res.Body.ComfortMin != c.Body.Comfort.Min-want {
		t.Errorf("proteção contra frio %.0f (faixa a partir de %.0f), esperado %.0f", res.Body.ColdProt, res.Body.ComfortMin, want)
	}
	// Com o casaco, 5 °C não incomoda; sem ele, sim.
	f.svc.DevBody(f.ctx, p, game.DevBodyRequest{Temp: ptr(5)})
	if v, _ := f.svc.Body(f.ctx, p); v.Cold {
		t.Error("de gorro, casaco e botas ainda com frio a 5 °C")
	}
	f.svc.Unwear(f.ctx, p, "body")
	f.svc.Unwear(f.ctx, p, "head")
	f.svc.Unwear(f.ctx, p, "feet")
	if v, _ := f.svc.Body(f.ctx, p); !v.Cold {
		t.Error("sem roupa e sem frio a 5 °C")
	}
	f.svc.Wear(f.ctx, p, "coat")
	res, err = f.svc.Dye(f.ctx, p, "body", "paint_red")
	if err != nil {
		t.Fatal(err)
	}
	if res.Look.Wear["body"].Color != c.Item("paint_red").Color || count(res.Inventory, "paint_red") != 0 {
		t.Errorf("tinta: %+v", res.Look.Wear["body"])
	}
	if _, err := f.svc.Wear(f.ctx, p, "axe"); err == nil {
		t.Error("vestiu um machado")
	}
}

// A capa de bandeiras mostra os países carimbados, na ordem.
func TestFlagCapeShowsVisitedCountries(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Viajante", "BRA")
	f.svc.DevGive(f.ctx, p, "flag_cape", 1)
	for _, code := range []string{"ARG", "CHL"} {
		if _, err := f.svc.DevPassport(f.ctx, p, "give", code); err != nil {
			t.Fatal(err)
		}
		if _, err := f.svc.Stamp(f.ctx, p, code); err != nil {
			t.Fatal(err)
		}
		f.clock.Advance(time.Minute)
	}
	res, err := f.svc.Wear(f.ctx, p, "flag_cape")
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Look.Cape) < 2 || res.Look.Cape[len(res.Look.Cape)-2] != "ARG" || res.Look.Cape[len(res.Look.Cape)-1] != "CHL" {
		t.Fatalf("capa: %v", res.Look.Cape)
	}
	if lv, _ := f.svc.LookOf(f.ctx, p); len(lv.Cape) != len(res.Look.Cape) {
		t.Errorf("LookOf da capa: %v", lv.Cape)
	}
}

// Comida: cozinhar receitas da fogueira, comer devolve fome e liga o bônus; o cantil vira o
// de pela metade; bancada não faz receita de fogueira.
func TestCookingFoodAndBuffs(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Cozinheiro", "BRA")
	f.svc.DevGive(f.ctx, p, "grain", 3)
	f.svc.DevGive(f.ctx, p, "canteen_full", 1)
	if _, err := f.svc.Craft(f.ctx, p, "grain_bread", 1); err == nil {
		t.Error("a bancada fez uma receita de fogueira")
	}
	res, err := f.svc.Cook(f.ctx, p, "grain_bread", 1)
	if err != nil {
		t.Fatal(err)
	}
	if count(res.Inventory, "grain_bread") != 1 || count(res.Inventory, "grain") != 0 {
		t.Fatalf("cozinhar: %+v", res.Inventory)
	}
	f.svc.DevBody(f.ctx, p, game.DevBodyRequest{Need: "all", Value: ptr(10)})
	eat, err := f.svc.Consume(f.ctx, p, "grain_bread")
	if err != nil {
		t.Fatal(err)
	}
	food := f.svc.Content().Item("grain_bread").Food
	if eat.Body.Hunger != 10+food.Hunger || len(eat.Body.Buffs) != 1 || eat.Body.Buffs[0].ID != food.Buff ||
		eat.Body.Buffs[0].Left != food.Minutes*60 {
		t.Fatalf("comer o pãozinho: %+v", eat.Body)
	}
	drink, err := f.svc.Consume(f.ctx, p, "canteen_full")
	if err != nil {
		t.Fatal(err)
	}
	if count(drink.Inventory, "canteen_half") != 1 || drink.Body.Thirst != 10+f.svc.Content().Item("canteen_full").Food.Thirst {
		t.Fatalf("beber do cantil: %+v", drink)
	}
	if _, err := f.svc.Consume(f.ctx, p, "wood"); err == nil {
		t.Error("comeu madeira")
	}
	// O bônus acaba com o tempo jogado.
	pos := world.LatLonToVec(-15.8, -47.9).Scale(f.world.Radius)
	v, _ := f.svc.BodyTick(f.ctx, p.ID, food.Minutes*60+1, pos, f.world.FindCell(pos, -1), false)
	if len(v.Buffs) != 0 {
		t.Errorf("bônus não acabou: %+v", v.Buffs)
	}
	// Toda receita de fogueira dá uma comida que existe.
	for _, r := range f.svc.Content().Recipes {
		if r.Station == game.StationFire && f.svc.Content().Item(r.Result).Food == nil {
			t.Errorf("receita de fogueira %s não dá comida", r.ID)
		}
	}
}

// Fase 4.1: cabelo separado da cabeça e quepe como acessório; cabelo desconhecido é recusado;
// visual sem cabelo escolhido continua valendo (o da própria cabeça).
func TestLookHaircut(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Cabeleira", "BRA")
	l := game.Look{Head: "male-c", Body: "female-a", Legs: "male-b", Hairstyle: "none", Accessory: "cap-male-c", Haircut: "female-e"}
	res, err := f.svc.SetLook(f.ctx, p, l)
	if err != nil {
		t.Fatal(err)
	}
	if res.Look.Look.Haircut != "female-e" || res.Look.Look.Accessory != "cap-male-c" {
		t.Errorf("visual salvo: %+v", res.Look.Look)
	}
	if lv, _ := f.svc.LookOf(f.ctx, p); lv.Look.Haircut != "female-e" {
		t.Errorf("LookOf: %+v", lv.Look)
	}
	l.Haircut = "male-c" // o quepe não é cabelo
	if _, err := f.svc.SetLook(f.ctx, p, l); err == nil {
		t.Error("aceitou cabelo desconhecido")
	}
	l.Haircut = ""
	if _, err := f.svc.SetLook(f.ctx, p, l); err != nil {
		t.Errorf("visual sem cabelo escolhido: %v", err)
	}
}

// Os bots do modo dev ganham um visual sorteado válido (com roupas que existem).
func TestDevRandomLookIsValid(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Robo", "BRA")
	n := 0
	pick := func(k int) int { n++; return (n * 7) % k }
	for i := 0; i < 20; i++ {
		v := f.svc.DevRandomLook(pick)
		if _, err := f.svc.SetLook(f.ctx, p, v.Look); err != nil {
			t.Fatalf("visual sorteado inválido %+v: %v", v.Look, err)
		}
		for slot, w := range v.Wear {
			it := f.svc.Content().Item(w.Item)
			if it == nil || it.Wear == nil || it.Wear.Slot != slot {
				t.Fatalf("peça %q no espaço %q", w.Item, slot)
			}
		}
	}
}
