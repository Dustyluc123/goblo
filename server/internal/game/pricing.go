package game

import (
	"context"
	"fmt"
	"math"
)

// Preços (fase 3.5, ADR 0041). Todo preço do jogo passa por Service.Price, que aplica os
// modificadores do país onde a transação acontece (countries.json). Hoje todos os países
// usam os valores padrão (imposto zero); no futuro, o governo de cada país muda os seus.

// PriceContext diz que tipo de preço é.
type PriceContext string

const (
	PriceSellBox  PriceContext = "sell_box"  // o jogador vende na caixa de vendas (por unidade)
	PriceShopSell PriceContext = "shop_sell" // o jogador vende na loja (paga um pouco mais)
	PriceShopBuy  PriceContext = "shop_buy"  // o jogador compra na loja (por unidade)
	PricePassport PriceContext = "passport"  // item = país do passaporte
	PriceTravel   PriceContext = "travel"    // item = "ORIGEM>DESTINO"
)

// Quote é um preço: base, imposto e o total que o jogador paga (compra) ou recebe (venda).
type Quote struct {
	Context PriceContext `json:"context"`
	Item    string       `json:"item"`
	Country string       `json:"country"` // onde acontece (o cofre que recebe o imposto)
	Base    int64        `json:"base"`
	Tax     int64        `json:"tax"`
	Total   int64        `json:"total"`
}

// CountryEconomy são os modificadores de um país (countries.json).
type CountryEconomy struct {
	GoodsTax      float64 `json:"goods_tax"`
	PassportTax   float64 `json:"passport_tax"`
	TravelTax     float64 `json:"travel_tax"`
	PassportPrice int64   `json:"passport_price"` // 0 = o de economy.json
	ShopMarkup    float64 `json:"shop_markup"`
}

// CountriesEconomy é countries.json.
type CountriesEconomy struct {
	Default   CountryEconomy            `json:"default"`
	Countries map[string]CountryEconomy `json:"countries"`
}

func (c *CountriesEconomy) check() error {
	for code, e := range c.Countries {
		if e.GoodsTax < 0 || e.GoodsTax >= 1 || e.PassportTax < 0 || e.TravelTax < 0 || e.ShopMarkup < 0 {
			return fmt.Errorf("countries.json: valores inválidos para %s", code)
		}
	}
	if c.Default.ShopMarkup <= 0 {
		return fmt.Errorf("countries.json: default.shop_markup precisa ser > 0")
	}
	return nil
}

// Of devolve os modificadores do país (os padrão, se o país não tiver os próprios).
func (c *CountriesEconomy) Of(country string) CountryEconomy {
	if e, ok := c.Countries[country]; ok {
		if e.ShopMarkup == 0 {
			e.ShopMarkup = c.Default.ShopMarkup
		}
		return e
	}
	return c.Default
}

// Price é a função única de preço: (contexto, item, país) → base, imposto e total. 0 de
// base = não tem preço nesse contexto.
func (s *Service) Price(kind PriceContext, item, country string) Quote {
	ce := s.content.Countries.Of(country)
	q := Quote{Context: kind, Item: item, Country: country}
	var rate float64
	sell := false
	switch kind {
	case PriceSellBox:
		q.Base, rate, sell = s.content.Economy.SellPrices[item], ce.GoodsTax, true
	case PriceShopSell:
		base := s.content.Economy.SellPrices[item]
		q.Base, rate, sell = int64(math.Ceil(float64(base)*s.content.Economy.ShopBuyBonus)), ce.GoodsTax, true
	case PriceShopBuy:
		if it := s.content.Shop.Item(item); it != nil {
			q.Base = int64(math.Round(float64(it.Price) * ce.ShopMarkup))
		}
		rate = ce.GoodsTax
	case PricePassport:
		target := s.content.Countries.Of(item)
		q.Base = s.content.PassportPrice(item)
		if target.PassportPrice > 0 {
			q.Base = target.PassportPrice
		}
		rate = ce.PassportTax
	case PriceTravel:
		var from, to string
		for i := 0; i < len(item); i++ {
			if item[i] == '>' {
				from, to = item[:i], item[i+1:]
			}
		}
		q.Base, rate = s.TravelPrice(from, to), ce.TravelTax
	}
	q.Tax = int64(math.Round(float64(q.Base) * rate))
	if sell {
		q.Total = q.Base - q.Tax
	} else {
		q.Total = q.Base + q.Tax
	}
	return q
}

// pay registra uma mudança de saldo com o país, o preço e o imposto; o imposto vai para o
// cofre do país. amount > 0 = o jogador recebe.
func (s *Service) pay(ctx context.Context, tx Store, p *Player, amount int64, reason, ref string, q Quote) (int64, error) {
	if amount == 0 {
		return tx.Coins(ctx, p.ID)
	}
	country := q.Country
	if country == "" {
		country = p.Country
	}
	price := q.Base
	if price == 0 {
		price = abs64(amount)
	}
	bal, err := tx.AddLedger(ctx, p.ID, LedgerEntry{Delta: amount, Reason: reason, Ref: ref, Country: country, Price: price, Tax: q.Tax}, s.clock.Now())
	if err != nil && ErrNoCoins.Is(err) {
		have, _ := tx.Coins(ctx, p.ID)
		return 0, ErrNoCoins.with("Faltam %s (você tem %s).", s.CoinsText(-amount-have), s.CoinsText(have))
	}
	if err == nil && q.Tax > 0 {
		err = tx.AddTreasury(ctx, country, q.Tax, s.clock.Now())
	}
	return bal, err
}

func abs64(x int64) int64 {
	if x < 0 {
		return -x
	}
	return x
}

// Treasury é o saldo do cofre de um país (hoje sempre zero: não há imposto).
func (s *Service) Treasury(ctx context.Context, country string) (int64, error) {
	return s.store.Treasury(ctx, country)
}
