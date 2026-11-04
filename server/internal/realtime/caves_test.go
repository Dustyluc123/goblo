package realtime_test

import (
	"testing"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Cavernas no tempo real (fase 4.5): só entra quem pediu na boca, anda dentro da caixa da
// caverna, vê só quem está na mesma caverna, volta ao começo e sai pela boca.
func TestCavesInRealtime(t *testing.T) {
	e := newEnv(t, true)
	a, _ := e.join(t, "Exploradora", "BRA")
	b, _ := e.join(t, "Espeleologo", "BRA")
	c, _ := e.join(t, "Outra", "BRA")
	caves := e.svc.Caves()
	cave, other := 0, 1
	mouth, _ := e.svc.CaveEntrancePoint(cave)
	mouth = mouth.Normalize().Scale(mouth.Len() + 0.2)
	for _, p := range []*conn{a, b} {
		if !p.tp("dev", mouth) {
			t.Fatal("teleporte para a boca recusado")
		}
	}
	start, _ := e.svc.CaveStartPoint(cave)
	if a.tp("cave", start) {
		t.Fatal("entrou sem pedir na boca")
	}
	for _, p := range []*conn{a, b} {
		if _, err := e.svc.EnterCave(e.ctx, p.player, cave); err != nil {
			t.Fatalf("pedir para entrar: %v", err)
		}
		if !p.tp("cave", start) {
			t.Fatal("entrar na caverna recusado")
		}
	}
	// c entra em outra caverna (modo dev): não vê os dois.
	if _, err := e.svc.DevEnterCave(e.ctx, c.player, other); err != nil {
		t.Fatal(err)
	}
	start2, _ := e.svc.CaveStartPoint(other)
	if !c.tp("cave", start2) {
		t.Fatal("entrar na outra caverna recusado")
	}
	// Andar dentro da caverna não é corrigido.
	l := e.svc.CaveLayoutOf(cave)
	f := l.FrameOf()
	p := start
	before := len(a.corrections()) // o teleporte recusado acima já mandou uma correção
	for i := 0; i < 10; i++ {
		time.Sleep(60 * time.Millisecond)
		p = p.Add(f.East.Scale(0.25))
		a.move(p)
	}
	time.Sleep(300 * time.Millisecond)
	if len(a.corrections()) != before {
		t.Fatalf("andar na caverna foi corrigido: %v", a.corrections())
	}
	// a e b se veem; c não.
	b.waitText("enter", 2*time.Second)
	time.Sleep(200 * time.Millisecond)
	if c.count("enter") != 0 {
		t.Fatal("quem está em outra caverna apareceu")
	}
	// Voltar ao começo e sair pela boca.
	if !a.tp("cave_start", start) {
		t.Fatal("voltar ao começo recusado")
	}
	if a.tp("cave_exit", ground(-23.55, -46.63)) {
		t.Fatal("saiu da caverna para longe da boca")
	}
	if !a.tp("cave_exit", mouth) {
		t.Fatal("sair pela boca recusado")
	}
	if a.tp("cave_start", start) {
		t.Fatal("voltou ao começo da caverna estando fora dela")
	}
	_ = caves
	_ = world.Vec3{}
}
