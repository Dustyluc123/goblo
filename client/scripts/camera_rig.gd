class_name CameraRig
extends Camera3D
## Câmera em terceira pessoa que orbita o personagem, com o "para cima" alinhado à superfície.
##
## O zoom é contínuo (0 = colado no personagem, 1 = planeta inteiro). Perto, a câmera fica
## atrás do personagem; longe, olha para o centro do planeta com o norte para cima e o globo
## gira devagar sozinho. Ao voltar o zoom, a câmera volta para o personagem.

@export var min_distance := 3.5
@export var max_distance := 165.0
@export var zoom_step := 0.06
@export var zoom := 0.18
@export var pitch_degrees := 28.0
@export var mouse_sensitivity := 0.006
@export var key_turn_speed := 2.0
## Velocidade do giro automático do globo na visão afastada (radianos por segundo).
@export var spin_speed := 0.08

var target: Node3D
var planet_radius := 100.0
## Luz que acompanha a câmera, para o lado visível do globo estar sempre iluminado.
var sun: DirectionalLight3D

var _zoom := zoom
var _heading := Vector3.FORWARD  # para onde a câmera olha, no plano tangente
var _spin := 0.0
var _dragging := false


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_zoom = zoom


## Coloca a câmera atrás do personagem, olhando para onde ele olha.
func snap_behind_target() -> void:
	if target:
		_heading = -target.global_basis.z
		_spin = 0.0


## Ajusta o zoom na hora, sem transição (útil para screenshots e testes).
func set_zoom_now(z: float) -> void:
	zoom = clampf(z, 0.0, 1.0)
	_zoom = zoom


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var step := zoom_step * (mb.factor if mb.factor > 0.0 else 1.0)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom = clampf(zoom - step, 0.0, 1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom = clampf(zoom + step, 0.0, 1.0)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_turn(-mm.relative.x * mouse_sensitivity)
		pitch_degrees = clampf(pitch_degrees + mm.relative.y * mouse_sensitivity * 60.0, 5.0, 80.0)
	elif event is InputEventPanGesture:  # trackpad do Mac: dois dedos
		zoom = clampf(zoom + (event as InputEventPanGesture).delta.y * 0.02, 0.0, 1.0)
	elif event is InputEventMagnifyGesture:  # trackpad: pinça
		zoom = clampf(zoom - ((event as InputEventMagnifyGesture).factor - 1.0) * 0.5, 0.0, 1.0)


func _process(delta: float) -> void:
	if target == null or not target.visible:
		return
	_zoom = lerpf(_zoom, zoom, 1.0 - exp(-8.0 * delta))
	var turn := Input.get_axis("camera_right", "camera_left")
	if turn != 0.0:
		_turn(turn * key_turn_speed * delta)

	var player_pos := target.get_global_transform_interpolated().origin
	var up := player_pos.normalized()
	_heading = _tangent(_heading, up)
	if _heading.length() < 0.01:
		_heading = _tangent(-target.global_basis.z, up)
	_heading = _heading.normalized()

	var dist := min_distance * pow(max_distance / min_distance, _zoom)
	var t := smoothstep(0.4, 0.9, _zoom)

	# Perto: atrás e acima do personagem.
	var pitch := deg_to_rad(pitch_degrees)
	var head := player_pos + up * 0.6
	var near_pos := head + (-_heading * cos(pitch) + up * sin(pitch)) * dist
	# Longe: em cima do personagem, olhando para o centro do planeta.
	var far_pos := up * (planet_radius + dist)
	var pos := near_pos.lerp(far_pos, t)
	var look := head.lerp(Vector3.ZERO, t)
	var min_r := planet_radius + 1.5
	if pos.length() < min_r:
		pos = pos.normalized() * min_r

	var north := _tangent(Vector3.UP, up)
	if north.length() < 0.05:
		north = _heading
	var cam_up := up.lerp(north.normalized(), t).normalized()

	# Giro automático na visão afastada: gira tudo em volta do eixo do planeta.
	if t >= 0.999:
		_spin = wrapf(_spin + spin_speed * delta, -PI, PI)
	elif t < 0.05:
		_spin = 0.0
	var spin_now := _spin * smoothstep(0.5, 1.0, t)
	var rot := Basis(Vector3.UP, spin_now)
	pos = rot * pos
	look = rot * look
	cam_up = rot * cam_up

	var dir := (look - pos).normalized()
	if absf(dir.dot(cam_up)) > 0.999:
		cam_up = rot * _heading
	look_at_from_position(pos, look, cam_up)
	far = maxf(2000.0, planet_radius * 6.0)

	if sun:
		# Luz vindo de trás e um pouco acima/à esquerda da câmera.
		sun.global_basis = global_basis * Basis.from_euler(Vector3(deg_to_rad(-30.0), deg_to_rad(25.0), 0.0))


func _turn(angle: float) -> void:
	if target == null:
		return
	var up := target.global_position.normalized()
	_heading = _heading.rotated(up, angle)


static func _tangent(v: Vector3, up: Vector3) -> Vector3:
	return v - up * v.dot(up)
