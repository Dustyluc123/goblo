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
	Solid     bool       `json:"solid,omitempty"`
}

// Content é todo o conteúdo balanceável do jogo, lido de server/data/game.
type Content struct {
	Items   []Item                  `json:"items"`
	Recipes []Recipe                `json:"recipes"`
	Houses  []HouseLevel            `json:"houses"`
	Objects map[string][]ObjectRule `json:"-"`

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
	for biome, rules := range c.Objects {
		for _, r := range rules {
			if len(r.Models) == 0 || r.Spacing <= 0 {
				return fmt.Errorf("objetos de %s: %s sem modelos ou sem spacing", biome, r.Kind)
			}
			if r.Kind == KindFlower {
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
