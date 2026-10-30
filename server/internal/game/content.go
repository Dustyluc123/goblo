package game

import (
	"encoding/json"
	"fmt"
	"io/fs"
	"sort"
	"strings"
)

// Categorias de item.
const (
	CategoryMaterial  = "material"
	CategoryTool      = "tool"
	CategoryPlaceable = "placeable"
)

// Item é uma entrada de items.json. Model, Scale e Height são só para o cliente.
type Item struct {
	ID        string   `json:"id"`
	Name      string   `json:"name"`
	Category  string   `json:"category"`
	Stack     int      `json:"stack"`
	Tags      []string `json:"tags,omitempty"`
	Footprint [2]int   `json:"footprint,omitempty"`
	Model     string   `json:"model"`
	Scale     float64  `json:"scale"`
	Height    float64  `json:"height"`
	Light     bool     `json:"light,omitempty"`
}

// HasTag diz se o item pertence ao grupo (ex.: "flower").
func (it *Item) HasTag(tag string) bool {
	for _, t := range it.Tags {
		if t == tag {
			return true
		}
	}
	return false
}

// Recipe é uma receita da bancada. Ingredientes com "#" são grupos (tags).
type Recipe struct {
	ID          string         `json:"id"`
	Result      string         `json:"result"`
	Count       int            `json:"count"`
	Ingredients map[string]int `json:"ingredients"`
}

// HouseLevel é um nível da casa.
type HouseLevel struct {
	Level     int            `json:"level"`
	Name      string         `json:"name"`
	Cost      map[string]int `json:"cost"`
	Footprint [2]int         `json:"footprint"`
	Scene     string         `json:"scene"`
}

// ObjectRule descreve um tipo de objeto gerado num bioma (objects.json).
type ObjectRule struct {
	Kind      string     `json:"kind"`
	Models    []string   `json:"models"`
	Autumn    []string   `json:"autumn,omitempty"`
	PerCell   float64    `json:"per_cell"`
	Scale     [2]float64 `json:"scale"`
	Spacing   float64    `json:"spacing"`
	Drop      string     `json:"drop,omitempty"`
	Chop      bool       `json:"chop,omitempty"`
	NearWater bool       `json:"near_water,omitempty"`
	Colors    []string   `json:"colors,omitempty"`
	RareColor string     `json:"rare_color,omitempty"`
	RareP     float64    `json:"rare_chance,omitempty"`
	Solid     bool       `json:"solid,omitempty"`
}

// Economy são os números do dinheiro (economy.json).
type Economy struct {
	Currency struct {
		Singular string `json:"singular"`
		Plural   string `json:"plural"`
	} `json:"currency"`
	StartingCoins int64            `json:"starting_coins"`
	SellPrices    map[string]int64 `json:"sell_prices"`
	Rewards       struct {
		PediaFirst int64 `json:"pedia_first"`
		StampFirst int64 `json:"stamp_first"`
	} `json:"rewards"`
	Travel struct {
		Base     float64 `json:"base"`
		Per1000K float64 `json:"per_1000_km"`
		Min      int64   `json:"min"`
	} `json:"travel"`
	Passport struct {
		Default   int64            `json:"default"`
		Countries map[string]int64 `json:"countries"`
	} `json:"passport"`
}

// Content é todo o conteúdo balanceável do jogo, lido de server/data/game.
type Content struct {
	Items   []Item                  `json:"items"`
	Recipes []Recipe                `json:"recipes"`
	Houses  []HouseLevel            `json:"houses"`
	Objects map[string][]ObjectRule `json:"-"`
	Economy Economy                 `json:"-"`
	Animals *AnimalContent          `json:"-"`
	Rules   Rules                   `json:"-"`
	Pedia   struct {
		Extras []PediaEntry `json:"extras"`
	} `json:"-"`

	items   map[string]*Item
	recipes map[string]*Recipe
}

// Tipos de objeto interativo.
const (
	KindTree   = "tree"
	KindRock   = "rock"
	KindFlower = "flower"
	KindPebble = "pebble"
	KindBranch = "branch"
	KindBush   = "bush"
	KindDecor  = "decor"
)

// LoadContent lê items.json, recipes.json, houses.json e objects.json de fsys
// (normalmente data.Game, com os arquivos em game/) e confere se tudo se refere a
// itens que existem.
func LoadContent(fsys fs.FS) (*Content, error) {
	c := &Content{}
	var items struct {
		Items []Item `json:"items"`
	}
	var recipes struct {
		Recipes []Recipe `json:"recipes"`
	}
	var houses struct {
		Levels []HouseLevel `json:"levels"`
	}
	var objects struct {
		Biomes map[string][]ObjectRule `json:"biomes"`
	}
	for _, f := range []struct {
		name string
		dst  any
	}{
		{"game/items.json", &items}, {"game/recipes.json", &recipes},
		{"game/houses.json", &houses}, {"game/objects.json", &objects},
		{"game/economy.json", &c.Economy}, {"game/animals.json", &c.Animals},
		{"game/goblopedia.json", &c.Pedia}, {"game/rules.json", &c.Rules},
	} {
		b, err := fs.ReadFile(fsys, f.name)
		if err != nil {
			return nil, err
		}
		if err := json.Unmarshal(b, f.dst); err != nil {
			return nil, fmt.Errorf("%s: %w", f.name, err)
		}
	}
	c.Items, c.Recipes, c.Houses, c.Objects = items.Items, recipes.Recipes, houses.Levels, objects.Biomes
	return c, c.index()
}

func (c *Content) index() error {
	c.items = map[string]*Item{}
	for i := range c.Items {
		it := &c.Items[i]
		if it.Stack <= 0 {
			return fmt.Errorf("item %s: stack precisa ser > 0", it.ID)
		}
		if it.Category == CategoryPlaceable && (it.Footprint[0] <= 0 || it.Footprint[1] <= 0) {
			return fmt.Errorf("item %s: colocável sem footprint", it.ID)
		}
		if _, dup := c.items[it.ID]; dup {
			return fmt.Errorf("item %s repetido", it.ID)
		}
		c.items[it.ID] = it
	}
	c.recipes = map[string]*Recipe{}
	for i := range c.Recipes {
		r := &c.Recipes[i]
		if c.items[r.Result] == nil || r.Count <= 0 {
			return fmt.Errorf("receita %s: resultado inválido", r.ID)
		}
		if err := c.checkCost(r.Ingredients); err != nil {
			return fmt.Errorf("receita %s: %w", r.ID, err)
		}
		c.recipes[r.ID] = r
	}
	for i, h := range c.Houses {
		if h.Level != i+1 {
			return fmt.Errorf("casa: níveis precisam ser 1, 2, 3… em ordem")
		}
		if err := c.checkCost(h.Cost); err != nil {
			return fmt.Errorf("casa nível %d: %w", h.Level, err)
		}
		if h.Footprint[0] > LotTiles || h.Footprint[1] > LotTiles {
			return fmt.Errorf("casa nível %d: maior que o lote", h.Level)
		}
	}
	if err := c.Rules.check(); err != nil {
		return err
	}
	if c.Economy.Currency.Plural == "" || c.Economy.Passport.Default <= 0 || c.Economy.Travel.Min <= 0 {
		return fmt.Errorf("economy.json: moeda, passaporte e passagem mínima são obrigatórios")
	}
	for id, price := range c.Economy.SellPrices {
		if c.items[id] == nil || price <= 0 {
			return fmt.Errorf("economy.json: preço de venda inválido para %s", id)
		}
	}
	if c.Animals == nil || len(c.Animals.Species) == 0 {
		return fmt.Errorf("animals.json: sem espécies")
	}
	for id, sp := range c.Animals.Species {
		if sp.Walk <= 0 || sp.Run <= 0 || sp.Roam <= 0 || sp.Leg <= 0 || sp.Height <= 0 || sp.Model == "" {
			return fmt.Errorf("animals.json: espécie %s com números inválidos", id)
		}
	}
	for biome, rules := range c.Animals.Biomes {
		for _, r := range rules {
			if len(r.Species) == 0 || r.Group[0] < 1 || r.Group[1] < r.Group[0] {
				return fmt.Errorf("animals.json: grupo de %s inválido", biome)
			}
			for _, sp := range r.Species {
				if _, ok := c.Animals.Species[sp]; !ok {
					return fmt.Errorf("animals.json: %s usa a espécie %s, que não existe", biome, sp)
				}
			}
		}
	}
	for _, sp := range c.Animals.Neighborhood.Species {
		if _, ok := c.Animals.Species[sp]; !ok {
			return fmt.Errorf("animals.json: bairro usa a espécie %s, que não existe", sp)
		}
	}
	for biome, rules := range c.Objects {
		for _, r := range rules {
			if len(r.Models) == 0 || r.Spacing <= 0 {
				return fmt.Errorf("objetos de %s: %s sem modelos ou sem spacing", biome, r.Kind)
			}
			if r.Kind == KindFlower {
				if r.RareColor != "" && c.items["flower_"+r.RareColor] == nil {
					return fmt.Errorf("objetos de %s: flor rara %s sem item", biome, r.RareColor)
				}
				for _, col := range r.Colors {
					if c.items["flower_"+col] == nil {
						return fmt.Errorf("objetos de %s: flor %s sem item", biome, col)
					}
				}
			}
		}
	}
	return nil
}

func (c *Content) checkCost(cost map[string]int) error {
	for id, n := range cost {
		if n <= 0 {
			return fmt.Errorf("quantidade inválida de %s", id)
		}
		if strings.HasPrefix(id, "#") {
			if len(c.itemsWithTag(id[1:])) == 0 {
				return fmt.Errorf("nenhum item com a tag %s", id)
			}
		} else if c.items[id] == nil {
			return fmt.Errorf("item %s não existe", id)
		}
	}
	return nil
}

// SellPrice é quanto a caixa de vendas paga por uma unidade (0 = não vende).
func (c *Content) SellPrice(item string) int64 { return c.Economy.SellPrices[item] }

// PassportPrice é o preço do passaporte de um país.
func (c *Content) PassportPrice(country string) int64 {
	if p, ok := c.Economy.Passport.Countries[country]; ok {
		return p
	}
	return c.Economy.Passport.Default
}

// Item devolve o item pelo id (nil se não existe).
func (c *Content) Item(id string) *Item { return c.items[id] }

// Recipe devolve a receita pelo id (nil se não existe).
func (c *Content) Recipe(id string) *Recipe { return c.recipes[id] }

// House devolve o nível da casa (nil se não existe).
func (c *Content) House(level int) *HouseLevel {
	if level < 1 || level > len(c.Houses) {
		return nil
	}
	return &c.Houses[level-1]
}

// ObjectModels lista, sem repetição e em ordem, os modelos usados pelos objetos do mundo
// (sem as versões de outono, que ainda não aparecem). O cliente pré-carrega esses modelos.
func (c *Content) ObjectModels() []string {
	seen := map[string]bool{}
	var out []string
	for _, rules := range c.Objects {
		for _, r := range rules {
			for _, m := range r.Models {
				if !seen[m] {
					seen[m] = true
					out = append(out, m)
				}
			}
		}
	}
	sort.Strings(out)
	return out
}

func (c *Content) itemsWithTag(tag string) []string {
	var out []string
	for _, it := range c.Items {
		if it.HasTag(tag) {
			out = append(out, it.ID)
		}
	}
	sort.Strings(out)
	return out
}
