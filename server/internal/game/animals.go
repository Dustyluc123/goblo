package game

import (
	"context"
	"fmt"
	"math"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Animais (fase 2.5, ADR 0032). O servidor sorteia, de forma determinística por célula,
// quais animais existem ali (espécie, id estável, casa do grupo e uns poucos pontos de
// passeio já conferidos: dentro da célula, fora dos lotes e longe de árvores e pedras). A
// posição em cada instante sai de AnimalAt, uma conta só com o animal e o horário do
// servidor; o cliente faz a mesma conta (client/scripts/animal_path.gd) e todos os jogadores
// veem o mesmo animal no mesmo lugar, sem o servidor simular nada.

// MaxAnimalsPerCell limita os animais de uma célula; o id do animal é célula × 16 + índice.
const MaxAnimalsPerCell = 16

// Quantos pontos de passeio cada animal tem (o trajeto vai de um para outro).
const animalPoints = 6

// Folgas do passeio (unidades): até a borda da célula, até os lotes e até árvores e pedras.
const (
	animalLotMargin  = 0.6
	animalTreeMargin = 1.1
)

// AnimalSpecies é uma espécie de animals.json.
type AnimalSpecies struct {
	Name   string  `json:"name"`
	Model  string  `json:"model"`
	Height float64 `json:"height"`
	Shy    bool    `json:"shy"`
	Walk   float64 `json:"walk"`
	Run    float64 `json:"run"`
	Roam   float64 `json:"roam"`
	Leg    float64 `json:"leg"`
	Jump   string  `json:"jump"`
}

// AnimalRule é um grupo de animais de um bioma.
type AnimalRule struct {
	Species []string `json:"species"`
	PerCell float64  `json:"per_cell"`
	Group   [2]int   `json:"group"`
}

// AnimalContent é o animals.json.
type AnimalContent struct {
	Species      map[string]AnimalSpecies `json:"species"`
	Biomes       map[string][]AnimalRule  `json:"biomes"`
	Neighborhood struct {
		Species    []string `json:"species"`
		PerLot     float64  `json:"per_lot"`
		MaxPerCell int      `json:"max_per_cell"`
	} `json:"neighborhood"`
}

// Animal é um animal do mundo. A posição é (x, y) no plano da célula (veja Frame).
type Animal struct {
	ID      int64        `json:"id"`
	Cell    int          `json:"cell"`
	Species string       `json:"species"`
	Points  [][2]float64 `json:"points"` // pontos de passeio (o trajeto vai de um a outro)
	Speed   float64      `json:"speed"`  // andando (unidades/s)
	Leg     float64      `json:"leg"`    // segundos de cada trecho (andar + ficar parado)
}

// AnimalID monta o id estável de um animal.
func AnimalID(cell, index int) int64 { return int64(cell)*MaxAnimalsPerCell + int64(index) }

// AnimalCell devolve a célula de um id de animal.
func AnimalCell(id int64) int { return int(id / MaxAnimalsPerCell) }

// GenerateAnimals sorteia os animais da célula. Depende só da célula (id, bioma,
// geometria), dos objetos dela e dos lotes ocupados: quem chama passa os mesmos dados que
// manda ao cliente, então todo mundo recebe os mesmos animais.
func GenerateAnimals(w *world.World, content *Content, cell int, objects []Object, lots []Lot) []Animal {
	if cell < 0 || cell >= len(w.Cells) || w.Cells[cell].Terrain != world.Land || content.Animals == nil {
		return nil
	}
	ac := content.Animals
	f := CellFrame(w, cell)
	var slots []int
	for _, l := range lots {
		if l.Cell == cell {
			slots = append(slots, l.Slot)
		}
	}
	var obstacles [][2]float64
	for _, o := range objects {
		if o.Kind == KindTree || o.Kind == KindRock || (o.Kind == KindDecor && o.Solid) {
			obstacles = append(obstacles, [2]float64{o.X, o.Y})
		}
	}
	free := func(x, y float64) bool {
		if !f.Inside(x, y, 1.2) || insideAnySlot(x, y, slots, animalLotMargin) {
			return false
		}
		for _, o := range obstacles {
			if (o[0]-x)*(o[0]-x)+(o[1]-y)*(o[1]-y) < animalTreeMargin*animalTreeMargin {
				return false
			}
		}
		return true
	}
	clear := func(a, b [2]float64) bool {
		steps := int(math.Hypot(b[0]-a[0], b[1]-a[1])/0.4) + 1
		for k := 1; k < steps; k++ {
			t := float64(k) / float64(steps)
			if !free(a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t) {
				return false
			}
		}
		return true
	}

	r := newRNG(mix(uint64(cell), 0xA21A15))
	var out []Animal
	add := func(r *rng, species string, home [2]float64) {
		sp, ok := ac.Species[species]
		if !ok || len(out) >= MaxAnimalsPerCell {
			return
		}
		var pts [][2]float64
		for try := 0; try < 40 && len(pts) < animalPoints; try++ {
			a := r.float() * 2 * math.Pi
			d := sp.Roam * math.Sqrt(r.float())
			p := [2]float64{round2(home[0] + math.Cos(a)*d), round2(home[1] + math.Sin(a)*d)}
			if !free(p[0], p[1]) {
				continue
			}
			ok := true
			for _, q := range pts {
				if !clear(p, q) {
					ok = false
					break
				}
			}
			if ok {
				pts = append(pts, p)
			}
		}
		if len(pts) < 2 {
			return
		}
		out = append(out, Animal{ID: AnimalID(cell, len(out)), Cell: cell, Species: species, Points: pts, Speed: sp.Walk, Leg: sp.Leg})
	}
	randomHome := func() [2]float64 {
		n := len(f.Poly)
		k := r.intn(n)
		u, v := r.float(), r.float()
		if u+v > 1 {
			u, v = 1-u, 1-v
		}
		a, b := f.Poly[k], f.Poly[(k+1)%n]
		return [2]float64{(a[0]*u + b[0]*v) * 0.75, (a[1]*u + b[1]*v) * 0.75}
	}
	for _, rule := range ac.Biomes[w.Cells[cell].Biome.String()] {
		groups := int(rule.PerCell)
		if r.float() < rule.PerCell-float64(groups) {
			groups++
		}
		for g := 0; g < groups; g++ {
			home := randomHome()
			species := rule.Species[r.intn(len(rule.Species))]
			size := rule.Group[0]
			if rule.Group[1] > rule.Group[0] {
				size += r.intn(rule.Group[1] - rule.Group[0] + 1)
			}
			for i := 0; i < size; i++ {
				add(r, species, home)
			}
		}
	}
	// Cachorros perto dos bairros (lotes ocupados em biomas agradáveis): sorteio separado,
	// para um lote novo não mudar os animais do bioma.
	if n := len(slots); n > 0 && pleasantBiomes[w.Cells[cell].Biome] && len(ac.Neighborhood.Species) > 0 {
		dr := newRNG(mix(uint64(cell), 0xD065))
		want := int(ac.Neighborhood.PerLot * float64(n))
		if dr.float() < ac.Neighborhood.PerLot*float64(n)-float64(want) {
			want++
		}
		want = min(want, ac.Neighborhood.MaxPerCell)
		for i := 0; i < want; i++ {
			species := ac.Neighborhood.Species[dr.intn(len(ac.Neighborhood.Species))]
			// Casa do cachorro: no anel entre os lotes e a borda da célula.
			a := dr.float() * 2 * math.Pi
			home := [2]float64{math.Cos(a) * 9.5, math.Sin(a) * 9.5}
			add(dr, species, home)
		}
	}
	return out
}

// --- Trajeto (a mesma conta em client/scripts/animal_path.gd) ---------------------------

// hash32 mistura três números de 32 bits (só multiplicações e xor em 32 bits, fácil de
// repetir igualzinho em GDScript).
func hash32(a, b, c uint32) uint32 {
	x := a*0x9E3779B1 ^ b*0x85EBCA77 ^ c*0xC2B2AE3D
	x ^= x >> 16
	x *= 0x7FEB352D
	x ^= x >> 15
	x *= 0x846CA68B
	x ^= x >> 16
	return x
}

// AnimalPose é onde o animal está e o que está fazendo num instante.
type AnimalPose struct {
	X, Y    float64
	Heading float64 // ângulo no plano da célula (radianos, 0 = leste, anti-horário)
	State   string  // "walk", "idle", "eat" ou "look"
}

// Parte de cada trecho que pode ser gasta andando (o resto é parado).
const animalWalkShare = 0.7

// AnimalAt calcula a pose do animal no instante t (segundos unix do servidor). O tempo é
// cortado em trechos de a.Leg segundos (com um deslocamento por animal, para eles não
// andarem todos juntos); em cada trecho o animal vai do ponto sorteado para o trecho
// anterior ao sorteado para este e depois fica parado (comendo, olhando ou parado) até o
// próximo. Se os dois sorteios dão o mesmo ponto, fica parado o trecho inteiro.
func AnimalAt(a *Animal, t float64) AnimalPose {
	n := len(a.Points)
	id := uint32(a.ID)
	off := float64(hash32(id, 0, 1)%1000) / 1000 * a.Leg
	k := math.Floor((t + off) / a.Leg)
	u := t + off - k*a.Leg
	ki := uint32(int64(k))
	pick := func(kk uint32) int { return int(hash32(id, kk, 2) % uint32(n)) }
	from := pick(ki - 1)
	to := pick(ki)
	p, q := a.Points[from], a.Points[to]
	dx, dy := q[0]-p[0], q[1]-p[1]
	dist := math.Hypot(dx, dy)
	if dist < 0.01 {
		// Sorteou o mesmo ponto: fica parado o trecho inteiro, virado para onde chegou.
		prev := a.Points[pick(ki-2)]
		heading := math.Atan2(p[1]-prev[1], p[0]-prev[0])
		if math.Hypot(p[0]-prev[0], p[1]-prev[1]) < 0.01 {
			heading = float64(hash32(id, ki, 4)%628) / 100
		}
		state := [...]string{"idle", "eat", "look"}[hash32(id, ki, 3)%3]
		return AnimalPose{X: q[0], Y: q[1], Heading: heading, State: state}
	}
	heading := math.Atan2(dy, dx)
	walk := dist / a.Speed
	if max := a.Leg * animalWalkShare; walk > max {
		walk = max
	}
	if u < walk {
		s := u / walk
		return AnimalPose{X: p[0] + dx*s, Y: p[1] + dy*s, Heading: heading, State: "walk"}
	}
	state := [...]string{"idle", "eat", "look"}[hash32(id, ki, 3)%3]
	return AnimalPose{X: q[0], Y: q[1], Heading: heading, State: state}
}

// Animals devolve os animais das células (os mesmos para todos os jogadores).
func (s *Service) Animals(ctx context.Context, cells []int) ([]Animal, error) {
	cells = sortedCells(cells)
	lots, err := s.store.LotsByCells(ctx, cells)
	if err != nil {
		return nil, err
	}
	out := []Animal{}
	for _, cell := range cells {
		if cell < 0 || cell >= len(s.world.Cells) {
			continue
		}
		out = append(out, GenerateAnimals(s.world, s.content, cell, s.cellObjects(cell, lots), lots)...)
	}
	return out, nil
}

// animal acha um animal pelo id (gerando a célula dele).
func (s *Service) animal(ctx context.Context, tx Store, id int64) (*Animal, error) {
	cell := AnimalCell(id)
	if id < 0 || cell >= len(s.world.Cells) {
		return nil, ErrNotFound
	}
	lots, err := tx.LotsByCells(ctx, []int{cell})
	if err != nil {
		return nil, err
	}
	for _, a := range GenerateAnimals(s.world, s.content, cell, s.cellObjects(cell, lots), lots) {
		if a.ID == id {
			return &a, nil
		}
	}
	return nil, ErrNotFound.with("Esse animal não está mais aqui.")
}

// FeedResult é a resposta de dar uma frutinha a um animal.
type FeedResult struct {
	Species   string      `json:"species"`
	Inventory []StackView `json:"inventory"`
	SlotsUsed int         `json:"slots_used"`
	Message   string      `json:"message"`
}

// FeedAnimal gasta uma frutinha do bolso para o animal comer (e virar amigo por um tempo,
// no cliente). Nunca há forma de machucar os animais.
//
// TODO(fase 3): conferir se o jogador está perto do animal.
func (s *Service) FeedAnimal(ctx context.Context, p *Player, id int64) (*FeedResult, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *FeedResult
	err := s.store.InTx(ctx, func(tx Store) error {
		a, err := s.animal(ctx, tx, id)
		if err != nil {
			return err
		}
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		if !has(inv, "berries") {
			return ErrMissingMaterials.with("Você não tem frutinhas no bolso.")
		}
		if err := consume(ctx, tx, p.ID, []StackView{{Item: "berries", Count: 1}}); err != nil {
			return err
		}
		if err := s.markFriend(ctx, tx, p, a.Species); err != nil {
			return err
		}
		inv, err = tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		name := s.content.Animals.Species[a.Species].Name
		res = &FeedResult{Species: a.Species, Message: fmt.Sprintf("%s comeu a frutinha e ficou seu amigo!", name)}
		res.Inventory, res.SlotsUsed = s.inventoryView(inv)
		return nil
	})
	return res, err
}

// markFriend guarda na Goblopédia que o jogador ficou amigo da espécie (fase 2.5, parte 4).
func (s *Service) markFriend(ctx context.Context, tx Store, p *Player, species string) error {
	return nil
}
