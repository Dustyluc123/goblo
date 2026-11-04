package game

import (
	"fmt"
	"math"
	"sort"
	"sync"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Cavernas (fase 4.5, ADR 0056). As bocas ficam no globo, em encostas de montanhas e morros,
// algumas por país, escolhidas só pelo mundo (determinístico). Cada boca leva a um mapa
// separado, longe do planeta: um ponto de uma espiral a shell_radius do centro. Lá, o
// "para cima" do personagem (a posição normalizada) é praticamente o mesmo em toda a
// caverna, e a área de interesse do tempo real separa as cavernas sozinha (estão a mais de
// mil unidades umas das outras). O desenho (salões, túneis, minérios, enfeites, sala do
// chefe) sai de uma semente da célula da boca.

// CaveContent é caves.json.
type CaveContent struct {
	ShellRadius float64 `json:"shell_radius"`
	Slots       int     `json:"slots"`
	Entrances   struct {
		PerLandCells  int      `json:"per_land_cells"`
		Min           int      `json:"min"`
		Max           int      `json:"max"`
		Biomes        []string `json:"biomes"`
		HillHeight    float64  `json:"hill_height"`
		FallbackCells int      `json:"fallback_cells"`
		Spot          float64  `json:"spot"`
		Clear         float64  `json:"clear"`
	} `json:"entrances"`
	Layout struct {
		Rooms       [2]int     `json:"rooms"`
		RoomRadius  [2]float64 `json:"room_radius"`
		BossRadius  float64    `json:"boss_radius"`
		Step        [2]float64 `json:"step"`
		Turn        float64    `json:"turn"`
		TunnelWidth float64    `json:"tunnel_width"`
		Rise        float64    `json:"rise"`
		Ledge       float64    `json:"ledge"`
		LedgeChance float64    `json:"ledge_chance"`
		SideChance  float64    `json:"side_chance"`
		Wall        float64    `json:"wall"`
		Grid        float64    `json:"grid"`
	} `json:"layout"`
	Ores        []OreRule  `json:"ores"`
	OresPerRoom [2]int     `json:"ores_per_room"`
	Glow        []GlowRule `json:"glow"`
	Torch       struct {
		Limit int     `json:"limit"`
		Hours float64 `json:"hours"`
		Reach float64 `json:"reach"`
	} `json:"torch"`
	Temperature  float64  `json:"temperature"`
	ChestSlots   int      `json:"chest_slots"`
	ChestReach   float64  `json:"chest_reach"`
	FurnaceReach float64  `json:"furnace_reach"`
	Reach        float64  `json:"reach"`
	Boss         BossRule `json:"boss"`
}

// OreRule é um minério de caves.json.
type OreRule struct {
	ID      string     `json:"id"`
	Item    string     `json:"item"`
	Name    string     `json:"name"`
	MinTier int        `json:"min_tier"`
	Hits    int        `json:"hits"`
	Count   [2]int     `json:"count"`
	Depth   [2]float64 `json:"depth"`
	Weight  float64    `json:"weight"`
	Glow    bool       `json:"glow,omitempty"`
}

// GlowRule é um enfeite que brilha (cogumelo, cristal), com página na Goblopédia.
type GlowRule struct {
	ID      string     `json:"id"`
	Name    string     `json:"name"`
	PerRoom [2]int     `json:"per_room"`
	Depth   [2]float64 `json:"depth"`
	Color   string     `json:"color"`
}

func (c *CaveContent) check(items map[string]*Item) error {
	if c.ShellRadius < 5000 || c.Slots < 64 {
		return fmt.Errorf("caves.json: shell_radius ou slots pequenos demais")
	}
	l := c.Layout
	if l.Rooms[0] < 3 || l.Rooms[1] < l.Rooms[0] || l.RoomRadius[0] <= 2 || l.Grid <= 0 || l.TunnelWidth <= 1 {
		return fmt.Errorf("caves.json: layout inválido")
	}
	if l.Ledge >= 1.3 {
		return fmt.Errorf("caves.json: o degrau (%.1f) precisa ser menor que o pulo (1,3)", l.Ledge)
	}
	if len(c.Ores) == 0 {
		return fmt.Errorf("caves.json: sem minérios")
	}
	for _, o := range c.Ores {
		if items[o.Item] == nil || o.MinTier < 1 || o.Hits < 1 || o.Count[0] < 1 || o.Count[1] < o.Count[0] || o.Weight <= 0 {
			return fmt.Errorf("caves.json: minério %s inválido", o.ID)
		}
	}
	b := c.Boss
	if b.Hits < 1 || b.Attacks < 1 || b.Sequences < 1 || b.Interval <= b.Warn || b.Warn <= 0 || items[b.Reward.Item] == nil {
		return fmt.Errorf("caves.json: chefe inválido")
	}
	if c.Torch.Limit < 1 {
		return fmt.Errorf("caves.json: torch.limit precisa ser > 0")
	}
	return nil
}

// Cave é uma boca de caverna no globo. (X, Y) é a posição no plano da célula (Frame) e Yaw a
// direção para onde a boca abre (radianos, a partir de East, girando para North).
type Cave struct {
	ID      int     `json:"id"`
	Cell    int     `json:"cell"`
	Country string  `json:"country"`
	X       float64 `json:"x"`
	Y       float64 `json:"y"`
	Yaw     float64 `json:"yaw"`
	Rooms   int     `json:"rooms"`
	slot    int
}

// CaveFrame é o sistema de coordenadas da caverna: P = Origin + East·x + Up·y + North·z.
type CaveFrame struct {
	Origin, East, Up, North world.Vec3
}

// Point leva um ponto da caverna (x, y = altura, z) para o espaço do mundo.
func (f CaveFrame) Point(x, y, z float64) world.Vec3 {
	return f.Origin.Add(f.East.Scale(x)).Add(f.Up.Scale(y)).Add(f.North.Scale(z))
}

// Local leva um ponto do mundo para a caverna (x, y = altura, z).
func (f CaveFrame) Local(p world.Vec3) (x, y, z float64) {
	d := p.Sub(f.Origin)
	return d.Dot(f.East), d.Dot(f.Up), d.Dot(f.North)
}

// CaveRoom é um salão: círculo de raio R em (X, Z), chão na altura Y.
type CaveRoom struct {
	X     float64 `json:"x"`
	Z     float64 `json:"z"`
	R     float64 `json:"r"`
	Y     float64 `json:"y"`
	Depth float64 `json:"depth"` // 0 = entrada, 1 = sala do chefe
	Boss  bool    `json:"boss,omitempty"`
	Side  bool    `json:"side,omitempty"`
}

// CaveTunnel liga dois salões. Com Ledge, o chão muda de altura de uma vez no meio (degrau
// que pede um pulo); sem, é uma rampa.
type CaveTunnel struct {
	A     int     `json:"a"`
	B     int     `json:"b"`
	W     float64 `json:"w"`
	Ledge bool    `json:"ledge,omitempty"`
}

// CaveOre é um minério colocado na caverna.
type CaveOre struct {
	ID      int64   `json:"id"`
	Ore     string  `json:"ore"`
	Item    string  `json:"item"`
	X       float64 `json:"x"`
	Y       float64 `json:"y"`
	Z       float64 `json:"z"`
	Yaw     float64 `json:"yaw"`
	MinTier int     `json:"min_tier"`
	Hits    int     `json:"hits"`
	Glow    bool    `json:"glow,omitempty"`
}

// CaveGlow é um enfeite que brilha (página da Goblopédia).
type CaveGlow struct {
	Kind  string  `json:"kind"`
	X     float64 `json:"x"`
	Y     float64 `json:"y"`
	Z     float64 `json:"z"`
	Yaw   float64 `json:"yaw"`
	Scale float64 `json:"scale"`
}

// CaveLayout é o desenho completo de uma caverna (o cliente desenha a partir dele).
type CaveLayout struct {
	ID      int          `json:"id"`
	Cell    int          `json:"cell"`
	Country string       `json:"country"`
	Rooms   []CaveRoom   `json:"rooms"`
	Tunnels []CaveTunnel `json:"tunnels"`
	Ores    []CaveOre    `json:"ores"`
	Glow    []CaveGlow   `json:"glow"`
	Start   [3]float64   `json:"start"`
	Exit    [3]float64   `json:"exit"`
	Furnace [3]float64   `json:"furnace"`
	Boss    [3]float64   `json:"boss"`
	Wall    float64      `json:"wall"`
	Grid    float64      `json:"grid"`
	// Retângulo (x0, z0, x1, z1) que contém a caverna.
	Bounds [4]float64 `json:"bounds"`
	Frame  struct {
		Origin [3]float64 `json:"origin"`
		East   [3]float64 `json:"east"`
		Up     [3]float64 `json:"up"`
		North  [3]float64 `json:"north"`
	} `json:"frame"`
	frame CaveFrame
}

// CaveObjectBase separa os ids dos minérios dos ids dos objetos do globo (célula × 64).
const CaveObjectBase int64 = 1 << 40

// CaveOreID é o id estável de um minério.
func CaveOreID(cave, index int) int64 { return CaveObjectBase + int64(cave)*1000 + int64(index) }

type caveIndex struct {
	once    sync.Once
	list    []Cave
	byCell  map[int][]int
	mu      sync.Mutex
	layouts map[int]*CaveLayout
}

// Caves lista as bocas de caverna do mundo (geradas na primeira chamada).
func (s *Service) Caves() []Cave {
	s.caves.once.Do(s.buildCaves)
	return s.caves.list
}

// CaveByID devolve a boca pelo id (nil se não existe).
func (s *Service) CaveByID(id int) *Cave {
	list := s.Caves()
	if id < 0 || id >= len(list) {
		return nil
	}
	return &list[id]
}

// CavesInCell lista as bocas de uma célula.
func (s *Service) CavesInCell(cell int) []Cave {
	s.Caves()
	var out []Cave
	for _, id := range s.caves.byCell[cell] {
		out = append(out, s.caves.list[id])
	}
	return out
}

// idealAirportCell é a célula de terra do país mais perto da capital, sem olhar os lotes:
// as cavernas nunca ficam nela nem nos vizinhos (o aeroporto costuma ir para lá).
func (s *Service) idealAirportCell(code string, cells []int) int {
	if s.geo == nil || len(cells) == 0 {
		return -1
	}
	c, ok := s.geo.Capitals[code]
	if !ok {
		return cells[0]
	}
	target := world.LatLonToVec(c.Lat, c.Lon)
	best, bestDot := -1, -2.0
	for _, cell := range cells {
		if d := cellVec(&s.world.Cells[cell]).Dot(target); d > bestDot {
			best, bestDot = cell, d
		}
	}
	return best
}

func (s *Service) buildCaves() {
	cc := s.content.Caves
	s.caves.byCell = map[int][]int{}
	s.caves.layouts = map[int]*CaveLayout{}
	codes := make([]string, 0, len(s.byCountry))
	for code := range s.byCountry {
		codes = append(codes, code)
	}
	sort.Strings(codes)
	mountain := map[string]bool{}
	for _, b := range cc.Entrances.Biomes {
		mountain[b] = true
	}
	var picked []Cave
	for _, code := range codes {
		cells := s.byCountry[code]
		avoid := map[int]bool{}
		if a := s.idealAirportCell(code, cells); a >= 0 {
			avoid[a] = true
			for _, nb := range s.world.Cells[a].Neighbors {
				avoid[nb] = true
			}
		}
		var cand []int
		for _, cell := range cells {
			c := &s.world.Cells[cell]
			if avoid[cell] || c.Country != code {
				continue
			}
			if mountain[c.Biome.String()] || c.Height >= cc.Entrances.HillHeight {
				cand = append(cand, cell)
			}
		}
		n := (len(cells) + cc.Entrances.PerLandCells/2) / cc.Entrances.PerLandCells
		n = max(cc.Entrances.Min, min(cc.Entrances.Max, n))
		// País sem montanhas e morros que bastem: os pontos mais altos dele contam como morro
		// (oito vezes o que precisa: os pontos altos ficam juntos e bocas vizinhas não valem).
		if len(cand) < n*8 && len(cells) >= cc.Entrances.FallbackCells {
			high := append([]int(nil), cells...)
			sort.Slice(high, func(i, j int) bool {
				hi, hj := s.world.Cells[high[i]].Height, s.world.Cells[high[j]].Height
				return hi > hj || (hi == hj && high[i] < high[j])
			})
			for _, cell := range high {
				if len(cand) >= n*8 {
					break
				}
				if !avoid[cell] && s.world.Cells[cell].Country == code && !slicesContainsInt(cand, cell) {
					cand = append(cand, cell)
				}
			}
		}
		if len(cand) == 0 {
			continue
		}
		// Ordem sorteada pela célula; nada de duas bocas vizinhas.
		sort.Slice(cand, func(i, j int) bool {
			hi, hj := mix(uint64(cand[i]), 0xCA7E), mix(uint64(cand[j]), 0xCA7E)
			return hi < hj || (hi == hj && cand[i] < cand[j])
		})
		used := map[int]bool{}
		for _, cell := range cand {
			if n == 0 {
				break
			}
			if used[cell] {
				continue
			}
			x, y, yaw, ok := s.caveSpot(cell)
			if !ok {
				continue
			}
			used[cell] = true
			for _, nb := range s.world.Cells[cell].Neighbors {
				used[nb] = true
			}
			picked = append(picked, Cave{Cell: cell, Country: code, X: x, Y: y, Yaw: yaw})
			n--
		}
	}
	sort.Slice(picked, func(i, j int) bool { return picked[i].Cell < picked[j].Cell })
	for i := range picked {
		picked[i].ID = i
		// Espalha as cavernas pela espiral (389 é primo com 1024: cada id um ponto).
		picked[i].slot = (i*389 + 17) % cc.Slots
		picked[i].Rooms = len(s.generateLayout(&picked[i]).Rooms)
		s.caves.byCell[picked[i].Cell] = append(s.caves.byCell[picked[i].Cell], i)
	}
	s.caves.list = picked
}

// caveSpot escolhe onde fica a boca na célula: fora dos lotes (o quadriculado 2 × 2 em volta
// do centro), num dos quatro lados, de preferência virada para o vizinho mais baixo (a
// encosta). Abre para fora da célula.
func (s *Service) caveSpot(cell int) (x, y, yaw float64, ok bool) {
	cc := s.content.Caves
	f := CellFrame(s.world, cell)
	c := &s.world.Cells[cell]
	bestScore := math.Inf(-1)
	r := newRNG(mix(uint64(cell), 0x5B07))
	// Os quatro lados do quadriculado dos lotes (nas diagonais ficariam em cima deles).
	// Em células pequenas, um pouco mais perto (ainda fora dos lotes, que vão até 7,25).
	for k := 0; k < 8; k++ {
		a := float64(k%4) * math.Pi / 2
		spot := cc.Entrances.Spot
		if k >= 4 {
			spot = math.Min(spot, 8.4)
		}
		px, py := math.Cos(a)*spot, math.Sin(a)*spot
		if !f.Inside(px, py, 1.6) {
			continue
		}
		// Encosta: quanto o vizinho naquela direção é mais baixo.
		dir := f.East.Scale(math.Cos(a)).Add(f.North.Scale(math.Sin(a)))
		drop := 0.0
		bestDot := -2.0
		for _, nb := range c.Neighbors {
			v := cellVec(&s.world.Cells[nb]).Sub(f.Center)
			if d := v.Normalize().Dot(dir); d > bestDot {
				bestDot = d
				drop = c.Height - s.world.Cells[nb].Height
				if s.world.Cells[nb].Terrain != world.Land {
					drop = -1
				}
			}
		}
		score := drop + r.float()*0.3
		if score > bestScore {
			bestScore, x, y, yaw, ok = score, px, py, a, true
		}
	}
	return
}

// CaveFrameOf é o sistema de coordenadas da caverna.
func (s *Service) CaveFrameOf(cv *Cave) CaveFrame {
	n := float64(s.content.Caves.Slots)
	i := float64(cv.slot) + 0.5
	// Espiral de Fibonacci: pontos espalhados por igual na esfera.
	y := 1 - 2*i/n
	rad := math.Sqrt(math.Max(0, 1-y*y))
	th := math.Pi * (3 - math.Sqrt(5)) * i
	up := world.Vec3{X: math.Cos(th) * rad, Y: y, Z: math.Sin(th) * rad}.Normalize()
	ref := world.Vec3{Y: 1}
	if math.Abs(up.Y) > 0.999 {
		ref = world.Vec3{Z: 1}
	}
	east := ref.Cross(up).Normalize()
	north := up.Cross(east)
	return CaveFrame{Origin: up.Scale(s.content.Caves.ShellRadius), East: east, Up: up, North: north}
}

// CaveLayoutOf devolve o desenho da caverna (gerado uma vez e guardado).
func (s *Service) CaveLayoutOf(id int) *CaveLayout {
	cv := s.CaveByID(id)
	if cv == nil {
		return nil
	}
	s.caves.mu.Lock()
	defer s.caves.mu.Unlock()
	if l, ok := s.caves.layouts[id]; ok {
		return l
	}
	l := s.generateLayout(cv)
	s.caves.layouts[id] = l
	return l
}

// generateLayout monta a caverna a partir da semente da célula da boca.
func (s *Service) generateLayout(cv *Cave) *CaveLayout {
	cc := s.content.Caves
	lc := cc.Layout
	r := newRNG(mix(uint64(cv.Cell), 0xCA7E5EED))
	between := func(a [2]float64) float64 { return a[0] + r.float()*(a[1]-a[0]) }
	n := lc.Rooms[0] + r.intn(lc.Rooms[1]-lc.Rooms[0]+1)
	l := &CaveLayout{ID: cv.ID, Cell: cv.Cell, Country: cv.Country, Wall: lc.Wall, Grid: lc.Grid}
	l.Rooms = append(l.Rooms, CaveRoom{R: between(lc.RoomRadius)})
	angle := r.float() * 2 * math.Pi
	turn := lc.Turn * math.Pi / 180
	fits := func(x, z, rad float64, skip int) bool {
		for i, o := range l.Rooms {
			if i == skip {
				continue
			}
			if math.Hypot(o.X-x, o.Z-z) < o.R+rad+3.5 {
				return false
			}
		}
		return true
	}
	for i := 1; i < n; i++ {
		prev := l.Rooms[len(l.Rooms)-1]
		prevIdx := len(l.Rooms) - 1
		boss := i == n-1
		rad := between(lc.RoomRadius)
		if boss {
			rad = lc.BossRadius
		}
		depth := float64(i) / float64(n-1)
		placed := false
		for try := 0; try < 40 && !placed; try++ {
			a := angle + (r.float()*2-1)*turn*(1+float64(try)/10)
			d := math.Max(between(lc.Step), prev.R+rad+5)
			x, z := prev.X+math.Cos(a)*d, prev.Z+math.Sin(a)*d
			if !fits(x, z, rad, prevIdx) {
				continue
			}
			ledge := !boss && i > 1 && r.float() < lc.LedgeChance*depth
			y := prev.Y + (r.float()*2-1)*lc.Rise
			if ledge {
				y = prev.Y + lc.Ledge
				if r.intn(2) == 0 {
					y = prev.Y - lc.Ledge
				}
			}
			if boss {
				y = prev.Y
			}
			l.Rooms = append(l.Rooms, CaveRoom{X: x, Z: z, R: rad, Y: y, Depth: depth, Boss: boss})
			l.Tunnels = append(l.Tunnels, CaveTunnel{A: prevIdx, B: len(l.Rooms) - 1, W: lc.TunnelWidth, Ledge: ledge})
			angle = a
			placed = true
		}
		if !placed {
			break // sem espaço: a caverna fica mais curta (o último vira a sala do chefe)
		}
	}
	// Garante a sala do chefe no fim.
	last := &l.Rooms[len(l.Rooms)-1]
	if !last.Boss {
		last.Boss = true
		last.Depth = 1
	}
	// Salões laterais (becos com minérios), saindo dos salões do meio.
	main := len(l.Rooms)
	for i := 1; i < main-1; i++ {
		if r.float() >= lc.SideChance {
			continue
		}
		base := l.Rooms[i]
		rad := between(lc.RoomRadius) * 0.8
		for try := 0; try < 12; try++ {
			a := r.float() * 2 * math.Pi
			d := base.R + rad + 5 + r.float()*3
			x, z := base.X+math.Cos(a)*d, base.Z+math.Sin(a)*d
			if !fits(x, z, rad, i) || s.crossesRoom(l, base.X, base.Z, x, z, i, -1) {
				continue
			}
			y := base.Y + (r.float()*2-1)*lc.Rise*0.6
			l.Rooms = append(l.Rooms, CaveRoom{X: x, Z: z, R: rad, Y: y, Depth: base.Depth, Side: true})
			l.Tunnels = append(l.Tunnels, CaveTunnel{A: i, B: len(l.Rooms) - 1, W: lc.TunnelWidth * 0.9})
			break
		}
	}
	// Entrada: a saída fica do lado oposto ao túnel do primeiro salão; o começo entre ela e
	// o meio; a fornalha antiga num canto.
	first := l.Rooms[0]
	out := math.Atan2(l.Rooms[1].Z-first.Z, l.Rooms[1].X-first.X) + math.Pi
	l.Exit = [3]float64{first.X + math.Cos(out)*first.R*0.86, first.Y, first.Z + math.Sin(out)*first.R*0.86}
	l.Start = [3]float64{first.X + math.Cos(out)*first.R*0.45, first.Y, first.Z + math.Sin(out)*first.R*0.45}
	fa := out + math.Pi/2
	l.Furnace = [3]float64{first.X + math.Cos(fa)*first.R*0.62, first.Y, first.Z + math.Sin(fa)*first.R*0.62}
	boss := l.Rooms[main-1]
	l.Boss = [3]float64{boss.X, boss.Y, boss.Z}
	s.placeCaveStuff(l, r, main)
	// Caixa da caverna.
	x0, z0, x1, z1 := math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
	for _, rm := range l.Rooms {
		x0, z0 = math.Min(x0, rm.X-rm.R), math.Min(z0, rm.Z-rm.R)
		x1, z1 = math.Max(x1, rm.X+rm.R), math.Max(z1, rm.Z+rm.R)
	}
	l.Bounds = [4]float64{x0 - 3, z0 - 3, x1 + 3, z1 + 3}
	l.frame = s.CaveFrameOf(cv)
	l.Frame.Origin = vecArr(l.frame.Origin)
	l.Frame.East = vecArr(l.frame.East)
	l.Frame.Up = vecArr(l.frame.Up)
	l.Frame.North = vecArr(l.frame.North)
	return l
}

func vecArr(v world.Vec3) [3]float64 { return [3]float64{v.X, v.Y, v.Z} }

// crossesRoom diz se o segmento (ax, az)–(bx, bz) passa por dentro de algum salão (fora os
// dois das pontas).
func (s *Service) crossesRoom(l *CaveLayout, ax, az, bx, bz float64, skipA, skipB int) bool {
	for i, rm := range l.Rooms {
		if i == skipA || i == skipB {
			continue
		}
		if segDist(rm.X, rm.Z, ax, az, bx, bz) < rm.R+1 {
			return true
		}
	}
	return false
}

// segDist é a distância de (px, pz) ao segmento a–b.
func segDist(px, pz, ax, az, bx, bz float64) float64 {
	dx, dz := bx-ax, bz-az
	t := 0.0
	if l2 := dx*dx + dz*dz; l2 > 0 {
		t = math.Max(0, math.Min(1, ((px-ax)*dx+(pz-az)*dz)/l2))
	}
	return math.Hypot(px-(ax+t*dx), pz-(az+t*dz))
}

// placeCaveStuff põe os minérios e os enfeites que brilham perto das paredes dos salões.
func (s *Service) placeCaveStuff(l *CaveLayout, r *rng, main int) {
	cc := s.content.Caves
	var spots [][3]float64 // tudo que já ocupa o chão (x, z, raio)
	spots = append(spots, [3]float64{l.Start[0], l.Start[2], 2.5}, [3]float64{l.Exit[0], l.Exit[2], 2.5},
		[3]float64{l.Furnace[0], l.Furnace[2], 2.0})
	free := func(x, z, rad float64) bool {
		for _, sp := range spots {
			if math.Hypot(sp[0]-x, sp[1]-z) < sp[2]+rad {
				return false
			}
		}
		// Longe da boca dos túneis (o caminho fica livre).
		for _, t := range l.Tunnels {
			a, b := l.Rooms[t.A], l.Rooms[t.B]
			if segDist(x, z, a.X, a.Z, b.X, b.Z) < t.W/2+1.0 && math.Hypot(x-a.X, z-a.Z) > a.R*0.5 && math.Hypot(x-b.X, z-b.Z) > b.R*0.5 {
				return false
			}
			if segDist(x, z, a.X, a.Z, b.X, b.Z) < t.W/2+1.2 {
				return false
			}
		}
		return true
	}
	at := func(rm CaveRoom, lo, hi, rad float64) (float64, float64, bool) {
		for try := 0; try < 24; try++ {
			a := r.float() * 2 * math.Pi
			d := rm.R * (lo + r.float()*(hi-lo))
			x, z := rm.X+math.Cos(a)*d, rm.Z+math.Sin(a)*d
			if free(x, z, rad) {
				return x, z, true
			}
		}
		return 0, 0, false
	}
	idx := 0
	for i, rm := range l.Rooms {
		if rm.Boss {
			continue
		}
		count := cc.OresPerRoom[0] + r.intn(cc.OresPerRoom[1]-cc.OresPerRoom[0]+1)
		if i == 0 {
			count = 2 // a entrada tem só carvão e ferro, para começar
		}
		if rm.Side {
			count++
		}
		for k := 0; k < count; k++ {
			rule := pickOre(cc.Ores, rm.Depth, r, i == 0)
			if rule == nil {
				continue
			}
			x, z, ok := at(rm, 0.55, 0.85, 1.4)
			if !ok {
				continue
			}
			spots = append(spots, [3]float64{x, z, 1.4})
			l.Ores = append(l.Ores, CaveOre{ID: CaveOreID(l.ID, idx), Ore: rule.ID, Item: rule.Item, X: x, Y: rm.Y, Z: z,
				Yaw: r.float() * 2 * math.Pi, MinTier: rule.MinTier, Hits: rule.Hits, Glow: rule.Glow})
			idx++
		}
	}
	for _, rm := range l.Rooms {
		for _, g := range cc.Glow {
			if rm.Depth < g.Depth[0] || rm.Depth > g.Depth[1] {
				continue
			}
			count := g.PerRoom[0] + r.intn(g.PerRoom[1]-g.PerRoom[0]+1)
			if rm.Boss {
				count = (count + 1) / 2
			}
			for k := 0; k < count; k++ {
				x, z, ok := at(rm, 0.7, 0.93, 0.6)
				if !ok {
					continue
				}
				spots = append(spots, [3]float64{x, z, 0.6})
				l.Glow = append(l.Glow, CaveGlow{Kind: g.ID, X: x, Y: rm.Y, Z: z, Yaw: r.float() * 2 * math.Pi, Scale: 0.8 + r.float()*0.5})
			}
		}
	}
}

func pickOre(rules []OreRule, depth float64, r *rng, entrance bool) *OreRule {
	total := 0.0
	ok := func(o *OreRule) bool {
		if entrance {
			return o.MinTier <= 1 && o.Depth[0] <= 0
		}
		return depth >= o.Depth[0] && depth <= o.Depth[1]
	}
	for i := range rules {
		if ok(&rules[i]) {
			total += rules[i].Weight
		}
	}
	if total <= 0 {
		return nil
	}
	x := r.float() * total
	for i := range rules {
		if !ok(&rules[i]) {
			continue
		}
		x -= rules[i].Weight
		if x < 0 {
			return &rules[i]
		}
	}
	return nil
}

// FloorAt é a altura do chão em (x, z) e se o ponto está dentro da caverna. Nos salões, a
// altura do salão; nos túneis, a rampa (ou o degrau) entre as alturas das pontas.
func (l *CaveLayout) FloorAt(x, z float64) (float64, bool) {
	best, in := math.Inf(-1), false
	for _, rm := range l.Rooms {
		if math.Hypot(x-rm.X, z-rm.Z) <= rm.R {
			best, in = math.Max(best, rm.Y), true
		}
	}
	if in {
		return best, true
	}
	for _, t := range l.Tunnels {
		a, b := l.Rooms[t.A], l.Rooms[t.B]
		if segDist(x, z, a.X, a.Z, b.X, b.Z) > t.W/2 {
			continue
		}
		dx, dz := b.X-a.X, b.Z-a.Z
		ln := math.Hypot(dx, dz)
		tt := ((x-a.X)*dx + (z-a.Z)*dz) / (ln * ln)
		ta, tb := a.R/ln, 1-b.R/ln
		u := math.Max(0, math.Min(1, (tt-ta)/math.Max(1e-6, tb-ta)))
		y := a.Y + (b.Y-a.Y)*u
		if t.Ledge {
			y = a.Y
			if u >= 0.5 {
				y = b.Y
			}
		}
		best, in = math.Max(best, y), true
	}
	return best, in
}

// FrameOf é o sistema de coordenadas da caverna do desenho.
func (l *CaveLayout) FrameOf() CaveFrame { return l.frame }

// CaveAt diz em que caverna está um ponto do mundo (-1 = no globo).
func (s *Service) CaveAt(p world.Vec3) int {
	cc := s.content.Caves
	if p.Len() < cc.ShellRadius*0.5 {
		return -1
	}
	best, bestD := -1, math.Inf(1)
	for i := range s.Caves() {
		f := s.CaveFrameOf(&s.caves.list[i])
		if d := f.Origin.Sub(p).Len(); d < bestD {
			best, bestD = i, d
		}
	}
	if bestD > 600 {
		return -1
	}
	return best
}

// InCaveBounds diz se o ponto do mundo está dentro da caixa da caverna (com folga), na
// altura dela. A camada em tempo real usa para validar o movimento lá dentro.
func (s *Service) InCaveBounds(id int, p world.Vec3) bool {
	l := s.CaveLayoutOf(id)
	if l == nil {
		return false
	}
	x, y, z := l.frame.Local(p)
	b := l.Bounds
	if x < b[0]-2 || z < b[1]-2 || x > b[2]+2 || z > b[3]+2 {
		return false
	}
	lo, hi := math.Inf(1), math.Inf(-1)
	for _, rm := range l.Rooms {
		lo, hi = math.Min(lo, rm.Y), math.Max(hi, rm.Y)
	}
	return y > lo-4 && y < hi+l.Wall+6
}

// CaveStartPoint é o começo da caverna no espaço do mundo (um pouco acima do chão).
func (s *Service) CaveStartPoint(id int) (world.Vec3, bool) {
	l := s.CaveLayoutOf(id)
	if l == nil {
		return world.Vec3{}, false
	}
	return l.frame.Point(l.Start[0], l.Start[1]+0.5, l.Start[2]), true
}

// CaveEntrancePoint é a boca da caverna no globo (no chão da célula).
func (s *Service) CaveEntrancePoint(id int) (world.Vec3, bool) {
	cv := s.CaveByID(id)
	if cv == nil {
		return world.Vec3{}, false
	}
	f := CellFrame(s.world, cv.Cell)
	return f.Point(cv.X, cv.Y), true
}
