class_name HomeIcon
extends RefCounted
## Ícone de casinha (telhado vermelho, parede creme, contorno marrom), desenhado em código:
## usado no mini mapa (polígonos) e no marcador da casa na visão afastada (textura).

const WALL := Color("fff3dc")
const ROOF := Color("e8665a")
const LINE := Color("5b4636")
const DOOR := Color("a8754a")

static var _texture: ImageTexture


## Polígonos da casinha centrada em `c`, com `s` de altura: [contorno, parede, telhado, porta].
static func polygons(c: Vector2, s: float) -> Array:
	var w := s * 0.72
	var roof_y := c.y - s * 0.08
	var body := PackedVector2Array([
		Vector2(c.x - w * 0.42, roof_y), Vector2(c.x + w * 0.42, roof_y),
		Vector2(c.x + w * 0.42, c.y + s * 0.5), Vector2(c.x - w * 0.42, c.y + s * 0.5)])
	var roof := PackedVector2Array([
		Vector2(c.x - w * 0.62, roof_y + s * 0.04), Vector2(c.x, c.y - s * 0.5), Vector2(c.x + w * 0.62, roof_y + s * 0.04)])
	var door := PackedVector2Array([
		Vector2(c.x - w * 0.12, c.y + s * 0.5), Vector2(c.x - w * 0.12, c.y + s * 0.18),
		Vector2(c.x + w * 0.12, c.y + s * 0.18), Vector2(c.x + w * 0.12, c.y + s * 0.5)])
	var outline := PackedVector2Array([
		Vector2(c.x - w * 0.42, c.y + s * 0.5), Vector2(c.x - w * 0.42, roof_y + s * 0.04),
		Vector2(c.x - w * 0.62, roof_y + s * 0.04), Vector2(c.x, c.y - s * 0.5),
		Vector2(c.x + w * 0.62, roof_y + s * 0.04), Vector2(c.x + w * 0.42, roof_y + s * 0.04),
		Vector2(c.x + w * 0.42, c.y + s * 0.5), Vector2(c.x - w * 0.42, c.y + s * 0.5)])
	return [outline, body, roof, door]


## Desenha a casinha num CanvasItem (dentro de um callback de draw).
static func draw(ci: CanvasItem, c: Vector2, s: float, alpha := 1.0) -> void:
	var p := polygons(c, s)
	var a := Color(1, 1, 1, alpha)
	ci.draw_colored_polygon(p[1], WALL * a)
	ci.draw_colored_polygon(p[2], ROOF * a)
	ci.draw_colored_polygon(p[3], DOOR * a)
	var outline: PackedVector2Array = p[0]
	outline.append(outline[0])
	ci.draw_polyline(outline, LINE * a, maxf(1.5, s * 0.08), true)


## Textura 64 × 64 com a casinha (para Sprite3D), feita pixel a pixel uma vez.
static func texture() -> ImageTexture:
	if _texture:
		return _texture
	const N := 64
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var p := polygons(Vector2(N * 0.5, N * 0.5), N * 0.86)
	var layers := [[p[0], LINE, 3.0], [p[1], WALL, 0.0], [p[2], ROOF, 0.0], [p[3], DOOR, 0.0]]
	for y in N:
		for x in N:
			var q := Vector2(x + 0.5, y + 0.5)
			for layer: Array in layers:
				var poly: PackedVector2Array = layer[0]
				var grow: float = layer[2]
				if Geometry2D.is_point_in_polygon(q, poly) or (grow > 0.0 and _near_polygon(q, poly, grow)):
					img.set_pixel(x, y, layer[1])
	_texture = ImageTexture.create_from_image(img)
	return _texture


static func _near_polygon(q: Vector2, poly: PackedVector2Array, d: float) -> bool:
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)) <= d:
			return true
	return false
