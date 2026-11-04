package game

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"sort"
	"sync"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Necessidades gentis (fase 4.0, ADR 0050): sede, conforto térmico e fome, de 0 a 100. Elas
// só servem para dar vantagem a quem cuida do personagem: todas cheias = um pouco mais
// rápido; alguma no mínimo = um pouco mais devagar (e, com fome, a tela fica zonza). Nada de
// dano, morte ou itens perdidos. Só caem com o jogador conectado (a camada em tempo real
// chama BodyTick uma vez por segundo); com o jogo fechado, nada muda. O modo tranquilo
// desliga tudo. O servidor é a fonte da verdade do multiplicador de velocidade, porque é ele
// quem valida o movimento.

// BodyContent é body.json.
type BodyContent struct {
	Climate ClimateRules `json:"climate"`
	Comfort struct {
		Min float64 `json:"min"`
		Max float64 `json:"max"`
	} `json:"comfort"`
	Sources struct {
		Fire struct {
			Radius  float64 `json:"radius"`
			Warmth  float64 `json:"warmth"`
			Minutes float64 `json:"minutes"`
		} `json:"fire"`
		Shade struct {
			Radius  float64 `json:"radius"`
			Cooling float64 `json:"cooling"`
			Above   float64 `json:"above"`
		} `json:"shade"`
		Water struct {
			Radius  float64 `json:"radius"`
			Cooling float64 `json:"cooling"`
			Above   float64 `json:"above"`
		} `json:"water"`
	} `json:"sources"`
	Needs NeedRules `json:"needs"`
	Speed struct {
		Optimal  float64 `json:"optimal"`
		Neutral  float64 `json:"neutral"`
		Critical float64 `json:"critical"`
	} `json:"speed"`
	Buffs     map[string]BuffRule `json:"buffs"`
	FillReach float64             `json:"fill_reach"`
	WearSlots []string            `json:"wear_slots"`
	CapeFlags int                 `json:"cape_flags"` // bandeiras que cabem na capa (fase 4.5)
	Look      LookOptions         `json:"look"`
}

// NeedRules é body.json → needs.
type NeedRules struct {
	Max                  float64 `json:"max"`
	ThirstPerMin         float64 `json:"thirst_per_min"`
	ThirstHotExtra       float64 `json:"thirst_hot_extra"`
	HungerPerMin         float64 `json:"hunger_per_min"`
	HungerRunExtra       float64 `json:"hunger_run_extra"`
	HungerPerCollect     float64 `json:"hunger_per_collect"`
	ComfortRecoverPerMin float64 `json:"comfort_recover_per_min"`
	ComfortLossPerDegree float64 `json:"comfort_loss_per_degree"`
	OptimalAt            float64 `json:"optimal_at"`
	CriticalAt           float64 `json:"critical_at"`
	DizzyHunger          float64 `json:"dizzy_hunger"`
}

// BuffRule é um bônus temporário da comida.
type BuffRule struct {
	Name  string  `json:"name"`
	Speed float64 `json:"speed,omitempty"` // multiplica a velocidade
	Needs float64 `json:"needs,omitempty"` // multiplica a queda das necessidades
	Cold  float64 `json:"cold,omitempty"`  // graus de proteção contra o frio
	Heat  float64 `json:"heat,omitempty"`  // graus de proteção contra o calor
}

// FoodInfo é o que um item faz ao ser comido ou bebido (items.json → food).
type FoodInfo struct {
	Hunger  float64 `json:"hunger,omitempty"`
	Thirst  float64 `json:"thirst,omitempty"`
	Buff    string  `json:"buff,omitempty"`
	Minutes float64 `json:"minutes,omitempty"`
	Becomes string  `json:"becomes,omitempty"` // o que fica no lugar (cantil pela metade)
	Returns string  `json:"returns,omitempty"` // o que volta ao bolso ao cozinhar com ele
}

// Níveis das necessidades.
const (
	LevelOptimal  = "optimal"
	LevelNeutral  = "neutral"
	LevelCritical = "critical"
	LevelQuiet    = "quiet"
)

func (b *BodyContent) check(items map[string]*Item) error {
	if err := b.Climate.check(); err != nil {
		return err
	}
	n := b.Needs
	if n.Max <= 0 || n.OptimalAt > n.Max || n.CriticalAt < 0 || n.CriticalAt >= n.OptimalAt {
		return fmt.Errorf("body.json: needs com limites inválidos")
	}
	if b.Speed.Optimal < b.Speed.Neutral || b.Speed.Critical > b.Speed.Neutral || b.Speed.Critical <= 0 {
		return fmt.Errorf("body.json: speed precisa ter crítico ≤ neutro ≤ ótimo")
	}
	if b.Comfort.Min >= b.Comfort.Max {
		return fmt.Errorf("body.json: comfort.min precisa ser menor que comfort.max")
	}
	for id, it := range items {
		if it.Food == nil {
			continue
		}
		if it.Food.Buff != "" {
			if _, ok := b.Buffs[it.Food.Buff]; !ok {
				return fmt.Errorf("item %s: bônus %s não existe em body.json", id, it.Food.Buff)
			}
			if it.Food.Minutes <= 0 {
				return fmt.Errorf("item %s: bônus sem minutos", id)
			}
		}
		for _, other := range []string{it.Food.Becomes, it.Food.Returns} {
			if other != "" && items[other] == nil {
				return fmt.Errorf("item %s: %s não existe", id, other)
			}
		}
	}
	return b.Look.check()
}

// --- Estado de cada jogador -----------------------------------------------------------------

// bodyRecord é o que vai para o banco (JSON).
type bodyRecord struct {
	Thirst  float64            `json:"thirst"`
	Hunger  float64            `json:"hunger"`
	Comfort float64            `json:"comfort"`
	Buffs   map[string]float64 `json:"buffs,omitempty"` // segundos que faltam (só contam conectado)
	Quiet   bool               `json:"quiet,omitempty"`
	Look    Look               `json:"look"`
	Wear    map[string]Worn    `json:"wear,omitempty"`
	Cape    []string           `json:"cape,omitempty"` // bandeiras escolhidas para a capa, na ordem (fase 4.5)
}

// bodyState é o corpo de um jogador na memória (enquanto ele joga).
type bodyState struct {
	bodyRecord
	dirty   bool
	frozen  bool     // modo dev: necessidades congeladas
	forced  *float64 // modo dev: temperatura do ar forçada
	exert   float64  // fome a mais das coletas desde o último tick
	air     float64
	felt    float64
	sources []string
	// Fontes de calor e frio perto (refeitas a cada sourceEvery ou quando muda de célula).
	srcAt   time.Time
	srcCell int
	shade   []world.Vec3
	heat    []world.Vec3
	water   [][2]world.Vec3 // beiras de mar perto (segmentos)
	// Multiplicador dos últimos segundos (validação do movimento com folga).
	speedAt  time.Time
	speedMax float64
}

const sourceEvery = 10 * time.Second

func newBodyRecord(max float64) bodyRecord {
	return bodyRecord{Thirst: max, Hunger: max, Comfort: max}
}

// bodies guarda os corpos carregados.
type bodies struct {
	mu   sync.Mutex
	m    map[int64]*bodyState
	fire []tempFire
	next int64
}

// tempFire é uma fogueira acesa no chão (fora do lote), que apaga sozinha.
type tempFire struct {
	ID    int64      `json:"id"`
	Owner int64      `json:"owner"`
	Cell  int        `json:"cell"`
	Pos   world.Vec3 `json:"-"`
	X     float64    `json:"x"` // no plano da célula
	Y     float64    `json:"y"`
	Until time.Time  `json:"-"`
	Left  float64    `json:"left"` // segundos que faltam
}

// body devolve o corpo do jogador, carregando do banco na primeira vez. Chame com
// s.body.mu travado.
func (s *Service) bodyLocked(ctx context.Context, id int64) (*bodyState, error) {
	if s.body.m == nil {
		s.body.m = map[int64]*bodyState{}
	}
	if b := s.body.m[id]; b != nil {
		return b, nil
	}
	rec := newBodyRecord(s.content.Body.Needs.Max)
	raw, err := s.store.Body(ctx, id)
	if err != nil {
		return nil, err
	}
	if raw != "" {
		if err := json.Unmarshal([]byte(raw), &rec); err != nil {
			return nil, err
		}
	}
	b := &bodyState{bodyRecord: rec, srcCell: -1, speedMax: 1}
	s.body.m[id] = b
	return b, nil
}

// ensureBody carrega o corpo do banco antes de uma transação (dentro dela, a conexão de fora
// ficaria esperando a própria transação).
func (s *Service) ensureBody(ctx context.Context, id int64) error {
	s.body.mu.Lock()
	defer s.body.mu.Unlock()
	_, err := s.bodyLocked(ctx, id)
	return err
}

// SaveBody grava o corpo do jogador (a camada em tempo real chama de tempos em tempos e ao
// sair). forget = tira da memória (o jogador saiu).
func (s *Service) SaveBody(ctx context.Context, id int64, forget bool) error {
	s.body.mu.Lock()
	b := s.body.m[id]
	var raw []byte
	if b != nil && b.dirty {
		raw, _ = json.Marshal(b.bodyRecord)
		b.dirty = false
	}
	if forget {
		delete(s.body.m, id)
	}
	s.body.mu.Unlock()
	if raw == nil {
		return nil
	}
	return s.store.SaveBody(ctx, id, string(raw))
}

// --- Visão para o cliente ---------------------------------------------------------------

// BuffView é um bônus ativo.
type BuffView struct {
	ID   string  `json:"id"`
	Name string  `json:"name"`
	Left float64 `json:"left"` // segundos
}

// BodyView é o corpo do jogador como o cliente mostra (mensagem body e GET /body).
type BodyView struct {
	Thirst     float64    `json:"thirst"`
	Hunger     float64    `json:"hunger"`
	Comfort    float64    `json:"comfort"`
	Max        float64    `json:"max"`
	Level      string     `json:"level"` // optimal, neutral, critical ou quiet
	Speed      float64    `json:"speed"` // multiplicador da velocidade
	Air        float64    `json:"air"`   // temperatura do ar
	Felt       float64    `json:"felt"`  // temperatura sentida (com fogueira, sombra, água)
	ComfortMin float64    `json:"comfort_min"`
	ComfortMax float64    `json:"comfort_max"`
	Cold       bool       `json:"cold"` // sentindo frio (fora da faixa, com as roupas)
	Hot        bool       `json:"hot"`
	Dizzy      bool       `json:"dizzy"`
	Quiet      bool       `json:"quiet"`
	Frozen     bool       `json:"frozen,omitempty"`
	Forced     bool       `json:"forced,omitempty"`
	Sources    []string   `json:"sources"` // fire, shade, water
	Buffs      []BuffView `json:"buffs"`
	ColdProt   float64    `json:"cold_protection"`
	HeatProt   float64    `json:"heat_protection"`
}

// protection soma a proteção das roupas e dos bônus.
func (s *Service) protection(b *bodyState) (cold, heat float64) {
	for _, w := range b.Wear {
		if it := s.content.Item(w.Item); it != nil && it.Wear != nil {
			cold += it.Wear.Cold
			heat += it.Wear.Heat
		}
	}
	for id, left := range b.Buffs {
		if r, ok := s.content.Body.Buffs[id]; ok && left > 0 {
			cold += r.Cold
			heat += r.Heat
		}
	}
	return cold, heat
}

// comfortBand é a faixa confortável com as roupas e os bônus.
func (s *Service) comfortBand(b *bodyState) (lo, hi float64) {
	cold, heat := s.protection(b)
	return s.content.Body.Comfort.Min - cold, s.content.Body.Comfort.Max + heat
}

// level diz o nível das necessidades.
func (s *Service) level(b *bodyState) string {
	if b.Quiet {
		return LevelQuiet
	}
	n := s.content.Body.Needs
	low := math.Min(b.Thirst, math.Min(b.Hunger, b.Comfort))
	switch {
	case low <= n.CriticalAt:
		return LevelCritical
	case low >= n.OptimalAt:
		return LevelOptimal
	}
	return LevelNeutral
}

// speedOf é o multiplicador da velocidade agora (nível × bônus).
func (s *Service) speedOf(b *bodyState) float64 {
	sp := s.content.Body.Speed
	m := sp.Neutral
	switch s.level(b) {
	case LevelOptimal:
		m = sp.Optimal
	case LevelCritical:
		m = sp.Critical
	case LevelQuiet:
		return sp.Neutral
	}
	for id, left := range b.Buffs {
		if r, ok := s.content.Body.Buffs[id]; ok && left > 0 && r.Speed > 0 {
			m *= r.Speed
		}
	}
	return m
}

func (s *Service) bodyView(b *bodyState) BodyView {
	n := s.content.Body.Needs
	lo, hi := s.comfortBand(b)
	cold, heat := s.protection(b)
	v := BodyView{Thirst: round1(b.Thirst), Hunger: round1(b.Hunger), Comfort: round1(b.Comfort), Max: n.Max,
		Level: s.level(b), Speed: s.speedOf(b), Air: round1(b.air), Felt: round1(b.felt), ComfortMin: lo, ComfortMax: hi,
		Cold: b.felt < lo, Hot: b.felt > hi, Quiet: b.Quiet, Frozen: b.frozen, Forced: b.forced != nil,
		Sources: append([]string{}, b.sources...), Buffs: []BuffView{}, ColdProt: cold, HeatProt: heat}
	v.Dizzy = !b.Quiet && b.Hunger <= n.DizzyHunger
	ids := make([]string, 0, len(b.Buffs))
	for id, left := range b.Buffs {
		if left > 0 {
			ids = append(ids, id)
		}
	}
	sort.Strings(ids)
	for _, id := range ids {
		v.Buffs = append(v.Buffs, BuffView{ID: id, Name: s.content.Body.Buffs[id].Name, Left: math.Round(b.Buffs[id])})
	}
	return v
}

func round1(x float64) float64 { return math.Round(x*10) / 10 }

// Body devolve o corpo do jogador (GET /body).
func (s *Service) Body(ctx context.Context, p *Player) (*BodyView, error) {
	s.body.mu.Lock()
	defer s.body.mu.Unlock()
	b, err := s.bodyLocked(ctx, p.ID)
	if err != nil {
		return nil, err
	}
	if b.srcCell < 0 {
		// Ainda sem tick (sem tempo real): a temperatura da casa ou do lugar de agora.
		if pos, cell, _, ok := s.presenceWhere(p.ID); ok {
			s.updateTemperature(ctx, b, p.ID, pos, cell, s.clock.Now())
		}
	}
	v := s.bodyView(b)
	return &v, nil
}

func (s *Service) presenceWhere(id int64) (world.Vec3, int, world.Vec3, bool) {
	if s.presence == nil {
		return world.Vec3{}, -1, world.Vec3{}, false
	}
	return s.presence.Where(id)
}

// SpeedFactor é o maior multiplicador da velocidade do jogador nos últimos segundos: a
// validação do movimento usa esta folga (o cliente pode estar um tico atrasado).
func (s *Service) SpeedFactor(id int64) float64 {
	s.body.mu.Lock()
	defer s.body.mu.Unlock()
	b := s.body.m[id]
	if b == nil {
		return 1
	}
	return math.Max(b.speedMax, s.speedOf(b))
}

// --- O tick (uma vez por segundo, com o jogador conectado) ------------------------------

// BodyTick avança as necessidades dt segundos para quem está em pos (célula cell); running
// diz se ele está correndo. Devolve a visão nova.
func (s *Service) BodyTick(ctx context.Context, id int64, dt float64, pos world.Vec3, cell int, running bool) (BodyView, error) {
	now := s.clock.Now()
	s.body.mu.Lock()
	defer s.body.mu.Unlock()
	b, err := s.bodyLocked(ctx, id)
	if err != nil {
		return BodyView{}, err
	}
	s.updateTemperature(ctx, b, id, pos, cell, now)
	before := s.speedOf(b)
	if !b.Quiet && !b.frozen && dt > 0 {
		s.decay(b, dt, running)
	}
	for k, left := range b.Buffs {
		if left -= dt; left <= 0 {
			delete(b.Buffs, k)
		} else {
			b.Buffs[k] = left
		}
		b.dirty = true
	}
	// Folga da velocidade: o maior multiplicador dos últimos 3 segundos.
	after := s.speedOf(b)
	if after >= b.speedMax || now.Sub(b.speedAt) > 3*time.Second {
		b.speedMax = math.Max(after, before)
		b.speedAt = now
	}
	return s.bodyView(b), nil
}

// decay tira das necessidades o que dt segundos de jogo gastam.
func (s *Service) decay(b *bodyState, dt float64, running bool) {
	n := s.content.Body.Needs
	mins := dt / 60
	mult := 1.0
	for id, left := range b.Buffs {
		if r, ok := s.content.Body.Buffs[id]; ok && left > 0 && r.Needs > 0 {
			mult *= r.Needs
		}
	}
	lo, hi := s.comfortBand(b)
	thirst := n.ThirstPerMin
	if b.felt > hi {
		thirst += n.ThirstHotExtra
	}
	hunger := n.HungerPerMin
	if running {
		hunger += n.HungerRunExtra
	}
	b.Thirst = clampNeed(b.Thirst-thirst*mins*mult, n.Max)
	b.Hunger = clampNeed(b.Hunger-hunger*mins*mult-b.exert*mult, n.Max)
	b.exert = 0
	switch {
	case b.felt < lo:
		b.Comfort = clampNeed(b.Comfort-n.ComfortLossPerDegree*(lo-b.felt)*mins*mult, n.Max)
	case b.felt > hi:
		b.Comfort = clampNeed(b.Comfort-n.ComfortLossPerDegree*(b.felt-hi)*mins*mult, n.Max)
	default:
		b.Comfort = clampNeed(b.Comfort+n.ComfortRecoverPerMin*mins, n.Max)
	}
	b.dirty = true
}

func clampNeed(v, max float64) float64 { return math.Max(0, math.Min(max, v)) }

// exertBody soma fome de uma coleta (chamado pelas regras de coleta).
func (s *Service) exertBody(id int64) {
	s.body.mu.Lock()
	defer s.body.mu.Unlock()
	if b := s.body.m[id]; b != nil && !b.Quiet && !b.frozen {
		b.exert += s.content.Body.Needs.HungerPerCollect
	}
}

// updateTemperature calcula o ar e a sensação no lugar do jogador.
func (s *Service) updateTemperature(ctx context.Context, b *bodyState, id int64, pos world.Vec3, cell int, now time.Time) {
	if cell < 0 || cell >= len(s.world.Cells) {
		cell = s.world.FindCell(pos, -1)
	}
	c := &s.world.Cells[cell]
	lat, lon := world.VecToLatLon(pos)
	h := c.Height
	if c.Terrain != world.Land {
		h = 0
	}
	air := s.content.Body.Climate.AirTemperature(lat, lon, c.Biome, h, now)
	if b.forced != nil {
		air = *b.forced
	}
	if now.Sub(b.srcAt) > sourceEvery || b.srcCell != cell {
		s.refreshSources(ctx, b, cell)
		b.srcAt, b.srcCell = now, cell
	}
	src := s.content.Body.Sources
	felt := air
	b.sources = b.sources[:0]
	// Fogueiras: as do lote (guardadas) e as acesas no chão (sempre na hora).
	warm := 0.0
	heat := append([]world.Vec3{}, b.heat...)
	for _, f := range s.body.fire {
		if now.Before(f.Until) {
			heat = append(heat, f.Pos)
		}
	}
	for _, f := range heat {
		if d := s.groundDistance(pos, f); d < src.Fire.Radius {
			warm = math.Max(warm, src.Fire.Warmth*(1-d/src.Fire.Radius))
		}
	}
	if warm > 0 {
		felt += warm
		b.sources = append(b.sources, "fire")
	}
	if air > src.Shade.Above {
		for _, t := range b.shade {
			if s.groundDistance(pos, t) < src.Shade.Radius {
				felt -= src.Shade.Cooling
				b.sources = append(b.sources, "shade")
				break
			}
		}
	}
	if air > src.Water.Above {
		for _, e := range b.water {
			if s.distanceToSegment(pos, e[0], e[1]) < src.Water.Radius {
				felt -= src.Water.Cooling
				b.sources = append(b.sources, "water")
				break
			}
		}
	}
	b.air, b.felt = air, felt
}

// refreshSources junta as árvores (sombra), as fogueiras dos lotes e as beiras de mar perto.
func (s *Service) refreshSources(ctx context.Context, b *bodyState, cell int) {
	b.shade, b.heat, b.water = b.shade[:0], b.heat[:0], b.water[:0]
	cells := s.cellsAround(cell, 1)
	lots, err := s.store.LotsByCells(ctx, cells)
	if err != nil {
		return
	}
	for _, c := range cells {
		for _, o := range s.cellObjects(c, lots) {
			if o.Kind == KindTree {
				b.shade = append(b.shade, s.ObjectPoint(&o))
			}
		}
		if s.world.Cells[c].Terrain != world.Land {
			continue
		}
		// Beiras de mar: as arestas da célula que dão para o oceano.
		cc := &s.world.Cells[c]
		top := s.world.Radius + cc.Height
		n := len(cc.Vertices)
		for k, nb := range cc.Neighbors {
			if s.world.Cells[nb].Terrain == world.Land {
				continue
			}
			a := cc.Vertices[k]
			z := cc.Vertices[(k+1)%n]
			b.water = append(b.water, [2]world.Vec3{
				world.Vec3{X: a[0], Y: a[1], Z: a[2]}.Normalize().Scale(top),
				world.Vec3{X: z[0], Y: z[1], Z: z[2]}.Normalize().Scale(top)})
		}
	}
	for _, pt := range s.placementPoints(ctx, lots, "heat") {
		b.heat = append(b.heat, pt)
	}
}

// placementPoints: o centro dos objetos colocados com a tag nos lotes dados.
func (s *Service) placementPoints(ctx context.Context, lots []Lot, tag string) []world.Vec3 {
	if len(lots) == 0 {
		return nil
	}
	ids := make([]int64, len(lots))
	byID := map[int64]*Lot{}
	for i := range lots {
		ids[i] = lots[i].ID
		byID[lots[i].ID] = &lots[i]
	}
	pls, err := s.store.Placements(ctx, ids)
	if err != nil {
		return nil
	}
	var out []world.Vec3
	for _, pl := range pls {
		it := s.content.Item(pl.Item)
		l := byID[pl.LotID]
		if it == nil || l == nil || !it.HasTag(tag) {
			continue
		}
		w, h := it.Footprint[0], it.Footprint[1]
		if pl.Rot%2 == 1 {
			w, h = h, w
		}
		f := CellFrame(s.world, l.Cell)
		x0, y0, _, _ := SlotRect(l.Slot)
		out = append(out, f.Point(x0+(float64(pl.X)+float64(w)/2)*TileSize, y0+(float64(pl.Y)+float64(h)/2)*TileSize))
	}
	return out
}

// distanceToSegment: distância no chão de p até o segmento a–b (aproximada pela corda, que
// basta para poucas unidades).
func (s *Service) distanceToSegment(p, a, b world.Vec3) float64 {
	ab := b.Sub(a)
	t := 0.0
	if l := ab.Dot(ab); l > 0 {
		t = math.Max(0, math.Min(1, p.Sub(a).Dot(ab)/l))
	}
	q := a.Add(ab.Scale(t))
	// Compara no mesmo raio (o topo da célula e a posição do personagem diferem um tico).
	return s.groundDistance(p, q)
}
