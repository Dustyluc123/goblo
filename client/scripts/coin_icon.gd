class_name CoinIcon
extends Control
## Moedinha fofa desenhada em código (dourada, com borda e uma estrelinha no meio), para o
## saldo no HUD e os preços nas janelas.

@export var diameter := 22.0

const GOLD := Color("f6c94b")
const GOLD_DARK := Color("d99a2b")
const SHINE := Color("fff1b8")


func _ready() -> void:
	custom_minimum_size = Vector2(diameter, diameter)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw(self, size * 0.5, diameter)


## Desenha a moeda centrada em `c` (pode ser chamado de qualquer CanvasItem).
static func draw(ci: CanvasItem, c: Vector2, d: float) -> void:
	var r := d * 0.5
	ci.draw_circle(c + Vector2(0, r * 0.12), r, GOLD_DARK)
	ci.draw_circle(c, r, GOLD)
	ci.draw_circle(c, r * 0.72, GOLD_DARK.lerp(GOLD, 0.55))
	ci.draw_circle(c, r * 0.62, GOLD)
	var star := PackedVector2Array()
	for k in 10:
		var a := -PI / 2 + k * PI / 5
		star.append(c + Vector2(cos(a), sin(a)) * (r * (0.42 if k % 2 == 0 else 0.18)))
	ci.draw_colored_polygon(star, GOLD_DARK)
	ci.draw_arc(c + Vector2(-r * 0.25, -r * 0.25), r * 0.45, PI * 1.05, PI * 1.45, 6, SHINE, maxf(1.0, r * 0.14), true)
