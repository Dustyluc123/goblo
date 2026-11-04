package game

import (
	"context"
	"fmt"
	"regexp"
	"sort"
)

// Roupas, tinta, visual do personagem e capa de bandeiras (fase 4.0, ADR 0051). Cada espaço
// (cabeça, corpo, pernas, pés e costas) tem uma peça; vestir outra devolve a antiga ao bolso.
// A tinta (feita de flores) muda a cor de uma peça vestida. O visual (partes dos personagens,
// pele e acessório) e as roupas ficam no servidor e vão para todo mundo.

// WearInfo é items.json → wear.
type WearInfo struct {
	Slot   string   `json:"slot"`
	Cold   float64  `json:"cold"`
	Heat   float64  `json:"heat"`
	Color  string   `json:"color"`
	Colors []string `json:"colors"`
}

// Worn é uma peça vestida.
type Worn struct {
	Item  string `json:"item"`
	Color string `json:"color"`
}

// Look é o visual do personagem (editor). A cabeça é uma das 12 cabeças originais, com o
// cabelo dela (fase 4.2, ADR 0053: sem cabelo, cor do cabelo e penteado separados).
type Look struct {
	Head      string `json:"head"`
	Body      string `json:"body"`
	Legs      string `json:"legs"`
	Skin      string `json:"skin"`
	Accessory string `json:"accessory"`
}

// LookOptions é body.json → look.
type LookOptions struct {
	Parts       []string `json:"parts"`
	Skins       []string `json:"skins"`
	Accessories []string `json:"accessories"`
}

var hexColor = regexp.MustCompile(`^#[0-9a-fA-F]{6}$`)

func (o *LookOptions) check() error {
	if len(o.Parts) == 0 || len(o.Accessories) == 0 {
		return fmt.Errorf("body.json: look sem opções")
	}
	for _, c := range o.Skins {
		if c != "" && !hexColor.MatchString(c) {
			return fmt.Errorf("body.json: cor %q inválida", c)
		}
	}
	return nil
}

func (c *Content) checkWear() error {
	slots := map[string]bool{}
	for _, s := range c.Body.WearSlots {
		slots[s] = true
	}
	for _, it := range c.Items {
		if it.Category == CategoryWear {
			if it.Wear == nil || !slots[it.Wear.Slot] {
				return fmt.Errorf("item %s: roupa sem espaço válido", it.ID)
			}
			for _, col := range append([]string{it.Wear.Color}, it.Wear.Colors...) {
				if !hexColor.MatchString(col) {
					return fmt.Errorf("item %s: cor %q inválida", it.ID, col)
				}
			}
		}
		if it.HasTag("paint") && !hexColor.MatchString(it.Color) {
			return fmt.Errorf("tinta %s sem cor", it.ID)
		}
	}
	return nil
}

// defaultLook: o visual a partir do personagem escolhido antes do editor (as três partes
// do mesmo personagem, cores originais).
func (s *Service) defaultLook(p *Player) Look {
	part := s.content.Body.Look.Parts[0]
	if len(p.Character) > len("character-") {
		cand := p.Character[len("character-"):]
		if slicesContains(s.content.Body.Look.Parts, cand) {
			part = cand
		}
	}
	return Look{Head: part, Body: part, Legs: part, Accessory: "none"}
}

func (s *Service) validLook(l Look) error {
	o := s.content.Body.Look
	for _, part := range []string{l.Head, l.Body, l.Legs} {
		if !slicesContains(o.Parts, part) {
			return ErrInvalid.with("Parte %q desconhecida.", part)
		}
	}
	if !slicesContains(o.Skins, l.Skin) {
		return ErrInvalid.with("Cor desconhecida.")
	}
	if !slicesContains(o.Accessories, l.Accessory) {
		return ErrInvalid.with("Acessório desconhecido.")
	}
	return nil
}

// LookView é o que os outros veem: visual, roupas e, com a capa, os países visitados.
type LookView struct {
	Look Look            `json:"look"`
	Wear map[string]Worn `json:"wear"`
	Cape []string        `json:"cape,omitempty"` // carimbos, na ordem em que foram ganhos
}

// lookLocked monta o LookView (corpo já carregado). Os carimbos vêm do banco.
func (s *Service) lookOf(ctx context.Context, st Store, p *Player, b *bodyState) (*LookView, error) {
	v := &LookView{Look: b.Look, Wear: map[string]Worn{}}
	if v.Look.Head == "" {
		v.Look = s.defaultLook(p)
	}
	for k, w := range b.Wear {
		v.Wear[k] = w
	}
	if w, ok := b.Wear["back"]; ok && w.Item == "flag_cape" {
		stamps, err := st.Stamps(ctx, p.ID)
		if err != nil {
			return nil, err
		}
		sort.Slice(stamps, func(i, j int) bool { return stamps[i].FirstAt.Before(stamps[j].FirstAt) })
		for _, st := range stamps {
			v.Cape = append(v.Cape, st.Country)
		}
	}
	return v, nil
}

// LookOf devolve o visual de um jogador (para a camada em tempo real e GET /look).
func (s *Service) LookOf(ctx context.Context, p *Player) (*LookView, error) {
	s.body.mu.Lock()
	b, err := s.bodyLocked(ctx, p.ID)
	if err != nil {
		s.body.mu.Unlock()
		return nil, err
	}
	rec := b.bodyRecord
	s.body.mu.Unlock()
	return s.lookOf(ctx, s.store, p, &bodyState{bodyRecord: rec})
}

// WearResult é a resposta das ações de roupa.
type WearResult struct {
	Look      LookView    `json:"look"`
	Body      BodyView    `json:"body"`
	Inventory []StackView `json:"inventory"`
	SlotsUsed int         `json:"slots_used"`
	Message   string      `json:"message"`
}

// changeBody roda fn com o corpo travado e grava o resultado: inventário, visual e eventos.
func (s *Service) changeWear(ctx context.Context, p *Player, fn func(tx Store, b *bodyState, inv []Stack) (string, error)) (*WearResult, error) {
	if err := s.ensureBody(ctx, p.ID); err != nil {
		return nil, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *WearResult
	err := s.store.InTx(ctx, func(tx Store) error {
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		s.body.mu.Lock()
		b, err := s.bodyLocked(ctx, p.ID)
		if err != nil {
			s.body.mu.Unlock()
			return err
		}
		before := b.bodyRecord
		before.Wear = copyWear(b.Wear)
		msg, err := fn(tx, b, inv)
		if err != nil {
			b.bodyRecord = before
			s.body.mu.Unlock()
			return err
		}
		b.dirty = true
		res = &WearResult{Body: s.bodyView(b), Message: msg}
		rec := b.bodyRecord
		s.body.mu.Unlock()
		lv, err := s.lookOf(ctx, tx, p, &bodyState{bodyRecord: rec})
		if err != nil {
			return err
		}
		res.Look = *lv
		inv, err = tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		res.Inventory, res.SlotsUsed = s.inventoryView(inv)
		return nil
	})
	if err != nil {
		return nil, err
	}
	if err := s.SaveBody(ctx, p.ID, false); err != nil {
		return nil, err
	}
	s.emit(Event{Kind: "look", Cell: -1, PlayerID: p.ID, Data: res.Look})
	return res, nil
}

func copyWear(m map[string]Worn) map[string]Worn {
	out := map[string]Worn{}
	for k, v := range m {
		out[k] = v
	}
	return out
}

// Wear veste uma roupa do bolso. A peça que estava no espaço volta para o bolso.
func (s *Service) Wear(ctx context.Context, p *Player, item string) (*WearResult, error) {
	it := s.content.Item(item)
	if it == nil || it.Wear == nil {
		return nil, ErrInvalid.with("Isso não é roupa.")
	}
	return s.changeWear(ctx, p, func(tx Store, b *bodyState, inv []Stack) (string, error) {
		if !has(inv, item) {
			return "", ErrMissingMaterials.with("Você não tem %s.", it.Name)
		}
		if err := tx.AddItem(ctx, p.ID, item, -1); err != nil {
			return "", err
		}
		if b.Wear == nil {
			b.Wear = map[string]Worn{}
		}
		msg := fmt.Sprintf("Você vestiu %s.", it.Name)
		if old, ok := b.Wear[it.Wear.Slot]; ok {
			if err := tx.AddItem(ctx, p.ID, old.Item, 1); err != nil {
				return "", err
			}
			msg = fmt.Sprintf("Você trocou %s por %s.", s.itemName(old.Item), it.Name)
		}
		b.Wear[it.Wear.Slot] = Worn{Item: item, Color: it.Wear.Color}
		return msg, nil
	})
}

// Unwear tira a peça de um espaço e guarda no bolso.
func (s *Service) Unwear(ctx context.Context, p *Player, slot string) (*WearResult, error) {
	return s.changeWear(ctx, p, func(tx Store, b *bodyState, inv []Stack) (string, error) {
		old, ok := b.Wear[slot]
		if !ok {
			return "", ErrNotFound.with("Não tem nada vestido aí.")
		}
		after := applyDelta(inv, []StackView{{Item: old.Item, Count: 1}}, 1)
		if s.slotsUsed(after) > InventorySlots {
			return "", ErrInventoryFull
		}
		if err := tx.AddItem(ctx, p.ID, old.Item, 1); err != nil {
			return "", err
		}
		delete(b.Wear, slot)
		return fmt.Sprintf("Você guardou %s no bolso.", s.itemName(old.Item)), nil
	})
}

// Dye pinta a peça vestida no espaço com uma tinta do bolso (gasta a tinta).
func (s *Service) Dye(ctx context.Context, p *Player, slot, paint string) (*WearResult, error) {
	pi := s.content.Item(paint)
	if pi == nil || !pi.HasTag("paint") {
		return nil, ErrInvalid.with("Isso não é tinta.")
	}
	return s.changeWear(ctx, p, func(tx Store, b *bodyState, inv []Stack) (string, error) {
		w, ok := b.Wear[slot]
		if !ok {
			return "", ErrNotFound.with("Vista uma peça nesse espaço antes de pintar.")
		}
		if !has(inv, paint) {
			return "", ErrMissingMaterials.with("Você não tem %s.", pi.Name)
		}
		if err := tx.AddItem(ctx, p.ID, paint, -1); err != nil {
			return "", err
		}
		w.Color = pi.Color
		b.Wear[slot] = w
		return fmt.Sprintf("%s ficou com a cor nova!", s.itemName(w.Item)), nil
	})
}

// SetLook guarda o visual do editor.
func (s *Service) SetLook(ctx context.Context, p *Player, l Look) (*WearResult, error) {
	if err := s.validLook(l); err != nil {
		return nil, err
	}
	return s.changeWear(ctx, p, func(tx Store, b *bodyState, inv []Stack) (string, error) {
		b.Look = l
		return "Visual salvo!", nil
	})
}

// DevWear (modo dev) dá todas as roupas (uma de cada) e as tintas.
func (s *Service) DevWear(ctx context.Context, p *Player) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.store.InTx(ctx, func(tx Store) error {
		for _, it := range s.content.Items {
			n := 0
			switch {
			case it.Category == CategoryWear:
				n = 1
			case it.HasTag("paint"):
				n = 2
			}
			if n > 0 {
				if err := tx.AddItem(ctx, p.ID, it.ID, n); err != nil {
					return err
				}
			}
		}
		return nil
	})
}

// DevRandomLook (modo dev) sorteia um visual com roupas para os bots: partes misturadas,
// cores e uma peça (com uma das cores da tinta) em cada espaço, quase sempre. Fica só na
// memória do hub (o bot não grava visual no banco).
func (s *Service) DevRandomLook(pick func(n int) int) *LookView {
	o := s.content.Body.Look
	one := func(list []string) string { return list[pick(len(list))] }
	v := &LookView{Look: Look{Head: one(o.Parts), Body: one(o.Parts), Legs: one(o.Parts), Skin: one(o.Skins),
		Accessory: one(o.Accessories)}, Wear: map[string]Worn{}}
	bySlot := map[string][]*Item{}
	for i := range s.content.Items {
		if it := &s.content.Items[i]; it.Category == CategoryWear && it.Wear != nil {
			bySlot[it.Wear.Slot] = append(bySlot[it.Wear.Slot], it)
		}
	}
	for _, slot := range s.content.Body.WearSlots {
		list := bySlot[slot]
		if len(list) == 0 || pick(4) == 0 {
			continue
		}
		it := list[pick(len(list))]
		col := it.Wear.Color
		if len(it.Wear.Colors) > 0 && pick(2) == 0 {
			col = it.Wear.Colors[pick(len(it.Wear.Colors))]
		}
		v.Wear[slot] = Worn{Item: it.ID, Color: col}
		if it.ID == "flag_cape" {
			v.Cape = []string{"BRA", "ARG", "JPN", "FRA"}
		}
	}
	return v
}
