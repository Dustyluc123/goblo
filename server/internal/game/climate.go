package game

import (
	"fmt"
	"math"
	"time"

	"github.com/Dustyluc123/goblo/server/internal/world"
)

// Clima (fase 4.0, ADR 0050). A temperatura do ar sai de quatro coisas: latitude (equador
// quente, polos frios), estação do hemisfério, altura e bioma da célula e hora local (pela
// longitude). São contas fofas e coerentes, não um modelo do tempo de verdade: Manaus fica
// quente o ano todo, a Patagônia fria, o Saara muito quente de dia e frio de madrugada, a
// Antártida sempre gelada. Os números ficam em body.json → climate.

// ClimateRules é body.json → climate.
type ClimateRules struct {
	Equator          float64                 `json:"equator"`
	PoleDrop         float64                 `json:"pole_drop"`
	LatCurve         float64                 `json:"lat_curve"`
	SeasonAmp        float64                 `json:"season_amp"`
	SeasonAmpTropics float64                 `json:"season_amp_tropics"`
	SummerPeakDay    float64                 `json:"summer_peak_day"`
	DailyPeakHour    float64                 `json:"daily_peak_hour"`
	HeightLapse      float64                 `json:"height_lapse"`
	BaseHeight       float64                 `json:"base_height"`
	Biomes           map[string]BiomeClimate `json:"biomes"`
}

// BiomeClimate: graus a mais do bioma e a amplitude entre o dia e a noite.
type BiomeClimate struct {
	Offset float64 `json:"offset"`
	Daily  float64 `json:"daily"`
}

func (r *ClimateRules) check() error {
	if r.LatCurve <= 0 {
		return fmt.Errorf("body.json: climate.lat_curve precisa ser > 0")
	}
	for _, b := range world.BiomeNames {
		if _, ok := r.Biomes[b]; !ok {
			return fmt.Errorf("body.json: climate.biomes sem o bioma %s", b)
		}
	}
	return nil
}

// AirTemperature é a temperatura do ar (°C) num ponto de latitude lat e longitude lon, numa
// célula de bioma b e altura h (acima do nível do mar), no instante t.
func (r *ClimateRules) AirTemperature(lat, lon float64, b world.Biome, h float64, t time.Time) float64 {
	t = t.UTC()
	a := math.Abs(lat) / 90
	temp := r.Equator + r.PoleDrop*math.Pow(a, r.LatCurve)
	// Estação: pico do verão no dia summer_peak_day no norte e meio ano depois no sul.
	amp := r.SeasonAmpTropics + (r.SeasonAmp-r.SeasonAmpTropics)*math.Sin(math.Abs(lat)*math.Pi/180)
	peak := r.SummerPeakDay
	if lat < 0 {
		peak += 365.2422 / 2
	}
	doy := float64(t.YearDay()-1) + float64(t.Hour())/24
	temp += amp * math.Cos(2*math.Pi*(doy-peak)/365.2422)
	// Hora local pela longitude: mais quente às daily_peak_hour, mais frio de madrugada.
	hour := math.Mod(float64(t.Hour())+float64(t.Minute())/60+lon/15+48, 24)
	bc := r.Biomes[b.String()]
	temp += bc.Daily * math.Cos(2*math.Pi*(hour-r.DailyPeakHour)/24)
	temp += bc.Offset + r.HeightLapse*math.Max(0, h-r.BaseHeight)
	return temp
}

// CellTemperature é a temperatura do ar no centro de uma célula.
func (s *Service) CellTemperature(cell int, t time.Time) float64 {
	c := &s.world.Cells[cell]
	h := c.Height
	if c.Terrain != world.Land {
		h = 0
	}
	return s.content.Body.Climate.AirTemperature(c.Lat, c.Lon, c.Biome, h, t)
}

// TemperatureAt é a temperatura do ar numa latitude e longitude (a célula de centro mais
// perto dá o bioma e a altura).
func (s *Service) TemperatureAt(lat, lon float64, t time.Time) (float64, int) {
	c := s.world.CellAt(lat, lon)
	cell := c.ID
	h := c.Height
	if c.Terrain != world.Land {
		h = 0
	}
	return s.content.Body.Climate.AirTemperature(lat, lon, c.Biome, h, t), cell
}
