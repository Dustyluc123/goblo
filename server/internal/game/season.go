package game

import (
	"math"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Estações do ano reais (fase 2.5). Vêm da data (UTC) e do hemisfério: no fim de outubro é
// outono no norte e primavera no sul. Entre os trópicos não há estação marcada. A mesma
// conta está em client/scripts/seasons.gd (o cliente usa para o visual).
//
// A "fase" vai de 0 a 4 no hemisfério norte: 0 = começo da primavera (20/3), 1 = verão
// (21/6), 2 = outono (22/9), 3 = inverno (21/12). No sul, soma 2. Perto de cada virada há
// uma faixa de SeasonBlendDays dias em que o visual muda aos poucos.

// Tropic é a latitude dos trópicos (graus).
const Tropic = 23.44

// SeasonBlendDays é a meia largura da transição entre estações (dias).
const SeasonBlendDays = 10.0

// Dia do ano (0 = 1º de janeiro) em que começa cada estação no norte.
var seasonStarts = [4]float64{78.5, 171.5, 264.5, 354.5}

// SeasonNames são as estações na ordem da fase.
var SeasonNames = [4]string{"spring", "summer", "autumn", "winter"}

// NorthPhase é a fase da estação no hemisfério norte no instante t (0 a 4).
func NorthPhase(t time.Time) float64 {
	t = t.UTC()
	start := time.Date(t.Year(), 1, 1, 0, 0, 0, 0, time.UTC)
	doy := t.Sub(start).Hours() / 24
	const year = 365.2422
	for i := 0; i < 4; i++ {
		a := seasonStarts[i]
		b := seasonStarts[(i+1)%4]
		if i == 3 {
			b += year
		}
		d := doy
		if i == 3 && d < a {
			d += year
		}
		if d >= a && d < b {
			return float64(i) + (d-a)/(b-a)
		}
	}
	return 3 + (doy+year-seasonStarts[3])/(seasonStarts[0]+year-seasonStarts[3])
}

// SeasonAt é a estação no instante t e na latitude lat: spring, summer, autumn, winter ou
// "none" (entre os trópicos).
func SeasonAt(t time.Time, lat float64) string {
	if math.Abs(lat) < Tropic {
		return "none"
	}
	p := NorthPhase(t)
	if lat < 0 {
		p = math.Mod(p+2, 4)
	}
	return SeasonNames[int(p)%4]
}

// SeasonFor é a estação de uma célula: só os biomas temperados e frios (floresta, campo,
// tundra e montanha) mudam; floresta tropical, praia, deserto e gelo ficam iguais o ano todo.
func SeasonFor(t time.Time, lat float64, b world.Biome) string {
	switch b {
	case world.BiomeForest, world.BiomeGrassland, world.BiomeTundra, world.BiomeMountain:
		return SeasonAt(t, lat)
	}
	return "none"
}
