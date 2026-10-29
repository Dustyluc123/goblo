package sqlitestore

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/game"
)

func TestMigrationsRunOnce(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "m.db")
	for i := 0; i < 2; i++ { // abrir de novo não pode reaplicar nada
		s, err := Open(ctx, path)
		if err != nil {
			t.Fatal(err)
		}
		if v, err := s.SchemaVersion(ctx); err != nil || v != 2 {
			t.Fatalf("versão do esquema %d (%v)", v, err)
		}
		s.Close()
	}
}

func TestRollbackAndCascade(t *testing.T) {
	ctx := context.Background()
	s, err := Open(ctx, ":memory:")
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	p := &game.Player{Nickname: "Teste", Country: "BRA", TokenHash: "h", CreatedAt: time.Now()}
	if err := s.CreatePlayer(ctx, p); err != nil {
		t.Fatal(err)
	}
	if err := s.CreatePlayer(ctx, &game.Player{Nickname: "teste", Country: "BRA", TokenHash: "h2"}); !errors.Is(err, game.ErrNicknameTaken) {
		t.Fatalf("apelido repetido: %v", err)
	}
	// Transação que falha não grava nada.
	boom := errors.New("falhou")
	err = s.InTx(ctx, func(tx game.Store) error {
		if err := tx.AddItem(ctx, p.ID, "wood", 5); err != nil {
			return err
		}
		return boom
	})
	if !errors.Is(err, boom) {
		t.Fatal(err)
	}
	if inv, _ := s.Inventory(ctx, p.ID); len(inv) != 0 {
		t.Fatalf("rollback deixou %v", inv)
	}
	if err := s.AddItem(ctx, p.ID, "wood", -1); !errors.Is(err, game.ErrMissingMaterials) {
		t.Fatalf("tirar o que não tem: %v", err)
	}
	if err := s.CreateLot(ctx, &game.Lot{ID: 40, Cell: 10, OwnerID: p.ID}); err != nil {
		t.Fatal(err)
	}
	if err := s.CreatePlacement(ctx, &game.Placement{LotID: 40, Item: "fence"}); err != nil {
		t.Fatal(err)
	}
	if err := s.DeletePlayer(ctx, p.ID); err != nil {
		t.Fatal(err)
	}
	if pl, _ := s.Placements(ctx, []int64{40}); len(pl) != 0 {
		t.Fatal("apagar o jogador deveria apagar os objetos do lote")
	}
}
