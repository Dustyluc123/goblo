class_name Compass
extends Control
## Bússola no topo da tela: mostra N, L, S, O (e intermediários) em relação à direção
## para onde a câmera olha, no lugar onde o personagem está.

const WIDTH := 380.0
const HEIGHT := 34.0
const SPAN := 180.0  # graus visíveis na faixa
const LABELS := {0: "N", 45: "NE", 90: "L", 135: "SE", 180: "S", 225: "SO", 270: "O", 315: "NO"}

## Para onde a câmera olha, em graus a partir do norte, no sentido horário.
var heading := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Calcula o rumo a partir da base da câmera e do "para cima" do personagem.
func update_from(camera_basis: Basis, up: Vector3) -> void:
	var north := Vector3.UP - up * up.y
	if north.length() < 0.01:  # bem no polo: qualquer direção serve
		north = Vector3.FORWARD - up * up.dot(Vector3.FORWARD)
	north = north.normalized()
	var east := north.cross(up)
	var fwd := -camera_basis.z
	fwd -= up * fwd.dot(up)
	if fwd.length() < 0.05:
		fwd = camera_basis.y - up * camera_basis.y.dot(up)
	heading = fposmod(rad_to_deg(atan2(fwd.dot(east), fwd.dot(north))), 360.0)
	queue_redraw()


func _draw() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 0.99, 0.97, 0.85)
	bg.set_corner_radius_all(12)
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	var font := get_theme_default_font()
	var ink := Color("3b3f5c")
	for deg in range(0, 360, 15):
		var rel := wrapf(float(deg) - heading, -180.0, 180.0)
		if absf(rel) > SPAN * 0.5:
			continue
		var x := WIDTH * 0.5 + rel / SPAN * WIDTH
		var fade := 1.0 - absf(rel) / (SPAN * 0.5)
		if LABELS.has(deg):
			var text: String = LABELS[deg]
			var fs := 18 if deg % 90 == 0 else 13
			var col := Color("e0566b") if deg == 0 else ink
			col.a = 0.35 + 0.65 * fade
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(x - w * 0.5, HEIGHT * 0.5 + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		else:
			draw_line(Vector2(x, HEIGHT * 0.38), Vector2(x, HEIGHT * 0.62), Color(ink, 0.3 * fade), 1.5)
	var c := WIDTH * 0.5
	draw_colored_polygon(PackedVector2Array([Vector2(c - 6, 0), Vector2(c + 6, 0), Vector2(c, 7)]), Color("e0566b"))
