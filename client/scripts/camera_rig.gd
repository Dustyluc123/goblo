class_name CameraRig
extends Camera3D
## Câmera em terceira pessoa que orbita o personagem, com o "para cima" alinhado à superfície.
##
## O zoom é contínuo (0 = colado no personagem, 1 = planeta inteiro). Perto, a câmera fica
## atrás do personagem; longe, olha para o centro do planeta com o norte para cima e o globo
## gira devagar sozinho. Ao voltar o zoom, a câmera volta para o personagem.
##
## As distâncias acompanham o raio do planeta (GameConfig), e near/far mudam com o zoom
## para manter a precisão de profundidade de 3 unidades a 1.650.
##
## Distância e ângulo só mudam quando o jogador mexe (mouse e zoom): nada de aproximar ou
## subir sozinha por causa de obstáculos. O que fica entre a câmera e o personagem fica
## semitransparente (CameraOcclusion). A única exceção é o chão: se o ângulo levaria a
## câmera para dentro do terreno, ela sobe o mínimo necessário, com suavidade.

@export var min_distance := GameConfig.CAMERA_MIN_DISTANCE
@export var max_distance := 1650.0
@export var zoom_step := 0.05
@export var zoom := 0.18
@export var pitch_degrees := 28.0
## Radianos por pixel de mouse (multiplicado pela sensibilidade das configurações).
@export var mouse_sensitivity := 0.006
## Velocidade do giro automático do globo na visão afastada (radianos por segundo).
@export var spin_speed := 0.08

var target: Node3D
## Gerenciador da interface: eventos que pertencem a ela não mexem na câmera.
var ui: GameUi
var planet_radius := 1000.0
## Mundo, para a câmera não entrar no chão (montanhas).
var world: WorldData
## 0 = câmera no personagem, 1 = planeta inteiro. Usado por céu, nuvens e vegetação.
var far_amount := 0.0
## Distância atual da câmera ao personagem.
var distance := 0.0

var _zoom := zoom
var _heading := Vector3.FORWARD  # para onde a câmera olha, no plano tangente
var _spin := 0.0
var _dragging := false
var _cam_cell := -1
## Limites do ângulo vertical (graus acima do horizonte).
const MIN_PITCH := 5.0
const MAX_PITCH := 80.0
## Altura mínima da câmera acima do chão.
const GROUND_CLEARANCE := 0.45
## Inclinação extra atual (graus) para a câmera não entrar no terreno (morros).
var _ground_pitch := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_zoom = zoom


## Ajusta as distâncias para um planeta de raio `r`.
func set_planet_radius(r: float) -> void:
	planet_radius = r
	max_distance = r * GameConfig.CAMERA_MAX_DISTANCE_RADII


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
	if ui and ui.captures(event):
		# Soltar o botão direito sempre para de girar (mesmo em cima de uma janela).
		if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
			_dragging = false
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var step := zoom_step * (mb.factor if mb.factor > 0.0 else 1.0)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom = clampf(zoom - step, 0.0, 1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom = clampf(zoom + step, 0.0, 1.0)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion:
		# Cursor capturado (jogo normal): o movimento do mouse gira a câmera. Cursor livre
		# (modo construção, Alt, depois de Esc): só com o botão direito segurado.
		if _dragging or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			look((event as InputEventMouseMotion).relative)
	elif event is InputEventPanGesture:  # trackpad do Mac: dois dedos
		zoom = clampf(zoom + (event as InputEventPanGesture).delta.y * 0.02, 0.0, 1.0)
	elif event is InputEventMagnifyGesture:  # trackpad: pinça
		zoom = clampf(zoom - ((event as InputEventMagnifyGesture).factor - 1.0) * 0.5, 0.0, 1.0)


func _process(delta: float) -> void:
	if target == null or not target.visible:
		return
	_zoom = lerpf(_zoom, zoom, 1.0 - exp(-8.0 * delta))

	var player_pos := target.get_global_transform_interpolated().origin
	var up := player_pos.normalized()
	_heading = _tangent(_heading, up)
	if _heading.length() < 0.01:
		_heading = _tangent(-target.global_basis.z, up)
	_heading = _heading.normalized()

	var dist := min_distance * pow(max_distance / min_distance, _zoom)
	var t := smoothstep(0.4, 0.9, _zoom)
	far_amount = t
	distance = dist

	# Perto: atrás e acima do personagem, sempre na distância do zoom.
	var head := player_pos + up * 0.6
	if t < 0.5:
		# Morro atrás: sobe o mínimo para não entrar no chão (rápido, mas sem salto) e
		# volta devagar quando o terreno deixa.
		var need := _ground_pitch_needed(head, up, dist)
		var rate := 10.0 if need > _ground_pitch else 2.0
		_ground_pitch = lerpf(_ground_pitch, need, 1.0 - exp(-rate * delta))
	else:
		_ground_pitch = 0.0
	var pitch := deg_to_rad(minf(pitch_degrees + _ground_pitch, 85.0))
	var back := -_heading * cos(pitch) + up * sin(pitch)
	var near_pos := head + back * dist
	# Longe: em cima do personagem, olhando para o centro do planeta.
	var far_pos := up * (planet_radius + dist)
	var pos := near_pos.lerp(far_pos, t)
	var look := head.lerp(Vector3.ZERO, t)
	# Rede de segurança (o ângulo acima já evita): nunca abaixo do chão.
	var min_r := planet_radius + GROUND_CLEARANCE
	if world:
		_cam_cell = world.find_cell(pos, _cam_cell)
		min_r = world.surface_radius(_cam_cell) + GROUND_CLEARANCE
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
	near = clampf(dist * 0.01, 0.05, 5.0)
	far = planet_radius * 2.0 + dist * 2.0 + 500.0


## Inclinação extra (graus) para a câmera, a `dist` da cabeça, ficar acima do terreno.
func _ground_pitch_needed(head: Vector3, up: Vector3, dist: float) -> float:
	if world == null:
		return 0.0
	var extra := 0.0
	while pitch_degrees + extra < 85.0:
		var pitch := deg_to_rad(pitch_degrees + extra)
		var pos := head + (-_heading * cos(pitch) + up * sin(pitch)) * dist
		_cam_cell = world.find_cell(pos, _cam_cell)
		if pos.length() >= world.surface_radius(_cam_cell) + GROUND_CLEARANCE:
			return extra
		extra += 2.5
	return 85.0 - pitch_degrees


## RID do corpo do personagem (para testes de colisão o ignorarem).
func target_body_rid() -> RID:
	return (target as CollisionObject3D).get_rid() if target is CollisionObject3D else RID()


## Gira a câmera por um movimento de mouse (pixels): horizontal em volta do personagem,
## vertical com limite. Usa a sensibilidade e o eixo invertido das configurações (F6).
func look(relative: Vector2) -> void:
	var s := mouse_sensitivity * MouseSettings.sensitivity()
	var dy := -relative.y if MouseSettings.invert_y() else relative.y
	_turn(-relative.x * s)
	pitch_degrees = clampf(pitch_degrees + dy * s * 60.0, MIN_PITCH, MAX_PITCH)


func _turn(angle: float) -> void:
	if target == null:
		return
	var up := target.global_position.normalized()
	_heading = _heading.rotated(up, angle)


static func _tangent(v: Vector3, up: Vector3) -> Vector3:
	return v - up * v.dot(up)
