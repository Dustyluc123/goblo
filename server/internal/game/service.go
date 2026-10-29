package game

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// InventorySlots é quantos espaços o inventário tem.
const InventorySlots = 20

// Limites diários por jogador e objeto.
var dailyLimits = map[string]int{"shake": 1, "chop": 3, "mine": 3, "pick": 1}

// Biomas preferidos para o lote de um jogador novo.
var pleasantBiomes = map[world.Biome]bool{
	world.BiomeGrassland: true, world.BiomeForest: true, world.BiomeTropicalForest: true, world.BiomeBeach: true,
}

// Onde fica a bancada num lote novo (canto, longe do meio, que é o lugar natural da casa).
const workbenchX, workbenchY = 11, 1

// Service aplica as regras do jogo. É a fonte da verdade do inventário, dos limites
// diários e dos lotes; o cliente só pede e mostra o resultado.
type Service struct {
	world   *world.World
	content *Content
	store   Store
	clock   Clock

	mu        sync.Mutex // as escritas são em série (SQLite tem um escritor só)
	byCountry map[string][]int
}

// NewService monta as regras. clock nil = relógio real.
func NewService(w *world.World, content *Content, store Store, clock Clock) *Service {
	if clock == nil {
		clock = RealClock{}
	}
	s := &Service{world: w, content: content, store: store, clock: clock}
	s.indexCountries()
	return s
}

// Content devolve o conteúdo do jogo (itens, receitas, casas).
func (s *Service) Content() *Content { return s.content }

// Clock devolve o relógio das regras.
func (s *Service) Clock() Clock { return s.clock }

// indexCountries ordena as células de cada país para a escolha de lote: biomas agradáveis
// primeiro e, dentro de cada grupo, as mais perto do "centro" do país. Assim os jogadores
// de um país vão enchendo as mesmas células e viram vizinhos.
func (s *Service) indexCountries() {
	s.byCountry = map[string][]int{}
	sums := map[string]world.Vec3{}
	for i, c := range s.world.Cells {
		if c.Terrain != world.Land || c.Country == "" {
			continue
		}
		s.byCountry[c.Country] = append(s.byCountry[c.Country], i)
		sums[c.Country] = sums[c.Country].Add(cellVec(&c))
	}
	for code, cells := range s.byCountry {
		anchor := sums[code].Normalize()
		sort.SliceStable(cells, func(a, b int) bool {
			ca, cb := &s.world.Cells[cells[a]], &s.world.Cells[cells[b]]
			pa, pb := pleasantBiomes[ca.Biome], pleasantBiomes[cb.Biome]
			if pa != pb {
				return pa
			}
			da, db := cellVec(ca).Dot(anchor), cellVec(cb).Dot(anchor)
			if da != db {
				return da > db
			}
			return cells[a] < cells[b]
		})
	}
}

func cellVec(c *world.Cell) world.Vec3 {
	return world.Vec3{X: c.Center[0], Y: c.Center[1], Z: c.Center[2]}
}

// --- Jogadores ----------------------------------------------------------------------------

// HashToken é o que fica guardado no banco no lugar do token.
func HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func newToken() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

// CreatePlayer cria o jogador com um lote livre no país dele e uma bancada no lote.
// Devolve o token secreto (só aparece aqui; o banco guarda o hash).
func (s *Service) CreatePlayer(ctx context.Context, nickname, country string) (*Player, string, error) {
	nick, err := ValidateNickname(nickname)
	if err != nil {
		return nil, "", err
	}
	if _, ok := s.world.Countries[country]; !ok {
		return nil, "", ErrCountry
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	token := newToken()
	p := &Player{Nickname: nick, Country: country, TokenHash: HashToken(token), CreatedAt: s.clock.Now().UTC()}
	err = s.store.InTx(ctx, func(tx Store) error {
		if err := tx.CreatePlayer(ctx, p); err != nil {
			return err
		}
		_, err := s.assignLot(ctx, tx, p, country)
		return err
	})
	if err != nil {
		return nil, "", err
	}
	return p, token, nil
}

// Authenticate acha o jogador pelo token.
func (s *Service) Authenticate(ctx context.Context, token string) (*Player, error) {
	if token == "" {
		return nil, ErrUnauthorized
	}
	p, err := s.store.PlayerByTokenHash(ctx, HashToken(token))
	if errors.Is(err, ErrNotFound) {
		return nil, ErrUnauthorized
	}
	return p, err
}

// assignLot escolhe um lote livre no país e já coloca a bancada. Usa as células do país na
// ordem de indexCountries; se o país não tem lote livre, erro.
func (s *Service) assignLot(ctx context.Context, tx Store, p *Player, country string) (*Lot, error) {
	cells := s.byCountry[country]
	const batch = 64
	for start := 0; start < len(cells); start += batch {
		end := min(start+batch, len(cells))
		if lot, err := s.firstFreeLot(ctx, tx, p, cells[start:end]); lot != nil || err != nil {
			return lot, err
		}
	}
	return nil, ErrNoLot.with("Não há lote livre em %s.", s.world.Countries[country])
}

// firstFreeLot ocupa o primeiro lote livre das células, na ordem dada.
func (s *Service) firstFreeLot(ctx context.Context, tx Store, p *Player, cells []int) (*Lot, error) {
	lots, err := tx.LotsByCells(ctx, cells)
	if err != nil {
		return nil, err
	}
	taken := map[int64]bool{}
	for _, l := range lots {
		taken[l.ID] = true
	}
	for _, cell := range cells {
		for _, slot := range LotSlots(s.world, cell) {
			if taken[slot.ID] {
				continue
			}
			lot := &Lot{ID: slot.ID, Cell: cell, Slot: slot.Slot, OwnerID: p.ID}
			if err := tx.CreateLot(ctx, lot); err != nil {
				return nil, err
			}
			wb := &Placement{LotID: lot.ID, Item: "workbench", X: workbenchX, Y: workbenchY}
			if err := tx.CreatePlacement(ctx, wb); err != nil {
				return nil, err
			}
			return lot, nil
		}
	}
	return nil, nil
}

// homeLon é a longitude da casa do jogador, que define quando o dia dele vira.
func (s *Service) homeLon(ctx context.Context, st Store, p *Player) float64 {
	if lot, err := st.LotByOwner(ctx, p.ID); err == nil {
		return s.world.Cells[lot.Cell].Lon
	}
	return 0
}

// --- Visões (o que vai em JSON para o cliente) ------------------------------------------

// StackView é um item do inventário.
type StackView struct {
	Item  string `json:"item"`
	Count int    `json:"count"`
}

// DayView diz em que dia do jogo o jogador está e quando o dia vira.
type DayView struct {
	Index        int64 `json:"index"`
	NextRollover int64 `json:"next_rollover"` // unix
	ServerTime   int64 `json:"server_time"`   // unix (o modo dev pode adiantar)
}

// HouseView é a casa de um lote.
type HouseView struct {
	Level        int    `json:"level"` // pronto (0 = sem casa)
	Name         string `json:"name"`
	PendingLevel int    `json:"pending_level"`
	ReadyAt      int64  `json:"ready_at"`
	X            int    `json:"x"`
	Y            int    `json:"y"`
	Rot          int    `json:"rot"`
	// Canto da obra (pode diferir de X, Y na melhoria; a obra pode crescer e se deslocar).
	PendingX int `json:"pending_x"`
	PendingY int `json:"pending_y"`
}

// PlacementView é um objeto colocado num lote.
type PlacementView struct {
	ID   int64  `json:"id"`
	Item string `json:"item"`
	X    int    `json:"x"`
	Y    int    `json:"y"`
	Rot  int    `json:"rot"`
}

// LotView é um lote ocupado com a casa e os objetos colocados.
type LotView struct {
	ID         int64           `json:"id"`
	Cell       int             `json:"cell"`
	Slot       int             `json:"slot"`
	X0         float64         `json:"x0"`
	Y0         float64         `json:"y0"`
	OwnerID    int64           `json:"owner_id"`
	Owner      string          `json:"owner"`
	House      *HouseView      `json:"house"`
	Placements []PlacementView `json:"placements"`
}

// MeView é tudo o que o cliente precisa saber do próprio jogador.
type MeView struct {
	ID          int64       `json:"id"`
	Nickname    string      `json:"nickname"`
	Country     string      `json:"country"`
	CountryName string      `json:"country_name"`
	Lot         *LotView    `json:"lot"`
	Inventory   []StackView `json:"inventory"`
	SlotsUsed   int         `json:"slots_used"`
	SlotsMax    int         `json:"slots_max"`
	Day         DayView     `json:"day"`
}

// Me devolve o estado do jogador.
func (s *Service) Me(ctx context.Context, p *Player) (*MeView, error) {
	return s.meView(ctx, s.store, p)
}

func (s *Service) meView(ctx context.Context, st Store, p *Player) (*MeView, error) {
	now := s.clock.Now()
	me := &MeView{ID: p.ID, Nickname: p.Nickname, Country: p.Country, CountryName: s.world.Countries[p.Country], SlotsMax: InventorySlots}
	lot, err := st.LotByOwner(ctx, p.ID)
	if err != nil && !errors.Is(err, ErrNotFound) {
		return nil, err
	}
	lon := 0.0
	if lot != nil {
		views, err := s.lotViews(ctx, st, []Lot{*lot})
		if err != nil {
			return nil, err
		}
		me.Lot = &views[0]
		lon = s.world.Cells[lot.Cell].Lon
	}
	inv, err := st.Inventory(ctx, p.ID)
	if err != nil {
		return nil, err
	}
	me.Inventory, me.SlotsUsed = s.inventoryView(inv)
	me.Day = DayView{Index: DayIndex(now, lon), NextRollover: NextRollover(now, lon).Unix(), ServerTime: now.Unix()}
	return me, nil
}

func (s *Service) inventoryView(inv []Stack) ([]StackView, int) {
	out := make([]StackView, 0, len(inv))
	for _, st := range inv {
		out = append(out, StackView{Item: st.Item, Count: st.Count})
	}
	return out, s.slotsUsed(inv)
}

func (s *Service) slotsUsed(inv []Stack) int {
	used := 0
	for _, st := range inv {
		stack := 99
		if it := s.content.Item(st.Item); it != nil {
			stack = it.Stack
		}
		used += (st.Count + stack - 1) / stack
	}
	return used
}

// settle conclui a obra se a hora de ficar pronta já passou. Devolve true se mudou.
func settle(l *Lot, now time.Time) bool {
	if l.PendingLevel > 0 && !now.Before(l.ReadyAt) {
		finish(l)
		return true
	}
	return false
}

// finish conclui a obra na hora: a casa nova assume o lugar da obra.
func finish(l *Lot) {
	l.HouseLevel = l.PendingLevel
	l.HouseX, l.HouseY = l.PendingX, l.PendingY
	l.PendingLevel = 0
	l.ReadyAt = time.Time{}
}

func (s *Service) lotViews(ctx context.Context, st Store, lots []Lot) ([]LotView, error) {
	now := s.clock.Now()
	ids := make([]int64, len(lots))
	owners := make([]int64, len(lots))
	for i, l := range lots {
		ids[i] = l.ID
		owners[i] = l.OwnerID
	}
	placements, err := st.Placements(ctx, ids)
	if err != nil {
		return nil, err
	}
	players, err := st.PlayersByIDs(ctx, owners)
	if err != nil {
		return nil, err
	}
	byLot := map[int64][]PlacementView{}
	for _, p := range placements {
		byLot[p.LotID] = append(byLot[p.LotID], PlacementView{ID: p.ID, Item: p.Item, X: p.X, Y: p.Y, Rot: p.Rot})
	}
	out := make([]LotView, len(lots))
	for i, l := range lots {
		settle(&l, now)
		x0, y0, _, _ := SlotRect(l.Slot)
		v := LotView{ID: l.ID, Cell: l.Cell, Slot: l.Slot, X0: x0, Y0: y0, OwnerID: l.OwnerID, Placements: byLot[l.ID]}
		if v.Placements == nil {
			v.Placements = []PlacementView{}
		}
		if p := players[l.OwnerID]; p != nil {
			v.Owner = p.Nickname
		}
		if l.HouseLevel > 0 || l.PendingLevel > 0 {
			h := &HouseView{Level: l.HouseLevel, PendingLevel: l.PendingLevel, X: l.HouseX, Y: l.HouseY, Rot: l.HouseRot, PendingX: l.PendingX, PendingY: l.PendingY}
			if l.PendingLevel > 0 {
				h.ReadyAt = l.ReadyAt.Unix()
			}
			if hl := s.content.House(l.HouseLevel); hl != nil {
				h.Name = hl.Name
			}
			v.House = h
		}
		out[i] = v
	}
	return out, nil
}

// Lots devolve os lotes ocupados das células (de todo mundo), com casas e objetos.
func (s *Service) Lots(ctx context.Context, cells []int) ([]LotView, error) {
	lots, err := s.store.LotsByCells(ctx, sortedCells(cells))
	if err != nil {
		return nil, err
	}
	return s.lotViews(ctx, s.store, lots)
}

// --- Objetos e coleta -----------------------------------------------------------------------

// ObjectView é um objeto com o que o jogador já fez nele hoje.
type ObjectView struct {
	Object
	State map[string]int `json:"state,omitempty"`
}

// cellObjects gera os objetos da célula e tira os que caem em lotes ocupados.
func (s *Service) cellObjects(cell int, lots []Lot) []Object {
	var slots []int
	for _, l := range lots {
		if l.Cell == cell {
			slots = append(slots, l.Slot)
		}
	}
	return FilterLots(GenerateObjects(s.world, s.content, cell), slots)
}

// Objects devolve os objetos interativos das células com o estado do dia para o jogador.
func (s *Service) Objects(ctx context.Context, p *Player, cells []int) ([]ObjectView, DayView, error) {
	cells = sortedCells(cells)
	now := s.clock.Now()
	lon := s.homeLon(ctx, s.store, p)
	day := DayIndex(now, lon)
	dv := DayView{Index: day, NextRollover: NextRollover(now, lon).Unix(), ServerTime: now.Unix()}
	lots, err := s.store.LotsByCells(ctx, cells)
	if err != nil {
		return nil, dv, err
	}
	cols, err := s.store.Collections(ctx, p.ID, day, cells)
	if err != nil {
		return nil, dv, err
	}
	state := map[int64]map[string]int{}
	for _, c := range cols {
		if state[c.ObjectID] == nil {
			state[c.ObjectID] = map[string]int{}
		}
		state[c.ObjectID][c.Action] = c.Count
	}
	var out []ObjectView
	for _, cell := range cells {
		if cell < 0 || cell >= len(s.world.Cells) {
			continue
		}
		for _, o := range s.cellObjects(cell, lots) {
			out = append(out, ObjectView{Object: o, State: state[o.ID]})
		}
	}
	if out == nil {
		out = []ObjectView{}
	}
	return out, dv, nil
}

// InteractResult é a resposta de uma interação.
type InteractResult struct {
	Action    string         `json:"action"`
	Gained    []StackView    `json:"gained"`
	State     map[string]int `json:"state"`
	Inventory []StackView    `json:"inventory"`
	SlotsUsed int            `json:"slots_used"`
	Message   string         `json:"message"`
}

// Interact aplica uma ação (shake, chop, mine, pick) num objeto.
//
// TODO(fase 3): conferir se o jogador está perto do objeto. Hoje o servidor não sabe onde
// o jogador está, então aceita a interação sem checar a distância (ADR 0021).
func (s *Service) Interact(ctx context.Context, p *Player, objectID int64, action string) (*InteractResult, error) {
	cell := ObjectCell(objectID)
	if objectID < 0 || cell >= len(s.world.Cells) {
		return nil, ErrNotFound
	}
	limit, ok := dailyLimits[action]
	if !ok {
		return nil, ErrWrongAction
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *InteractResult
	err := s.store.InTx(ctx, func(tx Store) error {
		lots, err := tx.LotsByCells(ctx, []int{cell})
		if err != nil {
			return err
		}
		var obj *Object
		for _, o := range s.cellObjects(cell, lots) {
			if o.ID == objectID {
				obj = &o
				break
			}
		}
		if obj == nil {
			return ErrNotFound
		}
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		if err := s.checkAction(obj, action, inv); err != nil {
			return err
		}
		day := DayIndex(s.clock.Now(), s.homeLon(ctx, tx, p))
		done, err := tx.CollectionCount(ctx, p.ID, objectID, action, day)
		if err != nil {
			return err
		}
		if done >= limit {
			return limitError(obj, action)
		}
		gained := s.reward(p, obj, action, day, done)
		if err := s.addItems(ctx, tx, p.ID, inv, gained); err != nil {
			return err
		}
		if err := tx.AddCollection(ctx, p.ID, objectID, cell, action, day); err != nil {
			return err
		}
		res = &InteractResult{Action: action, Gained: gained, Message: s.rewardMessage(obj, action, gained)}
		cols, err := tx.Collections(ctx, p.ID, day, []int{cell})
		if err != nil {
			return err
		}
		res.State = map[string]int{}
		for _, c := range cols {
			if c.ObjectID == objectID {
				res.State[c.Action] = c.Count
			}
		}
		inv, err = tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		res.Inventory, res.SlotsUsed = s.inventoryView(inv)
		return nil
	})
	return res, err
}

func has(inv []Stack, item string) bool {
	for _, st := range inv {
		if st.Item == item && st.Count > 0 {
			return true
		}
	}
	return false
}

// checkAction confere se a ação faz sentido para o tipo de objeto e se há ferramenta.
func (s *Service) checkAction(o *Object, action string, inv []Stack) error {
	switch o.Kind {
	case KindTree:
		switch action {
		case "shake":
			return nil
		case "chop":
			if !o.Chop {
				return ErrWrongAction.with("Não dá para cortar isso.")
			}
			if !has(inv, "axe") {
				return ErrNoTool.with("Você precisa de um machado.")
			}
			return nil
		}
	case KindRock:
		if action == "mine" {
			if !has(inv, "pickaxe") {
				return ErrNoTool.with("Você precisa de uma picareta.")
			}
			return nil
		}
	case KindBush:
		if action == "shake" || action == "pick" {
			if action == "pick" {
				return ErrWrongAction.with("Sacuda o arbusto para colher.")
			}
			return nil
		}
	case KindFlower, KindPebble, KindBranch:
		if action == "pick" {
			return nil
		}
	}
	return ErrWrongAction
}

func limitError(o *Object, action string) error {
	switch action {
	case "shake":
		return ErrLimit.with("Você já sacudiu isso hoje. Volte amanhã!")
	case "chop":
		return ErrLimit.with("Esta árvore já deu toda a madeira de hoje.")
	case "mine":
		return ErrLimit.with("Esta pedra já deu tudo o que podia hoje.")
	}
	return ErrLimit.with("Você já pegou isso hoje.")
}

// reward sorteia o que a ação dá. A semente é (jogador, objeto, dia, ação, vez), então o
// resultado é reproduzível nos testes.
func (s *Service) reward(p *Player, o *Object, action string, day int64, done int) []StackView {
	r := newRNG(mix(uint64(p.ID), uint64(o.ID), uint64(day), uint64(len(action)), uint64(action[0]), uint64(done)))
	switch {
	case action == "chop":
		return []StackView{{Item: "wood", Count: 1}}
	case action == "mine":
		return []StackView{{Item: "stone", Count: 1}}
	case o.Kind == KindTree && action == "shake":
		switch o.Drop {
		case "coconut":
			return []StackView{{Item: "coconut", Count: 1}}
		case "none":
			return nil
		}
		return []StackView{{Item: "branch", Count: 1 + r.intn(3)}}
	case o.Kind == KindBush:
		return []StackView{{Item: "berries", Count: 1 + r.intn(3)}}
	case o.Kind == KindFlower:
		item := o.Item
		if item == "" {
			item = "flower_red"
		}
		return []StackView{{Item: item, Count: 1}}
	case o.Kind == KindPebble:
		return []StackView{{Item: "stone", Count: 1}}
	case o.Kind == KindBranch:
		return []StackView{{Item: "branch", Count: 1}}
	}
	return nil
}

func (s *Service) rewardMessage(o *Object, action string, gained []StackView) string {
	if len(gained) == 0 {
		if o.Kind == KindTree && action == "shake" {
			return "A árvore balançou, mas não caiu nada."
		}
		return ""
	}
	parts := make([]string, len(gained))
	for i, g := range gained {
		name := g.Item
		if it := s.content.Item(g.Item); it != nil {
			name = it.Name
		}
		parts[i] = fmt.Sprintf("%d× %s", g.Count, name)
	}
	return "Você pegou " + strings.Join(parts, ", ") + "!"
}

// addItems soma itens ao inventário, conferindo se cabem nos 20 espaços.
func (s *Service) addItems(ctx context.Context, tx Store, player int64, inv []Stack, gained []StackView) error {
	next := applyDelta(inv, gained, 1)
	if s.slotsUsed(next) > InventorySlots && s.slotsUsed(next) > s.slotsUsed(inv) {
		return ErrInventoryFull
	}
	for _, g := range gained {
		if err := tx.AddItem(ctx, player, g.Item, g.Count); err != nil {
			return err
		}
	}
	return nil
}

func applyDelta(inv []Stack, delta []StackView, sign int) []Stack {
	out := append([]Stack(nil), inv...)
	for _, d := range delta {
		found := false
		for i := range out {
			if out[i].Item == d.Item {
				out[i].Count += sign * d.Count
				found = true
			}
		}
		if !found && sign > 0 {
			out = append(out, Stack{Item: d.Item, Count: d.Count})
		}
	}
	return out
}

// --- Fabricação -----------------------------------------------------------------------------

// CraftResult é a resposta de uma fabricação.
type CraftResult struct {
	Crafted   StackView   `json:"crafted"`
	Consumed  []StackView `json:"consumed"`
	Inventory []StackView `json:"inventory"`
	SlotsUsed int         `json:"slots_used"`
	Message   string      `json:"message"`
}

// resolveCost transforma um custo (com grupos "#tag") em itens concretos do inventário.
// Para grupos, gasta primeiro o que o jogador tem mais. Erro se faltar algo.
func (s *Service) resolveCost(cost map[string]int, times int, inv []Stack) ([]StackView, error) {
	have := map[string]int{}
	for _, st := range inv {
		have[st.Item] = st.Count
	}
	keys := make([]string, 0, len(cost))
	for k := range cost {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(a, b int) bool { // itens exatos antes dos grupos
		ga, gb := strings.HasPrefix(keys[a], "#"), strings.HasPrefix(keys[b], "#")
		if ga != gb {
			return !ga
		}
		return keys[a] < keys[b]
	})
	used := map[string]int{}
	var missing []string
	for _, k := range keys {
		need := cost[k] * times
		if !strings.HasPrefix(k, "#") {
			if have[k]-used[k] < need {
				missing = append(missing, fmt.Sprintf("%d× %s", need-(have[k]-used[k]), s.itemName(k)))
				continue
			}
			used[k] += need
			continue
		}
		cands := s.content.itemsWithTag(k[1:])
		sort.SliceStable(cands, func(a, b int) bool { return have[cands[a]]-used[cands[a]] > have[cands[b]]-used[cands[b]] })
		for _, c := range cands {
			take := min(need, have[c]-used[c])
			if take > 0 {
				used[c] += take
				need -= take
			}
		}
		if need > 0 {
			missing = append(missing, fmt.Sprintf("%d× %s", need, groupName(k)))
		}
	}
	if len(missing) > 0 {
		return nil, ErrMissingMaterials.with("Faltam: %s.", strings.Join(missing, ", "))
	}
	out := make([]StackView, 0, len(used))
	for item, n := range used {
		out = append(out, StackView{Item: item, Count: n})
	}
	sort.Slice(out, func(a, b int) bool { return out[a].Item < out[b].Item })
	return out, nil
}

func (s *Service) itemName(id string) string {
	if it := s.content.Item(id); it != nil {
		return strings.ToLower(it.Name)
	}
	return id
}

func groupName(tag string) string {
	if tag == "#flower" {
		return "flor (qualquer cor)"
	}
	return tag
}

// consume tira os itens do inventário.
func consume(ctx context.Context, tx Store, player int64, items []StackView) error {
	for _, it := range items {
		if err := tx.AddItem(ctx, player, it.Item, -it.Count); err != nil {
			return err
		}
	}
	return nil
}

// Craft fabrica uma receita `times` vezes.
//
// TODO(fase 3): conferir se o jogador está perto de uma bancada (hoje só o cliente confere).
func (s *Service) Craft(ctx context.Context, p *Player, recipeID string, times int) (*CraftResult, error) {
	r := s.content.Recipe(recipeID)
	if r == nil {
		return nil, ErrNotFound.with("Receita desconhecida.")
	}
	if times <= 0 || times > 99 {
		return nil, ErrInvalid
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *CraftResult
	err := s.store.InTx(ctx, func(tx Store) error {
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		used, err := s.resolveCost(r.Ingredients, times, inv)
		if err != nil {
			return err
		}
		made := StackView{Item: r.Result, Count: r.Count * times}
		after := applyDelta(applyDelta(inv, used, -1), []StackView{made}, 1)
		if s.slotsUsed(after) > InventorySlots {
			return ErrInventoryFull
		}
		if err := consume(ctx, tx, p.ID, used); err != nil {
			return err
		}
		if err := tx.AddItem(ctx, p.ID, made.Item, made.Count); err != nil {
			return err
		}
		inv, err = tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		res = &CraftResult{Crafted: made, Consumed: used, Message: fmt.Sprintf("Você fabricou %d× %s!", made.Count, s.itemName(made.Item))}
		res.Inventory, res.SlotsUsed = s.inventoryView(inv)
		return nil
	})
	return res, err
}

// --- Lote: decoração e casa -----------------------------------------------------------------

type rect struct{ x0, y0, x1, y1 int } // [x0, x1) × [y0, y1)

func (a rect) overlaps(b rect) bool { return a.x0 < b.x1 && b.x0 < a.x1 && a.y0 < b.y1 && b.y0 < a.y1 }

func footprintRect(fp [2]int, x, y, rot int) rect {
	w, h := fp[0], fp[1]
	if rot%2 == 1 {
		w, h = h, w
	}
	return rect{x, y, x + w, y + h}
}

func (r rect) inLot() bool { return r.x0 >= 0 && r.y0 >= 0 && r.x1 <= LotTiles && r.y1 <= LotTiles }

func (s *Service) houseRect(l *Lot, level int) (rect, bool) {
	h := s.content.House(level)
	if h == nil {
		return rect{}, false
	}
	return footprintRect(h.Footprint, l.HouseX, l.HouseY, l.HouseRot), true
}

// occupied devolve os retângulos ocupados no lote: casa pronta, obra e objetos (sem as
// casas se skipHouse).
func (s *Service) occupied(l *Lot, placements []Placement, skipHouse bool) []rect {
	var out []rect
	if !skipHouse {
		if r, ok := s.houseRect(l, l.HouseLevel); ok {
			out = append(out, r)
		}
		if h := s.content.House(l.PendingLevel); h != nil {
			out = append(out, footprintRect(h.Footprint, l.PendingX, l.PendingY, l.HouseRot))
		}
	}
	for _, p := range placements {
		if it := s.content.Item(p.Item); it != nil {
			out = append(out, footprintRect(it.Footprint, p.X, p.Y, p.Rot))
		}
	}
	return out
}

// ownLot devolve o lote do jogador (com a obra já concluída, se for a hora).
func (s *Service) ownLot(ctx context.Context, tx Store, p *Player) (*Lot, error) {
	lot, err := tx.LotByOwner(ctx, p.ID)
	if errors.Is(err, ErrNotFound) {
		return nil, ErrNoLot.with("Você ainda não tem lote.")
	}
	if err != nil {
		return nil, err
	}
	if settle(lot, s.clock.Now()) {
		if err := tx.UpdateLot(ctx, lot); err != nil {
			return nil, err
		}
	}
	return lot, nil
}

// PlaceResult é a resposta de colocar ou guardar um objeto.
type PlaceResult struct {
	Lot       LotView     `json:"lot"`
	Inventory []StackView `json:"inventory"`
	SlotsUsed int         `json:"slots_used"`
}

func (s *Service) placeResult(ctx context.Context, tx Store, p *Player, lot *Lot) (*PlaceResult, error) {
	views, err := s.lotViews(ctx, tx, []Lot{*lot})
	if err != nil {
		return nil, err
	}
	inv, err := tx.Inventory(ctx, p.ID)
	if err != nil {
		return nil, err
	}
	res := &PlaceResult{Lot: views[0]}
	res.Inventory, res.SlotsUsed = s.inventoryView(inv)
	return res, nil
}

// Place coloca um item do inventário no lote do jogador. lotID precisa ser o lote dele.
func (s *Service) Place(ctx context.Context, p *Player, lotID int64, item string, x, y, rot int) (*PlaceResult, error) {
	it := s.content.Item(item)
	if it == nil || it.Category != CategoryPlaceable {
		return nil, ErrInvalid.with("Isso não dá para colocar no lote.")
	}
	if rot < 0 || rot > 3 {
		return nil, ErrInvalid.with("Rotação inválida.")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *PlaceResult
	err := s.store.InTx(ctx, func(tx Store) error {
		lot, err := s.ownLot(ctx, tx, p)
		if err != nil {
			return err
		}
		if lotID != lot.ID {
			return ErrNotOwner
		}
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		if !has(inv, item) {
			return ErrMissingMaterials.with("Você não tem %s.", s.itemName(item))
		}
		r := footprintRect(it.Footprint, x, y, rot)
		if !r.inLot() {
			return ErrOutOfLot
		}
		placements, err := tx.Placements(ctx, []int64{lot.ID})
		if err != nil {
			return err
		}
		for _, o := range s.occupied(lot, placements, false) {
			if o.overlaps(r) {
				return ErrOverlap
			}
		}
		if err := tx.AddItem(ctx, p.ID, item, -1); err != nil {
			return err
		}
		if err := tx.CreatePlacement(ctx, &Placement{LotID: lot.ID, Item: item, X: x, Y: y, Rot: rot}); err != nil {
			return err
		}
		res, err = s.placeResult(ctx, tx, p, lot)
		return err
	})
	return res, err
}

// Remove guarda de volta no inventário um objeto do lote do jogador.
func (s *Service) Remove(ctx context.Context, p *Player, placementID int64) (*PlaceResult, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *PlaceResult
	err := s.store.InTx(ctx, func(tx Store) error {
		lot, err := s.ownLot(ctx, tx, p)
		if err != nil {
			return err
		}
		pl, err := tx.PlacementByID(ctx, placementID)
		if err != nil {
			return err
		}
		if pl.LotID != lot.ID {
			return ErrNotOwner
		}
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		if err := s.addItems(ctx, tx, p.ID, inv, []StackView{{Item: pl.Item, Count: 1}}); err != nil {
			return err
		}
		if err := tx.DeletePlacement(ctx, pl.ID); err != nil {
			return err
		}
		res, err = s.placeResult(ctx, tx, p, lot)
		return err
	})
	return res, err
}

// Blocker é um objeto do lote que atrapalha a obra da casa (vai em details.blockers).
type Blocker struct {
	ID   int64  `json:"id"`
	Item string `json:"item"`
	Name string `json:"name"`
}

// upgradeOrigin é onde a casa do nível seguinte (footprint fp) fica, a partir da casa
// atual `cur`: a parede da porta continua no mesmo lugar e a casa cresce para os lados
// (centralizada) e para trás. rot 0 → porta no sul (y0), 1 → leste (x1), 2 → norte (y1),
// 3 → oeste (x0).
func upgradeOrigin(cur rect, fp [2]int, rot int) (int, int) {
	n := footprintRect(fp, 0, 0, rot)
	w, h := n.x1, n.y1
	cx := cur.x0 - (w-(cur.x1-cur.x0))/2
	cy := cur.y0 - (h-(cur.y1-cur.y0))/2
	switch rot {
	case 0:
		return cx, cur.y0
	case 1:
		return cur.x1 - w, cy
	case 2:
		return cx, cur.y1 - h
	default:
		return cur.x0, cy
	}
}

// placeUpgrade escolhe a posição da casa melhorada: a preferida (upgradeOrigin) ou, se
// ela passar da borda ou bater num objeto, a mais próxima dentro do lote que continue
// cobrindo a casa atual (a casa cresce, não muda de lugar). Se todas baterem em objetos,
// devolve a mais próxima e os objetos que atrapalham.
func (s *Service) placeUpgrade(l *Lot, fp [2]int, placements []Placement) (rect, []Placement) {
	cur, _ := s.houseRect(l, l.HouseLevel)
	px, py := upgradeOrigin(cur, fp, l.HouseRot)
	n := footprintRect(fp, 0, 0, l.HouseRot)
	type cand struct {
		r    rect
		dist int
	}
	var cands []cand
	for y := 0; y+n.y1 <= LotTiles; y++ {
		for x := 0; x+n.x1 <= LotTiles; x++ {
			r := footprintRect(fp, x, y, l.HouseRot)
			covers := r.x0 <= cur.x0 && r.y0 <= cur.y0 && r.x1 >= cur.x1 && r.y1 >= cur.y1
			if !covers {
				continue
			}
			dx, dy := x-px, y-py
			cands = append(cands, cand{r, dx*dx + dy*dy})
		}
	}
	if len(cands) == 0 { // não cobre a casa atual em lugar nenhum: aceita qualquer posição
		for y := 0; y+n.y1 <= LotTiles; y++ {
			for x := 0; x+n.x1 <= LotTiles; x++ {
				dx, dy := x-px, y-py
				cands = append(cands, cand{footprintRect(fp, x, y, l.HouseRot), dx*dx + dy*dy})
			}
		}
	}
	if len(cands) == 0 {
		return footprintRect(fp, px, py, l.HouseRot), nil
	}
	sort.SliceStable(cands, func(i, j int) bool { return cands[i].dist < cands[j].dist })
	blockersOf := func(r rect) []Placement {
		var out []Placement
		for _, p := range placements {
			if it := s.content.Item(p.Item); it != nil && footprintRect(it.Footprint, p.X, p.Y, p.Rot).overlaps(r) {
				out = append(out, p)
			}
		}
		return out
	}
	for _, c := range cands {
		if len(blockersOf(c.r)) == 0 {
			return c.r, nil
		}
	}
	return cands[0].r, blockersOf(cands[0].r)
}

// BuildHouse começa a obra do próximo nível da casa. Na primeira casa, (x, y, rot) dizem
// onde ela fica; nas melhorias, (x, y, rot) são ignorados: a casa cresce a partir da atual,
// com a porta no mesmo lado (placeUpgrade). Se objetos atrapalharem, o erro traz a lista
// em details.blockers. A obra fica pronta na próxima virada do dia (5h locais).
func (s *Service) BuildHouse(ctx context.Context, p *Player, lotID int64, x, y, rot int) (*PlaceResult, error) {
	if rot < 0 || rot > 3 {
		return nil, ErrInvalid.with("Rotação inválida.")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *PlaceResult
	err := s.store.InTx(ctx, func(tx Store) error {
		lot, err := s.ownLot(ctx, tx, p)
		if err != nil {
			return err
		}
		if lotID != lot.ID {
			return ErrNotOwner
		}
		if lot.PendingLevel > 0 {
			return ErrBusy
		}
		next := lot.HouseLevel + 1
		level := s.content.House(next)
		if level == nil {
			return ErrMaxLevel
		}
		placements, err := tx.Placements(ctx, []int64{lot.ID})
		if err != nil {
			return err
		}
		var r rect
		if lot.HouseLevel == 0 {
			r = footprintRect(level.Footprint, x, y, rot)
			if !r.inLot() {
				return ErrOutOfLot.with("A %s não cabe aí no lote.", strings.ToLower(level.Name))
			}
			for _, o := range s.occupied(lot, placements, true) {
				if o.overlaps(r) {
					return ErrOverlap.with("Já tem alguma coisa aí: a %s precisa de %d × %d quadradinhos livres.", strings.ToLower(level.Name), r.x1-r.x0, r.y1-r.y0)
				}
			}
			lot.HouseX, lot.HouseY, lot.HouseRot = x, y, rot
		} else {
			var blockers []Placement
			r, blockers = s.placeUpgrade(lot, level.Footprint, placements)
			if !r.inLot() {
				return ErrOutOfLot.with("A %s não cabe neste lote.", strings.ToLower(level.Name))
			}
			if len(blockers) > 0 {
				list := make([]Blocker, len(blockers))
				names := make([]string, len(blockers))
				for i, b := range blockers {
					list[i] = Blocker{ID: b.ID, Item: b.Item, Name: s.itemName(b.Item)}
					names[i] = strings.ToLower(list[i].Name)
				}
				return ErrOverlap.with("Para a %s caber, guarde no bolso: %s.", strings.ToLower(level.Name), strings.Join(names, ", ")).
					withDetails(map[string]any{"blockers": list})
			}
		}
		lot.PendingX, lot.PendingY = r.x0, r.y0
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		used, err := s.resolveCost(level.Cost, 1, inv)
		if err != nil {
			return err
		}
		if err := consume(ctx, tx, p.ID, used); err != nil {
			return err
		}
		lot.PendingLevel = next
		lot.ReadyAt = NextRollover(s.clock.Now(), s.world.Cells[lot.Cell].Lon)
		if err := tx.UpdateLot(ctx, lot); err != nil {
			return err
		}
		res, err = s.placeResult(ctx, tx, p, lot)
		return err
	})
	return res, err
}

// CountryForA2 traduz um código ISO A2 (do IP ou do idioma do sistema) para o código A3
// usado no mundo. Devolve "" se o país não existe no mundo.
func (s *Service) CountryForA2(a2 string, table map[string]string) string {
	if len(a2) != 2 {
		return ""
	}
	code := table[strings.ToUpper(a2)]
	if _, ok := s.world.Countries[code]; ok {
		return code
	}
	return ""
}

// distanceDeg é a distância angular (graus) entre duas células, para o modo dev.
func (s *Service) distanceDeg(a, b int) float64 {
	va, vb := cellVec(&s.world.Cells[a]), cellVec(&s.world.Cells[b])
	return math.Acos(math.Max(-1, math.Min(1, va.Normalize().Dot(vb.Normalize())))) * 180 / math.Pi
}
