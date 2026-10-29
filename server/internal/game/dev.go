package game

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Ações do modo dev. Só são chamadas pelas rotas /dev/…, que só existem com GOBLO_DEV=1.

// DevGive dá qualquer item, em qualquer quantidade (respeitando os 20 espaços).
func (s *Service) DevGive(ctx context.Context, p *Player, item string, count int) (*MeView, error) {
	if s.content.Item(item) == nil {
		return nil, ErrNotFound.with("Item desconhecido: %s.", item)
	}
	if count == 0 || count > 9999 || count < -9999 {
		return nil, ErrInvalid
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var me *MeView
	err := s.store.InTx(ctx, func(tx Store) error {
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		if count < 0 {
			have := 0
			for _, st := range inv {
				if st.Item == item {
					have = st.Count
				}
			}
			count = -min(have, -count)
			if count == 0 {
				return nil
			}
			if err := tx.AddItem(ctx, p.ID, item, count); err != nil {
				return err
			}
		} else if err := s.addItems(ctx, tx, p.ID, inv, []StackView{{Item: item, Count: count}}); err != nil {
			return err
		}
		me, err = s.meView(ctx, tx, p)
		return err
	})
	return me, err
}

// DevFinishHouse conclui a obra na hora.
func (s *Service) DevFinishHouse(ctx context.Context, p *Player) (*MeView, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var me *MeView
	err := s.store.InTx(ctx, func(tx Store) error {
		lot, err := s.ownLot(ctx, tx, p)
		if err != nil {
			return err
		}
		if lot.PendingLevel == 0 {
			return ErrInvalid.with("Não há obra em andamento.")
		}
		finish(lot)
		if err := tx.UpdateLot(ctx, lot); err != nil {
			return err
		}
		me, err = s.meView(ctx, tx, p)
		return err
	})
	return me, err
}

// DevNextDay adianta o relógio do servidor até logo depois da próxima virada do dia do
// jogador. Vale para todos (é o relógio do servidor) e só funciona com OffsetClock.
func (s *Service) DevNextDay(ctx context.Context, p *Player) (*MeView, error) {
	oc, ok := s.clock.(*OffsetClock)
	if !ok {
		return nil, ErrDevOnly.with("O relógio do servidor não pode ser adiantado.")
	}
	now := oc.Now()
	next := NextRollover(now, s.homeLon(ctx, s.store, p))
	oc.Advance(next.Sub(now) + time.Second)
	return s.Me(ctx, p)
}

// DevSetCountry troca o país do jogador e muda o lote dele para um lote livre no país novo
// (o lote antigo, com casa e decoração, é liberado).
func (s *Service) DevSetCountry(ctx context.Context, p *Player, country string) (*MeView, error) {
	if _, ok := s.world.Countries[country]; !ok {
		return nil, ErrCountry
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var me *MeView
	err := s.store.InTx(ctx, func(tx Store) error {
		if lot, err := tx.LotByOwner(ctx, p.ID); err == nil {
			if err := tx.DeleteLot(ctx, lot.ID); err != nil {
				return err
			}
		} else if !errors.Is(err, ErrNotFound) {
			return err
		}
		if err := tx.UpdatePlayerCountry(ctx, p.ID, country); err != nil {
			return err
		}
		p.Country = country
		if _, err := s.assignLot(ctx, tx, p, country); err != nil {
			return err
		}
		var err error
		me, err = s.meView(ctx, tx, p)
		return err
	})
	return me, err
}

// DevReset apaga parte do jogador: "lot" (casa e decoração; volta só a bancada),
// "inventory", "collections" (limites do dia) ou "player" (tudo; o cliente volta à tela
// de primeiro acesso).
func (s *Service) DevReset(ctx context.Context, p *Player, what string) (*MeView, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var me *MeView
	err := s.store.InTx(ctx, func(tx Store) error {
		switch what {
		case "player":
			return tx.DeletePlayer(ctx, p.ID)
		case "inventory":
			if err := tx.ClearInventory(ctx, p.ID); err != nil {
				return err
			}
		case "collections":
			if err := tx.ClearCollections(ctx, p.ID); err != nil {
				return err
			}
		case "lot":
			lot, err := tx.LotByOwner(ctx, p.ID)
			if err != nil {
				return err
			}
			if err := tx.DeleteLotPlacements(ctx, lot.ID); err != nil {
				return err
			}
			*lot = Lot{ID: lot.ID, Cell: lot.Cell, Slot: lot.Slot, OwnerID: lot.OwnerID}
			if err := tx.UpdateLot(ctx, lot); err != nil {
				return err
			}
			if err := tx.CreatePlacement(ctx, &Placement{LotID: lot.ID, Item: "workbench", X: workbenchX, Y: workbenchY}); err != nil {
				return err
			}
		default:
			return ErrInvalid.with("Reset desconhecido: %s (use lot, inventory, collections ou player).", what)
		}
		var err error
		me, err = s.meView(ctx, tx, p)
		return err
	})
	if what == "player" && err == nil {
		return nil, nil
	}
	return me, err
}

var fakeNames = []string{
	"Bia", "Caio", "Duda", "Enzo", "Fefa", "Gabi", "Heitor", "Iara", "Juca", "Kiki", "Lulu", "Malu",
	"Nina", "Otto", "Pipo", "Quim", "Rafa", "Sol", "Teca", "Uli", "Vivi", "Zeca", "Nico", "Tati",
}

// decorações que os vizinhos falsos recebem (tentativas em lugares sorteados).
var fakeDecor = []string{"lantern", "flowerbed", "flowerbed", "bench", "rock_small", "berry_bush", "stool", "path", "path", "fence", "hedge", "cart", "stall", "rock_large", "fountain"}

// DevFakeNeighbors cria `count` jogadores falsos com casas prontas e decoração sorteada,
// nos lotes livres mais perto da célula `near` (andando pelos vizinhos, só em terra).
func (s *Service) DevFakeNeighbors(ctx context.Context, p *Player, near, count int) (int, error) {
	if near < 0 || near >= len(s.world.Cells) || count <= 0 || count > 200 {
		return 0, ErrInvalid
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	created := 0
	r := newRNG(mix(uint64(s.clock.Now().UnixNano()), uint64(p.ID)))
	cells := s.landCellsNear(near, 400)
	err := s.store.InTx(ctx, func(tx Store) error {
		for _, cell := range cells {
			if created >= count {
				return nil
			}
			lots, err := tx.LotsByCells(ctx, []int{cell})
			if err != nil {
				return err
			}
			taken := map[int64]bool{}
			for _, l := range lots {
				taken[l.ID] = true
			}
			for _, slot := range LotSlots(s.world, cell) {
				if created >= count {
					break
				}
				if taken[slot.ID] {
					continue
				}
				if err := s.createFake(ctx, tx, r, cell, slot); err != nil {
					return err
				}
				created++
			}
		}
		return nil
	})
	return created, err
}

func (s *Service) createFake(ctx context.Context, tx Store, r *rng, cell int, slot LotSlot) error {
	country := s.world.Cells[cell].Country
	var fp *Player
	for try := 0; ; try++ {
		nick := fmt.Sprintf("%s %d", fakeNames[r.intn(len(fakeNames))], 10+r.intn(990))
		fp = &Player{Nickname: nick, Country: country, TokenHash: HashToken(newToken()), CreatedAt: s.clock.Now().UTC(), Fake: true}
		err := tx.CreatePlayer(ctx, fp)
		if err == nil {
			break
		}
		if !errors.Is(err, ErrNicknameTaken) || try > 20 {
			return err
		}
	}
	level := 1 + r.intn(len(s.content.Houses))
	h := s.content.House(level)
	lot := &Lot{ID: slot.ID, Cell: cell, Slot: slot.Slot, OwnerID: fp.ID, HouseLevel: level, HouseRot: 0}
	lot.HouseX = (LotTiles - h.Footprint[0]) / 2
	lot.HouseY = LotTiles - h.Footprint[1] - 1 - r.intn(2)
	lot.PendingX, lot.PendingY = lot.HouseX, lot.HouseY
	if err := tx.CreateLot(ctx, lot); err != nil {
		return err
	}
	placed := []Placement{{LotID: lot.ID, Item: "workbench", X: workbenchX, Y: workbenchY}}
	for i := 0; i < 6+r.intn(6); i++ {
		item := fakeDecor[r.intn(len(fakeDecor))]
		it := s.content.Item(item)
		for try := 0; try < 12; try++ {
			pl := Placement{LotID: lot.ID, Item: item, X: r.intn(LotTiles), Y: r.intn(LotTiles), Rot: r.intn(4)}
			rr := footprintRect(it.Footprint, pl.X, pl.Y, pl.Rot)
			if !rr.inLot() {
				continue
			}
			ok := true
			for _, o := range s.occupied(lot, placed, false) {
				if o.overlaps(rr) {
					ok = false
					break
				}
			}
			if ok {
				placed = append(placed, pl)
				break
			}
		}
	}
	for i := range placed {
		if err := tx.CreatePlacement(ctx, &placed[i]); err != nil {
			return err
		}
	}
	return nil
}

// landCellsNear devolve até `limit` células de terra, das mais perto às mais longe de
// `start` (busca em largura pelos vizinhos, atravessando o mar se preciso).
func (s *Service) landCellsNear(start, limit int) []int {
	seen := map[int]bool{start: true}
	queue := []int{start}
	var out []int
	for len(queue) > 0 && len(out) < limit {
		cur := queue[0]
		queue = queue[1:]
		if s.world.Cells[cur].Terrain == world.Land {
			out = append(out, cur)
		}
		for _, nb := range s.world.Cells[cur].Neighbors {
			if !seen[nb] && s.distanceDeg(start, nb) < 20 {
				seen[nb] = true
				queue = append(queue, nb)
			}
		}
	}
	return out
}
