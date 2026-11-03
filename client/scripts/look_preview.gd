class_name LookPreview
extends SubViewportContainer
## Prévia do personagem (editor e guarda-roupa; fase 4.0, controles na 4.1). Monta a malha na
## hora (CharacterLook.build_now) sobre o personagem do corpo, numa pose neutra parada (o
## primeiro quadro do repouso, sem andar). Fica de frente e não gira sozinha: arrastar com o
## mouse ou A/D gira; a roda aproxima (do corpo inteiro até o rosto); show_back/show_front
## viram de costas e de frente.

## Graus por segundo com A/D e por pixel arrastado.
const KEY_SPEED := 160.0
const DRAG_SPEED := 0.6
## Distância da câmera: corpo inteiro (0) até o rosto (1).
const FAR := Vector3(0, 0.55, 3.6)
const NEAR := Vector3(0, 0.66, 1.45)
const FAR_LOOK := Vector3(0, 0.5, 0)
const NEAR_LOOK := Vector3(0, 0.62, 0)

var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _model: Node3D
var _body := ""
var _yaw := 0.0  # graus (0 = de frente)
var _target_yaw := 0.0
var _zoom := 0.0
var _dragging := false


func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(280, 360)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 26
	_vp.add_child(_cam)
	_place_camera()
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
	tooltip_text = tr("Arraste ou use A/D para girar · roda para aproximar")
	# Escondida, não desenha (fase 4.1: nada de viewport ligado à toa).
	visibility_changed.connect(func() -> void:
		_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED)


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
		# Do tamanho do personagem do jogo (1 de altura), de frente para a câmera.
		_model.scale = Vector3.ONE / maxf(Player._model_height(_model), 0.01)
		_pivot.add_child(_model)
		_body = body
		# Pose neutra parada: o primeiro quadro do repouso, tocando com velocidade zero (sem
		# andar nem respirar; o "static" do pacote é a pose em T).
		var aps := _model.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			var ap := aps[0] as AnimationPlayer
			ap.play("idle")
			ap.speed_scale = 0.0
	var mesh := CharacterLook.build_now(look, wear)
	CharacterLook.apply(_model, mesh, look, view.get("cape", []) if view.get("cape") is Array else [])


func show_back() -> void:
	_target_yaw = 180.0


func show_front() -> void:
	_target_yaw = 0.0


## De frente e com o corpo inteiro (ao abrir a janela).
func reset_view() -> void:
	_target_yaw = 0.0
	_yaw = 0.0
	_zoom = 0.0
	_place_camera()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging = mb.pressed
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom = clampf(_zoom + 0.12, 0.0, 1.0)
					_place_camera()
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom = clampf(_zoom - 0.12, 0.0, 1.0)
					_place_camera()
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_target_yaw += (event as InputEventMouseMotion).relative.x * DRAG_SPEED
		_yaw = _target_yaw
		accept_event()


func _place_camera() -> void:
	if _cam == null:
		return
	var e := smoothstep(0.0, 1.0, _zoom)
	_cam.position = FAR.lerp(NEAR, e)
	_cam.look_at(FAR_LOOK.lerp(NEAR_LOOK, e))


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _pivot == null:
		return
	# A/D giram (o personagem do jogo não anda com a janela aberta).
	var turn := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		turn -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		turn += 1.0
	if turn != 0.0:
		_target_yaw += turn * KEY_SPEED * delta
		_yaw = _target_yaw
	else:
		_yaw = lerpf(_yaw, _target_yaw, minf(1.0, delta * 8.0))
	_pivot.rotation.y = deg_to_rad(_yaw)
