package game

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Loja da praça central de cada país (fase 3.5, ADR 0042). O estoque do dia sai de uma
// semente (país + dia do jogo no horário do país), então todos os jogadores do país veem o
// mesmo, e muda na virada das 5h locais. Compra e venda passam por Service.Price.

// ShopContent é shop.json.
type ShopContent struct {
	Fixed         []string         `json:"fixed"`
	Rotating      []string         `json:"rotating"`
	RotatingCount int              `json:"rotating_count"`
	Regional      []ShopRegional   `json:"regional"`
	Prices        map[string]int64 `json:"prices"`
	byID          map[string]*ShopItem
}

// ShopRegional é um item exclusivo de alguns países.
type ShopRegional struct {
	Item      string   `json:"item"`
	Countries []string `json:"countries"`
}

// ShopItem é um item que a loja pode vender e o preço de compra.
type ShopItem struct {
	ID    string
	Price int64
}

// Item devolve o item da loja (nil se a loja não vende).
func (c *ShopContent) Item(id string) *ShopItem {
	if c == nil {
		return nil
	}
	return c.byID[id]
}

func (c *ShopContent) check(items map[string]*Item) error {
	c.byID = map[string]*ShopItem{}
	all := append(append([]string{}, c.Fixed...), c.Rotating...)
	for _, r := range c.Regional {
		all = append(all, r.Item)
	}
	for _, id := range all {
		if items[id] == nil {
			return fmt.Errorf("shop.json: item %s não existe", id)
		}
		p := c.Prices[id]
		if p <= 0 {
			return fmt.Errorf("shop.json: item %s sem preço", id)
		}
		c.byID[id] = &ShopItem{ID: id, Price: p}
	}
	if c.RotatingCount < 0 || c.RotatingCount > len(c.Rotating) {
		return fmt.Errorf("shop.json: rotating_count inválido")
	}
	return nil
}

// Semente do sorteio do estoque do dia. A loja fica na praça (Airport.ShopX/ShopY, ver
// plaza.go); nos países pequenos (balcão compartilhado), no mesmo balcão.
const shopDaySalt = 0x5A0F

// ShopPoint é onde fica o balcão da loja do país.
func (s *Service) ShopPoint(country string) (world.Vec3, bool) {
	a := s.airportBy[country]
	if a == nil {
		return world.Vec3{}, false
	}
	f := CellFrame(s.world, a.Cell)
	if a.Small {
		return f.Point(a.X, a.Y), true
	}
	return f.Point(a.ShopX, a.ShopY), true
}

// ShopDay é o dia do jogo da loja do país (vira às 5h no horário do aeroporto). O modo dev
// pode adiantar o estoque de um país (DevShopRestock).
func (s *Service) ShopDay(country string, now time.Time) int64 {
	lon := 0.0
	if a := s.airportBy[country]; a != nil {
		lon = a.Lon
	}
	s.shopMu.Lock()
	off := s.shopOffset[country]
	s.shopMu.Unlock()
	return DayIndex(now, lon) + off
}

// ShopStockItem é uma linha do estoque do dia.
type ShopStockItem struct {
	Item  string `json:"item"`
	Name  string `json:"name"`
	Kind  string `json:"kind"` // fixed, rotating ou regional
	Price Quote  `json:"price"`
}

// ShopView é a loja de um país hoje.
type ShopView struct {
	Country      string          `json:"country"`
	CountryName  string          `json:"country_name"`
	Day          int64           `json:"day"`
	NextRollover int64           `json:"next_rollover"`
	Stock        []ShopStockItem `json:"stock"`
	BuyBonus     float64         `json:"buy_bonus"` // a loja paga isso × a caixa de vendas
}

// ShopStock é o estoque do país num dia (determinístico: país + dia).
func (s *Service) ShopStock(country string, day int64) []ShopStockItem {
	c := s.content.Shop
	var out []ShopStockItem
	add := func(id, kind string) {
		out = append(out, ShopStockItem{Item: id, Name: s.itemName(id), Kind: kind, Price: s.Price(PriceShopBuy, id, country)})
	}
	for _, id := range c.Fixed {
		add(id, "fixed")
	}
	// Sorteio do dia: embaralha a lista com a semente país + dia e pega os primeiros.
	seed := uint32(day) ^ shopDaySalt
	for _, ch := range country {
		seed = seed*31 + uint32(ch)
	}
	rot := append([]string{}, c.Rotating...)
	for i := len(rot) - 1; i > 0; i-- {
		j := int(hash32(seed, uint32(i), 7) % uint32(i+1))
		rot[i], rot[j] = rot[j], rot[i]
	}
	for _, id := range rot[:c.RotatingCount] {
		add(id, "rotating")
	}
	for _, r := range c.Regional {
		for _, code := range r.Countries {
			if code == country {
				add(r.Item, "regional")
			}
		}
	}
	return out
}

// Shop devolve a loja do país hoje.
func (s *Service) Shop(country string) (*ShopView, error) {
	a := s.airportBy[country]
	if a == nil {
		return nil, ErrNotFound.with("%s não tem loja.", s.CountryName(country))
	}
	now := s.clock.Now()
	day := s.ShopDay(country, now)
	return &ShopView{Country: country, CountryName: s.CountryName(country), Day: day,
		NextRollover: NextRollover(now, a.Lon).Unix(), Stock: s.ShopStock(country, day),
		BuyBonus: s.content.Economy.ShopBuyBonus}, nil
}

// ShopResult é a resposta de comprar ou vender na loja.
type ShopResult struct {
	Coins     int64       `json:"coins"`
	Inventory []StackView `json:"inventory"`
	SlotsUsed int         `json:"slots_used"`
	Message   string      `json:"message"`
	Total     int64       `json:"total"`
}

// requireShop: o jogador precisa estar no balcão da loja do país (com o tempo real ligado).
func (s *Service) requireShop(p *Player, country string) error {
	pt, ok := s.ShopPoint(country)
	if !ok {
		return ErrNotFound.with("%s não tem loja.", s.CountryName(country))
	}
	return s.requireNear(p, pt, s.content.Rules.Reach.Shop, "do balcão da loja")
}

// ShopBuy compra `count` unidades de um item do estoque de hoje.
func (s *Service) ShopBuy(ctx context.Context, p *Player, country, item string, count int) (*ShopResult, error) {
	if count <= 0 || count > 99 {
		return nil, ErrInvalid
	}
	if err := s.requireShop(p, country); err != nil {
		return nil, err
	}
	var q *Quote
	for _, st := range s.ShopStock(country, s.ShopDay(country, s.clock.Now())) {
		if st.Item == item {
			x := st.Price
			q = &x
		}
	}
	if q == nil || q.Total <= 0 {
		return nil, ErrNotFound.with("A loja não tem %s hoje.", s.itemName(item))
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	var res *ShopResult
	err := s.store.InTx(ctx, func(tx Store) error {
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		total := *q
		total.Base *= int64(count)
		total.Tax *= int64(count)
		total.Total *= int64(count)
		bal, err := s.pay(ctx, tx, p, -total.Total, "shop_buy", fmt.Sprintf("%s×%d", item, count), total)
		if err != nil {
			return err
		}
		if err := s.addItems(ctx, tx, p.ID, inv, []StackView{{Item: item, Count: count}}); err != nil {
			return err
		}
		inv, err = tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		res = &ShopResult{Coins: bal, Total: total.Total,
			Message: fmt.Sprintf("Você comprou %d× %s por %s.", count, s.itemName(item), s.CoinsText(total.Total))}
		res.Inventory, res.SlotsUsed = s.inventoryView(inv)
		return nil
	})
	return res, err
}

// ShopSell vende itens na loja (paga mais que a caixa de vendas).
func (s *Service) ShopSell(ctx context.Context, p *Player, country string, items []StackView) (*ShopResult, error) {
	if err := s.requireShop(p, country); err != nil {
		return nil, err
	}
	want := map[string]int{}
	for _, it := range items {
		if it.Count <= 0 || it.Count > 9999 {
			return nil, ErrInvalid
		}
		if s.Price(PriceShopSell, it.Item, country).Base <= 0 {
			return nil, ErrNotForSale.with("A loja não compra %s.", s.itemName(it.Item))
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
	var res *ShopResult
	err := s.store.InTx(ctx, func(tx Store) error {
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		have := map[string]int{}
		for _, st := range inv {
			have[st.Item] = st.Count
		}
		total := Quote{Context: PriceShopSell, Country: country}
		var sold []StackView
		var refs []string
		for _, id := range ids {
			if have[id] < want[id] {
				return ErrMissingMaterials.with("Você não tem %d× %s.", want[id], s.itemName(id))
			}
			q := s.Price(PriceShopSell, id, country)
			total.Base += q.Base * int64(want[id])
			total.Tax += q.Tax * int64(want[id])
			total.Total += q.Total * int64(want[id])
			sold = append(sold, StackView{Item: id, Count: want[id]})
			refs = append(refs, fmt.Sprintf("%s×%d", id, want[id]))
		}
		if err := consume(ctx, tx, p.ID, sold); err != nil {
			return err
		}
		bal, err := s.pay(ctx, tx, p, total.Total, "shop_sell", strings.Join(refs, ","), total)
		if err != nil {
			return err
		}
		inv, err = tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		res = &ShopResult{Coins: bal, Total: total.Total, Message: fmt.Sprintf("A loja pagou %s.", s.CoinsText(total.Total))}
		res.Inventory, res.SlotsUsed = s.inventoryView(inv)
		return nil
	})
	return res, err
}

// DevShopRestock adianta o estoque da loja de um país um dia (modo dev).
func (s *Service) DevShopRestock(country string) (*ShopView, error) {
	s.shopMu.Lock()
	if s.shopOffset == nil {
		s.shopOffset = map[string]int64{}
	}
	s.shopOffset[country]++
	s.shopMu.Unlock()
	return s.Shop(country)
}
