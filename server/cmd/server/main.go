// Comando server sobe o servidor do mundo do Goblo.
//
// Configuração (flag ou variável de ambiente):
//
//	-addr       GOBLO_ADDR       endereço HTTP (padrão :8080)
//	-frequency  GOBLO_FREQUENCY  frequência da grade; células = 10·n²+2 (padrão 20)
//	-radius     GOBLO_RADIUS     raio sugerido do planeta (padrão 100)
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
	"github.com/Dustyluc123/goblo/server/internal/httpapi"
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
	flag.Parse()

	start := time.Now()
	geo, err := world.LoadGeography(data.NaturalEarth)
	if err != nil {
		return err
	}
	w, err := world.New(world.Config{Frequency: *freq, Radius: *radius}, geo)
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

	srv := &http.Server{
		Addr:              *addr,
		Handler:           httpapi.NewHandler(w, snap, log),
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
