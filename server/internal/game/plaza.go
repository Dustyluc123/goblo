package game

import "math"

// Praça central na escala nova (fase 3.6, ADR 0047). A praça é desenhada num sistema próprio
// (u, v): a pista corre ao longo de u, na diagonal do hexágono (de um canto ao canto oposto),
// do lado v < 0; terminal, torre, loja e chafariz ficam do lado v > 0. O ângulo da praça
// (Airport.Rot) é o de um dos cantos da célula no plano dela, escolhido para que tudo caiba
// com folga; nos hexágonos menores a praça inteira encolhe um pouco (Airport.Scale). O cliente (airports.gd) monta o cenário com o mesmo ângulo e os mesmos números.

// Pontos da praça em (u, v), que o servidor confere (balcão e loja).
const (
	plazaCounterU, plazaCounterV = 0.0, 3.6
	plazaShopU, plazaShopV       = -7.6, 3.4
)

// Escala mínima da praça nos hexágonos pequenos e o passo da procura.
const plazaMinScale, plazaScaleStep = 0.75, 0.025

// Pontos que precisam caber no hexágono (u, v, folga até a borda): pontas da pista, cantos
// do terminal, torre, loja, carros e pontas das asas do avião.
var plazaFit = [][3]float64{
	{-8.5, -2.3, 0.3}, {8.5, -2.3, 0.3}, {-8.5, -6.9, 0.3}, {8.5, -6.9, 0.3},
	{-4.0, 8.6, 0.3}, {4.0, 8.6, 0.3}, {6.6, 5.8, 1.0}, {plazaShopU, plazaShopV, 1.0},
	{-8.6, 6.6, 0.3}, {-1.0, -10.3, 0.1}, {8.8, 0.6, 0.5},
}

// rotate leva (u, v) da praça para (x, y) do plano da célula.
func rotate(u, v, rot float64) (float64, float64) {
	s, c := math.Sincos(rot)
	return u*c - v*s, u*s + v*c
}

// plazaFitMargin: a pior folga dos pontos da praça girada `rot` e escalada `scale`.
func plazaFitMargin(f Frame, rot, scale float64) float64 {
	worst := math.Inf(1)
	for _, q := range plazaFit {
		x, y := rotate(q[0]*scale, q[1]*scale, rot)
		worst = math.Min(worst, f.EdgeDistance(x, y)-q[2])
	}
	return worst
}

// plazaLayout escolhe o ângulo da praça (entre as direções dos cantos da célula, a que deixa
// a maior folga até a borda) e a escala: 1, ou um pouco menor nos hexágonos pequenos, até
// plazaMinScale. Determinístico (empate fica com o primeiro canto).
func plazaLayout(f Frame) (rot, scale float64) {
	for scale = 1.0; ; scale -= plazaScaleStep {
		best, bestMargin := 0.0, math.Inf(-1)
		for _, p := range f.Poly {
			r := math.Atan2(p[1], p[0])
			if m := plazaFitMargin(f, r, scale); m > bestMargin {
				best, bestMargin = r, m
			}
		}
		if bestMargin >= 0 || scale-plazaScaleStep < plazaMinScale-1e-9 {
			return best, scale
		}
	}
}

// placePlaza põe o balcão e a loja da praça (aeroporto grande) no plano da célula.
func placePlaza(a *Airport, f Frame) {
	a.Rot, a.Scale = plazaLayout(f)
	a.X, a.Y = rotate(plazaCounterU*a.Scale, plazaCounterV*a.Scale, a.Rot)
	a.ShopX, a.ShopY = rotate(plazaShopU*a.Scale, plazaShopV*a.Scale, a.Rot)
}

// PlazaMargin é a menor folga (unidades) entre os pontos da praça e a borda do hexágono do
// aeroporto; negativa se algo passa da borda. Para os testes.
func (s *Service) PlazaMargin(a Airport) float64 {
	return plazaFitMargin(CellFrame(s.world, a.Cell), a.Rot, a.Scale)
}
