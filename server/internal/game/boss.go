package game

import (
	"context"
	"fmt"
	"math"
	"time"
)

// Chefe da caverna (fase 4.5, ADR 0056): um golem grande, fofo e sonolento na última sala.
// Ele bate no chão em ataques com aviso: círculos marcados no chão warn segundos antes do
// impacto, um debaixo de cada jogador na sala e mais alguns sorteados. Quem está dentro de
// um círculo (no chão) no impacto leva um acerto; hits acertos levam de volta ao começo da
// caverna, sem perder nada. Depois de sequences sequências, ele cansa e dorme: quem desviou
// de pelo menos dodge_to_win ataques nessa rodada vence ao interagir com ele (E).
//
// O chefe é o mesmo para todos na sala (um estado por caverna, na memória do servidor); os
// acertos e a vitória são de cada jogador. A camada em tempo real chama BossTick com as
// posições validadas de quem está na caverna e manda as mensagens.

// BossRule é caves.json → boss.
type BossRule struct {
	ID           string  `json:"id"`
	Name         string  `json:"name"`
	Attacks      int     `json:"attacks"`
	Interval     float64 `json:"interval"`
	Warn         float64 `json:"warn"`
	CircleRadius float64 `json:"circle_radius"`
	Extra        [2]int  `json:"extra"`
	Pause        float64 `json:"pause"`
	Sequences    int     `json:"sequences"`
	Sleep        float64 `json:"sleep"`
	DodgeToWin   int     `json:"dodge_to_win"`
	Hits         int     `json:"hits"`
	Reach        float64 `json:"reach"`
	Reward       struct {
		Coins       int64  `json:"coins"`
		Item        string `json:"item"`
		Count       int    `json:"count"`
		Achievement string `json:"achievement"`
	} `json:"reward"`
}

// Fases do chefe.
const (
	BossIdle   = "idle"   // ninguém na sala: cochilando de leve, esperando
	BossAwake  = "awake"  // atacando
	BossAsleep = "asleep" // cansou e dormiu: dá para vencer
)

type bossState struct {
	phase   string
	cycle   int
	seq     int
	attack  int
	next    time.Time
	wakeAt  time.Time
	empty   time.Time // desde quando a sala está vazia (acordado)
	pending []BossAttack
	nextID  int
	players map[int64]*bossPlayer
}

type bossPlayer struct {
	hits   int
	dodged int
	cycle  int
	seen   time.Time // última vez na caverna (quem sai por um tempo começa do zero)
}

// BossAttack é um ataque anunciado: círculos (x, z, raio) no chão da sala e a hora do impacto.
type BossAttack struct {
	ID      int          `json:"id"`
	Circles [][3]float64 `json:"circles"`
	Warn    float64      `json:"warn"` // segundos até o impacto, quando foi anunciado
	impact  time.Time
	floor   float64
}

// BossMsg é uma mensagem para a camada em tempo real: To = 0 para todos na caverna.
type BossMsg struct {
	To   int64
	Data map[string]any
}

// BossPlayerView é o estado do chefe para um jogador.
type BossPlayerView struct {
	Phase  string `json:"phase"`
	Hits   int    `json:"hits"`
	Max    int    `json:"max"`
	Dodged int    `json:"dodged"`
	Need   int    `json:"need"`
	Won    bool   `json:"won"` // já venceu hoje nesta caverna
	Name   string `json:"name"`
}

func (s *Service) bossOf(cave int) *bossState {
	s.cave.init()
	st := s.cave.boss[cave]
	if st == nil {
		st = &bossState{phase: BossIdle, players: map[int64]*bossPlayer{}}
		s.cave.boss[cave] = st
	}
	return st
}

func (st *bossState) player(id int64) *bossPlayer {
	bp := st.players[id]
	if bp == nil {
		bp = &bossPlayer{}
		st.players[id] = bp
	}
	if bp.cycle != st.cycle {
		bp.cycle, bp.dodged = st.cycle, 0
	}
	return bp
}

// inBossRoom: a posição (x, y, z da caverna) está na sala do chefe?
func inBossRoom(l *CaveLayout, p [3]float64) bool {
	rm := l.Rooms[len(l.Rooms)-1]
	for _, r := range l.Rooms {
		if r.Boss {
			rm = r
		}
	}
	return math.Hypot(p[0]-rm.X, p[2]-rm.Z) <= rm.R+0.5 && p[1] > rm.Y-2 && p[1] < rm.Y+6
}

func bossRoom(l *CaveLayout) CaveRoom {
	for _, r := range l.Rooms {
		if r.Boss {
			return r
		}
	}
	return l.Rooms[len(l.Rooms)-1]
}

// BossTick avança a luta da caverna. present = jogadores na caverna → posição (x, y, z da
// caverna). Devolve as mensagens para mandar.
func (s *Service) BossTick(cave int, present map[int64][3]float64, now time.Time) []BossMsg {
	l := s.CaveLayoutOf(cave)
	if l == nil {
		return nil
	}
	b := s.content.Caves.Boss
	s.cave.mu.Lock()
	defer s.cave.mu.Unlock()
	st := s.bossOf(cave)
	var out []BossMsg
	room := bossRoom(l)
	in := map[int64][3]float64{}
	for id, p := range present {
		st.player(id).seen = now
		if inBossRoom(l, p) {
			in[id] = p
		}
	}
	for id, bp := range st.players {
		if now.Sub(bp.seen) > 30*time.Second {
			delete(st.players, id)
		}
	}
	state := func() {
		out = append(out, BossMsg{Data: map[string]any{"t": "boss", "cave": cave, "phase": st.phase}})
	}
	// Impactos que chegaram.
	keep := st.pending[:0]
	for _, a := range st.pending {
		if now.Before(a.impact) {
			keep = append(keep, a)
			continue
		}
		for id, p := range in {
			bp := st.player(id)
			hit := false
			if !s.cave.god[id] && p[1] < a.floor+0.7 {
				for _, c := range a.Circles {
					if math.Hypot(p[0]-c[0], p[2]-c[1]) <= c[2] {
						hit = true
						break
					}
				}
			}
			if !hit {
				bp.dodged++
				continue
			}
			bp.hits++
			msg := map[string]any{"t": "boss_hit", "cave": cave, "hits": bp.hits, "max": b.Hits}
			if bp.hits >= b.Hits {
				bp.hits, bp.dodged = 0, 0
				msg["reset"] = true
			}
			out = append(out, BossMsg{To: id, Data: msg})
		}
	}
	st.pending = keep
	switch st.phase {
	case BossIdle:
		if len(in) > 0 {
			st.phase, st.cycle, st.seq, st.attack = BossAwake, st.cycle+1, 0, 0
			st.next = now.Add(1500 * time.Millisecond)
			st.empty = time.Time{}
			state()
		}
	case BossAwake:
		if len(in) == 0 {
			if st.empty.IsZero() {
				st.empty = now
			} else if now.Sub(st.empty) > 10*time.Second {
				st.phase, st.pending = BossIdle, nil
				state()
			}
			break
		}
		st.empty = time.Time{}
		if st.seq >= b.Sequences {
			if len(st.pending) == 0 {
				st.phase = BossAsleep
				st.wakeAt = now.Add(time.Duration(b.Sleep * float64(time.Second)))
				state()
			}
			break
		}
		if now.Before(st.next) {
			break
		}
		r := newRNG(mix(uint64(cave), uint64(st.cycle), uint64(st.seq), uint64(st.attack), 0xB055))
		a := BossAttack{ID: st.nextID, Warn: b.Warn, impact: now.Add(time.Duration(b.Warn * float64(time.Second))), floor: room.Y}
		st.nextID++
		for _, p := range in {
			a.Circles = append(a.Circles, [3]float64{p[0], p[2], b.CircleRadius})
		}
		extra := b.Extra[0] + r.intn(b.Extra[1]-b.Extra[0]+1) + st.seq
		for k := 0; k < extra; k++ {
			ang := r.float() * 2 * math.Pi
			d := math.Sqrt(r.float()) * (room.R - b.CircleRadius)
			a.Circles = append(a.Circles, [3]float64{room.X + math.Cos(ang)*d, room.Z + math.Sin(ang)*d, b.CircleRadius})
		}
		st.pending = append(st.pending, a)
		out = append(out, BossMsg{Data: map[string]any{"t": "boss_attack", "cave": cave, "attack": a, "y": room.Y}})
		st.attack++
		st.next = now.Add(time.Duration(b.Interval * float64(time.Second)))
		if st.attack >= b.Attacks {
			st.seq++
			st.attack = 0
			st.next = st.next.Add(time.Duration(b.Pause * float64(time.Second)))
		}
	case BossAsleep:
		if !now.Before(st.wakeAt) {
			st.phase = BossIdle
			state()
		}
	}
	return out
}

// bossDayKey: o "objeto" da recompensa do chefe nas coletas do dia (uma por caverna).
func bossDayKey(cave int) int64 { return CaveOreID(cave, 999) }

func (s *Service) bossPlayerView(ctx context.Context, p *Player, cave int) BossPlayerView {
	b := s.content.Caves.Boss
	s.cave.mu.Lock()
	st := s.bossOf(cave)
	bp := st.player(p.ID)
	v := BossPlayerView{Phase: st.phase, Hits: bp.hits, Max: b.Hits, Dodged: bp.dodged, Need: b.DodgeToWin, Name: b.Name}
	s.cave.mu.Unlock()
	day := DayIndex(s.clock.Now(), s.homeLon(ctx, s.store, p))
	if n, err := s.store.CollectionCount(ctx, p.ID, bossDayKey(cave), "boss", day); err == nil && n > 0 {
		v.Won = true
	}
	return v
}

// BossResult é a resposta de interagir com o chefe.
type BossResult struct {
	Won         bool        `json:"won"`
	Reward      int64       `json:"reward"`
	Coins       int64       `json:"coins"`
	Gained      []StackView `json:"gained,omitempty"`
	Achievement string      `json:"achievement,omitempty"`
	PediaFirst  bool        `json:"pedia_first"`
	Message     string      `json:"message"`
	Inventory   []StackView `json:"inventory"`
	SlotsUsed   int         `json:"slots_used"`
}

// WakeBoss: o jogador chega até o chefe e interage (E). Com ele dormindo e o jogador tendo
// desviado de dodge_to_win ataques nessa rodada, vence: gobolares, o item exclusivo, a
// página da Goblopédia e a conquista, uma vez por dia por caverna.
func (s *Service) WakeBoss(ctx context.Context, p *Player, cave int) (*BossResult, error) {
	l := s.CaveLayoutOf(cave)
	if l == nil {
		return nil, ErrNotFound.with("Caverna desconhecida.")
	}
	b := s.content.Caves.Boss
	if err := s.requireNearCave(p, cave, l.Boss[0], l.Boss[1], l.Boss[2], b.Reach+bossRoom(l).R*0.25, "do golem"); err != nil {
		return nil, err
	}
	s.cave.mu.Lock()
	st := s.bossOf(cave)
	bp := st.player(p.ID)
	phase, dodged := st.phase, bp.dodged
	s.cave.mu.Unlock()
	if phase != BossAsleep {
		return &BossResult{Message: fmt.Sprintf("O %s ainda está acordado. Desvie dos círculos até ele cansar!", b.Name)}, nil
	}
	if dodged < b.DodgeToWin {
		return &BossResult{Message: fmt.Sprintf("Ele está dormindo, mas você chegou agora: desvie de %d ataques na próxima rodada (%d até aqui).", b.DodgeToWin, dodged)}, nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	res := &BossResult{}
	err := s.store.InTx(ctx, func(tx Store) error {
		day := DayIndex(s.clock.Now(), s.homeLon(ctx, tx, p))
		done, err := tx.CollectionCount(ctx, p.ID, bossDayKey(cave), "boss", day)
		if err != nil {
			return err
		}
		inv, err := tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		res.Won = true
		if done > 0 {
			res.Message = fmt.Sprintf("O %s ronca tranquilo. Você já ganhou o presente dele hoje: volte amanhã!", b.Name)
			res.Inventory, res.SlotsUsed = s.inventoryView(inv)
			return nil
		}
		gained := []StackView{{Item: b.Reward.Item, Count: b.Reward.Count}}
		if err := s.addItems(ctx, tx, p.ID, inv, gained); err != nil {
			return err
		}
		if err := tx.AddCollection(ctx, p.ID, bossDayKey(cave), -1, "boss", day); err != nil {
			return err
		}
		res.Gained = gained
		res.Reward = b.Reward.Coins
		if res.Coins, err = s.grant(ctx, tx, p, b.Reward.Coins, "boss", fmt.Sprint(cave), s.CaveByID(cave).Country); err != nil {
			return err
		}
		if res.PediaFirst, err = tx.PediaSighting(ctx, p.ID, b.ID, s.CaveByID(cave).Country, "", s.clock.Now()); err != nil {
			return err
		}
		if b.Reward.Achievement != "" {
			added, err := tx.AddAchievement(ctx, p.ID, b.Reward.Achievement, s.clock.Now())
			if err != nil {
				return err
			}
			if added {
				res.Achievement = b.Reward.Achievement
			}
		}
		res.Message = fmt.Sprintf("O %s acordou feliz e te deu %d× %s e %s!", b.Name, b.Reward.Count, s.itemName(b.Reward.Item), s.CoinsText(b.Reward.Coins))
		inv, err = tx.Inventory(ctx, p.ID)
		if err != nil {
			return err
		}
		res.Inventory, res.SlotsUsed = s.inventoryView(inv)
		return nil
	})
	return res, err
}

// DevBossSleep (modo dev): o chefe da caverna dorme agora e o jogador conta como quem desviou
// o bastante (para testar a vitória).
func (s *Service) DevBossSleep(p *Player, cave int) {
	b := s.content.Caves.Boss
	s.cave.mu.Lock()
	defer s.cave.mu.Unlock()
	st := s.bossOf(cave)
	st.cycle++
	st.phase, st.pending = BossAsleep, nil
	st.wakeAt = s.clock.Now().Add(time.Duration(b.Sleep * float64(time.Second)))
	bp := st.player(p.ID)
	bp.dodged = b.DodgeToWin
}

// AchievementView é uma conquista do jogador.
type AchievementView struct {
	ID      string `json:"id"`
	FirstAt int64  `json:"first_at"`
}

// AchievementsOf lista as conquistas do jogador.
func (s *Service) AchievementsOf(ctx context.Context, p *Player) ([]AchievementView, error) {
	list, err := s.store.Achievements(ctx, p.ID)
	if err != nil {
		return nil, err
	}
	out := []AchievementView{}
	for _, a := range list {
		out = append(out, AchievementView{ID: a.ID, FirstAt: a.FirstAt.Unix()})
	}
	return out, nil
}
