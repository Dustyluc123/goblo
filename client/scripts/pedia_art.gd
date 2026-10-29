class_name PediaArt
extends Node
## Desenhos das páginas da Goblopédia: cada animal (no meio do "Idle") e cada coisa rara,
## renderizados numa SubViewport, um por quadro, quando o álbum abre pela primeira vez.
## A página não descoberta mostra o mesmo desenho escurecido (silhueta). Sem janela
## (headless), devolve um quadradinho.

signal art_ready(id: String)

const SIZE := 256

var _art := {}  # id → Texture2D
var _queue: Array = []
var _entries := {}  # id → página
var _viewport: SubViewport
var _camera: Camera3D
var _holder: Node3D
var _busy := false
var _scenes := {}
var _species := {}


func setup(entries: Array, animal_scenes: Dictionary, species: Dictionary) -> void:
	for e: Dictionary in entries:
		_entries[str(e["id"])] = e
	_scenes = animal_scenes
	_species = species


func art(id: String) -> Texture2D:
	if _art.has(id):
		return _art[id]
	if DisplayServer.get_name() != "headless" and not _queue.has(id) and _entries.has(id):
		_queue.append(id)
		_next.call_deferred()
	return _placeholder()


func _placeholder() -> Texture2D:
	if _art.has("_ph"):
		return _art["_ph"]
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	_art["_ph"] = tex
	return tex


func _make_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 0.97, 0.92)
	env.environment.ambient_light_energy = 0.8
	_viewport.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	light.light_energy = 1.1
	_viewport.add_child(light)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_viewport.add_child(_camera)


func _next() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	if _viewport == null:
		_make_viewport()
	var id: String = _queue.pop_front()
	var e: Dictionary = _entries[id]
	if _holder:
		_holder.queue_free()
	_holder = Node3D.new()
	_viewport.add_child(_holder)
	var aabb := AABB()
	if str(e["kind"]) == "animal" and _scenes.has(id):
		var model := (_scenes[id] as PackedScene).instantiate() as Node3D
		var s := float(_species[id]["height"]) / maxf(Player._model_height(model), 0.01)
		model.scale = Vector3.ONE * s
		_holder.add_child(model)
		var aps := model.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			(aps[0] as AnimationPlayer).play("Idle")
			(aps[0] as AnimationPlayer).seek(0.4, true)
		var first := true
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var box := mi.global_transform * mi.get_aabb()  # já com a escala do modelo
			aabb = box if first else aabb.merge(box)
			first = false
	else:
		var lib := ModelLibrary.get_model(str(e.get("model", "")))
		if not lib.is_empty():
			var mi := MeshInstance3D.new()
			mi.mesh = lib["mesh"]
			_holder.add_child(mi)
			aabb = lib["aabb"]
	var center := aabb.get_center()
	var radius := maxf(aabb.size.length() * 0.5, 0.1)
	var dist := radius / tan(deg_to_rad(_camera.fov * 0.5)) * 1.02
	_camera.look_at_from_position(center + Vector3(1.0, 0.35, 0.75).normalized() * dist, center)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_art[id] = ImageTexture.create_from_image(_viewport.get_texture().get_image())
	_busy = false
	art_ready.emit(id)
	_next()
