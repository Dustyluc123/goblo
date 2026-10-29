package game

// rng é um gerador pseudoaleatório pequeno e determinístico (SplitMix64). Mesma semente,
// mesma sequência, em qualquer máquina: é o que deixa os objetos do mundo iguais para todos.
type rng struct{ state uint64 }

func newRNG(seed uint64) *rng { return &rng{state: seed*0x9E3779B97F4A7C15 + 0x632BE59BD9B4E019} }

func (r *rng) next() uint64 {
	r.state += 0x9E3779B97F4A7C15
	z := r.state
	z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
	z = (z ^ (z >> 27)) * 0x94D049BB133111EB
	return z ^ (z >> 31)
}

// float devolve um número em [0, 1).
func (r *rng) float() float64 { return float64(r.next()>>11) / (1 << 53) }

// intn devolve um inteiro em [0, n).
func (r *rng) intn(n int) int { return int(r.next() % uint64(n)) }

// mix junta vários números numa semente.
func mix(parts ...uint64) uint64 {
	h := uint64(0xCBF29CE484222325)
	for _, p := range parts {
		h ^= p
		h *= 0x100000001B3
		h ^= h >> 29
	}
	return h
}
