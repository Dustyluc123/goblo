class_name DecorRng
extends RefCounted
## Gerador de números pseudoaleatórios determinístico (mulberry32) para espalhar a
## decoração. Mesma semente → mesma sequência em qualquer máquina, o que garante que
## todos os jogadores vejam as mesmas árvores. O algoritmo é curto de propósito, para
## ser reproduzido igual no servidor em Go quando a colisão das árvores for autoritativa.
##
## Semente de uma célula: cell_id × 16 + índice da entrada na lista do bioma
## (BiomeStyle.DECOR). Ver docs/decisoes/0011-espalhamento-deterministico.md.

var _state := 0


func _init(seed_value: int) -> void:
	_state = seed_value & 0xFFFFFFFF


## Próximo inteiro sem sinal de 32 bits.
func next_u32() -> int:
	_state = (_state + 0x6D2B79F5) & 0xFFFFFFFF
	var t := _state
	t = _imul(t ^ (t >> 15), t | 1)
	t ^= (t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF
	return (t ^ (t >> 14)) & 0xFFFFFFFF


## Próximo número em [0, 1).
func next_float() -> float:
	return float(next_u32()) / 4294967296.0


## Multiplicação de 32 bits (os 32 bits de baixo do produto), como Math.imul.
static func _imul(a: int, b: int) -> int:
	var lo := (a & 0xFFFF) * b
	var hi := ((a >> 16) & 0xFFFF) * b
	return (lo + ((hi & 0xFFFF) << 16)) & 0xFFFFFFFF
