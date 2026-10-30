package realtime

import (
	"context"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/game"
)

// Troca entre jogadores (fase 3.5, ADR 0044; protocolo em docs/PROTOCOLO.md):
//
//	trade_req (pede) → trade_answer (aceita ou recusa) → trade_open
//	trade_offer (itens e gobolares) → trade_update para os dois; desfaz os "pronto"
//	trade_ready → quando os dois estão prontos, falta a confirmação final
//	trade_confirm → os dois confirmaram: Service.ExecuteTrade (atômica) → trade_done
//	trade_cancel (qualquer um, a qualquer momento) → trade_closed
//
// A negociação fica na memória do hub; só a execução mexe no banco.

type trade struct {
	id      int64
	sides   [2]*client
	offers  [2]game.TradeOffer
	ready   [2]bool
	confirm [2]bool
	done    bool
}

const tradeRequestTTL = 30 * time.Second

func (t *trade) side(c *client) int {
	if t.sides[0] == c {
		return 0
	}
	return 1
}

func (t *trade) view(for_ *client) map[string]any {
	i := t.side(for_)
	other := t.sides[1-i]
	return map[string]any{"id": t.id, "with": other.id, "nick": other.player.Nickname,
		"mine": t.offers[i], "theirs": t.offers[1-i], "my_ready": t.ready[i], "their_ready": t.ready[1-i],
		"my_confirm": t.confirm[i], "their_confirm": t.confirm[1-i], "both_ready": t.ready[0] && t.ready[1]}
}

func (h *Hub) sendTrade(t *trade, kind string) {
	for _, c := range t.sides {
		v := t.view(c)
		v["t"] = kind
		c.sendJSON(v)
		if c.bot != nil {
			h.botTrade(c, t)
		}
	}
}

// closeTrade encerra a troca e avisa os dois.
func (h *Hub) closeTrade(t *trade, reason string) {
	if t.done {
		return
	}
	t.done = true
	for _, c := range t.sides {
		if c.trade == t {
			c.trade = nil
		}
		c.sendJSON(map[string]any{"t": "trade_closed", "id": t.id, "reason": reason})
	}
}

// onTrade trata as mensagens de troca. Chamado sem Hub.mu (pode ler o banco).
func (c *client) onTrade(ctx context.Context, kind string, m map[string]any, now time.Time) {
	h := c.hub
	switch kind {
	case "trade_req":
		other := int64(num(m, "to"))
		h.mu.Lock()
		defer h.mu.Unlock()
		o := h.clients[other]
		switch {
		case o == nil || !o.spawned || !c.spawned:
			c.info("Esse jogador não está mais por perto.")
		case o.blocked[c.id] || o.blockedBy[c.id] || c.blocked[o.id]:
			c.info("Vocês não podem trocar (bloqueio).")
		case o.noTrades:
			c.info(o.player.Nickname + " não está aceitando pedidos de troca agora.")
		case groundDistance(h.world, c.pos, o.pos) > h.rules.Reach.Trade:
			c.info("Chegue mais perto de " + o.player.Nickname + " para propor uma troca.")
		case c.trade != nil || o.trade != nil:
			c.info("Um de vocês já está numa troca.")
		default:
			if o.tradeReqs == nil {
				o.tradeReqs = map[int64]time.Time{}
			}
			o.tradeReqs[c.id] = now
			o.sendJSON(map[string]any{"t": "trade_req", "from": c.id, "nick": c.player.Nickname})
			c.info("Pedido de troca enviado para " + o.player.Nickname + ".")
			if o.bot != nil {
				h.botAnswer(o, c)
			}
		}
	case "trade_answer":
		from := int64(num(m, "from"))
		ok, _ := m["ok"].(bool)
		h.mu.Lock()
		defer h.mu.Unlock()
		h.answerTrade(c, from, ok, now)
	case "trade_offer":
		var offer game.TradeOffer
		if raw, ok := m["items"].([]any); ok {
			for _, x := range raw {
				it, _ := x.(map[string]any)
				offer.Items = append(offer.Items, game.StackView{Item: str(it, "item"), Count: int(num(it, "count"))})
			}
		}
		offer.Coins = int64(num(m, "coins"))
		if err := h.svc.CheckOffer(ctx, c.player, offer); err != nil {
			h.mu.Lock()
			c.info(err.Error())
			h.mu.Unlock()
			return
		}
		h.mu.Lock()
		defer h.mu.Unlock()
		if t := c.trade; t != nil && !t.done {
			t.offers[t.side(c)] = offer
			t.ready, t.confirm = [2]bool{}, [2]bool{} // mudou algo: os dois "pronto" caem
			h.sendTrade(t, "trade_update")
		}
	case "trade_ready":
		on, _ := m["on"].(bool)
		h.mu.Lock()
		defer h.mu.Unlock()
		if t := c.trade; t != nil && !t.done {
			t.ready[t.side(c)] = on
			if !on {
				t.confirm = [2]bool{}
			}
			h.sendTrade(t, "trade_update")
		}
	case "trade_confirm":
		h.mu.Lock()
		t := c.trade
		if t == nil || t.done || !(t.ready[0] && t.ready[1]) {
			h.mu.Unlock()
			return
		}
		t.confirm[t.side(c)] = true
		run := t.confirm[0] && t.confirm[1]
		h.sendTrade(t, "trade_update")
		h.mu.Unlock()
		if run {
			h.executeTrade(ctx, t)
		}
	case "trade_cancel":
		h.mu.Lock()
		defer h.mu.Unlock()
		if t := c.trade; t != nil {
			h.closeTrade(t, c.player.Nickname+" cancelou a troca.")
		}
	case "trade_block":
		on, _ := m["on"].(bool)
		h.mu.Lock()
		c.noTrades = on
		h.mu.Unlock()
	}
}

func (c *client) info(text string) { c.sendJSON(map[string]any{"t": "info", "text": text}) }

// answerTrade: c aceitou (ou recusou) o pedido de `from`. Com Hub.mu.
func (h *Hub) answerTrade(c *client, from int64, ok bool, now time.Time) {
	at, asked := c.tradeReqs[from]
	delete(c.tradeReqs, from)
	o := h.clients[from]
	if !asked || now.Sub(at) > tradeRequestTTL || o == nil {
		c.info("Esse pedido de troca já expirou.")
		return
	}
	if !ok {
		o.info(c.player.Nickname + " recusou a troca.")
		return
	}
	if c.trade != nil || o.trade != nil {
		c.info("Um de vocês já está numa troca.")
		return
	}
	h.nextTrade++
	t := &trade{id: h.nextTrade, sides: [2]*client{o, c}}
	o.trade, c.trade = t, t
	h.sendTrade(t, "trade_open")
}

// executeTrade roda a troca no banco (sem Hub.mu) e avisa os dois.
func (h *Hub) executeTrade(ctx context.Context, t *trade) {
	a, b := t.sides[0], t.sides[1]
	res, err := h.svc.ExecuteTrade(ctx, a.player, b.player, t.offers[0], t.offers[1])
	h.mu.Lock()
	defer h.mu.Unlock()
	if t.done {
		return
	}
	if err != nil {
		// Algo mudou (alguém gastou o item, saiu de perto): nada aconteceu; os "pronto"
		// caem e a troca continua aberta para ajustar.
		t.ready, t.confirm = [2]bool{}, [2]bool{}
		for _, c := range t.sides {
			c.info("A troca não deu certo: " + err.Error())
		}
		h.sendTrade(t, "trade_update")
		return
	}
	t.done = true
	for i, c := range t.sides {
		side := res.A
		if i == 1 {
			side = res.B
		}
		c.trade = nil
		c.sendJSON(map[string]any{"t": "trade_done", "id": t.id, "inventory": side.Inventory,
			"slots_used": side.SlotsUsed, "coins": side.Coins, "message": res.Message})
	}
}

// dropTrade: o jogador saiu; a troca dele acaba. Com Hub.mu.
func (h *Hub) dropTrade(c *client) {
	if c.trade != nil {
		h.closeTrade(c.trade, c.player.Nickname+" saiu.")
	}
}

// --- Bots do modo dev -----------------------------------------------------------------------

// botAnswer: bots de número par aceitam pedidos de troca; os outros recusam. Com Hub.mu.
func (h *Hub) botAnswer(bot, from *client) {
	bot.tradeReqs[from.id] = time.Now()
	h.answerTrade(bot, from.id, bot.id%2 == 0, time.Now())
}

// botTrade: o bot oferece 3 madeiras e acompanha o jogador: fica pronto quando o outro
// fica, e confirma quando o outro confirma. Com Hub.mu.
func (h *Hub) botTrade(bot *client, t *trade) {
	i := t.side(bot)
	if len(t.offers[i].Items) == 0 && t.offers[i].Coins == 0 {
		t.offers[i] = game.TradeOffer{Items: []game.StackView{{Item: "wood", Count: 3}}}
		go func() {
			time.Sleep(300 * time.Millisecond)
			h.mu.Lock()
			defer h.mu.Unlock()
			if !t.done {
				h.sendTrade(t, "trade_update")
			}
		}()
		return
	}
	other := 1 - i
	if t.ready[other] && !t.ready[i] {
		t.ready[i] = true
		go func() {
			time.Sleep(300 * time.Millisecond)
			h.mu.Lock()
			defer h.mu.Unlock()
			if !t.done {
				h.sendTrade(t, "trade_update")
			}
		}()
	}
	if t.confirm[other] && !t.confirm[i] {
		t.confirm[i] = true
		go h.executeTrade(context.Background(), t)
	}
}
