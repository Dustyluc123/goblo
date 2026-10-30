// Comando bots simula jogadores conectados ao servidor (fase 3, teste de carga): cada bot
// cria um jogador, entra pelo WebSocket, anda numa região (sempre em terra), vai até
// árvores e flores para coletar, manda emotes e fala de vez em quando. No fim, imprime o
// que cada bot recebeu e mandou.
//
//	go run ./cmd/bots -server http://127.0.0.1:8080 -n 100 -duration 60s
//
// O servidor precisa estar com GOBLO_DEV=1 (os bots nascem na região escolhida, não em
// casa). Cada bot cria um jogador de verdade no banco: use um banco de teste (-db).
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math"
	"math/rand/v2"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"

	"github.com/Dustyluc123/goblo/server/data"
	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/realtime"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

var (
	server   = flag.String("server", "http://127.0.0.1:8080", "endereço do servidor")
	count    = flag.Int("n", 20, "quantos bots")
	lat      = flag.Float64("lat", -23.55, "latitude do centro da região")
	lon      = flag.Float64("lon", -46.63, "longitude do centro da região")
	radius   = flag.Float64("radius", 25, "raio da região (unidades)")
	duration = flag.Duration("duration", 60*time.Second, "quanto tempo os bots ficam")
	country  = flag.String("country", "BRA", "país dos bots")
	hz       = flag.Int("hz", 15, "posições por segundo")
)

// Totais de todos os bots.
var (
	bytesIn, bytesOut, snaps, corrections, chats, interacts, interactFail atomic.Int64
	visibleSum, visibleN                                                  atomic.Int64
)

func main() {
	flag.Parse()
	geo, err := world.LoadGeography(data.NaturalEarth)
	if err != nil {
		log.Fatal(err)
	}
	w, err := world.New(world.DefaultConfig, geo)
	if err != nil {
		log.Fatal(err)
	}
	center := world.LatLonToVec(*lat, *lon)
	log.Printf("mundo pronto; %d bots em %.2f, %.2f por %s", *count, *lat, *lon, *duration)
	ctx, cancel := context.WithTimeout(context.Background(), *duration)
	defer cancel()
	var wg sync.WaitGroup
	start := time.Now()
	stamp := time.Now().UnixMilli() % 100000
	for i := 0; i < *count; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			b := &bot{w: w, center: center, rng: rand.New(rand.NewPCG(uint64(i), uint64(stamp))),
				nick: fmt.Sprintf("Carga%d %d", stamp%1000, i)}
			if err := b.run(ctx); err != nil && ctx.Err() == nil {
				log.Printf("bot %d: %v", i, err)
			}
		}(i)
		time.Sleep(30 * time.Millisecond) // entram aos poucos
	}
	wg.Wait()
	secs := time.Since(start).Seconds()
	n := float64(*count)
	vis := 0.0
	if visibleN.Load() > 0 {
		vis = float64(visibleSum.Load()) / float64(visibleN.Load())
	}
	fmt.Printf("bots: %d por %.0f s\n", *count, secs)
	fmt.Printf("recebido por bot: %.1f KB/s (%.1f fotos/s, %.1f jogadores visíveis em média)\n",
		float64(bytesIn.Load())/1024/secs/n, float64(snaps.Load())/secs/n, vis)
	fmt.Printf("mandado por bot: %.2f KB/s\n", float64(bytesOut.Load())/1024/secs/n)
	fmt.Printf("correções: %d · chats recebidos: %d · coletas: %d ok, %d recusadas\n",
		corrections.Load(), chats.Load(), interacts.Load(), interactFail.Load())
}

type bot struct {
	w      *world.World
	center world.Vec3
	rng    *rand.Rand
	nick   string
	token  string
	pos    world.Vec3
	cell   int
	target world.Vec3
	object int64 // objeto que está indo coletar (0 = só passeando)
	action string
	mu     sync.Mutex
}

func (b *bot) post(path string, body any, out any) error {
	data, _ := json.Marshal(body)
	req, _ := http.NewRequest("POST", *server+path, bytes.NewReader(data))
	req.Header.Set("Content-Type", "application/json")
	if b.token != "" {
		req.Header.Set("Authorization", "Bearer "+b.token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode >= 300 {
		return fmt.Errorf("%s: HTTP %d", path, res.StatusCode)
	}
	if out != nil {
		return json.NewDecoder(res.Body).Decode(out)
	}
	return nil
}

func (b *bot) get(path string, out any) error {
	req, _ := http.NewRequest("GET", *server+path, nil)
	req.Header.Set("Authorization", "Bearer "+b.token)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	return json.NewDecoder(res.Body).Decode(out)
}

// landNear: ponto em terra a até r unidades do centro.
func (b *bot) landNear(r float64) world.Vec3 {
	east, north := realtime.Tangent(b.center)
	for {
		a := b.rng.Float64() * 2 * math.Pi
		d := r * math.Sqrt(b.rng.Float64())
		p := b.center.Scale(b.w.Radius).Add(east.Scale(d * math.Cos(a))).Add(north.Scale(d * math.Sin(a)))
		c := b.w.FindCell(p, -1)
		if b.w.Cells[c].Terrain == world.Land {
			return p.Normalize().Scale(b.w.Radius + b.w.Cells[c].Height)
		}
	}
}

func (b *bot) run(ctx context.Context) error {
	var created struct {
		Token string `json:"token"`
	}
	if err := b.post("/players", map[string]any{"nickname": b.nick, "country": *country}, &created); err != nil {
		return err
	}
	b.token = created.Token
	url := "ws" + strings.TrimPrefix(*server, "http") + "/ws"
	ws, _, err := websocket.Dial(ctx, url, &websocket.DialOptions{HTTPHeader: http.Header{"Authorization": {"Bearer " + b.token}}})
	if err != nil {
		return err
	}
	defer ws.Close(websocket.StatusNormalClosure, "")
	ws.SetReadLimit(1 << 20)
	go b.read(ctx, ws)
	b.pos = b.landNear(*radius)
	b.cell = b.w.FindCell(b.pos, -1)
	b.target = b.pos
	send := func(v any) {
		data, _ := json.Marshal(v)
		bytesOut.Add(int64(len(data)))
		ws.Write(ctx, websocket.MessageText, data)
	}
	send(map[string]any{"t": "tp", "why": "dev", "pos": []float64{b.pos.X, b.pos.Y, b.pos.Z}})
	tick := time.NewTicker(time.Second / time.Duration(*hz))
	defer tick.Stop()
	nextChat := time.Now().Add(time.Duration(10+b.rng.IntN(30)) * time.Second)
	nextEmote := time.Now().Add(time.Duration(5+b.rng.IntN(15)) * time.Second)
	var seq uint16
	dt := 1 / float64(*hz)
	for {
		select {
		case <-ctx.Done():
			return nil
		case now := <-tick.C:
			b.mu.Lock()
			to := b.target.Sub(b.pos)
			up := b.pos.Normalize()
			to = to.Sub(up.Scale(to.Dot(up)))
			dist := to.Len()
			anim := uint8(0)
			if dist < 1.2 {
				if b.object != 0 {
					b.collect()
				}
				b.pickTarget()
			} else {
				step := math.Min(dist, 5.0*dt)
				p := b.pos.Add(to.Scale(step / dist))
				c := b.w.FindCell(p, b.cell)
				if b.w.Cells[c].Terrain == world.Land {
					b.pos = p.Normalize().Scale(b.w.Radius + b.w.Cells[c].Height)
					b.cell = c
					anim = 1
				} else {
					b.pickTarget()
				}
			}
			e, n := realtime.Tangent(b.pos)
			yaw := math.Atan2(to.Dot(n), to.Dot(e))
			seq++
			m := realtime.EncodeMove(realtime.Move{Seq: seq, Pos: b.pos, Yaw: yaw, Anim: anim, Flags: realtime.FlagOnFloor})
			b.mu.Unlock()
			bytesOut.Add(int64(len(m)))
			if err := ws.Write(ctx, websocket.MessageBinary, m); err != nil {
				return nil
			}
			if now.After(nextChat) {
				nextChat = now.Add(time.Duration(20+b.rng.IntN(40)) * time.Second)
				send(map[string]any{"t": "chat", "text": "olá do " + b.nick})
			}
			if now.After(nextEmote) {
				nextEmote = now.Add(time.Duration(10+b.rng.IntN(20)) * time.Second)
				send(map[string]any{"t": "emote", "e": []string{"wave", "yes", "cheer", "sit"}[b.rng.IntN(4)]})
			}
		}
	}
}

// pickTarget: metade das vezes vai até uma árvore ou flor da célula para coletar; senão
// passeia.
func (b *bot) pickTarget() {
	b.object = 0
	if b.rng.IntN(2) == 0 {
		var res struct {
			Objects []game.ObjectView `json:"objects"`
		}
		if err := b.get(fmt.Sprintf("/objects?cells=%d", b.cell), &res); err == nil && len(res.Objects) > 0 {
			o := res.Objects[b.rng.IntN(len(res.Objects))]
			if o.Kind == game.KindTree || o.Kind == game.KindFlower {
				f := game.CellFrame(b.w, o.Cell)
				b.target = f.Point(o.X, o.Y)
				b.object = o.ID
				b.action = map[string]string{game.KindTree: "shake", game.KindFlower: "pick"}[o.Kind]
				return
			}
		}
	}
	b.target = b.landNear(*radius)
}

func (b *bot) collect() {
	if err := b.post("/interact", map[string]any{"object": b.object, "action": b.action}, nil); err != nil {
		interactFail.Add(1) // limite do dia (sacudir uma vez) também conta aqui
		return
	}
	interacts.Add(1)
}

func (b *bot) read(ctx context.Context, ws *websocket.Conn) {
	for {
		typ, data, err := ws.Read(ctx)
		if err != nil {
			return
		}
		bytesIn.Add(int64(len(data)))
		if typ == websocket.MessageBinary && len(data) > 0 {
			switch data[0] {
			case realtime.MsgSnapshot:
				snaps.Add(1)
				visibleSum.Add(int64(data[5]))
				visibleN.Add(1)
			case realtime.MsgCorrection:
				corrections.Add(1)
				if _, p, _, err := realtime.DecodeCorrection(data); err == nil {
					b.mu.Lock()
					b.pos = p
					b.target = p
					b.mu.Unlock()
				}
			}
		} else if typ == websocket.MessageText && bytes.Contains(data, []byte(`"t":"chat"`)) {
			chats.Add(1)
		}
	}
}
