package game

import (
	"context"
	"fmt"
	"sort"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Goblopédia (fase 2.5): um álbum com uma página por espécie de animal e por coisa rara
// (flor azul, árvore de outono, árvore com neve). O progresso fica no servidor; as fotos,
// só no computador do jogador. O primeiro registro de cada coisa dá moedas uma vez só.

// PediaEntry é uma página da Goblopédia.
type PediaEntry struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Kind   string `json:"kind"` // animal, flower ou tree
	Model  string `json:"model"`
	Season string `json:"season,omitempty"`
}

// PediaEntries lista as páginas: os animais (por nome) e depois as coisas de goblopedia.json.
func (c *Content) PediaEntries() []PediaEntry {
	var out []PediaEntry
	for id, sp := range c.Animals.Species {
		out = append(out, PediaEntry{ID: id, Name: sp.Name, Kind: "animal", Model: sp.Model})
	}
	sort.Slice(out, func(a, b int) bool { return out[a].Name < out[b].Name })
	return append(out, c.Pedia.Extras...)
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
// TODO(fase 3): o servidor ainda não sabe se o animal estava mesmo na frente do jogador.
func (s *Service) RegisterPedia(ctx context.Context, p *Player, entry, country, biome string) (*PediaResult, error) {
	e := s.content.PediaEntry(entry)
	if e == nil {
		return nil, ErrNotFound.with("Isso não está na Goblopédia.")
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
		if res.Coins, err = s.grant(ctx, tx, p, res.Reward, "pedia", entry); err != nil {
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

// DevPedia completa ("complete": todas as páginas descobertas e amigos, sem moedas) ou
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
