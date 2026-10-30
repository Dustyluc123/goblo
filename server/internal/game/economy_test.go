package game_test

import (
	"context"
	"math"
	"path/filepath"
	"testing"
	"time"

	"github.com/Dustyluc123/goblo/server/data"
	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/store/sqlitestore"
)

// Todo item do jogo pode ser vendido (fase 3.5): na caixa de vendas e, por um pouco mais,
// na loja.
func TestEveryItemHasSellPrice(t *testing.T) {
	f := newFixture(t)
	for _, it := range f.svc.Content().Items {
		box := f.svc.Price(game.PriceSellBox, it.ID, "BRA")
		shop := f.svc.Price(game.PriceShopSell, it.ID, "BRA")
		if box.Total <= 0 {
			t.Errorf("%s sem preço na caixa de vendas", it.ID)
		}
		if shop.Total < box.Total {
			t.Errorf("%s: a loja paga %d, menos que a caixa (%d)", it.ID, shop.Total, box.Total)
		}
	}
}

// Modificadores por país (ADR 0041): imposto, preço de passaporte e margem da loja vêm de
// countries.json; o imposto vai para o cofre do país e o histórico guarda país, preço e
// imposto.
func TestPriceUsesCountryModifiers(t *testing.T) {
	w, _ := sharedWorld(t)
	c, err := game.LoadContent(data.Game)
	if err != nil {
		t.Fatal(err)
	}
	c.Countries.Countries = map[string]game.CountryEconomy{
		"FRA": {GoodsTax: 0.2, PassportPrice: 99, PassportTax: 0.1, ShopMarkup: 2},
	}
	store, err := sqlitestore.Open(context.Background(), filepath.Join(t.TempDir(), "eco.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	svc := game.NewService(w, c, store, game.NewOffsetClock(game.FixedClock{T: start}))
	svc.SetGeography(testGeo)
	ctx := context.Background()

	wood := svc.Price(game.PriceSellBox, "wood", "FRA")
	base := c.Economy.SellPrices["wood"]
	if wood.Base != base || wood.Tax != int64(math.Round(float64(base)*0.2)) || wood.Total != wood.Base-wood.Tax {
		t.Fatalf("venda na França com imposto: %+v", wood)
	}
	if def := svc.Price(game.PriceSellBox, "wood", "BRA"); def.Tax != 0 || def.Total != base {
		t.Fatalf("país sem modificador não tem imposto: %+v", def)
	}
	if pp := svc.Price(game.PricePassport, "FRA", "BRA"); pp.Base != 99 {
		t.Fatalf("passaporte da França com preço próprio: %+v", pp)
	}
	if pp := svc.Price(game.PricePassport, "BRA", "FRA"); pp.Tax != int64(math.Round(float64(pp.Base)*0.1)) {
		t.Fatalf("passaporte comprado na França paga o imposto de lá: %+v", pp)
	}
	if b := svc.Price(game.PriceShopBuy, "axe", "FRA"); b.Base != 2*c.Shop.Prices["axe"] {
		t.Fatalf("margem da loja francesa: %+v", b)
	}

	p, _, err := svc.CreatePlayer(ctx, "Francês", "FRA")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.DevGive(ctx, p, "wood", 10); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Sell(ctx, p, []game.StackView{{Item: "wood", Count: 10}}); err != nil {
		t.Fatal(err)
	}
	cofre, _ := svc.Treasury(ctx, "FRA")
	if cofre != 10*wood.Tax {
		t.Fatalf("cofre da França: %d, esperado %d", cofre, 10*wood.Tax)
	}
	txs, _ := svc.Transactions(ctx, p, 5)
	if len(txs) == 0 || txs[0].Reason != "sell" || txs[0].Country != "FRA" || txs[0].Tax != 10*wood.Tax || txs[0].Price != 10*base {
		t.Fatalf("histórico da venda: %+v", txs[0])
	}
	if cofre, _ := svc.Treasury(ctx, "BRA"); cofre != 0 {
		t.Fatalf("cofre do Brasil deveria estar zerado: %d", cofre)
	}
}

func TestShopBuyAndSell(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Freguês", "BRA")
	me, err := f.svc.DevCoins(f.ctx, p, 100)
	if err != nil {
		t.Fatal(err)
	}
	shop, err := f.svc.Shop("BRA")
	if err != nil {
		t.Fatal(err)
	}
	var axe *game.ShopStockItem
	for i := range shop.Stock {
		if shop.Stock[i].Item == "axe" {
			axe = &shop.Stock[i]
		}
	}
	if axe == nil || axe.Kind != "fixed" {
		t.Fatalf("machado não está fixo no estoque: %+v", shop.Stock)
	}
	res, err := f.svc.ShopBuy(f.ctx, p, "BRA", "axe", 1)
	if err != nil {
		t.Fatal(err)
	}
	if res.Coins != me.Coins-axe.Price.Total || count(res.Inventory, "axe") != 1 {
		t.Fatalf("compra do machado: saldo %d (era %d, preço %d)", res.Coins, me.Coins, axe.Price.Total)
	}
	if _, err := f.svc.ShopBuy(f.ctx, p, "BRA", "windmill", 1); err == nil {
		t.Fatal("moinho (exclusivo de outros países) comprado no Brasil")
	}
	if _, err := f.svc.ShopBuy(f.ctx, p, "BRA", "fountain_square", 50); err == nil {
		t.Fatal("comprou sem gobolares")
	}
	f.give(t, p, "wood", 4)
	sold, err := f.svc.ShopSell(f.ctx, p, "BRA", []game.StackView{{Item: "wood", Count: 4}})
	if err != nil {
		t.Fatal(err)
	}
	box := f.svc.Price(game.PriceSellBox, "wood", "BRA").Total
	if sold.Total != 4*f.svc.Price(game.PriceShopSell, "wood", "BRA").Total || sold.Total <= 4*box {
		t.Fatalf("a loja pagou %d pela madeira (a caixa pagaria %d)", sold.Total, 4*box)
	}
}

// O estoque do dia é igual para todo mundo do mesmo país e muda de um dia para o outro.
func TestShopStockDaily(t *testing.T) {
	f := newFixture(t)
	names := func(list []game.ShopStockItem) string {
		s := ""
		for _, x := range list {
			s += x.Item + ","
		}
		return s
	}
	day := f.svc.ShopDay("BRA", f.clock.Now())
	a := names(f.svc.ShopStock("BRA", day))
	if a != names(f.svc.ShopStock("BRA", day)) {
		t.Fatal("o mesmo dia deu estoques diferentes")
	}
	changed := false
	for d := int64(1); d <= 7; d++ {
		if names(f.svc.ShopStock("BRA", day+d)) != a {
			changed = true
		}
	}
	if !changed {
		t.Fatal("o estoque não mudou em uma semana")
	}
	// Exclusivo regional: o moinho só nos Países Baixos (e vizinhos).
	if !contains(names(f.svc.ShopStock("NLD", day)), "windmill") || contains(a, "windmill") {
		t.Fatal("moinho deveria estar só no estoque dos Países Baixos")
	}
	// Virada às 5h do país: um dia depois, o dia da loja anda um.
	f.clock.Advance(24 * time.Hour)
	if f.svc.ShopDay("BRA", f.clock.Now()) != day+1 {
		t.Fatal("o dia da loja não virou")
	}
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
