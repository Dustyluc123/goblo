package game

import (
	"context"
	"fmt"
	"math"
	"sort"
	"sync"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Ações dentro das cavernas (fase 4.5, ADR 0056): entrar e sair, minerar, tochas.

// caveState é o que fica na memória: entradas pendentes, tochas acesas e o chefe.
type caveState struct {
	mu      sync.Mutex
	entries map[int64]caveEntry // jogador → caverna que ele pediu para entrar
	torches map[int][]Torch     // caverna → tochas acesas
	nextID  int64
	boss    map[int]*bossState // caverna → luta
	god     map[int64]bool     // modo dev: o chefe não acerta
}

type caveEntry struct {
	cave int
	at   time.Time
}

// Torch é uma tocha colocada numa caverna (na memória: some depois de torch.hours ou se o
// servidor reiniciar).
type Torch struct {
	ID    int64      `json:"id"`
	Owner int64      `json:"owner"`
	Pos   [3]float64 `json:"pos"` // na caverna (x, y, z)
	Until int64      `json:"until"`
}

func (st *caveState) init() {
	if st.entries == nil {
		st.entries = map[int64]caveEntry{}
		st.torches = map[int][]Torch{}
		st.boss = map[int]*bossState{}
		st.god = map[int64]bool{}
	}
}

// CaveView é o que o cliente recebe ao entrar: o desenho e o estado do dia.
type CaveView struct {
	Layout  *CaveLayout     `json:"layout"`
	Mined   []int64         `json:"mined"` // minérios que o jogador já quebrou hoje
	Hits    map[int64]int   `json:"hits"`  // golpes dados hoje nos que ainda não quebraram
	Torches []Torch         `json:"torches"`
	Boss    *BossPlayerView `json:"boss"`
	Spawn   [3]float64      `json:"spawn"` // onde nascer (espaço do mundo)
	Name    string          `json:"name"`
}

// CaveName é o nome da caverna para a interface ("Caverna do Brasil 2").
func (s *Service) CaveName(id int) string {
	cv := s.CaveByID(id)
	if cv == nil {
		return ""
	}
	n := 0
	for _, o := range s.Caves() {
		if o.Country == cv.Country {
			n++
			if o.ID == cv.ID {
				break
			}
		}
	}
	return fmt.Sprintf("Caverna %s %d", s.CountryName(cv.Country), n)
}

// requireNearCave confere se o jogador está dentro da caverna e a até reach (em linha reta)
// do ponto (x, y, z da caverna).
func (s *Service) requireNearCave(p *Player, cave int, x, y, z, reach float64, what string) error {
	pos, _, _, checked, err := s.where(p)
	if err != nil || !checked {
		return err
	}
	l := s.CaveLayoutOf(cave)
	if l == nil || s.CaveAt(pos) != cave {
		return ErrTooFar.with("Você não está nessa caverna.")
	}
	if pos.Sub(l.frame.Point(x, y, z)).Len() > reach {
		return ErrTooFar.with("Chegue mais perto %s.", what)
	}
	return nil
}

// EnterCave: o jogador está na boca da caverna (no globo) e pede para entrar. A entrada fica
// pendente; o teleporte "cave" da camada em tempo real a consome (ConsumeCaveEntry).
func (s *Service) EnterCave(ctx context.Context, p *Player, cave int) (*CaveView, error) {
	cv := s.CaveByID(cave)
	if cv == nil {
		return nil, ErrNotFound.with("Caverna desconhecida.")
	}
	at, _ := s.CaveEntrancePoint(cave)
	if err := s.requireNear(p, at, s.content.Caves.Reach+2, "da boca da caverna"); err != nil {
		return nil, err
	}
	s.cave.mu.Lock()
	s.cave.init()
	s.cave.entries[p.ID] = caveEntry{cave: cave, at: s.clock.Now()}
	s.cave.mu.Unlock()
	return s.CaveInfo(ctx, p, cave)
}

// ConsumeCaveEntry: a caverna que o jogador pediu para entrar há pouco (uma vez só).
func (s *Service) ConsumeCaveEntry(player int64) (int, bool) {
	s.cave.mu.Lock()
	defer s.cave.mu.Unlock()
	s.cave.init()
	e, ok := s.cave.entries[player]
	delete(s.cave.entries, player)
	if !ok || s.clock.Now().Sub(e.at) > time.Minute {
		return -1, false
	}
	return e.cave, true
}

// CaveInfo devolve o desenho da caverna e o estado do jogador nela hoje.
func (s *Service) CaveInfo(ctx context.Context, p *Player, cave int) (*CaveView, error) {
	l := s.CaveLayoutOf(cave)
	if l == nil {
		return nil, ErrNotFound.with("Caverna desconhecida.")
	}
	v := &CaveView{Layout: l, Hits: map[int64]int{}, Mined: []int64{}, Name: s.CaveName(cave)}
	day := DayIndex(s.clock.Now(), s.homeLon(ctx, s.store, p))
	for _, o := range l.Ores {
		mined, err := s.store.CollectionCount(ctx, p.ID, o.ID, "mine", day)
		if err != nil {
			return nil, err
		}
		if mined > 0 {
			v.Mined = append(v.Mined, o.ID)
			continue
		}
		hits, err := s.store.CollectionCount(ctx, p.ID, o.ID, "hit", day)
		if err != nil {
			return nil, err
		}
		if hits > 0 {
			v.Hits[o.ID] = hits
		}
	}
	v.Torches = s.CaveTorches(cave)
	start, _ := s.CaveStartPoint(cave)
	v.Spawn = vecArr(start)
	bv := s.bossPlayerView(ctx, p, cave)
	v.Boss = &bv
	return v, nil
}

// toolTier é o maior nível de ferramenta daquele tipo no bolso (0 = nenhuma).
func (s *Service) toolTier(inv []Stack, tool string) int {
	best := 0
	for _, st := range inv {
		if it := s.content.Item(st.Item); it != nil && it.Tool == tool && st.Count > 0 && it.Tier > best {
			best = it.Tier
		}
	}
	return best
}

func (s *Service) tierName(tool string, tier int) string {
	for _, it := range s.content.Items {
		if it.Tool == tool && it.Tier == tier {
			return it.Name
		}
	}
	return tool
}

// MineResult é a resposta de um golpe num minério.
type MineResult struct {
	Ore       int64       `json:"ore"`
	Hits      int         `json:"hits"` // golpes dados hoje
	Need      int         `json:"need"` // golpes para quebrar com a picareta atual
	Broken    bool        `json:"broken"`
	Gained    []StackView `json:"gained,omitempty"`
	Message   string      `json:"message"`
	Inventory []StackView `json:"inventory"`
	SlotsUsed int         `json:"slots_used"`
}

// MineOre dá um golpe num minério. Cada minério exige uma picareta mínima; com uma melhor,
// precisa de menos golpes e dá mais. Quebra uma vez por dia por jogador (todos veem os
// mesmos minérios).
func (s *Service) MineOre(ctx context.Context, p *Player, cave int, oreID int64) (*MineResult, error) {
	l := s.CaveLayoutOf(cave)
	if l == nil {
		return nil, ErrNotFound.with("Caverna desconhecida.")
	}
	var ore *CaveOre
	for i := range l.Ores {
		if l.Ores[i].ID == oreID {
			ore = &l.Ores[i]
		}
	}
	if ore == nil {
		return nil, ErrNotFound.with("Minério desconhecido.")
	}
	if err := s.requireNearCave(p, cave, ore.X, ore.Y, ore.Z, s.content.Caves.Reach, "do minério"); err != nil {
		return nil, err
	}
	var rule *OreRule
	for i := range s.content.Caves.Ores {
		if s.content.Caves.Ores[i].ID == ore.Ore {
			rule = &s.content.Caves.Ores[i]
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *MineResult
	err := s.store.InTx(ctx, func(tx Store) error {
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		tier := s.toolTier(inv, "pickaxe")
		if tier == 0 {
			return ErrNoTool.with("Você precisa de uma picareta.")
		}
		if tier < ore.MinTier {
			return ErrNoTool.with("Esse minério é duro demais: precisa de uma %s.", s.tierName("pickaxe", ore.MinTier))
		}
		day := DayIndex(s.clock.Now(), s.homeLon(ctx, tx, p))
		done, err := tx.CollectionCount(ctx, p.ID, ore.ID, "mine", day)
		if err != nil {
			return err
		}
		if done > 0 {
			return ErrLimit.with("Este veio já deu tudo hoje. Volte amanhã!")
		}
		hits, err := tx.CollectionCount(ctx, p.ID, ore.ID, "hit", day)
		if err != nil {
			return err
		}
		need := OreHits(ore.Hits, tier, ore.MinTier)
		hits++
		res = &MineResult{Ore: ore.ID, Hits: hits, Need: need}
		if hits < need {
			if err := tx.AddCollection(ctx, p.ID, ore.ID, -1, "hit", day); err != nil {
				return err
			}
			res.Message = fmt.Sprintf("Toc! (%d de %d)", hits, need)
		} else {
			r := newRNG(mix(uint64(p.ID), uint64(ore.ID), uint64(day)))
			n := rule.Count[0] + r.intn(rule.Count[1]-rule.Count[0]+1) + (tier - ore.MinTier)
			gained := []StackView{{Item: ore.Item, Count: n}}
			if err := s.addItems(ctx, tx, p.ID, inv, gained); err != nil {
				return err
			}
			if err := tx.AddCollection(ctx, p.ID, ore.ID, -1, "mine", day); err != nil {
				return err
			}
			res.Broken, res.Gained = true, gained
			res.Message = fmt.Sprintf("Você pegou %d× %s!", n, s.itemName(ore.Item))
		}
		inv, err = tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		res.Inventory, res.SlotsUsed = s.inventoryView(inv)
		return nil
	})
	if err == nil {
		s.exertBody(p.ID)
		s.emit(Event{Kind: "cave", Cell: -1, PlayerID: p.ID, Data: map[string]any{"cave": cave, "ore": oreID, "broken": res.Broken}})
	}
	return res, err
}

// OreHits: golpes para quebrar um minério com a picareta do nível tier (um a menos por
// nível acima do mínimo, pelo menos um).
func OreHits(hits, tier, minTier int) int {
	return max(1, hits-(tier-minTier))
}

// --- Tochas --------------------------------------------------------------------------------

// CaveTorches lista as tochas acesas de uma caverna (tira as que apagaram).
func (s *Service) CaveTorches(cave int) []Torch {
	s.cave.mu.Lock()
	defer s.cave.mu.Unlock()
	s.cave.init()
	now := s.clock.Now().Unix()
	list := s.cave.torches[cave][:0]
	for _, t := range s.cave.torches[cave] {
		if t.Until > now {
			list = append(list, t)
		}
	}
	s.cave.torches[cave] = list
	return append([]Torch{}, list...)
}

// TorchResult é a resposta de pôr ou tirar uma tocha.
type TorchResult struct {
	Torches   []Torch     `json:"torches"`
	Message   string      `json:"message"`
	Inventory []StackView `json:"inventory"`
	SlotsUsed int         `json:"slots_used"`
}

// PlaceTorch põe uma tocha do bolso na caverna (parede ou chão), até torch.limit acesas por
// jogador em cada caverna.
func (s *Service) PlaceTorch(ctx context.Context, p *Player, cave int, pos [3]float64) (*TorchResult, error) {
	cc := s.content.Caves
	if !finite3(pos) {
		return nil, ErrInvalid
	}
	if err := s.requireNearCave(p, cave, pos[0], pos[1], pos[2], cc.Torch.Reach, "de onde quer pôr a tocha"); err != nil {
		return nil, err
	}
	mine := 0
	for _, t := range s.CaveTorches(cave) {
		if t.Owner == p.ID {
			mine++
		}
	}
	if mine >= cc.Torch.Limit {
		return nil, ErrLimit.with("Você já tem %d tochas acesas nesta caverna. Pegue uma de volta (E) para mudar de lugar.", cc.Torch.Limit)
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *TorchResult
	err := s.store.InTx(ctx, func(tx Store) error {
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		if !has(inv, "torch") {
			return ErrMissingMaterials.with("Você não tem tochas. Faça na bancada (carvão + galho).")
		}
		if err := tx.AddItem(ctx, p.ID, "torch", -1); err != nil {
			return err
		}
		inv, err = tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		res = &TorchResult{Message: "Tocha acesa!"}
		res.Inventory, res.SlotsUsed = s.inventoryView(inv)
		return nil
	})
	if err != nil {
		return nil, err
	}
	s.cave.mu.Lock()
	s.cave.init()
	s.cave.nextID++
	s.cave.torches[cave] = append(s.cave.torches[cave], Torch{ID: s.cave.nextID, Owner: p.ID, Pos: pos,
		Until: s.clock.Now().Add(time.Duration(cc.Torch.Hours * float64(time.Hour))).Unix()})
	s.cave.mu.Unlock()
	res.Torches = s.CaveTorches(cave)
	s.emit(Event{Kind: "cave", Cell: -1, PlayerID: p.ID, Data: map[string]any{"cave": cave, "torches": res.Torches}})
	return res, nil
}

// TakeTorch pega de volta uma tocha própria (volta para o bolso).
func (s *Service) TakeTorch(ctx context.Context, p *Player, cave int, id int64) (*TorchResult, error) {
	var t *Torch
	for _, o := range s.CaveTorches(cave) {
		if o.ID == id {
			t = &o
			break
		}
	}
	if t == nil {
		return nil, ErrNotFound.with("Essa tocha já apagou.")
	}
	if t.Owner != p.ID {
		return nil, ErrNotOwner.with("Essa tocha é de outra pessoa.")
	}
	if err := s.requireNearCave(p, cave, t.Pos[0], t.Pos[1], t.Pos[2], s.content.Caves.Torch.Reach, "da tocha"); err != nil {
		return nil, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *TorchResult
	err := s.store.InTx(ctx, func(tx Store) error {
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		if err := s.addItems(ctx, tx, p.ID, inv, []StackView{{Item: "torch", Count: 1}}); err != nil {
			return err
		}
		inv, err = tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		res = &TorchResult{Message: "Você pegou a tocha de volta."}
		res.Inventory, res.SlotsUsed = s.inventoryView(inv)
		return nil
	})
	if err != nil {
		return nil, err
	}
	s.cave.mu.Lock()
	list := s.cave.torches[cave]
	for i := range list {
		if list[i].ID == id {
			s.cave.torches[cave] = append(list[:i:i], list[i+1:]...)
			break
		}
	}
	s.cave.mu.Unlock()
	res.Torches = s.CaveTorches(cave)
	s.emit(Event{Kind: "cave", Cell: -1, PlayerID: p.ID, Data: map[string]any{"cave": cave, "torches": res.Torches}})
	return res, nil
}

func finite3(a [3]float64) bool {
	for _, v := range a {
		if math.IsNaN(v) || math.IsInf(v, 0) {
			return false
		}
	}
	return true
}

// --- Modo dev ------------------------------------------------------------------------------

// NearestCave é a boca de caverna mais perto de um ponto do globo.
func (s *Service) NearestCave(p world.Vec3) *Cave {
	best, bestD := -1, -2.0
	for i := range s.Caves() {
		at, _ := s.CaveEntrancePoint(i)
		if d := at.Normalize().Dot(p.Normalize()); d > bestD {
			best, bestD = i, d
		}
	}
	return s.CaveByID(best)
}

// DevEnterCave (modo dev): entra em qualquer caverna, de onde estiver.
func (s *Service) DevEnterCave(ctx context.Context, p *Player, cave int) (*CaveView, error) {
	if s.CaveByID(cave) == nil {
		return nil, ErrNotFound.with("Caverna desconhecida.")
	}
	s.cave.mu.Lock()
	s.cave.init()
	s.cave.entries[p.ID] = caveEntry{cave: cave, at: s.clock.Now()}
	s.cave.mu.Unlock()
	return s.CaveInfo(ctx, p, cave)
}

// DevCaveKit (modo dev): picaretas e machados de todos os níveis, tochas, minérios e barras.
func (s *Service) DevCaveKit(ctx context.Context, p *Player) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	give := map[string]int{"torch": 20, "coal": 30, "iron_ore": 20, "iron_bar": 12, "goblita": 10, "goblita_bar": 6,
		"diamond": 8, "auralita": 6, "auralita_bar": 3, "golem_heart": 2, "lamp_helmet": 1, "furnace": 1, "chest": 1}
	for _, it := range s.content.Items {
		if it.Tool == "pickaxe" || it.Tool == "axe" {
			give[it.ID] = 1
		}
	}
	keys := make([]string, 0, len(give))
	for k := range give {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return s.store.InTx(ctx, func(tx Store) error {
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		for _, k := range keys {
			if has(inv, k) && s.content.Item(k).Stack == 1 {
				continue
			}
			if err := tx.AddItem(ctx, p.ID, k, give[k]); err != nil {
				return err
			}
		}
		return nil
	})
}

// DevBossGod (modo dev): o chefe não acerta o jogador.
func (s *Service) DevBossGod(p *Player, on bool) {
	s.cave.mu.Lock()
	defer s.cave.mu.Unlock()
	s.cave.init()
	if on {
		s.cave.god[p.ID] = true
	} else {
		delete(s.cave.god, p.ID)
	}
}
