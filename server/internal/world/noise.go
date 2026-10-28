package world

import "math"

// noise3 é um ruído de valor 3D determinístico, entre 0 e 1. Serve para espalhar colinas
// e dunas em manchas em vez de células soltas. Não depende de nenhum estado global.
func noise3(p Vec3) float64 {
	x0, y0, z0 := math.Floor(p.X), math.Floor(p.Y), math.Floor(p.Z)
	fx, fy, fz := smooth(p.X-x0), smooth(p.Y-y0), smooth(p.Z-z0)
	ix, iy, iz := int64(x0), int64(y0), int64(z0)
	lerp := func(a, b, t float64) float64 { return a + (b-a)*t }
	c := func(dx, dy, dz int64) float64 { return latticeValue(ix+dx, iy+dy, iz+dz) }
	x00 := lerp(c(0, 0, 0), c(1, 0, 0), fx)
	x10 := lerp(c(0, 1, 0), c(1, 1, 0), fx)
	x01 := lerp(c(0, 0, 1), c(1, 0, 1), fx)
	x11 := lerp(c(0, 1, 1), c(1, 1, 1), fx)
	return lerp(lerp(x00, x10, fy), lerp(x01, x11, fy), fz)
}

func smooth(t float64) float64 { return t * t * (3 - 2*t) }

// latticeValue sorteia um valor em [0, 1) para um ponto inteiro (hash splitmix64).
func latticeValue(x, y, z int64) float64 {
	h := uint64(x)*0x9E3779B97F4A7C15 ^ uint64(y)*0xC2B2AE3D27D4EB4F ^ uint64(z)*0x165667B19E3779F9
	h ^= h >> 30
	h *= 0xBF58476D1CE4E5B9
	h ^= h >> 27
	h *= 0x94D049BB133111EB
	h ^= h >> 31
	return float64(h>>11) / float64(1<<53)
}
