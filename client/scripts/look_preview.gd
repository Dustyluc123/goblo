class_name LookPreview
extends SubViewportContainer
## Prévia do personagem girando devagar (editor e guarda-roupa, fase 4.0). Monta a malha na
## hora (CharacterLook.build_now) sobre o personagem do corpo e toca a animação parado.

var _vp: SubViewport
var _pivot: Node3D
var _model: Node3D
var _body := ""


func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(260, 320)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.5, 2.0)
	cam.fov = 32
	_vp.add_child(cam)
	cam.look_at(Vector3(0, 0.42, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	_vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.environment.ambient_light_energy = 0.7
	_vp.add_child(env)


## Mostra o visual (LookView: look, wear, cape).
func show_look(view: Dictionary) -> void:
	var look: Dictionary = view.get("look", {})
	var wear: Dictionary = view.get("wear", {}) if view.get("wear") is Dictionary else {}
	var body := str(look.get("body", "male-a"))
	if _model == null or body != _body:
		if _model:
			_model.queue_free()
		var sc := load("res://assets/kenney/mini-characters/character-%s.glb" % body) as PackedScene
		if sc == null:
			return
		_model = sc.instantiate() as Node3D
		_pivot.add_child(_model)
		_body = body
		var aps := _model.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			var ap := aps[0] as AnimationPlayer
			ap.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
			ap.play("idle")
	var mesh := CharacterLook.build_now(look, wear)
	CharacterLook.apply(_model, mesh, look, view.get("cape", []) if view.get("cape") is Array else [])


func _process(delta: float) -> void:
	if is_visible_in_tree() and _pivot:
		_pivot.rotation.y += delta * 0.6
