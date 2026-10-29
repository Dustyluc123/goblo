package game_test

import (
	"errors"
	"testing"

	"github.com/Dustyluc123/goblo/server/internal/game"
)

func TestNewPlayerStartsWithCoins(t *testing.T) {
	f := newFixture(t)
	_, me := f.player(t, "Rica", "BRA")
	if want := f.svc.Content().Economy.StartingCoins; me.Coins != want {
		t.Fatalf("saldo inicial %d, esperado %d", me.Coins, want)
	}
}

func TestSellCreditsTheRightAmount(t *testing.T) {
	f := newFixture(t)
	p, me := f.player(t, "Vendedora", "BRA")
	start := me.Coins
	if _, err := f.svc.DevGive(f.ctx, p, "wood", 5); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.DevGive(f.ctx, p, "stone", 2); err != nil {
		t.Fatal(err)
	}
	c := f.svc.Content()
	res, err := f.svc.Sell(f.ctx, p, []game.StackView{{Item: "wood", Count: 3}, {Item: "stone", Count: 2}})
	if err != nil {
		t.Fatal(err)
	}
	want := 3*c.SellPrice("wood") + 2*c.SellPrice("stone")
	if res.Earned != want || res.Coins != start+want {
		t.Fatalf("ganhou %d (saldo %d), esperado %d (saldo %d)", res.Earned, res.Coins, want, start+want)
	}
	if count(res.Inventory, "wood") != 2 || count(res.Inventory, "stone") != 0 {
		t.Fatalf("inventário depois da venda: %+v", res.Inventory)
	}
	tr, err := f.svc.Transactions(f.ctx, p, 10)
	if err != nil || len(tr) < 1 || tr[0].Reason != "sell" || tr[0].Delta != want {
		t.Fatalf("histórico: %+v %v", tr, err)
	}
}

func TestSellRejectsWhatYouDontHave(t *testing.T) {
	f := newFixture(t)
	p, me := f.player(t, "Pobre", "BRA")
	if _, err := f.svc.Sell(f.ctx, p, []game.StackView{{Item: "wood", Count: 1}}); !errors.Is(err, game.ErrMissingMaterials) {
		t.Fatalf("vender o que não tem: %v", err)
	}
	if _, err := f.svc.DevGive(f.ctx, p, "axe", 1); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Sell(f.ctx, p, []game.StackView{{Item: "axe", Count: 1}}); !errors.Is(err, game.ErrNotForSale) {
		t.Fatalf("vender o machado: %v", err)
	}
	if _, err := f.svc.Sell(f.ctx, p, []game.StackView{{Item: "wood", Count: -2}}); !errors.Is(err, game.ErrInvalid) {
		t.Fatalf("quantidade negativa: %v", err)
	}
	after, _ := f.svc.Me(f.ctx, p)
	if after.Coins != me.Coins {
		t.Fatalf("saldo mudou depois de vendas recusadas: %d → %d", me.Coins, after.Coins)
	}
}
