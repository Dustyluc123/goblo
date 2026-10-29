package game

import (
	"sync"
	"time"
)

// Clock dá a hora atual. As regras só leem o tempo por aqui, para os testes poderem
// avançar o relógio (virada do dia, obra pronta) sem esperar.
type Clock interface {
	Now() time.Time
}

// RealClock é o relógio do sistema.
type RealClock struct{}

func (RealClock) Now() time.Time { return time.Now() }

// OffsetClock é um relógio (real ou não) com um deslocamento ajustável. O modo dev usa
// para "avançar para o dia seguinte"; os testes usam com uma base fixa.
type OffsetClock struct {
	mu     sync.Mutex
	base   Clock
	offset time.Duration
}

// NewOffsetClock cria um relógio deslocado a partir de base (nil = relógio real).
func NewOffsetClock(base Clock) *OffsetClock {
	if base == nil {
		base = RealClock{}
	}
	return &OffsetClock{base: base}
}

func (c *OffsetClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.base.Now().Add(c.offset)
}

// Advance adianta o relógio.
func (c *OffsetClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.offset += d
}

// FixedClock sempre devolve a mesma hora (testes).
type FixedClock struct{ T time.Time }

func (c FixedClock) Now() time.Time { return c.T }
