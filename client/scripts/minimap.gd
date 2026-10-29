class_name Minimap
extends Control
## Mini mapa: um globinho no canto da tela, sempre virado para a posição do jogador (com o
## norte para cima), com um ponto marcando onde ele está e a linha dia/noite.
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

	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.albedo_color = Color("ff5a72")
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.045
	dot_mesh.height = 0.09
	dot_mesh.material = dot_mat
	var dot := MeshInstance3D.new()
	dot.mesh = dot_mesh
	dot.position = Vector3(0, 0, 1.02)
	_viewport.add_child(dot)
	var ring_mat := dot_mat.duplicate() as StandardMaterial3D
	ring_mat.albedo_color = Color.WHITE
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.055
	ring_mesh.outer_radius = 0.075
	ring_mesh.material = ring_mat
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.position = Vector3(0, 0, 1.03)
	ring.rotation.x = PI / 2
	_viewport.add_child(ring)


## Tamanho do SubViewport em pixels de verdade (tamanho na tela × escala da interface).
func _resize_viewport() -> void:
	var px := get_global_transform_with_canvas().get_scale().x * get_viewport().get_final_transform().get_scale().x
	var side := int(clampf(SIZE * maxf(px, 1.0), SIZE, 1024))
	_viewport.size = Vector2i(side, side)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Pinta a textura do mapa a partir do mundo (uma vez, ao carregar).
func build(world: WorldData) -> void:
	var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGB8)
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
			img.set_pixel(px, py, col)
	_material.set_shader_parameter("map", ImageTexture.create_from_image(img))


var _since_render := 1.0


## Gira o globinho para o ponto `up` (direção do jogador) ficar de frente, com o norte para cima.
func update_view(up: Vector3, sun_dir: Vector3) -> void:
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
	_material.set_shader_parameter("sun_dir", sun_dir)
