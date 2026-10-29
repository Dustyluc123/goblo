package game

import (
	"math"
	"time"
)

// RolloverHour é a hora local em que o dia do jogo vira (como no Animal Crossing).
const RolloverHour = 5

// localOffsetSeconds é o fuso aproximado pela longitude: 15° = 1 hora. É o mesmo horário
// solar que o cliente mostra no HUD (sem a equação do tempo, que muda poucos minutos).
func localOffsetSeconds(lon float64) int64 {
	return int64(math.Round(lon * 240))
}

// DayIndex é o número do dia do jogo para quem mora na longitude lon: muda às 5h locais.
func DayIndex(t time.Time, lon float64) int64 {
	s := t.Unix() + localOffsetSeconds(lon) - RolloverHour*3600
	return floorDiv(s, 86400)
}

// NextRollover é o instante da próxima virada do dia (5h locais) depois de t.
func NextRollover(t time.Time, lon float64) time.Time {
	day := DayIndex(t, lon)
	return time.Unix((day+1)*86400-localOffsetSeconds(lon)+RolloverHour*3600, 0).UTC()
}

func floorDiv(a, b int64) int64 {
	q := a / b
	if (a%b != 0) && ((a < 0) != (b < 0)) {
		q--
	}
	return q
}
