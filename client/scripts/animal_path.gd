class_name AnimalPath
extends RefCounted
## Trajeto dos animais: a mesma conta de AnimalAt (server/internal/game/animals.go), para
## todos os jogadores verem o mesmo animal no mesmo lugar sem o servidor simular nada
## (ADR 0032). tests/test_animais.gd confere contra poses calculadas pelo Go.
##
## O GDScript usa inteiros de 64 bits com sinal; as contas de 32 bits do hash são feitas
## em pedaços de 16 bits e cortadas com MASK, para darem exatamente o mesmo resultado.

const MASK := 0xFFFFFFFF
const WALK_SHARE := 0.7
const STATES := ["idle", "eat", "look"]


## a × b com 32 bits (sem estourar os 64 bits com sinal).
static func mul32(a: int, b: int) -> int:
	a &= MASK
	b &= MASK
	var lo := a * (b & 0xFFFF)
	var hi := ((a * (b >> 16)) & 0xFFFF) << 16
	return (lo + hi) & MASK


static func hash32(a: int, b: int, c: int) -> int:
	var x := mul32(a, 0x9E3779B1) ^ mul32(b, 0x85EBCA77) ^ mul32(c, 0xC2B2AE3D)
	x ^= x >> 16
	x = mul32(x, 0x7FEB352D)
	x ^= x >> 15
	x = mul32(x, 0x846CA68B)
	x ^= x >> 16
	return x & MASK


## Pose do animal no instante t (segundos unix do servidor):
## {"x", "y", "heading" (radianos no plano da célula, 0 = leste), "state" (walk, idle, eat, look)}.
static func at(a: Dictionary, t: float) -> Dictionary:
	var pts: Array = a["points"]
	var n := pts.size()
	var id := int(a["id"]) & MASK
	var leg := float(a["leg"])
	var off := float(hash32(id, 0, 1) % 1000) / 1000.0 * leg
	var k := floorf((t + off) / leg)
	var u := t + off - k * leg
	var ki := int(k) & MASK
	var from := hash32(id, (ki - 1) & MASK, 2) % n
	var to := hash32(id, ki, 2) % n
	var p: Array = pts[from]
	var q: Array = pts[to]
	var dx := float(q[0]) - float(p[0])
	var dy := float(q[1]) - float(p[1])
	var dist := sqrt(dx * dx + dy * dy)
	if dist < 0.01:
		var prev: Array = pts[hash32(id, (ki - 2) & MASK, 2) % n]
		var hx := float(p[0]) - float(prev[0])
		var hy := float(p[1]) - float(prev[1])
		var heading := atan2(hy, hx)
		if sqrt(hx * hx + hy * hy) < 0.01:
			heading = float(hash32(id, ki, 4) % 628) / 100.0
		return {"x": float(q[0]), "y": float(q[1]), "heading": heading, "state": STATES[hash32(id, ki, 3) % 3]}
	var heading := atan2(dy, dx)
	var walk := minf(dist / float(a["speed"]), leg * WALK_SHARE)
	if u < walk:
		var s := u / walk
		return {"x": float(p[0]) + dx * s, "y": float(p[1]) + dy * s, "heading": heading, "state": "walk"}
	return {"x": float(q[0]), "y": float(q[1]), "heading": heading, "state": STATES[hash32(id, ki, 3) % 3]}
