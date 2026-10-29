package game_test

import (
	"testing"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

func TestSeasonsByDateAndLatitude(t *testing.T) {
	day := func(m time.Month, d int) time.Time { return time.Date(2027, m, d, 12, 0, 0, 0, time.UTC) }
	const berlin, saoPaulo, manaus, sydney = 52.52, -23.55, -3.12, -33.87
	for _, tc := range []struct {
		when time.Time
		lat  float64
		want string
	}{
		{day(time.January, 15), berlin, "winter"},
		{day(time.January, 15), saoPaulo, "summer"},
		{day(time.January, 15), manaus, "none"},
		{day(time.July, 15), berlin, "summer"},
		{day(time.July, 15), sydney, "winter"},
		{day(time.April, 20), berlin, "spring"},
		{day(time.April, 20), sydney, "autumn"},
		{time.Date(2026, 10, 29, 12, 0, 0, 0, time.UTC), berlin, "autumn"},   // fim de outubro: outono no norte
		{time.Date(2026, 10, 29, 12, 0, 0, 0, time.UTC), saoPaulo, "spring"}, // e primavera no sul
		{day(time.December, 25), berlin, "winter"},
		{day(time.March, 1), 60, "winter"},
		{day(time.September, 1), -40, "winter"},
	} {
		if got := game.SeasonAt(tc.when, tc.lat); got != tc.want {
			t.Errorf("%s em %.2f: %s, esperado %s", tc.when.Format("02/01"), tc.lat, got, tc.want)
		}
	}
	if got := game.SeasonFor(day(time.January, 15), berlin, world.BiomeTropicalForest); got != "none" {
		t.Errorf("floresta tropical não muda: %s", got)
	}
	if got := game.SeasonFor(day(time.January, 15), berlin, world.BiomeForest); got != "winter" {
		t.Errorf("floresta em Berlim em janeiro: %s", got)
	}
}

func TestSeasonPhaseIsContinuous(t *testing.T) {
	start := time.Date(2027, 1, 1, 0, 0, 0, 0, time.UTC)
	last := game.NorthPhase(start)
	for h := 6; h < 24*366; h += 6 {
		p := game.NorthPhase(start.Add(time.Duration(h) * time.Hour))
		d := p - last
		if d < 0 {
			d += 4
		}
		if d > 0.02 || p < 0 || p >= 4 {
			t.Fatalf("fase pulou de %.4f para %.4f em %d h", last, p, h)
		}
		last = p
	}
}
