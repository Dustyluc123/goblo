class_name ItemIcons
extends Node
## Ícones dos itens, desenhados a partir dos próprios modelos 3D numa SubViewport (um por
## quadro, no começo do jogo). Enquanto o ícone não fica pronto, devolve uma bolinha da
## cor do item. Sem janela (testes headless), só as bolinhas.

signal icon_ready(id: String)

const SIZE := 192

var _icons := {}  # id → Texture2D
var _queue: Array = []
var _viewport: SubViewport
var _holder: MeshInstance3D
var _camera: Camera3D
var _busy := false
var _items := {}


func setup(items: Dictionary) -> void:
	_items = items
	if DisplayServer.get_name() == "headless":
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 0.97, 0.92)
	env.environment.ambient_light_energy = 0.75
	_viewport.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 35, 0)
	light.light_energy = 1.1
	_viewport.add_child(light)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_viewport.add_child(_camera)
	_holder = MeshInstance3D.new()
	_viewport.add_child(_holder)
	for id: String in items:
		_queue.append(id)
	_next()


func icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	return _placeholder(id)


func _placeholder(id: String) -> Texture2D:
	var key := "_ph_" + id
	if _icons.has(key):
		return _icons[key]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var c := Color.from_hsv(float(hash(id) % 360) / 360.0, 0.35, 0.9)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length()
			img.set_pixel(x, y, c if d < 12 else Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


func _next() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var id: String = _queue.pop_front()
	var model := str(_items[id].get("model", ""))
	var lib := ModelLibrary.get_model(model)
	if lib.is_empty():
		_busy = false
		_next.call_deferred()
		return
	var aabb: AABB = lib["aabb"]
	_holder.mesh = lib["mesh"]
	_holder.position = -aabb.get_center()
	var radius := aabb.size.length() * 0.5
	var dist := radius / tan(deg_to_rad(_camera.fov * 0.5)) * 1.05
	_camera.look_at_from_position(Vector3(0.9, 0.75, 1.2).normalized() * dist, Vector3.ZERO)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _viewport.get_texture().get_image()
	_icons[id] = ImageTexture.create_from_image(img)
	_busy = false
	icon_ready.emit(id)
	_next()
