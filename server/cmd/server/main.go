// Comando server sobe o servidor do Goblo: o mundo e as regras do jogo.
//
// Configuração (flag ou variável de ambiente):
//
//	-addr       GOBLO_ADDR       endereço HTTP (padrão :8080)
//	-frequency  GOBLO_FREQUENCY  frequência da grade; células = 10·n²+2 (padrão 50)
//	-radius     GOBLO_RADIUS     raio sugerido do planeta (padrão 1000)
//	-db         GOBLO_DB         arquivo do banco SQLite (padrão goblo.db)
//	-geoip      GOBLO_GEOIP      base IP → país da DB-IP (padrão data/raw/dbip-country-lite.csv.gz)
//	            GOBLO_DEV=1      liga o modo desenvolvedor (rotas /dev/…)
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/Dustyluc123/goblo/server/data"
	"github.com/Dustyluc123/goblo/server/internal/game"
	"github.com/Dustyluc123/goblo/server/internal/geoip"
	"github.com/Dustyluc123/goblo/server/internal/httpapi"
	"github.com/Dustyluc123/goblo/server/internal/store/sqlitestore"
	"github.com/Dustyluc123/goblo/server/internal/world"
)

func main() {
	log := slog.New(slog.NewTextHandler(os.Stdout, nil))
	if err := run(log); err != nil {
		log.Error("servidor parou", "erro", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	addr := flag.String("addr", env("GOBLO_ADDR", ":8080"), "endereço HTTP")
	freq := flag.Int("frequency", envInt("GOBLO_FREQUENCY", world.DefaultConfig.Frequency), "frequência da grade (células = 10·n²+2)")
	radius := flag.Float64("radius", envFloat("GOBLO_RADIUS", world.DefaultConfig.Radius), "raio sugerido do planeta")
	dbPath := flag.String("db", env("GOBLO_DB", "goblo.db"), "arquivo do banco SQLite")
	geoPath := flag.String("geoip", env("GOBLO_GEOIP", "data/raw/dbip-country-lite.csv.gz"), "base IP → país (CSV da DB-IP)")
	flag.Parse()
	dev := os.Getenv("GOBLO_DEV") == "1"

	start := time.Now()
	geoData, err := world.LoadGeography(data.NaturalEarth)
	if err != nil {
		return err
	}
	w, err := world.New(world.Config{Frequency: *freq, Radius: *radius}, geoData)
	if err != nil {
		return err
	}
	snap, err := w.Snapshot()
	if err != nil {
		return err
	}
	log.Info("mundo gerado", "versão", w.Version, "frequência", w.Frequency, "células", len(w.Cells),
		"raio", w.Radius, "oceano", fmt.Sprintf("%.1f%%", 100*w.OceanRatio()), "países", len(w.Countries),
		"bin_kb", len(snap.Binary)/1024, "bin_gzip_kb", len(snap.BinaryGzip)/1024,
		"json_kb", len(snap.JSON)/1024, "json_gzip_kb", len(snap.JSONGzip)/1024,
		"tempo", time.Since(start).Round(time.Millisecond))
	counts := w.BiomeCounts()
	attrs := make([]any, 0, 2*len(world.BiomeNames))
	for i, name := range world.BiomeNames {
		attrs = append(attrs, name, counts[world.Biome(i)])
	}
	log.Info("biomas", attrs...)

	content, err := game.LoadContent(data.Game)
	if err != nil {
		return err
	}
	ctx0 := context.Background()
	store, err := sqlitestore.Open(ctx0, *dbPath)
	if err != nil {
		return fmt.Errorf("banco %s: %w", *dbPath, err)
	}
	defer store.Close()
	schema, _ := store.SchemaVersion(ctx0)
	log.Info("banco aberto", "arquivo", *dbPath, "migração", schema)

	var geo *geoip.DB
	if g, err := geoip.LoadFile(*geoPath); err == nil {
		geo = g
		log.Info("base de IP carregada", "faixas", g.Ranges(), "crédito", geoip.Attribution)
	} else {
		log.Warn("sem base de IP: o país vem só do idioma do sistema (rode ./scripts/baixar-dados.sh)", "arquivo", *geoPath)
	}
	a2 := map[string]string{}
	for _, c := range geoData.Countries {
		if c.A2 != "" {
			a2[c.A2] = c.Code
		}
	}

	var clock game.Clock = game.RealClock{}
	if dev {
		clock = game.NewOffsetClock(nil) // o modo dev pode adiantar o relógio ("dia seguinte")
		log.Warn("MODO DEV LIGADO: rotas /dev/… liberadas (não use em produção)")
	}
	svc := game.NewService(w, content, store, clock)
	svc.SetGeography(geoData)
	if list, err := svc.BorderLots(ctx0); err == nil && len(list) > 0 {
		crossing := 0
		for _, b := range list {
			if b.Crossing {
				crossing++
			}
		}
		log.Info("lotes antigos perto de fronteira (contam como país do dono; F1 → Mundo pode mudá-los)",
			"total", len(list), "cruzando", crossing)
	}
	api := &httpapi.Server{
		World: w, Geo: geoData, Snapshot: snap, Game: svc,
		GeoIP: geo, A2ToA3: a2, Dev: dev, Log: log,
	}
	srv := &http.Server{
		Addr:              *addr,
		Handler:           api.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	errc := make(chan error, 1)
	go func() {
		log.Info("servidor no ar", "endereço", *addr)
		errc <- srv.ListenAndServe()
	}()
	select {
	case err := <-errc:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
	case <-ctx.Done():
		log.Info("desligando")
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		return srv.Shutdown(shutdown)
	}
	return nil
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	if v, err := strconv.Atoi(os.Getenv(key)); err == nil {
		return v
	}
	return def
}

func envFloat(key string, def float64) float64 {
	if v, err := strconv.ParseFloat(os.Getenv(key), 64); err == nil {
		return v
	}
	return def
}
