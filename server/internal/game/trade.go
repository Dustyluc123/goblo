package game

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
)

// Troca entre jogadores (fase 3.5, ADR 0044). A negociação (quem oferece o quê, "pronto",
// confirmação) acontece na camada em tempo real; aqui fica a execução: atômica (tudo ou
// nada), conferindo itens, gobolares, espaço no bolso, distância e bloqueio.

// TradeOffer é o lado de um jogador: itens e gobolares.
type TradeOffer struct {
	Items []StackView `json:"items"`
	Coins int64       `json:"coins"`
}

// TradeSide é como cada um fica depois da troca.
type TradeSide struct {
	Inventory []StackView `json:"inventory"`
	SlotsUsed int         `json:"slots_used"`
	Coins     int64       `json:"coins"`
}

// TradeResult é o resultado da troca para os dois.
type TradeResult struct {
	A, B    TradeSide
	Message string
}

var (
	ErrBlocked   = &Error{"blocked", 403, "Vocês não podem trocar (bloqueio).", nil}
	ErrTradeFull = &Error{"trade_full", 409, "Não cabe no bolso.", nil}
)

// CheckOffer confere se o jogador tem o que oferece (antes de mostrar ao outro lado).
func (s *Service) CheckOffer(ctx context.Context, p *Player, o TradeOffer) error {
	if err := s.validOffer(o); err != nil {
		return err
	}
	inv, err := s.store.Inventory(ctx, p.ID)
	if err != nil {
		return err
	}
	coins, err := s.store.Coins(ctx, p.ID)
	if err != nil {
		return err
	}
	return s.hasOffer(inv, coins, o)
}

func (s *Service) validOffer(o TradeOffer) error {
	if o.Coins < 0 || o.Coins > 1_000_000 || len(o.Items) > InventorySlots {
		return ErrInvalid
	}
	seen := map[string]bool{}
	for _, it := range o.Items {
		if it.Count <= 0 || it.Count > 9999 || s.content.Item(it.Item) == nil || seen[it.Item] {
			return ErrInvalid.with("Oferta inválida.")
		}
		seen[it.Item] = true
	}
	return nil
}

func (s *Service) hasOffer(inv []Stack, coins int64, o TradeOffer) error {
	have := map[string]int{}
	for _, st := range inv {
		have[st.Item] = st.Count
	}
	for _, it := range o.Items {
		if have[it.Item] < it.Count {
			return ErrMissingMaterials.with("Você não tem %d× %s.", it.Count, s.itemName(it.Item))
		}
	}
	if coins < o.Coins {
		return ErrNoCoins.with("Você não tem %s.", s.CoinsText(o.Coins))
	}
	return nil
}

// ExecuteTrade troca o que a oferece pelo que b oferece, de uma vez: se qualquer coisa
// falhar (alguém não tem mais o item, não cabe no bolso, estão longe, bloqueio), nada muda.
func (s *Service) ExecuteTrade(ctx context.Context, a, b *Player, oa, ob TradeOffer) (*TradeResult, error) {
	if a.ID == b.ID {
		return nil, ErrInvalid
	}
	if err := s.validOffer(oa); err != nil {
		return nil, err
	}
	if err := s.validOffer(ob); err != nil {
		return nil, err
	}
	if len(oa.Items) == 0 && len(ob.Items) == 0 && oa.Coins == 0 && ob.Coins == 0 {
		return nil, ErrInvalid.with("A troca está vazia.")
	}
	blocked, blockedBy, err := s.store.Blocks(ctx, a.ID)
	if err != nil {
		return nil, err
	}
	if slices.Contains(blocked, b.ID) || slices.Contains(blockedBy, b.ID) {
		return nil, ErrBlocked
	}
	// Perto um do outro (com o tempo real ligado).
	if s.presence != nil {
		pa, _, _, okA := s.presence.Where(a.ID)
		pb, _, _, okB := s.presence.Where(b.ID)
		if !okA || !okB {
			return nil, ErrOffline
		}
		if s.groundDistance(pa, pb) > s.content.Rules.Reach.Trade {
			return nil, ErrTooFar.with("Vocês precisam estar perto para trocar.")
		}
	}
	country := s.hereCountry(a)
	s.mu.Lock()
	defer s.mu.Unlock()
	res := &TradeResult{}
	err = s.store.InTx(ctx, func(tx Store) error {
		invA, err := tx.Inventory(ctx, a.ID)
		if err != nil {
			return err
		}
		invB, err := tx.Inventory(ctx, b.ID)
		if err != nil {
			return err
		}
		coinsA, err := tx.Coins(ctx, a.ID)
		if err != nil {
			return err
		}
		coinsB, err := tx.Coins(ctx, b.ID)
		if err != nil {
			return err
		}
		if err := s.hasOffer(invA, coinsA, oa); err != nil {
			return fmt.Errorf("%s: %w", a.Nickname, err)
		}
		if err := s.hasOffer(invB, coinsB, ob); err != nil {
			return fmt.Errorf("%s: %w", b.Nickname, err)
		}
		afterA := applyDelta(applyDelta(invA, oa.Items, -1), ob.Items, 1)
		afterB := applyDelta(applyDelta(invB, ob.Items, -1), oa.Items, 1)
		if s.slotsUsed(afterA) > InventorySlots {
			return ErrTradeFull.with("Não cabe no bolso de %s.", a.Nickname)
		}
		if s.slotsUsed(afterB) > InventorySlots {
			return ErrTradeFull.with("Não cabe no bolso de %s.", b.Nickname)
		}
		if err := consume(ctx, tx, a.ID, oa.Items); err != nil {
			return err
		}
		if err := consume(ctx, tx, b.ID, ob.Items); err != nil {
			return err
		}
		for _, it := range ob.Items {
			if err := tx.AddItem(ctx, a.ID, it.Item, it.Count); err != nil {
				return err
			}
		}
		for _, it := range oa.Items {
			if err := tx.AddItem(ctx, b.ID, it.Item, it.Count); err != nil {
				return err
			}
		}
		refA := fmt.Sprintf("com %s: %s", b.Nickname, offerText(oa, ob))
		refB := fmt.Sprintf("com %s: %s", a.Nickname, offerText(ob, oa))
		if d := ob.Coins - oa.Coins; d != 0 {
			if _, err := s.pay(ctx, tx, a, d, "trade", refA, Quote{Country: country}); err != nil {
				return err
			}
			if _, err := s.pay(ctx, tx, b, -d, "trade", refB, Quote{Country: country}); err != nil {
				return err
			}
		}
		for i, side := range []*TradeSide{&res.A, &res.B} {
			id := []int64{a.ID, b.ID}[i]
			inv, err := tx.Inventory(ctx, id)
			if err != nil {
				return err
			}
			side.Inventory, side.SlotsUsed = s.inventoryView(inv)
			if side.Coins, err = tx.Coins(ctx, id); err != nil {
				return err
			}
		}
		res.Message = "Troca feita!"
		return nil
	})
	if err != nil {
		var ge *Error
		if !errors.As(err, &ge) {
			// Erro de regra com o apelido na frente: mantém o código do erro original.
			for _, e := range []*Error{ErrMissingMaterials, ErrNoCoins} {
				if errors.Is(err, e) {
					return nil, e.with("%s", err.Error())
				}
			}
		}
		return nil, err
	}
	return res, nil
}

// offerText: "3× Madeira por 10 G$" (para o histórico).
func offerText(give, get TradeOffer) string {
	part := func(o TradeOffer) string {
		var p []string
		for _, it := range o.Items {
			p = append(p, fmt.Sprintf("%s×%d", it.Item, it.Count))
		}
		if o.Coins > 0 {
			p = append(p, fmt.Sprintf("G$%d", o.Coins))
		}
		if len(p) == 0 {
			return "nada"
		}
		return strings.Join(p, ",")
	}
	return part(give) + " por " + part(get)
}

// DevCreateBot cria um jogador falso sem lote, com alguns itens e gobolares, para os bots
// do modo dev (que podem trocar de verdade).
func (s *Service) DevCreateBot(ctx context.Context, nick, country, character string) (*Player, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var p *Player
	err := s.store.InTx(ctx, func(tx Store) error {
		for try := 0; ; try++ {
			n := nick
			if try > 0 {
				n = fmt.Sprintf("%s %d", nick, try)
			}
			p = &Player{Nickname: n, Country: country, Character: character, TokenHash: HashToken(newToken()), CreatedAt: s.clock.Now().UTC(), Fake: true}
			err := tx.CreatePlayer(ctx, p)
			if err == nil {
				break
			}
			if !errors.Is(err, ErrNicknameTaken) || try > 20 {
				return err
			}
		}
		for item, n := range map[string]int{"wood": 12, "stone": 8, "flower_red": 4, "berries": 5, "seeds": 3} {
			if err := tx.AddItem(ctx, p.ID, item, n); err != nil {
				return err
			}
		}
		_, err := s.grant(ctx, tx, p, 80, "dev", "bot", country)
		return err
	})
	return p, err
}

// DevDeleteBot apaga um jogador falso criado para os bots.
func (s *Service) DevDeleteBot(ctx context.Context, id int64) error {
	p, err := s.store.PlayerByID(ctx, id)
	if err != nil || !p.Fake {
		return err
	}
	return s.store.DeletePlayer(ctx, id)
}

// InventoryOf devolve o bolso e o saldo de um jogador (bots do modo dev).
func (s *Service) InventoryOf(ctx context.Context, id int64) ([]StackView, int64, error) {
	inv, err := s.store.Inventory(ctx, id)
	if err != nil {
		return nil, 0, err
	}
	coins, err := s.store.Coins(ctx, id)
	view, _ := s.inventoryView(inv)
	return view, coins, err
}
