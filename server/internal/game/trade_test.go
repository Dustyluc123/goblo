package game_test

import (
	"errors"
	"testing"

	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

func offer(coins int64, items ...game.StackView) game.TradeOffer {
	return game.TradeOffer{Items: items, Coins: coins}
}

// A troca é atômica: ou tudo acontece, ou nada.
func TestTradeIsAtomic(t *testing.T) {
	f := newFixture(t)
	a, _ := f.player(t, "Trocador A", "BRA")
	b, _ := f.player(t, "Trocador B", "BRA")
	f.give(t, a, "wood", 10)
	f.give(t, b, "flower_red", 5)
	res, err := f.svc.ExecuteTrade(f.ctx, a, b, offer(5, game.StackView{Item: "wood", Count: 4}), offer(0, game.StackView{Item: "flower_red", Count: 2}))
	if err != nil {
		t.Fatal(err)
	}
	if count(res.A.Inventory, "wood") != 6 || count(res.A.Inventory, "flower_red") != 2 ||
		count(res.B.Inventory, "wood") != 4 || count(res.B.Inventory, "flower_red") != 3 {
		t.Fatalf("inventários depois da troca: A %v, B %v", res.A.Inventory, res.B.Inventory)
	}
	start := f.svc.Content().Economy.StartingCoins
	if res.A.Coins != start-5 || res.B.Coins != start+5 {
		t.Fatalf("gobolares: A %d, B %d", res.A.Coins, res.B.Coins)
	}
	// O lado B não cabe no bolso: nada muda para ninguém.
	big, _ := f.player(t, "Bolso Cheio", "BRA")
	for i, it := range []string{"branch", "stone", "flower_yellow", "flower_white", "flower_purple", "berries", "coconut", "seeds",
		"fence", "hedge", "lantern", "bench", "stool", "path", "flowerbed", "stall", "cart", "fountain", "rock_large", "rock_small"} {
		f.give(t, big, it, 1+i%2)
	}
	beforeA := f.inventory(t, a)
	_, err = f.svc.ExecuteTrade(f.ctx, a, big, offer(0, game.StackView{Item: "wood", Count: 2}), offer(0, game.StackView{Item: "stone", Count: 1}))
	if !errors.Is(err, game.ErrTradeFull) {
		t.Fatalf("bolso cheio: %v", err)
	}
	if count(f.inventory(t, a), "wood") != count(beforeA, "wood") || count(f.inventory(t, big), "wood") != 0 {
		t.Fatal("a troca recusada mudou algum inventário")
	}
}

func TestTradeRefusesWhatYouDontHave(t *testing.T) {
	f := newFixture(t)
	a, _ := f.player(t, "Sem Nada", "BRA")
	b, _ := f.player(t, "Com Algo", "BRA")
	f.give(t, b, "wood", 3)
	if _, err := f.svc.ExecuteTrade(f.ctx, a, b, offer(0, game.StackView{Item: "stone", Count: 1}), offer(0, game.StackView{Item: "wood", Count: 1})); !errors.Is(err, game.ErrMissingMaterials) {
		t.Fatalf("trocar o que não tem: %v", err)
	}
	if _, err := f.svc.ExecuteTrade(f.ctx, a, b, offer(99999), offer(0, game.StackView{Item: "wood", Count: 1})); !errors.Is(err, game.ErrNoCoins) {
		t.Fatalf("oferecer gobolares que não tem: %v", err)
	}
	if err := f.svc.CheckOffer(f.ctx, a, offer(0, game.StackView{Item: "wood", Count: 1})); !errors.Is(err, game.ErrMissingMaterials) {
		t.Fatalf("oferta conferida antes: %v", err)
	}
	if count(f.inventory(t, b), "wood") != 3 {
		t.Fatal("a troca recusada mexeu no inventário")
	}
}

func TestTradeNeedsNearAndNotBlocked(t *testing.T) {
	f := newFixture(t)
	pres := &fakePresence{pos: map[int64]world.Vec3{}}
	f.svc.SetPresence(pres)
	a, _ := f.player(t, "Longe A", "BRA")
	b, _ := f.player(t, "Longe B", "BRA")
	f.give(t, a, "wood", 2)
	here := world.LatLonToVec(-23.55, -46.63).Scale(1000)
	east := world.Vec3{Y: 1}.Cross(here.Normalize()).Normalize()
	pres.pos[a.ID] = here
	pres.pos[b.ID] = here.Add(east.Scale(40))
	w := offer(0, game.StackView{Item: "wood", Count: 1})
	if _, err := f.svc.ExecuteTrade(f.ctx, a, b, w, offer(0)); !errors.Is(err, game.ErrTooFar) {
		t.Fatalf("jogadores longe: %v", err)
	}
	pres.pos[b.ID] = here.Add(east.Scale(2))
	if err := f.svc.SetBlock(f.ctx, b, a.ID, true); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.ExecuteTrade(f.ctx, a, b, w, offer(0)); !errors.Is(err, game.ErrBlocked) {
		t.Fatalf("jogador bloqueado: %v", err)
	}
	f.svc.SetBlock(f.ctx, b, a.ID, false)
	if _, err := f.svc.ExecuteTrade(f.ctx, a, b, w, offer(0)); err != nil {
		t.Fatalf("perto e sem bloqueio: %v", err)
	}
}
