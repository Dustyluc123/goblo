class_name CoinIcon
extends Control
## O gobolar (G$), o dinheiro do Goblo: moedinha low-poly fofa (um octógono facetado, mais
## claro em cima e mais escuro embaixo, como as peças dos pacotes) com um "G" gravado. Para o
## saldo no HUD e os preços nas janelas e na loja.

@export var diameter := 22.0

const GOLD := Color("f6c94b")
const GOLD_DARK := Color("d99a2b")
const GOLD_DEEP := Color("b8791f")
const SHINE := Color("fff1b8")


func _ready() -> void:
	custom_minimum_size = Vector2(diameter, diameter)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw(self, size * 0.5, diameter)


## Desenha o gobolar centrado em `c` (pode ser chamado de qualquer CanvasItem).
static func draw(ci: CanvasItem, c: Vector2, d: float) -> void:
	var r := d * 0.5
	var sides := 8
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for k in sides:
		var a := -PI / 2 + PI / sides + k * TAU / sides
		outer.append(c + Vector2(cos(a), sin(a)) * r)
		inner.append(c + Vector2(cos(a), sin(a)) * r * 0.74)
	# Espessura (a borda de baixo, mais escura).
	var rim := PackedVector2Array()
	for p in outer:
		rim.append(p + Vector2(0, r * 0.14))
	ci.draw_colored_polygon(rim, GOLD_DEEP)
	# Facetas da borda: claras em cima à esquerda, escuras embaixo à direita.
	for k in sides:
		var k2 := (k + 1) % sides
		var mid := ((outer[k] + outer[k2]) * 0.5 - c).normalized()
		var light := clampf(0.5 - mid.dot(Vector2(0.6, 0.8)) * 0.5, 0.0, 1.0)
		ci.draw_colored_polygon(PackedVector2Array([outer[k], outer[k2], inner[k2], inner[k]]), GOLD_DARK.lerp(SHINE, light * 0.7))
	ci.draw_colored_polygon(inner, GOLD)
	# O "G": um arco aberto à direita com a perninha para dentro.
	var w := maxf(1.2, r * 0.17)
	ci.draw_arc(c, r * 0.4, deg_to_rad(20), deg_to_rad(330), 12, GOLD_DEEP, w, true)
	ci.draw_line(c + Vector2(r * 0.05, r * 0.02), c + Vector2(r * 0.4, r * 0.02), GOLD_DEEP, w, true)
	ci.draw_line(c + Vector2(r * 0.4, r * 0.02), c + Vector2(r * 0.4, r * 0.18), GOLD_DEEP, w, true)
	# Brilho.
	ci.draw_line(c + Vector2(-r * 0.55, -r * 0.2), c + Vector2(-r * 0.3, -r * 0.5), SHINE, maxf(1.0, r * 0.12), true)
