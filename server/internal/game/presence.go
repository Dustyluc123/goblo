package game

import (
	"context"
	"errors"
	"math"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Presence é quem sabe onde cada jogador está agora: a camada em tempo real
// (internal/realtime), que valida o movimento (ADR 0039). Com ela, as regras conferem a
// distância até o que o jogador usa (ADR 0040).
type Presence interface {
	// Where devolve a posição validada do jogador, a célula e para onde ele olha (no
	// chão). ok = false se o jogador não está conectado em tempo real.
	Where(player int64) (pos world.Vec3, cell int, facing world.Vec3, ok bool)
}

// SetPresence liga as conferências de distância. Sem presença (testes antigos, ferramentas),
// elas não são feitas.
func (s *Service) SetPresence(p Presence) { s.presence = p }

// Event é algo que os jogadores perto precisam ver na hora (árvore sacudida, lote mudou,
// passaportes mudaram). A camada em tempo real manda para quem está perto de Cell.
type Event struct {
	Kind     string // "object", "lot", "passports"
	Cell     int
	PlayerID int64 // quem fez
	Data     any
}

// SetEvents registra quem recebe os eventos (a camada em tempo real).
func (s *Service) SetEvents(fn func(Event)) { s.events = fn }

func (s *Service) emit(e Event) {
	if s.events != nil {
		s.events(e)
	}
}

var (
	ErrTooFar  = &Error{"too_far", 403, "Chegue mais perto.", nil}
	ErrOffline = &Error{"offline", 409, "Sem conexão com o servidor em tempo real. Espere reconectar.", nil}
)

// where devolve a posição do jogador; ok = false sem presença ligada (não confere nada).
func (s *Service) where(p *Player) (pos world.Vec3, cell int, facing world.Vec3, checked bool, err error) {
	if s.presence == nil {
		return world.Vec3{}, -1, world.Vec3{}, false, nil
	}
	pos, cell, facing, ok := s.presence.Where(p.ID)
	if !ok {
		return pos, cell, facing, false, ErrOffline
	}
	return pos, cell, facing, true, nil
}

// requireNear confere se o jogador está a até reach unidades (no chão) do ponto.
func (s *Service) requireNear(p *Player, target world.Vec3, reach float64, what string) error {
	pos, _, _, checked, err := s.where(p)
	if err != nil || !checked {
		return err
	}
	if s.groundDistance(pos, target) > reach {
		return ErrTooFar.with("Chegue mais perto %s.", what)
	}
	return nil
}

// groundDistance é a distância no chão (arco do globo) entre dois pontos.
func (s *Service) groundDistance(a, b world.Vec3) float64 {
	d := a.Normalize().Dot(b.Normalize())
	return math.Acos(math.Max(-1, math.Min(1, d))) * s.world.Radius
}

// ObjectPoint é a posição do objeto no mundo.
func (s *Service) ObjectPoint(o *Object) world.Vec3 {
	f := CellFrame(s.world, o.Cell)
	return f.Point(o.X, o.Y)
}

// AnimalPoint é onde o animal está agora no trajeto comum.
func (s *Service) AnimalPoint(a *Animal, at time.Time) world.Vec3 {
	pose := AnimalAt(a, float64(at.UnixNano())/1e9)
	f := CellFrame(s.world, a.Cell)
	return f.Point(pose.X, pose.Y)
}

// SetCharacter guarda o personagem escolhido.
func (s *Service) SetCharacter(ctx context.Context, p *Player, character string) error {
	if !s.content.Rules.ValidCharacter(character) {
		return ErrInvalid.with("Personagem desconhecido.")
	}
	if err := s.store.UpdatePlayerCharacter(ctx, p.ID, character); err != nil {
		return err
	}
	p.Character = character
	return nil
}

// SetBlock bloqueia ou desbloqueia outro jogador (chat e emotes param nos dois sentidos).
func (s *Service) SetBlock(ctx context.Context, p *Player, other int64, on bool) error {
	if other == p.ID {
		return ErrInvalid.with("Não dá para bloquear você mesmo.")
	}
	if _, err := s.store.PlayerByID(ctx, other); err != nil {
		return err
	}
	return s.store.SetBlock(ctx, p.ID, other, on, s.clock.Now())
}

// Blocks: quem o jogador bloqueou e quem bloqueou o jogador.
func (s *Service) Blocks(ctx context.Context, p *Player) (blocked, blockedBy []int64, err error) {
	return s.store.Blocks(ctx, p.ID)
}

// PlayerByID acha um jogador (camada em tempo real).
func (s *Service) PlayerByID(ctx context.Context, id int64) (*Player, error) {
	return s.store.PlayerByID(ctx, id)
}

// MovementState é o que a camada em tempo real precisa para validar o movimento: o lote,
// os passaportes e o ponto de casa.
type MovementState struct {
	Lot       *Lot
	Passports map[string]bool
	Home      world.Vec3 // centro do lote (ou da célula do país, sem lote)
	Stamped   map[string]bool
}

// MovementStateOf monta o estado de movimento do jogador.
func (s *Service) MovementStateOf(ctx context.Context, p *Player) (*MovementState, error) {
	st := &MovementState{Passports: map[string]bool{}, Stamped: map[string]bool{}}
	lot, err := s.store.LotByOwner(ctx, p.ID)
	if err == nil {
		st.Lot = lot
		f := CellFrame(s.world, lot.Cell)
		x0, y0, x1, y1 := SlotRect(lot.Slot)
		st.Home = f.Point((x0+x1)/2, (y0+y1)/2)
	} else if !errors.Is(err, ErrNotFound) {
		return nil, err
	}
	list, err := s.passportsOf(ctx, s.store, p)
	if err != nil {
		return nil, err
	}
	for _, c := range list {
		st.Passports[c] = true
	}
	stamps, err := s.store.Stamps(ctx, p.ID)
	if err != nil {
		return nil, err
	}
	for _, x := range stamps {
		st.Stamped[x.Country] = true
	}
	return st, nil
}

// ArrivalPoint é onde o voo chega no país (o balcão do aeroporto), para a camada em
// tempo real aceitar o teleporte da chegada.
func (s *Service) ArrivalPoint(country string) (world.Vec3, bool) {
	a := s.airportBy[country]
	if a == nil {
		return world.Vec3{}, false
	}
	f := CellFrame(s.world, a.Cell)
	return f.Point(a.X, a.Y), true
}

// World é o mundo das regras.
func (s *Service) World() *world.World { return s.world }

// nearCountry: o ponto, ou algum a até r unidades dele, é do país?
func (s *Service) nearCountry(pos world.Vec3, country string, r float64) bool {
	if s.CountryAtPoint(pos) == country {
		return true
	}
	cell := s.world.FindCell(pos, -1)
	f := CellFrame(s.world, cell)
	x, y := f.Coords(pos)
	for k := 0; k < 8; k++ {
		a := float64(k) * math.Pi / 4
		if s.CountryAtPoint(f.Point(x+r*math.Cos(a), y+r*math.Sin(a))) == country {
			return true
		}
	}
	return false
}

// requireSellBox: para vender, o jogador precisa estar na caixa de vendas do próprio lote.
func (s *Service) requireSellBox(ctx context.Context, p *Player) error {
	if s.presence == nil {
		return nil
	}
	lot, err := s.store.LotByOwner(ctx, p.ID)
	if err != nil {
		return ErrNotFound.with("Você ainda não tem lote.")
	}
	pls, err := s.store.Placements(ctx, []int64{lot.ID})
	if err != nil {
		return err
	}
	f := CellFrame(s.world, lot.Cell)
	x0, y0, _, _ := SlotRect(lot.Slot)
	var last error = ErrNotFound.with("Coloque uma caixa de vendas no seu lote.")
	for _, pl := range pls {
		if pl.Item != "sell_box" {
			continue
		}
		pt := f.Point(x0+(float64(pl.X)+0.5)*TileSize, y0+(float64(pl.Y)+0.5)*TileSize)
		if last = s.requireNear(p, pt, s.content.Rules.Reach.SellBox, "da sua caixa de vendas"); last == nil {
			return nil
		}
	}
	return last
}

// arrival é um voo pago esperando a chegada (a camada em tempo real aceita o teleporte).
type arrival struct {
	country string
	until   time.Time
}

func (s *Service) allowArrival(player int64, country string) {
	s.arrivalMu.Lock()
	defer s.arrivalMu.Unlock()
	if s.arrivals == nil {
		s.arrivals = map[int64]arrival{}
	}
	s.arrivals[player] = arrival{country: country, until: time.Now().Add(2 * time.Minute)}
}

// ConsumeArrival devolve o ponto de chegada de um voo pago há pouco (uma vez só).
func (s *Service) ConsumeArrival(player int64) (world.Vec3, bool) {
	s.arrivalMu.Lock()
	a, ok := s.arrivals[player]
	delete(s.arrivals, player)
	s.arrivalMu.Unlock()
	if !ok || time.Now().After(a.until) {
		return world.Vec3{}, false
	}
	return s.ArrivalPoint(a.country)
}

// pediaSeen confere a foto: um animal da espécie (na posição do trajeto comum, com a folga
// das reações locais), a flor azul ou uma árvore da estação, perto do jogador e na direção
// da câmera.
func (s *Service) pediaSeen(ctx context.Context, p *Player, e *PediaEntry, look world.Vec3) error {
	pos, cell, _, checked, err := s.where(p)
	if err != nil || !checked {
		return err
	}
	if cell < 0 || cell >= len(s.world.Cells) {
		cell = s.world.FindCell(pos, -1)
	}
	r := s.content.Rules.Reach
	cosMax := math.Cos(r.PhotoAngle * math.Pi / 180)
	up := pos.Normalize()
	inView := func(target world.Vec3, maxDist float64) bool {
		d := s.groundDistance(pos, target)
		if d > maxDist {
			return false
		}
		if look.Len() < 1e-6 || d < 3 {
			return true
		}
		to := target.Sub(pos)
		to = to.Sub(up.Scale(to.Dot(up))).Normalize()
		l := look.Sub(up.Scale(look.Dot(up))).Normalize()
		return to.Dot(l) >= cosMax
	}
	cells := s.cellsAround(cell, 2)
	now := s.clock.Now()
	switch e.Kind {
	case "animal":
		animals, err := s.Animals(ctx, cells)
		if err != nil {
			return err
		}
		for i := range animals {
			if animals[i].Species == e.ID && inView(s.AnimalPoint(&animals[i], now), r.PhotoAnimal+r.AnimalDrift) {
				return nil
			}
		}
	default:
		lots, err := s.store.LotsByCells(ctx, cells)
		if err != nil {
			return err
		}
		for _, c := range cells {
			lat := s.world.Cells[c].Lat
			season := SeasonFor(now, lat, s.world.Cells[c].Biome)
			for _, o := range s.cellObjects(c, lots) {
				ok := false
				switch {
				case e.Kind == "flower":
					ok = o.Kind == KindFlower && o.Item == e.ID
				case e.Kind == "tree":
					ok = o.Kind == KindTree && ((e.Season == "autumn" && season == "autumn") || ((e.Season == "snow" || e.Season == "winter") && season == "winter"))
				}
				if ok && inView(s.ObjectPoint(&o), r.PhotoObject) {
					return nil
				}
			}
		}
	}
	return ErrTooFar.with("Não deu para ver %s daqui. Chegue mais perto e enquadre.", e.Name)
}

// cellsAround: a célula e as vizinhas até `rings` anéis.
func (s *Service) cellsAround(cell, rings int) []int {
	seen := map[int]bool{cell: true}
	front := []int{cell}
	for k := 0; k < rings; k++ {
		var next []int
		for _, c := range front {
			for _, nb := range s.world.Cells[c].Neighbors {
				if !seen[nb] {
					seen[nb] = true
					next = append(next, nb)
				}
			}
		}
		front = next
	}
	out := make([]int, 0, len(seen))
	for c := range seen {
		out = append(out, c)
	}
	return out
}
