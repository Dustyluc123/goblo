package sqlitestore

import (
	"context"
	"errors"
	"io/fs"
	"path/filepath"
	"testing"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/game"
)

func TestMigrationsRunOnce(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "m.db")
	files, _ := fs.Glob(migrations, "migrations/*.sql")
	for i := 0; i < 2; i++ { // abrir de novo não pode reaplicar nada
		s, err := Open(ctx, path)
		if err != nil {
			t.Fatal(err)
		}
		if v, err := s.SchemaVersion(ctx); err != nil || v != len(files) {
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

func TestCoinsNeverNegative(t *testing.T) {
	ctx := context.Background()
	s, err := Open(ctx, ":memory:")
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	p := &game.Player{Nickname: "Moedas", Country: "BRA", TokenHash: "h", CreatedAt: time.Now()}
	if err := s.CreatePlayer(ctx, p); err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	if bal, err := s.AddCoins(ctx, p.ID, 10, "sell", "wood×3", now); err != nil || bal != 10 {
		t.Fatalf("ganhar 10: %d %v", bal, err)
	}
	if _, err := s.AddCoins(ctx, p.ID, -11, "travel", "ARG", now); !errors.Is(err, game.ErrNoCoins) {
		t.Fatalf("gastar mais do que tem: %v", err)
	}
	if bal, err := s.AddCoins(ctx, p.ID, -10, "travel", "ARG", now); err != nil || bal != 0 {
		t.Fatalf("gastar tudo: %d %v", bal, err)
	}
	tr, err := s.Transactions(ctx, p.ID, 10)
	if err != nil || len(tr) != 2 || tr[0].Delta != -10 || tr[0].Balance != 0 || tr[1].Reason != "sell" {
		t.Fatalf("histórico: %+v %v", tr, err)
	}
}
