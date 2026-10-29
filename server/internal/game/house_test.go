package game_test

import (
	"errors"
	"strings"
	"testing"

	"github.com/Dustyluc123/goblo/server/internal/game"
)

// buildAndFinish constrói (ou melhora) a casa e conclui a obra pelo modo dev.
func (f *fixture) buildAndFinish(t *testing.T, p *game.Player, lot int64, x, y int) *game.MeView {
	t.Helper()
	for _, it := range []string{"wood", "stone", "flower_red"} {
		f.give(t, p, it, 60)
	}
	if _, err := f.svc.BuildHouse(f.ctx, p, lot, x, y, 0); err != nil {
		t.Fatalf("obra em (%d, %d): %v", x, y, err)
	}
	if _, err := f.svc.DevFinishHouse(f.ctx, p); err != nil {
		t.Fatal(err)
	}
	me, err := f.svc.Me(f.ctx, p)
	if err != nil {
		t.Fatal(err)
	}
	return me
}

func TestUpgradeWithHouseAloneInLot(t *testing.T) {
	f := newFixture(t)
	p, me := f.player(t, "Sozinha", "BRA")
	me = f.buildAndFinish(t, p, me.Lot.ID, 4, 6) // barraca 6 × 6 em (4, 6)
	me = f.buildAndFinish(t, p, me.Lot.ID, 0, 0) // casinha: x e y são ignorados
	if h := me.Lot.House; h.Level != 2 || h.X != 3 || h.Y != 6 {
		t.Fatalf("casinha: %+v", h)
	}
	// Casa grande (10 × 10): no lugar preferido passaria da borda de trás; vai para a
	// posição mais próxima que cabe, ainda cobrindo a casinha, sem bater na bancada.
	me = f.buildAndFinish(t, p, me.Lot.ID, 0, 0)
	if h := me.Lot.House; h.Level != 3 || h.X != 3 || h.Y != 4 {
		t.Fatalf("casa grande: %+v", h)
	}
}

func TestUpgradeNearBorderFindsPosition(t *testing.T) {
	f := newFixture(t)
	p, me := f.player(t, "Beirada", "BRA")
	me = f.buildAndFinish(t, p, me.Lot.ID, 8, 8) // barraca no canto (8..14, 8..14)
	me = f.buildAndFinish(t, p, me.Lot.ID, 0, 0)
	if h := me.Lot.House; h.Level != 2 || h.X != 5 || h.Y != 7 {
		t.Fatalf("casinha encostada na borda deveria ir para (5, 7): %+v", h)
	}
}

func TestUpgradeBlockedByDecorationListsObjects(t *testing.T) {
	f := newFixture(t)
	p, me := f.player(t, "Enfeitada", "BRA")
	me = f.buildAndFinish(t, p, me.Lot.ID, 4, 6) // barraca em (4..10, 6..12)
	// Um lampião atrás e outro na frente: a casinha não cabe em nenhuma posição.
	f.give(t, p, "lantern", 2)
	var lanterns []int64
	for _, pos := range [][2]int{{5, 12}, {5, 5}} {
		res, err := f.svc.Place(f.ctx, p, me.Lot.ID, "lantern", pos[0], pos[1], 0)
		if err != nil {
			t.Fatalf("lampião em %v: %v", pos, err)
		}
		for _, pl := range res.Lot.Placements {
			if pl.Item == "lantern" && pl.X == pos[0] && pl.Y == pos[1] {
				lanterns = append(lanterns, pl.ID)
			}
		}
	}
	f.give(t, p, "wood", 30)
	f.give(t, p, "stone", 20)
	_, err := f.svc.BuildHouse(f.ctx, p, me.Lot.ID, 0, 0, 0)
	var ge *game.Error
	if !errors.As(err, &ge) || ge.Code != "overlap" {
		t.Fatalf("melhoria com decoração no caminho: %v", err)
	}
	d, _ := ge.Details.(map[string]any)
	blockers, _ := d["blockers"].([]game.Blocker)
	if len(blockers) != 1 || blockers[0].ID != lanterns[0] || blockers[0].Item != "lantern" || !strings.Contains(ge.Message, "lampião") {
		t.Fatalf("deveria listar o lampião de trás: %q %+v", ge.Message, ge.Details)
	}
	// Guardando o lampião, a melhoria passa.
	if _, err := f.svc.Remove(f.ctx, p, blockers[0].ID); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.BuildHouse(f.ctx, p, me.Lot.ID, 0, 0, 0); err != nil {
		t.Fatalf("depois de guardar: %v", err)
	}
}

func TestDevRealTimeUndoesNextDay(t *testing.T) {
	f := newFixture(t)
	p, _ := f.player(t, "Relojoeira", "BRA")
	before := f.clock.Now()
	if _, err := f.svc.DevNextDay(f.ctx, p); err != nil {
		t.Fatal(err)
	}
	if !f.clock.Now().After(before) {
		t.Fatal("o dia seguinte deveria adiantar o relógio")
	}
	if _, err := f.svc.DevRealTime(f.ctx, p); err != nil {
		t.Fatal(err)
	}
	if f.clock.Offset() != 0 {
		t.Fatalf("depois de voltar para a hora real, o relógio ainda está adiantado %v", f.clock.Offset())
	}
}
