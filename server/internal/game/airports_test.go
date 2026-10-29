package game_test

import (
	"errors"
	"fmt"
	"math"
	"testing"

	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

func airport(t *testing.T, f *fixture, code string) game.Airport {
	t.Helper()
	for _, a := range f.svc.Airports() {
		if a.Country == code {
			return a
		}
	}
	t.Fatalf("%s sem aeroporto", code)
	return game.Airport{}
}

func TestAirportsNearCapitals(t *testing.T) {
	f := newFixture(t)
	for _, tc := range []struct {
		code     string
		lat, lon float64
	}{{"BRA", -15.78, -47.92}, {"ARG", -34.6, -58.4}, {"FRA", 48.86, 2.35}, {"JPN", 35.68, 139.69}} {
		a := airport(t, f, tc.code)
		d := world.LatLonToVec(a.Lat, a.Lon).Dot(world.LatLonToVec(tc.lat, tc.lon))
		if deg := math.Acos(math.Min(1, d)) * 180 / math.Pi; deg > 2.5 {
			t.Errorf("aeroporto de %s a %.1f° da capital", tc.code, deg)
		}
		if f.world.Cells[a.Cell].Country != tc.code || a.Small || !f.svc.IsAirportCell(a.Cell) {
			t.Errorf("aeroporto de %s: %+v", tc.code, a)
		}
		if objs, _, _ := f.svc.Objects(f.ctx, &game.Player{ID: 999}, []int{a.Cell}); len(objs) != 0 {
			t.Errorf("hexágono do aeroporto de %s com %d objetos", tc.code, len(objs))
		}
	}
	// País de um hexágono só: ponto de chegada, sem tirar o lugar dos lotes.
	alb := airport(t, f, "ALB")
	if !alb.Small || f.svc.IsAirportCell(alb.Cell) {
		t.Errorf("Albânia: %+v", alb)
	}
}

func TestTravelPriceByDistance(t *testing.T) {
	f := newFixture(t)
	near := f.svc.TravelPrice("BRA", "PRY")
	far := f.svc.TravelPrice("BRA", "JPN")
	tr := f.svc.Content().Economy.Travel
	if near < tr.Min || far <= near {
		t.Fatalf("Brasil → Paraguai %d, Brasil → Japão %d", near, far)
	}
	// Brasília → Tóquio são ~17.700 km.
	want := int64(math.Round(tr.Base + tr.Per1000K*17.7))
	if math.Abs(float64(far-want)) > float64(tr.Per1000K)*0.6+1 {
		t.Fatalf("Brasil → Japão custa %d, esperado ~%d", far, want)
	}
	if f.svc.TravelPrice("BRA", "PRY") != f.svc.TravelPrice("PRY", "BRA") {
		t.Fatalf("ida e volta com preços diferentes")
	}
}

func TestPassportRequiredAndCoinsChecked(t *testing.T) {
	f := newFixture(t)
	p, me := f.player(t, "Viajante", "BRA")
	if _, err := f.svc.Travel(f.ctx, p, "BRA", "ARG", false, false); !errors.Is(err, game.ErrNoPassport) {
		t.Fatalf("viajar sem passaporte: %v", err)
	}
	// Não dá para gastar o que não tem: nada muda.
	if _, err := f.svc.Travel(f.ctx, p, "BRA", "ARG", true, false); !errors.Is(err, game.ErrNoCoins) {
		t.Fatalf("sem moedas: %v", err)
	}
	if _, err := f.svc.BuyPassport(f.ctx, p, "ARG"); !errors.Is(err, game.ErrNoCoins) {
		t.Fatalf("passaporte sem moedas: %v", err)
	}
	after, _ := f.svc.Me(f.ctx, p)
	if after.Coins != me.Coins || len(after.Passports) != 1 || after.Passports[0] != "BRA" {
		t.Fatalf("depois das recusas: %d moedas, passaportes %v", after.Coins, after.Passports)
	}
	if _, err := f.svc.DevCoins(f.ctx, p, 1000); err != nil {
		t.Fatal(err)
	}
	c := f.svc.Content()
	res, err := f.svc.Travel(f.ctx, p, "BRA", "ARG", true, false)
	if err != nil {
		t.Fatal(err)
	}
	want := f.svc.TravelPrice("BRA", "ARG") + c.PassportPrice("ARG")
	if res.Price != want || res.Airport == nil || res.Airport.Country != "ARG" {
		t.Fatalf("viagem: preço %d (esperado %d), %+v", res.Price, want, res.Airport)
	}
	if res.Stamp == nil || res.Stamp.Country != "ARG" || res.Reward != c.Economy.Rewards.StampFirst {
		t.Fatalf("chegada sem carimbo: %+v", res)
	}
	if res.Passport.Coins != me.Coins+1000-want+res.Reward {
		t.Fatalf("saldo depois da viagem: %d", res.Passport.Coins)
	}
	// Volta para casa: o passaporte do Brasil é o da residência (grátis).
	back, err := f.svc.Travel(f.ctx, p, "ARG", "BRA", false, false)
	if err != nil || back.Price != f.svc.TravelPrice("ARG", "BRA") {
		t.Fatalf("volta: %+v %v", back, err)
	}
}

func TestStampOncePerCountry(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Carimbada", "BRA")
	if _, err := f.svc.Stamp(f.ctx, p, "PRY"); !errors.Is(err, game.ErrNoPassport) {
		t.Fatalf("carimbo sem passaporte: %v", err)
	}
	if _, err := f.svc.DevCoins(f.ctx, p, 500); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.BuyPassport(f.ctx, p, "PRY"); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.BuyPassport(f.ctx, p, "PRY"); !errors.Is(err, game.ErrInvalid) {
		t.Fatalf("comprar de novo: %v", err)
	}
	r1, err := f.svc.Stamp(f.ctx, p, "PRY")
	if err != nil || r1.Stamp == nil || r1.Reward == 0 {
		t.Fatalf("primeiro carimbo: %+v %v", r1, err)
	}
	r2, err := f.svc.Stamp(f.ctx, p, "PRY")
	if err != nil || r2.Stamp != nil || r2.Reward != 0 || r2.Passport.Coins != r1.Passport.Coins {
		t.Fatalf("segundo carimbo não pode pagar: %+v %v", r2, err)
	}
	home, err := f.svc.Stamp(f.ctx, p, "BRA")
	if err != nil || home.Stamp == nil {
		t.Fatalf("carimbo do próprio país: %+v %v", home, err)
	}
	if len(home.Passport.Stamps) != 2 {
		t.Fatalf("livro com %d carimbos", len(home.Passport.Stamps))
	}
	// País pequeno sem hexágono também tem passaporte e carimbo.
	if _, err := f.svc.BuyPassport(f.ctx, p, "LUX"); err != nil {
		t.Fatalf("passaporte de Luxemburgo: %v", err)
	}
}

func TestNoNewLotsInAirportCells(t *testing.T) {
	f := newFixture(t)
	bra := airport(t, f, "BRA")
	for i := 0; i < 30; i++ {
		_, me := f.player(t, fmt.Sprintf("Morador %d", i), "BRA")
		if me.Lot.Cell == bra.Cell {
			t.Fatalf("lote no hexágono do aeroporto")
		}
	}
}
