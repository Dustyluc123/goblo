package game

import (
	"context"
	"fmt"
	"time"
)

// Fornalha e baú (fase 4.5, ADR 0057).
//
// Fornalha: transforma minério em barra com carvão (receitas station furnace), com uma espera
// por unidade. Vale a fornalha do próprio lote ou a fornalha antiga da entrada de qualquer
// caverna. O que entra fica "derretendo" e depois pronto, guardado no banco por jogador, até
// ele buscar em qualquer fornalha (nada se perde se o jogo fechar).
//
// Baú: colocado no lote, guarda itens (chest_slots espaços, o mesmo limite por item do bolso).
// Só o dono abre; o servidor guarda o conteúdo; com coisas dentro, não dá para guardar o baú.

// FurnaceJobView é um item na fornalha.
type FurnaceJobView struct {
	ID      int64  `json:"id"`
	Item    string `json:"item"`
	Count   int    `json:"count"`
	ReadyAt int64  `json:"ready_at"` // unix
	Ready   bool   `json:"ready"`
}

// FurnaceView é a fornalha do jogador.
type FurnaceView struct {
	Jobs      []FurnaceJobView `json:"jobs"`
	Now       int64            `json:"now"`
	Message   string           `json:"message,omitempty"`
	Inventory []StackView      `json:"inventory,omitempty"`
	SlotsUsed int              `json:"slots_used,omitempty"`
}

// requireFurnace: perto da fornalha do lote (cave < 0) ou da fornalha antiga da caverna.
func (s *Service) requireFurnace(ctx context.Context, p *Player, cave int) error {
	reach := s.content.Caves.FurnaceReach
	if cave >= 0 {
		l := s.CaveLayoutOf(cave)
		if l == nil {
			return ErrNotFound.with("Caverna desconhecida.")
		}
		return s.requireNearCave(p, cave, l.Furnace[0], l.Furnace[1], l.Furnace[2], reach, "da fornalha antiga")
	}
	return s.requireOwnPlacement(ctx, p, "furnace", reach, "Coloque uma fornalha no seu lote (ou use a da entrada de uma caverna).", "da sua fornalha")
}

func (s *Service) furnaceView(ctx context.Context, st Store, p *Player) (*FurnaceView, error) {
	jobs, err := st.FurnaceJobs(ctx, p.ID)
	if err != nil {
		return nil, err
	}
	now := s.clock.Now()
	v := &FurnaceView{Jobs: []FurnaceJobView{}, Now: now.Unix()}
	for _, j := range jobs {
		v.Jobs = append(v.Jobs, FurnaceJobView{ID: j.ID, Item: j.Item, Count: j.Count, ReadyAt: j.ReadyAt.Unix(), Ready: !now.Before(j.ReadyAt)})
	}
	return v, nil
}

// Furnace devolve o que está na fornalha do jogador.
func (s *Service) Furnace(ctx context.Context, p *Player) (*FurnaceView, error) {
	return s.furnaceView(ctx, s.store, p)
}

// Smelt põe `times` vezes a receita da fornalha para derreter. A espera de cada unidade é
// recipe.seconds, depois do que já está na fila.
func (s *Service) Smelt(ctx context.Context, p *Player, recipeID string, times, cave int) (*FurnaceView, error) {
	r := s.content.Recipe(recipeID)
	if r == nil || r.Station != StationFurnace {
		return nil, ErrNotFound.with("Essa receita não é da fornalha.")
	}
	if times <= 0 || times > 99 {
		return nil, ErrInvalid
	}
	if err := s.requireFurnace(ctx, p, cave); err != nil {
		return nil, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *FurnaceView
	err := s.store.InTx(ctx, func(tx Store) error {
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		used, err := s.resolveCost(r.Ingredients, times, inv)
		if err != nil {
			return err
		}
		if err := consume(ctx, tx, p.ID, used); err != nil {
			return err
		}
		jobs, err := tx.FurnaceJobs(ctx, p.ID)
		if err != nil {
			return err
		}
		start := s.clock.Now()
		for _, j := range jobs {
			if j.ReadyAt.After(start) {
				start = j.ReadyAt
			}
		}
		ready := start.Add(time.Duration(r.Seconds * float64(times) * float64(time.Second)))
		if err := tx.AddFurnaceJob(ctx, p.ID, r.Result, r.Count*times, ready); err != nil {
			return err
		}
		if res, err = s.furnaceView(ctx, tx, p); err != nil {
			return err
		}
		res.Message = fmt.Sprintf("%d× %s na fornalha. Pronto em %d s.", r.Count*times, s.itemName(r.Result), int(ready.Sub(s.clock.Now()).Seconds()+0.5))
		inv, err = tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		res.Inventory, res.SlotsUsed = s.inventoryView(inv)
		return nil
	})
	return res, err
}

// CollectFurnace pega o que já ficou pronto (o que não cabe no bolso continua na fornalha).
func (s *Service) CollectFurnace(ctx context.Context, p *Player, cave int) (*FurnaceView, error) {
	if err := s.requireFurnace(ctx, p, cave); err != nil {
		return nil, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *FurnaceView
	err := s.store.InTx(ctx, func(tx Store) error {
		jobs, err := tx.FurnaceJobs(ctx, p.ID)
		if err != nil {
			return err
		}
		now := s.clock.Now()
		got, full := 0, false
		for _, j := range jobs {
			if now.Before(j.ReadyAt) {
				continue
			}
			inv, err := tx.Inventory(ctx, p.ID)
			if err != nil {
				return err
			}
			if err := s.addItems(ctx, tx, p.ID, inv, []StackView{{Item: j.Item, Count: j.Count}}); err != nil {
				if err == ErrInventoryFull {
					full = true
					continue
				}
				return err
			}
			if err := tx.DeleteFurnaceJob(ctx, p.ID, j.ID); err != nil {
				return err
			}
			got += j.Count
		}
		if res, err = s.furnaceView(ctx, tx, p); err != nil {
			return err
		}
		switch {
		case full:
			res.Message = "O bolso encheu: o resto continua na fornalha."
		case got == 0:
			res.Message = "Nada pronto ainda."
		default:
			res.Message = fmt.Sprintf("Você pegou %d itens da fornalha!", got)
		}
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		res.Inventory, res.SlotsUsed = s.inventoryView(inv)
		return nil
	})
	return res, err
}

// --- Baú -----------------------------------------------------------------------------------

// ChestView é o conteúdo de um baú (e o bolso, depois de mexer).
type ChestView struct {
	ID        int64       `json:"id"`
	Items     []StackView `json:"items"`
	SlotsUsed int         `json:"slots_used_chest"`
	SlotsMax  int         `json:"slots_max_chest"`
	Inventory []StackView `json:"inventory"`
	BagUsed   int         `json:"slots_used"`
	Message   string      `json:"message,omitempty"`
}

// chestOf confere que a peça é um baú do lote do jogador e que ele está perto.
func (s *Service) chestOf(ctx context.Context, tx Store, p *Player, id int64) error {
	pl, err := tx.PlacementByID(ctx, id)
	if err != nil {
		return ErrNotFound.with("Baú não encontrado.")
	}
	it := s.content.Item(pl.Item)
	if it == nil || !it.HasTag("chest") {
		return ErrWrongAction.with("Isso não é um baú.")
	}
	lot, err := tx.LotByOwner(ctx, p.ID)
	if err != nil || lot.ID != pl.LotID {
		return ErrNotOwner.with("Esse baú é de outra pessoa.")
	}
	if s.presence == nil {
		return nil
	}
	f := CellFrame(s.world, lot.Cell)
	x0, y0, _, _ := SlotRect(lot.Slot)
	w, h := it.Footprint[0], it.Footprint[1]
	if pl.Rot%2 == 1 {
		w, h = h, w
	}
	pt := f.Point(x0+(float64(pl.X)+float64(w)/2)*TileSize, y0+(float64(pl.Y)+float64(h)/2)*TileSize)
	return s.requireNear(p, pt, s.content.Caves.ChestReach, "do baú")
}

func (s *Service) chestView(ctx context.Context, tx Store, p *Player, id int64) (*ChestView, error) {
	items, err := tx.ChestItems(ctx, id)
	if err != nil {
		return nil, err
	}
	v := &ChestView{ID: id, SlotsMax: s.content.Caves.ChestSlots}
	v.Items, v.SlotsUsed = s.inventoryView(items)
	inv, err := tx.Inventory(ctx, p.ID)
	if err != nil {
		return nil, err
	}
	v.Inventory, v.BagUsed = s.inventoryView(inv)
	return v, nil
}

// Chest abre o baú (só o dono, perto dele).
func (s *Service) Chest(ctx context.Context, p *Player, id int64) (*ChestView, error) {
	if err := s.chestOf(ctx, s.store, p, id); err != nil {
		return nil, err
	}
	return s.chestView(ctx, s.store, p, id)
}

// MoveChest guarda (put = true, do bolso para o baú) ou tira (do baú para o bolso) itens.
func (s *Service) MoveChest(ctx context.Context, p *Player, id int64, item string, count int, put bool) (*ChestView, error) {
	if count <= 0 || count > 9999 || s.content.Item(item) == nil {
		return nil, ErrInvalid
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *ChestView
	err := s.store.InTx(ctx, func(tx Store) error {
		if err := s.chestOf(ctx, tx, p, id); err != nil {
			return err
		}
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		inside, err := tx.ChestItems(ctx, id)
		if err != nil {
			return err
		}
		move := []StackView{{Item: item, Count: count}}
		if put {
			if !hasCount(inv, item, count) {
				return ErrMissingMaterials.with("Você não tem tudo isso no bolso.")
			}
			if s.slotsUsed(applyDelta(inside, move, 1)) > s.content.Caves.ChestSlots {
				return ErrInventoryFull.with("O baú está cheio.")
			}
			if err := tx.AddItem(ctx, p.ID, item, -count); err != nil {
				return err
			}
			if err := tx.AddChestItem(ctx, id, item, count); err != nil {
				return err
			}
		} else {
			if !hasCount(inside, item, count) {
				return ErrMissingMaterials.with("Não tem tudo isso no baú.")
			}
			if err := s.addItems(ctx, tx, p.ID, inv, move); err != nil {
				return err
			}
			if err := tx.AddChestItem(ctx, id, item, -count); err != nil {
				return err
			}
		}
		res, err = s.chestView(ctx, tx, p, id)
		return err
	})
	return res, err
}

func hasCount(list []Stack, item string, n int) bool {
	for _, st := range list {
		if st.Item == item {
			return st.Count >= n
		}
	}
	return false
}

// DevFillChest (modo dev): enche o baú do lote com um pouco de cada material.
func (s *Service) DevFillChest(ctx context.Context, p *Player, id int64) (*ChestView, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *ChestView
	err := s.store.InTx(ctx, func(tx Store) error {
		pl, err := tx.PlacementByID(ctx, id)
		if err != nil {
			return err
		}
		lot, err := tx.LotByOwner(ctx, p.ID)
		if err != nil || lot.ID != pl.LotID {
			return ErrNotOwner
		}
		n := 0
		for _, it := range s.content.Items {
			if it.Category != CategoryMaterial || n >= s.content.Caves.ChestSlots {
				continue
			}
			if err := tx.AddChestItem(ctx, id, it.ID, min(it.Stack, 10)); err != nil {
				return err
			}
			n++
		}
		res, err = s.chestView(ctx, tx, p, id)
		return err
	})
	return res, err
}
