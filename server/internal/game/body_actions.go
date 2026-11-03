package game

import (
	"context"
	"fmt"
	"math"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Ações do corpo (fase 4.0, ADR 0050): comer e beber do bolso, cozinhar na fogueira, encher
// o cantil, acender uma fogueira no chão, o modo tranquilo e as ferramentas do modo dev.

// BodyResult é a resposta das ações do corpo.
type BodyResult struct {
	Body      BodyView    `json:"body"`
	Inventory []StackView `json:"inventory"`
	SlotsUsed int         `json:"slots_used"`
	Message   string      `json:"message"`
	Fire      *tempFire   `json:"fire,omitempty"`
}

var (
	ErrNotFood   = &Error{"not_food", 400, "Isso não dá para comer nem beber.", nil}
	ErrNoFire    = &Error{"no_fire", 403, "Chegue perto de uma fogueira acesa.", nil}
	ErrNoWater   = &Error{"no_water", 403, "Chegue perto de uma fonte ou de um poço para encher o cantil.", nil}
	ErrNoCanteen = &Error{"no_canteen", 400, "Você precisa de um cantil vazio ou pela metade.", nil}
)

// result monta a resposta com o corpo e o bolso do jogador.
func (s *Service) bodyResult(ctx context.Context, tx Store, p *Player, msg string) (*BodyResult, error) {
	inv, err := tx.Inventory(ctx, p.ID)
	if err != nil {
		return nil, err
	}
	res := &BodyResult{Message: msg}
	res.Inventory, res.SlotsUsed = s.inventoryView(inv)
	s.body.mu.Lock()
	b, err := s.bodyLocked(ctx, p.ID)
	if err == nil {
		res.Body = s.bodyView(b)
	}
	s.body.mu.Unlock()
	return res, err
}

// applyFood soma o que a comida dá e liga o bônus.
func (s *Service) applyFood(ctx context.Context, p *Player, f *FoodInfo) error {
	s.body.mu.Lock()
	defer s.body.mu.Unlock()
	b, err := s.bodyLocked(ctx, p.ID)
	if err != nil {
		return err
	}
	max := s.content.Body.Needs.Max
	b.Hunger = clampNeed(b.Hunger+f.Hunger, max)
	b.Thirst = clampNeed(b.Thirst+f.Thirst, max)
	if f.Buff != "" {
		if b.Buffs == nil {
			b.Buffs = map[string]float64{}
		}
		b.Buffs[f.Buff] = math.Max(b.Buffs[f.Buff], f.Minutes*60)
	}
	b.dirty = true
	return nil
}

// Consume come ou bebe um item do bolso. A água do mar não mata a sede (não há item para
// ela); o cantil vira o cantil pela metade e depois o vazio.
func (s *Service) Consume(ctx context.Context, p *Player, item string) (*BodyResult, error) {
	if err := s.ensureBody(ctx, p.ID); err != nil {
		return nil, err
	}
	it := s.content.Item(item)
	if it == nil || it.Food == nil || (it.Food.Hunger <= 0 && it.Food.Thirst <= 0) {
		return nil, ErrNotFood
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *BodyResult
	err := s.store.InTx(ctx, func(tx Store) error {
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		if !has(inv, item) {
			return ErrMissingMaterials.with("Você não tem %s.", it.Name)
		}
		if err := tx.AddItem(ctx, p.ID, item, -1); err != nil {
			return err
		}
		if it.Food.Becomes != "" {
			if err := tx.AddItem(ctx, p.ID, it.Food.Becomes, 1); err != nil {
				return err
			}
		}
		if err := s.applyFood(ctx, p, it.Food); err != nil {
			return err
		}
		verb := "comeu"
		if it.Food.Thirst > it.Food.Hunger {
			verb = "bebeu"
		}
		msg := fmt.Sprintf("Você %s %s.", verb, it.Name)
		if it.Food.Buff != "" {
			msg += fmt.Sprintf(" %s por %.0f min!", s.content.Body.Buffs[it.Food.Buff].Name, it.Food.Minutes)
		}
		res, err = s.bodyResult(ctx, tx, p, msg)
		return err
	})
	return res, err
}

// --- Fogueiras -----------------------------------------------------------------------------

// fireNear diz se o jogador está perto de uma fogueira (do lote de qualquer um, ou acesa no
// chão). Sem tempo real, não confere.
func (s *Service) requireFire(ctx context.Context, p *Player) error {
	pos, cell, _, checked, err := s.where(p)
	if err != nil || !checked {
		return err
	}
	reach := s.content.Body.Sources.Fire.Radius
	now := s.clock.Now()
	s.body.mu.Lock()
	for _, f := range s.body.fire {
		if now.Before(f.Until) && s.groundDistance(pos, f.Pos) <= reach {
			s.body.mu.Unlock()
			return nil
		}
	}
	s.body.mu.Unlock()
	lots, err := s.store.LotsByCells(ctx, s.cellsAround(cell, 1))
	if err != nil {
		return err
	}
	for _, pt := range s.placementPoints(ctx, lots, "fire") {
		if s.groundDistance(pos, pt) <= reach {
			return nil
		}
	}
	return ErrNoFire
}

// LightFire acende uma fogueira (do bolso) no chão, na frente do jogador. Ela aquece e serve
// para cozinhar por sources.fire.minutes minutos e depois apaga.
func (s *Service) LightFire(ctx context.Context, p *Player) (*BodyResult, error) {
	pos, cell, facing, checked, err := s.where(p)
	if err != nil {
		return nil, err
	}
	if !checked {
		return nil, ErrOffline
	}
	if s.world.Cells[cell].Terrain != world.Land {
		return nil, ErrInvalid.with("Aqui não dá para acender fogueira.")
	}
	at := pos.Add(facing.Scale(1.2))
	if err := s.ensureBody(ctx, p.ID); err != nil {
		return nil, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *BodyResult
	err = s.store.InTx(ctx, func(tx Store) error {
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		if !has(inv, "campfire") {
			return ErrMissingMaterials.with("Você não tem uma fogueira no bolso. Fabrique uma na bancada.")
		}
		if err := tx.AddItem(ctx, p.ID, "campfire", -1); err != nil {
			return err
		}
		res, err = s.bodyResult(ctx, tx, p, "Você acendeu uma fogueira. Ela fica acesa uns minutos.")
		return err
	})
	if err != nil {
		return nil, err
	}
	f := s.addFire(p.ID, at)
	res.Fire = &f
	s.emit(Event{Kind: "fire", Cell: f.Cell, PlayerID: p.ID, Data: f})
	return res, nil
}

func (s *Service) addFire(owner int64, at world.Vec3) tempFire {
	now := s.clock.Now()
	cell := s.world.FindCell(at, -1)
	fr := CellFrame(s.world, cell)
	x, y := fr.Coords(at)
	s.body.mu.Lock()
	defer s.body.mu.Unlock()
	// Tira as apagadas e limita uma acesa por jogador (a nova substitui a velha).
	keep := s.body.fire[:0]
	for _, f := range s.body.fire {
		if now.Before(f.Until) && f.Owner != owner {
			keep = append(keep, f)
		}
	}
	s.body.next++
	until := now.Add(time.Duration(s.content.Body.Sources.Fire.Minutes * float64(time.Minute)))
	f := tempFire{ID: s.body.next, Owner: owner, Cell: cell, Pos: at, X: round2(x), Y: round2(y), Until: until}
	s.body.fire = append(keep, f)
	f.Left = until.Sub(now).Seconds()
	return f
}

// Fires lista as fogueiras acesas no chão nas células dadas.
func (s *Service) Fires(cells []int) []tempFire {
	want := map[int]bool{}
	for _, c := range cells {
		want[c] = true
	}
	now := s.clock.Now()
	s.body.mu.Lock()
	defer s.body.mu.Unlock()
	out := []tempFire{}
	for _, f := range s.body.fire {
		if now.Before(f.Until) && want[f.Cell] {
			f.Left = f.Until.Sub(now).Seconds()
			out = append(out, f)
		}
	}
	return out
}

// Cook cozinha uma receita da fogueira (station fire), perto de uma fogueira.
func (s *Service) Cook(ctx context.Context, p *Player, recipeID string, times int) (*CraftResult, error) {
	r := s.content.Recipe(recipeID)
	if r == nil || r.Station != StationFire {
		return nil, ErrNotFound.with("Essa receita não é de fogueira.")
	}
	if err := s.requireFire(ctx, p); err != nil {
		return nil, err
	}
	return s.craft(ctx, p, r, times)
}

// --- Cantil --------------------------------------------------------------------------------

// waterPoints são os lugares que enchem o cantil perto do jogador: fontes e poços dos lotes
// e o chafariz da praça.
func (s *Service) requireWater(ctx context.Context, p *Player) error {
	pos, cell, _, checked, err := s.where(p)
	if err != nil || !checked {
		return err
	}
	reach := s.content.Body.FillReach
	cells := s.cellsAround(cell, 1)
	lots, err := s.store.LotsByCells(ctx, cells)
	if err != nil {
		return err
	}
	for _, pt := range s.placementPoints(ctx, lots, "water") {
		// As fontes são grandes: mede da borda (metade do tamanho) mais o alcance.
		if s.groundDistance(pos, pt) <= reach+1.5 {
			return nil
		}
	}
	for _, c := range cells {
		for _, a := range s.airports {
			if a.Cell == c && !a.Small {
				f := CellFrame(s.world, c)
				x, y := rotate(plazaFountainU*a.Scale, plazaFountainV*a.Scale, a.Rot)
				if s.groundDistance(pos, f.Point(x, y)) <= reach+1.2*a.Scale {
					return nil
				}
			}
		}
	}
	return ErrNoWater
}

// FillCanteen enche o cantil (vazio ou pela metade) numa fonte ou num poço.
func (s *Service) FillCanteen(ctx context.Context, p *Player) (*BodyResult, error) {
	if err := s.ensureBody(ctx, p.ID); err != nil {
		return nil, err
	}
	if err := s.requireWater(ctx, p); err != nil {
		return nil, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *BodyResult
	err := s.store.InTx(ctx, func(tx Store) error {
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		from := ""
		for _, id := range []string{"canteen", "canteen_half"} {
			if has(inv, id) {
				from = id
				break
			}
		}
		if from == "" {
			return ErrNoCanteen
		}
		if err := tx.AddItem(ctx, p.ID, from, -1); err != nil {
			return err
		}
		if err := tx.AddItem(ctx, p.ID, "canteen_full", 1); err != nil {
			return err
		}
		res, err = s.bodyResult(ctx, tx, p, "Cantil cheio! Dá para beber em qualquer lugar.")
		return err
	})
	return res, err
}

// --- Modo tranquilo e modo dev ------------------------------------------------------------

// SetQuiet liga ou desliga o modo tranquilo (sem necessidades, sem bônus e sem penalidade).
func (s *Service) SetQuiet(ctx context.Context, p *Player, on bool) (*BodyView, error) {
	s.body.mu.Lock()
	b, err := s.bodyLocked(ctx, p.ID)
	if err != nil {
		s.body.mu.Unlock()
		return nil, err
	}
	b.Quiet = on
	b.dirty = true
	v := s.bodyView(b)
	s.body.mu.Unlock()
	return &v, s.SaveBody(ctx, p.ID, false)
}

// DevBody (modo dev): need = thirst, hunger, comfort ou all com value (0 a max); freeze
// congela as necessidades; temp força a temperatura do ar (nil = volta ao normal); buff dá
// um bônus por minutes minutos.
type DevBodyRequest struct {
	Need    string   `json:"need"`
	Value   *float64 `json:"value"`
	Freeze  *bool    `json:"freeze"`
	Temp    *float64 `json:"temp"`
	Unforce bool     `json:"unforce"`
	Buff    string   `json:"buff"`
	Minutes float64  `json:"minutes"`
}

func (s *Service) DevBody(ctx context.Context, p *Player, r DevBodyRequest) (*BodyView, error) {
	s.body.mu.Lock()
	defer s.body.mu.Unlock()
	b, err := s.bodyLocked(ctx, p.ID)
	if err != nil {
		return nil, err
	}
	max := s.content.Body.Needs.Max
	if r.Value != nil {
		v := clampNeed(*r.Value, max)
		switch r.Need {
		case "thirst":
			b.Thirst = v
		case "hunger":
			b.Hunger = v
		case "comfort":
			b.Comfort = v
		case "all":
			b.Thirst, b.Hunger, b.Comfort = v, v, v
		default:
			return nil, ErrInvalid.with("Use thirst, hunger, comfort ou all.")
		}
	}
	if r.Freeze != nil {
		b.frozen = *r.Freeze
	}
	if r.Temp != nil {
		t := *r.Temp
		b.forced = &t
		b.felt, b.air = t, t
	}
	if r.Unforce {
		b.forced = nil
	}
	if r.Buff != "" {
		if _, ok := s.content.Body.Buffs[r.Buff]; !ok {
			return nil, ErrInvalid.with("Bônus %s não existe.", r.Buff)
		}
		if b.Buffs == nil {
			b.Buffs = map[string]float64{}
		}
		if r.Minutes <= 0 {
			delete(b.Buffs, r.Buff)
		} else {
			b.Buffs[r.Buff] = r.Minutes * 60
		}
	}
	b.dirty = true
	if pos, cell, _, ok := s.presenceWhere(p.ID); ok {
		s.updateTemperature(ctx, b, p.ID, pos, cell, s.clock.Now())
	}
	v := s.bodyView(b)
	return &v, nil
}
