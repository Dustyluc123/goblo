package game

import (
	"context"
	"fmt"
	"sort"
	"strings"
)

// Dinheiro (fase 2.5, versão inicial). O saldo fica no servidor; cada mudança vai para o
// histórico (transactions). Ganha-se vendendo na caixa de vendas e com recompensas
// (primeiro registro na Goblopédia, primeiro carimbo de cada país); gasta-se em passagens
// e passaportes. Números em economy.json.

// Onde fica a caixa de vendas num lote novo (ao lado da bancada).
const sellBoxX, sellBoxY = 8, 1

// CoinsText escreve "1 moeda" ou "12 moedas" com o nome de economy.json.
func (s *Service) CoinsText(n int64) string {
	e := s.content.Economy.Currency
	if n == 1 || n == -1 {
		return fmt.Sprintf("%d %s", n, e.Singular)
	}
	return fmt.Sprintf("%d %s", n, e.Plural)
}

// grant credita (ou debita, com amount negativo) moedas dentro de uma transação.
func (s *Service) grant(ctx context.Context, tx Store, p *Player, amount int64, reason, ref string) (int64, error) {
	if amount == 0 {
		return tx.Coins(ctx, p.ID)
	}
	bal, err := tx.AddCoins(ctx, p.ID, amount, reason, ref, s.clock.Now())
	if err != nil && ErrNoCoins.Is(err) {
		have, _ := tx.Coins(ctx, p.ID)
		return 0, ErrNoCoins.with("Faltam %s (você tem %s).", s.CoinsText(-amount-have), s.CoinsText(have))
	}
	return bal, err
}

// SellResult é a resposta da caixa de vendas.
type SellResult struct {
	Sold      []StackView `json:"sold"`
	Earned    int64       `json:"earned"`
	Coins     int64       `json:"coins"`
	Inventory []StackView `json:"inventory"`
	SlotsUsed int         `json:"slots_used"`
	Message   string      `json:"message"`
}

// Sell vende itens do inventário na caixa de vendas e paga na hora.
//
// TODO(fase 3): conferir se o jogador está perto de uma caixa de vendas (hoje só o cliente
// confere, como na bancada).
func (s *Service) Sell(ctx context.Context, p *Player, items []StackView) (*SellResult, error) {
	want := map[string]int{}
	for _, it := range items {
		if it.Count <= 0 || it.Count > 9999 {
			return nil, ErrInvalid
		}
		if s.content.SellPrice(it.Item) <= 0 {
			return nil, ErrNotForSale.with("A caixa de vendas não aceita %s.", s.itemName(it.Item))
		}
		want[it.Item] += it.Count
	}
	if len(want) == 0 {
		return nil, ErrInvalid.with("Escolha o que vender.")
	}
	ids := make([]string, 0, len(want))
	for id := range want {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *SellResult
	err := s.store.InTx(ctx, func(tx Store) error {
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		have := map[string]int{}
		for _, st := range inv {
			have[st.Item] = st.Count
		}
		sold := make([]StackView, 0, len(ids))
		var earned int64
		var refs []string
		for _, id := range ids {
			if have[id] < want[id] {
				return ErrMissingMaterials.with("Você não tem %d× %s.", want[id], s.itemName(id))
			}
			sold = append(sold, StackView{Item: id, Count: want[id]})
			earned += s.content.SellPrice(id) * int64(want[id])
			refs = append(refs, fmt.Sprintf("%s×%d", id, want[id]))
		}
		if err := consume(ctx, tx, p.ID, sold); err != nil {
			return err
		}
		bal, err := s.grant(ctx, tx, p, earned, "sell", strings.Join(refs, ","))
		if err != nil {
			return err
		}
		inv, err = tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		names := make([]string, len(sold))
		for i, st := range sold {
			names[i] = fmt.Sprintf("%d× %s", st.Count, s.itemName(st.Item))
		}
		res = &SellResult{Sold: sold, Earned: earned, Coins: bal,
			Message: fmt.Sprintf("Você vendeu %s e ganhou %s!", strings.Join(names, ", "), s.CoinsText(earned))}
		res.Inventory, res.SlotsUsed = s.inventoryView(inv)
		return nil
	})
	return res, err
}

// Transactions devolve as últimas transações do jogador (mais novas primeiro).
func (s *Service) Transactions(ctx context.Context, p *Player, limit int) ([]Transaction, error) {
	if limit <= 0 || limit > 500 {
		limit = 50
	}
	out, err := s.store.Transactions(ctx, p.ID, limit)
	if out == nil {
		out = []Transaction{}
	}
	return out, err
}

// DevCoins dá (ou tira, com amount negativo) moedas. O saldo nunca fica negativo.
func (s *Service) DevCoins(ctx context.Context, p *Player, amount int64) (*MeView, error) {
	if amount == 0 || amount > 1_000_000 || amount < -1_000_000 {
		return nil, ErrInvalid
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var me *MeView
	err := s.store.InTx(ctx, func(tx Store) error {
		if amount < 0 {
			have, err := tx.Coins(ctx, p.ID)
			if err != nil {
				return err
			}
			amount = -min(have, -amount)
		}
		if amount != 0 {
			if _, err := tx.AddCoins(ctx, p.ID, amount, "dev", "", s.clock.Now()); err != nil {
				return err
			}
		}
		var err error
		me, err = s.meView(ctx, tx, p)
		return err
	})
	return me, err
}
