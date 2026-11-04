package game

import (
	"context"
	"fmt"
	"sort"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Goblopédia (fase 2.5): um álbum com uma página por espécie de animal e por coisa rara
// (flor azul, árvore de outono, árvore com neve). O progresso fica no servidor; as fotos,
// só no computador do jogador. O primeiro registro de cada coisa dá gobolares uma vez só.

// PediaEntry é uma página da Goblopédia.
type PediaEntry struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Kind   string `json:"kind"` // animal, flower ou tree
	Model  string `json:"model"`
	Season string `json:"season,omitempty"`
	// Flores (fase 4.0): raridade e cor.
	Rarity string `json:"rarity,omitempty"`
	Color  string `json:"color,omitempty"`
	// Fase 4.5: lendas (kind legend) com o país e a historinha; cavernas (kind cave).
	Country string `json:"country,omitempty"`
	Story   string `json:"story,omitempty"`
}

// PediaEntries lista as páginas: os animais (por nome) e depois as coisas de goblopedia.json.
func (c *Content) PediaEntries() []PediaEntry {
	var out []PediaEntry
	for id, sp := range c.Animals.Species {
		out = append(out, PediaEntry{ID: id, Name: sp.Name, Kind: "animal", Model: sp.Model})
	}
	sort.Slice(out, func(a, b int) bool { return out[a].Name < out[b].Name })
	// Flores (fase 4.0): todo item com a tag flower vira página, em ordem de nome.
	var flowers []PediaEntry
	for _, it := range c.Items {
		if it.HasTag("flower") {
			flowers = append(flowers, PediaEntry{ID: it.ID, Name: it.Name, Kind: "flower", Model: it.Model, Rarity: it.Rarity, Color: it.Color})
		}
	}
	sort.Slice(flowers, func(a, b int) bool { return flowers[a].Name < flowers[b].Name })
	out = append(out, flowers...)
	out = append(out, c.Pedia.Extras...)
	// Fase 4.5: o que brilha nas cavernas, o chefe e as lendas.
	for _, g := range c.Caves.Glow {
		out = append(out, PediaEntry{ID: g.ID, Name: g.Name, Kind: "cave", Model: "cave:" + g.ID, Color: g.Color})
	}
	out = append(out, PediaEntry{ID: c.Caves.Boss.ID, Name: c.Caves.Boss.Name, Kind: "cave", Model: "creature:" + c.Caves.Boss.ID})
	for _, l := range c.Folklore.Legends {
		out = append(out, PediaEntry{ID: l.ID, Name: l.Name, Kind: "legend", Model: "creature:" + l.ID, Country: l.Country, Story: l.Story})
	}
	return out
}

// PediaEntry devolve a página pelo id (nil se não existe).
func (c *Content) PediaEntry(id string) *PediaEntry {
	for _, e := range c.PediaEntries() {
		if e.ID == id {
			return &e
		}
	}
	return nil
}

// PediaView é uma página com o progresso do jogador.
type PediaView struct {
	PediaEntry
	Discovered  bool   `json:"discovered"`
	FirstAt     int64  `json:"first_at"` // unix da primeira foto (0 = ainda não)
	Country     string `json:"country"`
	CountryName string `json:"country_name"`
	Biome       string `json:"biome"`
	Sightings   int    `json:"sightings"`
	Friend      bool   `json:"friend"`
}

// SetGeography liga os países pela posição exata (nomes de países sem hexágono, capitais
// dos aeroportos). Sem ela, só os países com hexágono existem.
func (s *Service) SetGeography(g *world.Geography) {
	s.geo = g
	s.buildAirports()
}

// CountryName é o nome do país (com ou sem hexágono).
func (s *Service) CountryName(code string) string {
	if n, ok := s.world.Countries[code]; ok {
		return n
	}
	if s.geo != nil {
		return s.geo.CountryName(code)
	}
	return ""
}

// Pedia devolve todas as páginas com o progresso do jogador.
func (s *Service) Pedia(ctx context.Context, p *Player) ([]PediaView, error) {
	return s.pediaView(ctx, s.store, p)
}

func (s *Service) pediaView(ctx context.Context, st Store, p *Player) ([]PediaView, error) {
	recs, err := st.Pedia(ctx, p.ID)
	if err != nil {
		return nil, err
	}
	by := map[string]PediaRecord{}
	for _, r := range recs {
		by[r.Entry] = r
	}
	entries := s.content.PediaEntries()
	out := make([]PediaView, len(entries))
	for i, e := range entries {
		v := PediaView{PediaEntry: e}
		if r, ok := by[e.ID]; ok {
			v.Discovered = !r.FirstAt.IsZero()
			if v.Discovered {
				v.FirstAt = r.FirstAt.Unix()
			}
			v.Country, v.Biome, v.Sightings, v.Friend = r.Country, r.Biome, r.Sightings, r.Friend
			v.CountryName = s.CountryName(r.Country)
		}
		out[i] = v
	}
	return out, nil
}

// PhotoShot é a câmera no momento da foto (fase 4.2): a direção (Look), a posição (Cam) e o
// ponto da coisa enquadrada (At). Zero = não mandou.
type PhotoShot struct {
	Look world.Vec3
	Cam  world.Vec3
	At   world.Vec3
}

// FlowerGrows diz se a flor `item` nasce no bioma (objects.json) em alguma das estações (as
// regras sem estação valem sempre). Fase 4.2: as flores decorativas do cliente registram na
// Goblopédia pela espécie que cresce ali.
func (c *Content) FlowerGrows(biome, item string, seasons []string) bool {
	for _, r := range c.Objects[biome] {
		if r.Kind != KindFlower || !slicesContains(r.flowerItems(), item) {
			continue
		}
		if len(r.Seasons) == 0 {
			return true
		}
		for _, se := range seasons {
			if slicesContains(r.Seasons, se) {
				return true
			}
		}
	}
	return false
}

// flowerItems: os itens que uma regra de flor dá (flower_<cor> e a cor rara).
func (r *ObjectRule) flowerItems() []string {
	var out []string
	for _, c := range r.Colors {
		out = append(out, "flower_"+c)
	}
	if r.RareColor != "" {
		out = append(out, "flower_"+r.RareColor)
	}
	return out
}

// FlowerBiomes: bioma → flor → estações em que nasce ("" = sempre). Vai no /content para o
// cliente saber quais flores decorativas registram na Goblopédia.
func (c *Content) FlowerBiomes() map[string]map[string][]string {
	out := map[string]map[string][]string{}
	for biome, rules := range c.Objects {
		for _, r := range rules {
			if r.Kind != KindFlower {
				continue
			}
			for _, it := range r.flowerItems() {
				if out[biome] == nil {
					out[biome] = map[string][]string{}
				}
				se := r.Seasons
				if len(se) == 0 {
					se = []string{""}
				}
				for _, x := range se {
					if !slicesContains(out[biome][it], x) {
						out[biome][it] = append(out[biome][it], x)
					}
				}
			}
		}
	}
	return out
}

// PediaResult é a resposta de registrar uma foto.
type PediaResult struct {
	Entry     string `json:"entry"`
	First     bool   `json:"first"`
	Reward    int64  `json:"reward"`
	Coins     int64  `json:"coins"`
	Sightings int    `json:"sightings"`
	Message   string `json:"message"`
}

// RegisterPedia registra uma foto de `entry`, tirada em `country` (posição exata) e
// `biome`. Na primeira foto, guarda onde foi e paga a recompensa (uma vez só).
//
// Com o tempo real ligado, a distância é conferida no servidor (ADR 0040).
//
// shot é a câmera no momento da foto (direção, posição e o ponto enquadrado; zero = não
// confere). Com a camada em tempo real ligada, o servidor confere se a coisa estava perto e
// centralizada (ADR 0040, 0053).
func (s *Service) RegisterPedia(ctx context.Context, p *Player, entry, country, biome string, shot PhotoShot) (*PediaResult, error) {
	e := s.content.PediaEntry(entry)
	if e == nil {
		return nil, ErrNotFound.with("Isso não está na Goblopédia.")
	}
	if err := s.pediaSeen(ctx, p, e, shot); err != nil {
		return nil, err
	}
	if s.CountryName(country) == "" {
		country = ""
	}
	if !validBiome(biome) {
		biome = ""
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *PediaResult
	err := s.store.InTx(ctx, func(tx Store) error {
		first, err := tx.PediaSighting(ctx, p.ID, entry, country, biome, s.clock.Now())
		if err != nil {
			return err
		}
		res = &PediaResult{Entry: entry, First: first}
		if first {
			res.Reward = s.content.Economy.Rewards.PediaFirst
			res.Message = fmt.Sprintf("Novo na Goblopédia: %s!", e.Name)
		} else {
			res.Message = fmt.Sprintf("%s de novo na Goblopédia.", e.Name)
		}
		if res.Coins, err = s.grant(ctx, tx, p, res.Reward, "pedia", entry, country); err != nil {
			return err
		}
		recs, err := tx.Pedia(ctx, p.ID)
		for _, r := range recs {
			if r.Entry == entry {
				res.Sightings = r.Sightings
			}
		}
		return err
	})
	return res, err
}

func validBiome(b string) bool {
	for _, n := range world.BiomeNames {
		if n == b {
			return true
		}
	}
	return false
}

// markFriend guarda na Goblopédia que o jogador ficou amigo da espécie.
func (s *Service) markFriend(ctx context.Context, tx Store, p *Player, species string) error {
	return tx.PediaFriend(ctx, p.ID, species)
}

// DevPedia completa ("complete": todas as páginas descobertas e amigos, sem gobolares) ou
// zera ("reset") a Goblopédia do jogador.
func (s *Service) DevPedia(ctx context.Context, p *Player, action string) ([]PediaView, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []PediaView
	err := s.store.InTx(ctx, func(tx Store) error {
		switch action {
		case "reset":
			if err := tx.ClearPedia(ctx, p.ID); err != nil {
				return err
			}
		case "complete":
			for _, e := range s.content.PediaEntries() {
				if _, err := tx.PediaSighting(ctx, p.ID, e.ID, p.Country, "", s.clock.Now()); err != nil {
					return err
				}
				if e.Kind == "animal" {
					if err := tx.PediaFriend(ctx, p.ID, e.ID); err != nil {
						return err
					}
				}
			}
		default:
			return ErrInvalid.with("Use complete ou reset.")
		}
		var err error
		out, err = s.pediaView(ctx, tx, p)
		return err
	})
	return out, err
}
