package game

import (
	"math"
	"regexp"
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

// --- Árvores de estação (fase 4.2, ADR 0053) ------------------------------------------------
// A mesma conta de Seasons.object_variant (client/scripts/seasons.gd): perto de cada virada,
// cada árvore troca de modelo num dia diferente (limiar pelo id). O servidor usa para saber
// se a árvore que o jogador fotografou estava de outono ou com neve na tela dele.

// seasonBlend é a meia largura da transição em unidades de fase (~91 dias por estação).
const seasonBlend = SeasonBlendDays / (365.2422 / 4)

// treeVariantModel: árvores do pacote que têm versão de outono e de neve.
var treeVariantModel = regexp.MustCompile(`^(CommonTree|BirchTree|PineTree|Willow)_\d$`)

func smoothstep(a, b, x float64) float64 {
	t := math.Max(0, math.Min(1, (x-a)/(b-a)))
	return t * t * (3 - 2*t)
}

// SeasonWeight é o peso (0 a 1) da estação s (0 a 3) na fase p, com a mistura nas viradas.
func SeasonWeight(p float64, s int) float64 {
	d := math.Mod(p-float64(s)+2+8, 4) - 2
	return smoothstep(-seasonBlend, seasonBlend, d) * (1 - smoothstep(1-seasonBlend, 1+seasonBlend, d))
}

// hash01 é BiomeStyle.hash01 do cliente: um número de 0 a 1 pelo id.
func hash01(x int64) float64 {
	h := (uint64(x) * 2654435761) & 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF
	h ^= h >> 13
	return float64(h&0xFFFF) / 65535
}

// TreeVariant é a versão da árvore que o cliente desenha no instante t: "autumn", "snow"
// ou "" (a de sempre).
func TreeVariant(o *Object, t time.Time, lat float64, b world.Biome) string {
	if o.Kind != KindTree || !treeVariantModel.MatchString(o.Model) || SeasonFor(t, lat, b) == "none" {
		return ""
	}
	p := NorthPhase(t)
	if lat < 0 {
		p = math.Mod(p+2, 4)
	}
	limit := 0.1 + 0.8*hash01(o.ID)
	if SeasonWeight(p, 3) > limit {
		return "snow"
	}
	if SeasonWeight(p, 2) > limit {
		return "autumn"
	}
	return ""
}
