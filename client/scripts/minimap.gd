class_name Minimap
extends Control
## Mini mapa: um globinho no canto da tela, sempre virado para a posição do jogador (com o
## norte para cima), com uma setinha marcando onde ele está e para onde está virado, uma
## casinha no lote dele e a linha dia/noite. Seta e casinha são desenhadas em 2D por cima.
## Fica num SubViewport com mundo 3D próprio, então não interfere na cena principal.
## O SubViewport renderiza na resolução real da tela (não na base 1280 × 720), para o
## globinho ficar nítido em tela Retina; um TextureRect mostra o resultado.

const SIZE := 210
const TEX_W := 512
const TEX_H := 256
const SHADER := preload("res://shaders/minimap_globe.gdshader")

var _viewport: SubViewport
var _view: TextureRect
var _globe: MeshInstance3D
var _material: ShaderMaterial
var _cam: Camera3D
var _overlay: Control
## Direção do jogador no mapa (radianos a partir do norte, sentido horário).
var _heading := 0.0
## Direção da casa (vetor unitário do centro do planeta); ZERO = sem casa.
var _home := Vector3.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	# Renderiza só 10 vezes por segundo (o globinho muda devagar).
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	_view = TextureRect.new()
	_view.texture = _viewport.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_resize_viewport()
	get_viewport().size_changed.connect(_resize_viewport)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 3.4)
	cam.fov = 38.0
	_viewport.add_child(cam)
	_cam = cam

	_material = ShaderMaterial.new()
	_material.shader = SHADER
	var sphere := SphereMesh.new()
	sphere.radial_segments = 64
	sphere.rings = 32
	sphere.radius = 1.0
	sphere.height = 2.0
	_globe = MeshInstance3D.new()
	_globe.mesh = sphere
	_globe.material_override = _material
	_viewport.add_child(_globe)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


## Casinha (onde fica o lote) e setinha do jogador, por cima do globinho.
func _draw_overlay() -> void:
	var size := _overlay.size
	var center := size * 0.5
	if _home != Vector3.ZERO and _globe:
		var p := _globe.basis * _home  # posição no globinho (raio 1)
		var vp := Vector2(_viewport.size)
		var screen := _cam.unproject_position(p) / vp * size
		var front := p.z > 0.0
		if not front:
			# Do outro lado do planeta: casinha clarinha na borda, na direção dela.
			var dir := Vector2(p.x, -p.y)
			dir = dir.normalized() if dir.length() > 0.001 else Vector2.UP
			screen = center + dir * size.x * 0.37
		HomeIcon.draw(_overlay, screen + Vector2(0, -2), 22.0, 1.0 if front else 0.55)
	# Setinha: ponta para onde o jogador está virado (norte = para cima).
	var fwd := Vector2(sin(_heading), -cos(_heading))
	var side := Vector2(-fwd.y, fwd.x)
	var tip := center + fwd * 11.0
	var pts := PackedVector2Array([tip, center - fwd * 7.0 + side * 8.0, center - fwd * 3.0, center - fwd * 7.0 - side * 8.0])
	var outline := pts.duplicate()
	outline.append(pts[0])
	_overlay.draw_colored_polygon(pts, Color("ff5a72"))
	_overlay.draw_polyline(outline, Color.WHITE, 2.5, true)


## Tamanho do SubViewport em pixels de verdade (tamanho na tela × escala da interface).
func _resize_viewport() -> void:
	var px := get_global_transform_with_canvas().get_scale().x * get_viewport().get_final_transform().get_scale().x
	var side := int(clampf(SIZE * maxf(px, 1.0), SIZE, 1024))
	_viewport.size = Vector2i(side, side)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Fase da estação no hemisfério norte (Seasons): o globinho mostra a diferença entre os
## hemisférios.
func set_season(north: float) -> void:
	_material.set_shader_parameter("season_phase", north)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Pinta a textura do mapa a partir do mundo (uma vez, ao carregar).
func build(world: WorldData) -> void:
	# Alfa = o bioma muda com as estações (o shader do globinho mistura as cores).
	var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	var hint := 0
	for py in TEX_H:
		var lat := 90.0 - (py + 0.5) / TEX_H * 180.0
		for px in TEX_W:
			var lon := (px + 0.5) / TEX_W * 360.0 - 180.0
			hint = world.find_cell(WorldData.lat_lon_to_vec(lat, lon), hint)
			var b: int = world.biomes[hint]
			var col: Color = BiomeStyle.COLORS[b]
			if b == WorldData.Biome.OCEAN:
				col = Color("9bd6e6").lerp(Color("3f7fb8"), clampf(float(world.water_depth[hint]) / 4.0, 0.0, 1.0))
			col.a = 1.0 if BiomeStyle.seasonal_ground(world, hint) else 0.0
			img.set_pixel(px, py, col)
	_material.set_shader_parameter("map", ImageTexture.create_from_image(img))


var _since_render := 1.0


## Lote do jogador (direção a partir do centro do planeta); ZERO esconde a casinha.
func set_home(dir: Vector3) -> void:
	_home = dir.normalized() if dir != Vector3.ZERO else Vector3.ZERO
	_overlay.queue_redraw()


## Ângulo da setinha: radianos a partir do norte, no sentido horário (leste = +90°),
## para quem está em `up` olhando para `facing`.
static func heading(up: Vector3, facing: Vector3) -> float:
	var n := Vector3.UP - up * up.y
	n = n.normalized() if n.length() > 0.01 else Vector3.FORWARD
	var e := n.cross(up)  # leste (norte × cima)
	return atan2(facing.dot(e), facing.dot(n))


## Gira o globinho para o ponto `up` (direção do jogador) ficar de frente, com o norte para
## cima; `facing` é para onde o jogador olha (vira a setinha).
func update_view(up: Vector3, sun_dir: Vector3, facing := Vector3.ZERO) -> void:
	if facing != Vector3.ZERO:
		var h := heading(up, facing)
		if absf(angle_difference(h, _heading)) > 0.02:
			_heading = h
			_overlay.queue_redraw()
	_since_render += get_process_delta_time()
	if _since_render < 0.1:
		return
	_since_render = 0.0
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var north := Vector3.UP - up * up.y
	if north.length() < 0.01:
		north = Vector3.FORWARD
	north = north.normalized()
	var x := north.cross(up)
	_globe.basis = Basis(x, north, up).transposed()
	_overlay.queue_redraw()
	_material.set_shader_parameter("sun_dir", sun_dir)
