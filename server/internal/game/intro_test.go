package game_test

import (
	"testing"

	"github.com/Dustyluc123/goblo/server/internal/game"
)

// A apresentação é vista uma vez por conta: conta nova começa sem ter visto; as tarefas
// pagam uma vez só e só enquanto a apresentação está em andamento; rever não paga de novo.
func TestIntroOncePerAccount(t *testing.T) {
	f := newFixture(t)
	p, me := f.player(t, "Novato", "BRA")
	v, err := f.svc.Intro(f.ctx, p)
	if err != nil || v.Done || len(v.Tasks) != 0 {
		t.Fatalf("conta nova: %+v %v", v, err)
	}
	objs, _, _ := f.svc.Objects(f.ctx, p, []int{me.Lot.Cell})
	var trees []game.ObjectView
	for _, o := range objs {
		if o.Kind == game.KindTree && o.Drop != "" {
			trees = append(trees, o)
		}
	}
	if len(trees) < 2 {
		t.Skip("poucas árvores no hexágono de casa")
	}
	r1, err := f.svc.Interact(f.ctx, p, trees[0].ID, "shake")
	if err != nil {
		t.Fatal(err)
	}
	reward := f.svc.Content().Economy.Rewards.IntroTask
	if r1.IntroTask != "shake" || r1.IntroReward != reward {
		t.Fatalf("primeira sacudida não cumpriu a tarefa: %+v", r1)
	}
	r2, err := f.svc.Interact(f.ctx, p, trees[1].ID, "shake")
	if err != nil || r2.IntroTask != "" {
		t.Fatalf("a tarefa pagou duas vezes: %+v %v", r2, err)
	}
	if _, err := f.svc.SetIntro(f.ctx, p, true); err != nil {
		t.Fatal(err)
	}
	f.give(t, p, "branch", 5)
	f.give(t, p, "stone", 5)
	c, err := f.svc.Craft(f.ctx, p, "axe", 1)
	if err != nil {
		t.Fatal(err)
	}
	if c.IntroTask != "" {
		t.Fatal("tarefa paga depois de terminar a apresentação")
	}
	// Rever (marcar como não vista) não paga de novo o que já pagou.
	f.svc.SetIntro(f.ctx, p, false)
	v, _ = f.svc.Intro(f.ctx, p)
	if v.Done || len(v.Tasks) != 1 || v.Tasks[0] != "shake" {
		t.Fatalf("rever a apresentação: %+v", v)
	}
	f.clock.Advance(24 * 3600 * 1e9)
	r3, err := f.svc.Interact(f.ctx, p, trees[0].ID, "shake")
	if err != nil || r3.IntroTask != "" {
		t.Fatalf("a tarefa já paga pagou de novo: %+v %v", r3, err)
	}
	// Nomes dos NPCs da praça por país.
	if a := f.svc.Airports()[0]; a.NPCs["shopkeeper"] == "" || a.NPCs["attendant"] == "" {
		t.Fatalf("aeroporto sem nomes de NPC: %+v", a.NPCs)
	}
}
