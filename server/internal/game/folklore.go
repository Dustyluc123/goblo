package game

import (
	"fmt"
	"math"
	"sort"
	"sync"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Folclore (fase 4.5, ADR 0058): criaturas raras e fofas inspiradas em lendas populares de
// domínio público, que aparecem de vez em quando no país de origem. O sorteio é por célula
// e por janela de tempo (determinístico): todo mundo vê a mesma criatura no mesmo lugar. O
// cliente pergunta quem está por perto (LegendsNear) e some com ela quando o jogador chega
// perto demais; a foto registra na seção Lendas da Goblopédia.

// FolkloreContent é folklore.json.
type FolkloreContent struct {
	Window  int      `json:"window"` // minutos
	Shy     float64  `json:"shy"`
	MaxDist float64  `json:"max_dist"`
	Legends []Legend `json:"legends"`
}

// Legend é uma criatura do folclore.
type Legend struct {
	ID       string     `json:"id"`
	Name     string     `json:"name"`
	Country  string     `json:"country"`
	Story    string     `json:"story"`
	Biomes   []string   `json:"biomes"`
	Lat      [2]float64 `json:"lat,omitempty"`
	Water    bool       `json:"water,omitempty"`
	Hours    [2]int     `json:"hours"`
	Seasons  []string   `json:"seasons,omitempty"`
	Chance   float64    `json:"chance"`
	Duration [2]int     `json:"duration"`
	Colors   []string   `json:"colors"`
}

func (f *FolkloreContent) check(c *Content) error {
	if f.Window < 5 || f.Shy <= 0 || f.MaxDist <= f.Shy {
		return fmt.Errorf("folklore.json: window, shy ou max_dist inválidos")
	}
	seen := map[string]bool{}
	for _, l := range f.Legends {
		if l.ID == "" || seen[l.ID] || l.Name == "" || l.Story == "" || len(l.Country) != 3 {
			return fmt.Errorf("folklore.json: lenda %q inválida", l.ID)
		}
		seen[l.ID] = true
		if l.Chance <= 0 || l.Chance > 1 || l.Duration[0] < 1 || l.Duration[1] < l.Duration[0] || l.Duration[1] > f.Window {
			return fmt.Errorf("folklore.json: %s com chance ou duração inválidas", l.ID)
		}
		if l.Hours[0] < 0 || l.Hours[0] > 23 || l.Hours[1] < 0 || l.Hours[1] > 24 {
			return fmt.Errorf("folklore.json: %s com horas inválidas", l.ID)
		}
		for _, b := range l.Biomes {
			if !validBiome(b) {
				return fmt.Errorf("folklore.json: %s com bioma %s desconhecido", l.ID, b)
			}
		}
		for _, se := range l.Seasons {
			if se != "none" && !slicesContains(SeasonNames[:], se) {
				return fmt.Errorf("folklore.json: %s com estação %s desconhecida", l.ID, se)
			}
		}
	}
	return nil
}

// Legend devolve a lenda pelo id (nil se não existe).
func (f *FolkloreContent) Legend(id string) *Legend {
	for i := range f.Legends {
		if f.Legends[i].ID == id {
			return &f.Legends[i]
		}
	}
	return nil
}

// inHours: a hora local h está na faixa [de, até) (passando da meia-noite se de > até)?
func inHours(h float64, r [2]int) bool {
	a, b := float64(r[0]), float64(r[1])
	if a <= b {
		return h >= a && h < b
	}
	return h >= a || h < b
}

// LegendSighting é uma criatura aparecendo: na célula, em (X, Y) do plano dela, de From a
// Until (unix).
type LegendSighting struct {
	Legend string  `json:"legend"`
	Cell   int     `json:"cell"`
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Yaw    float64 `json:"yaw"`
	From   int64   `json:"from"`
	Until  int64   `json:"until"`
	Water  bool    `json:"water,omitempty"`
}

type legendIndex struct {
	once   sync.Once
	byCell map[int][]int // célula → lendas que podem aparecer nela
	mu     sync.Mutex
	forced []LegendSighting // modo dev
}

func (s *Service) buildLegends() {
	f := s.content.Folklore
	s.legends.byCell = map[int][]int{}
	for li, l := range f.Legends {
		for _, cell := range s.byCountry[l.Country] {
			c := &s.world.Cells[cell]
			if c.Country != l.Country || !slicesContains(l.Biomes, world.BiomeNames[c.Biome]) || s.airportCells[cell] {
				continue
			}
			if l.Lat != [2]float64{} && (c.Lat < l.Lat[0] || c.Lat > l.Lat[1]) {
				continue
			}
			if l.Water && !s.coastal(cell) {
				continue
			}
			s.legends.byCell[cell] = append(s.legends.byCell[cell], li)
		}
	}
}

func (s *Service) coastal(cell int) bool {
	for _, nb := range s.world.Cells[cell].Neighbors {
		if s.world.Cells[nb].Terrain != world.Land {
			return true
		}
	}
	return false
}

// LegendCells lista as células onde a lenda pode aparecer (testes e modo dev).
func (s *Service) LegendCells(id string) []int {
	s.legends.once.Do(s.buildLegends)
	var out []int
	for cell, list := range s.legends.byCell {
		for _, li := range list {
			if s.content.Folklore.Legends[li].ID == id {
				out = append(out, cell)
			}
		}
	}
	sort.Ints(out)
	return out
}

// legendAt: a criatura li aparece na célula na janela w? (determinístico)
func (s *Service) legendAt(li, cell int, w int64) (LegendSighting, bool) {
	f := s.content.Folklore
	l := &f.Legends[li]
	r := newRNG(mix(uint64(cell), uint64(w), uint64(li), 0xF01C))
	if r.float() >= l.Chance {
		return LegendSighting{}, false
	}
	win := int64(f.Window) * 60
	dur := int64(l.Duration[0]+r.intn(l.Duration[1]-l.Duration[0]+1)) * 60
	start := w*win + int64(r.float()*float64(win-dur))
	c := &s.world.Cells[cell]
	t := time.Unix(start, 0).UTC()
	hour := math.Mod(float64(t.Unix()+localOffsetSeconds(c.Lon))/3600, 24)
	if hour < 0 {
		hour += 24
	}
	if !inHours(hour, l.Hours) {
		return LegendSighting{}, false
	}
	if len(l.Seasons) > 0 && !slicesContains(l.Seasons, SeasonFor(t, c.Lat, c.Biome)) {
		return LegendSighting{}, false
	}
	fr := CellFrame(s.world, cell)
	x, y := 0.0, 0.0
	if l.Water {
		// Na borda da célula, virada para o mar.
		for _, nb := range c.Neighbors {
			if s.world.Cells[nb].Terrain != world.Land {
				v := cellVec(&s.world.Cells[nb]).Scale(fr.Top)
				x, y = v.Dot(fr.East), v.Dot(fr.North)
				d := math.Hypot(x, y)
				edge := math.Max(0, fr.EdgeDistanceAlong(x/d, y/d))
				x, y = x/d*(edge+2.5), y/d*(edge+2.5)
				break
			}
		}
	} else {
		for try := 0; try < 10; try++ {
			ang := r.float() * 2 * math.Pi
			d := 2 + r.float()*9
			x, y = math.Cos(ang)*d, math.Sin(ang)*d
			if fr.Inside(x, y, 1.5) {
				break
			}
		}
	}
	return LegendSighting{Legend: l.ID, Cell: cell, X: x, Y: y, Yaw: r.float() * 2 * math.Pi,
		From: start, Until: start + dur, Water: l.Water}, true
}

// LegendsNear lista as criaturas aparecendo agora nas células em volta (rings anéis).
func (s *Service) LegendsNear(cell, rings int, at time.Time) []LegendSighting {
	s.legends.once.Do(s.buildLegends)
	if cell < 0 || cell >= len(s.world.Cells) {
		return nil
	}
	win := int64(s.content.Folklore.Window) * 60
	now := at.Unix()
	w := floorDiv(now, win)
	out := []LegendSighting{}
	cells := s.cellsAround(cell, rings)
	sort.Ints(cells)
	for _, c := range cells {
		for _, li := range s.legends.byCell[c] {
			if sg, ok := s.legendAt(li, c, w); ok && sg.From <= now && now < sg.Until {
				out = append(out, sg)
			}
		}
	}
	s.legends.mu.Lock()
	keep := s.legends.forced[:0]
	for _, sg := range s.legends.forced {
		if sg.Until <= now {
			continue
		}
		keep = append(keep, sg)
		if slicesContainsInt(cells, sg.Cell) {
			out = append(out, sg)
		}
	}
	s.legends.forced = keep
	s.legends.mu.Unlock()
	return out
}

func slicesContainsInt(list []int, v int) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

// legendPoint é a posição da criatura no mundo (no chão da célula; na água, um pouco abaixo).
func (s *Service) legendPoint(sg LegendSighting) world.Vec3 {
	f := CellFrame(s.world, sg.Cell)
	p := f.Point(sg.X, sg.Y)
	if sg.Water {
		p = p.Normalize().Scale(s.world.Radius)
	}
	return p
}

// DevLegend (modo dev): a criatura aparece agora perto do jogador, por 10 minutos (todos
// veem). Fora do país dela também, para testar.
func (s *Service) DevLegend(p *Player, id string) (*LegendSighting, error) {
	f := s.content.Folklore
	li := -1
	for i := range f.Legends {
		if f.Legends[i].ID == id {
			li = i
		}
	}
	if li < 0 {
		return nil, ErrNotFound.with("Lenda desconhecida.")
	}
	pos, cell, facing, checked, err := s.where(p)
	if err != nil {
		return nil, err
	}
	if !checked {
		return nil, ErrOffline
	}
	fr := CellFrame(s.world, cell)
	at := pos.Add(facing.Scale(9))
	x, y := at.Dot(fr.East), at.Dot(fr.North)
	now := s.clock.Now().Unix()
	sg := LegendSighting{Legend: id, Cell: cell, X: x, Y: y, Yaw: math.Atan2(-facing.Dot(fr.North), -facing.Dot(fr.East)),
		From: now, Until: now + 600}
	s.legends.mu.Lock()
	s.legends.forced = append(s.legends.forced, sg)
	s.legends.mu.Unlock()
	return &sg, nil
}
