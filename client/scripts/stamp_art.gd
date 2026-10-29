class_name StampArt
extends Control
## Carimbo de um país no passaporte, desenhado em código. Forma (círculo, oval, retângulo
## arredondado, hexágono, estrela ou escudo), cor, borda dupla ou pontilhada, enfeite no
## meio e um leve giro saem de um sorteio pelo código do país: cada país tem o seu, sempre
## igual. Mostra o nome do país e a data da primeira visita.

const SIZE := Vector2(190, 150)
const INKS := [Color("c0392b"), Color("2e6da4"), Color("2f8a5b"), Color("8e44ad"), Color("d35400"), Color("16a085"), Color("b03a6f"), Color("5d4e9c")]

var code := ""
var country_name := ""
var date := ""


func _ready() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _rand(k: int) -> float:
	return float(hash(code + str(k)) % 10000) / 10000.0


func _draw() -> void:
	var c := size * 0.5
	var ink: Color = INKS[int(_rand(1) * INKS.size()) % INKS.size()]
	ink.a = 0.88
	var shape := int(_rand(2) * 6.0)
	var tilt := (_rand(3) - 0.5) * 0.35
	draw_set_transform(c, tilt, Vector2.ONE)
	var r := minf(SIZE.x, SIZE.y) * 0.44
	var outline := _outline(shape, r)
	var inner := _outline(shape, r * 0.84)
	var dotted := _rand(4) > 0.5
	_poly(outline, ink, 3.0, false)
	_poly(inner, ink, 1.6, dotted)
	# Enfeite no alto: estrelinhas, ondas ou um aviãozinho.
	match int(_rand(5) * 3.0):
		0:
			for k in 3:
				_star(Vector2((k - 1) * 18.0, -r * 0.52), 6.0, ink)
		1:
			for k in 2:
				var y := -r * 0.55 + k * 6.0
				var pts := PackedVector2Array()
				for i in 13:
					pts.append(Vector2(-30 + i * 5.0, y + sin(i * 1.2) * 2.5))
				draw_polyline(pts, ink, 1.5, true)
		_:
			var plane := Airports.plane_polygon(Vector2(0, -r * 0.5), 20.0)
			draw_colored_polygon(plane, ink)
	var font := ThemeDB.fallback_font
	var title := country_name.to_upper()
	var fs := 17 if title.length() <= 12 else (13 if title.length() <= 18 else 10)
	draw_string(font, Vector2(-r * 1.05, 4), title, HORIZONTAL_ALIGNMENT_CENTER, r * 2.1, fs, ink)
	draw_string(font, Vector2(-r, r * 0.42), date, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 13, ink)
	draw_string(font, Vector2(-r, r * 0.66), code, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 11, ink)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _outline(shape: int, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match shape:
		0:  # círculo
			for i in 40:
				pts.append(Vector2.from_angle(i * TAU / 40.0) * r)
		1:  # oval
			for i in 40:
				var a := i * TAU / 40.0
				pts.append(Vector2(cos(a) * r * 1.25, sin(a) * r * 0.8))
		2:  # retângulo arredondado
			var w := r * 1.2
			var h := r * 0.8
			var k := r * 0.25
			for corner: Array in [[w - k, -h + k, -PI / 2], [w - k, h - k, 0.0], [-w + k, h - k, PI / 2], [-w + k, -h + k, PI]]:
				for i in 6:
					var a: float = corner[2] + i * (PI / 2) / 5.0
					pts.append(Vector2(corner[0], corner[1]) + Vector2.from_angle(a) * k)
		3:  # hexágono
			for i in 6:
				pts.append(Vector2.from_angle(i * TAU / 6.0) * r * 1.1)
		4:  # estrela de muitas pontas (selo)
			for i in 32:
				pts.append(Vector2.from_angle(i * TAU / 32.0) * r * (1.05 if i % 2 == 0 else 0.92))
		_:  # escudo
			pts.append_array([Vector2(-r, -r * 0.8), Vector2(r, -r * 0.8), Vector2(r, r * 0.1), Vector2(0, r), Vector2(-r, r * 0.1)])
	return pts


func _poly(pts: PackedVector2Array, ink: Color, width: float, dotted: bool) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	if not dotted:
		draw_polyline(closed, ink, width, true)
		return
	for i in closed.size() - 1:
		if i % 2 == 0:
			draw_line(closed[i], closed[i + 1], ink, width, true)


func _star(p: Vector2, r: float, ink: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		pts.append(p + Vector2.from_angle(-PI / 2 + k * PI / 5) * (r if k % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, ink)
