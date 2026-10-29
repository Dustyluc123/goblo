class_name Player
extends CharacterBody3D
## Personagem que anda e pula por cima da esfera.
##
## A gravidade aponta para o centro do planeta (a origem). A cada quadro, `up_direction`
## vira `position.normalized()` e o corpo é girado para ficar em pé na superfície.
## WASD move no plano tangente, relativo à câmera; Espaço pula para longe do centro.
## O personagem não entra no oceano e sobe sozinho degraus pequenos.
##
## O visual é um personagem do Mini Characters (Kenney), escolhido por `character` e
## escalado para `model_height`. Um AnimationTree mistura idle/walk/sprint pela velocidade
## e jump/fall no ar, e toca ações por cima (interact-right, pick-up).
## A ferramenta na mão fica presa ao osso "arm-right". No modo dev dá para voar (noclip).

signal cell_changed(cell_id: int)

const CHARACTERS_DIR := "res://assets/kenney/mini-characters/"

## Qual dos 12 personagens do Mini Characters usar.
@export_enum(
	"character-female-a", "character-female-b", "character-female-c",
	"character-female-d", "character-female-e", "character-female-f",
	"character-male-a", "character-male-b", "character-male-c",
	"character-male-d", "character-male-e", "character-male-f"
) var character := "character-male-a"
## Altura do personagem em unidades do jogo.
@export var model_height := 1.0

@export var walk_speed := GameConfig.WALK_SPEED
@export var run_multiplier := GameConfig.RUN_MULTIPLIER
@export var acceleration := 12.0
@export var air_acceleration := 5.0
@export var turn_speed := 10.0
@export var gravity := GameConfig.GRAVITY
@export var jump_height := GameConfig.JUMP_HEIGHT
@export var step_height := GameConfig.STEP_HEIGHT
@export var coyote_time := GameConfig.COYOTE_TIME
@export var jump_buffer := GameConfig.JUMP_BUFFER
## Distância à frente usada para "olhar" a célula seguinte antes de pisar nela.
@export var ocean_probe := 0.6

var world: WorldData
var camera: Camera3D
var cell_id := -1
var facing := Vector3.FORWARD
## Mistura atual da animação no chão: 0 = idle, 1 = walk, 2 = sprint.
var anim_blend := 0.0
## 0 = no chão, 1 = no ar (mistura das animações de pulo/queda).
var air_blend := 0.0
## Quantos pulos foram dados (usado pelos testes automáticos).
var jumps := 0
## Quando true, a direção vem de `auto_wish` em vez do teclado (testes automáticos).
var autopilot := false
var auto_wish := Vector3.ZERO
var auto_run := false
## Quando true, o teclado não move o personagem (janela aberta, digitando).
var input_blocked := false
## Modo dev: voa e atravessa tudo.
var noclip := false
## Barreira do passaporte (ADR 0035): func(de: Vector3, para: Vector3) -> Vector3 que devolve
## a direção (no chão) para dentro de um país sem passaporte, ou ZERO se pode passar.
var border_guard := Callable()
## Velocidade do voo (unidades/s), multiplicada por 4 com Shift.
var fly_speed := 14.0
## Pose do selfie (modo foto) e a mistura atual dela (0 a 1).
var posing := false
var pose_blend := 0.0

var _tool_holder: Node3D
var _skeleton: Skeleton3D

var _anim_tree: AnimationTree
var _since_floor := 0.0
var _since_jump_pressed := 1.0
var _jumping := false

@onready var _visual: Node3D = $Visual


func _ready() -> void:
	floor_snap_length = 0.5
	floor_stop_on_slope = true
	floor_max_angle = deg_to_rad(50.0)
	visible = false
	set_physics_process(false)
	_load_character()


## Troca o modelo em tempo de execução (ex.: set_character("character-female-c")).
func set_character(id: String) -> void:
	character = id
	_load_character()


func _load_character() -> void:
	for child in _visual.get_children():
		child.queue_free()
	var scene := load(CHARACTERS_DIR + character + ".glb") as PackedScene
	if scene == null:
		push_error("Personagem não encontrado: " + character)
		return
	var model := scene.instantiate() as Node3D
	# Os modelos da Kenney olham para +Z; o Godot (e este script) usa -Z como frente.
	model.rotation.y = PI
	var height := _model_height(model)
	if height > 0.0:
		model.scale = Vector3.ONE * (model_height / height)
	_visual.add_child(model)
	_setup_animation(model)
	var sks := model.find_children("*", "Skeleton3D", true, false)
	_skeleton = sks[0] if not sks.is_empty() else null
	_tool_holder = null


## Altura do modelo na pose de repouso, somando as malhas (a origem fica nos pés).
static func _model_height(model: Node3D) -> float:
	var top := 0.0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != model and n is Node3D:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		top = maxf(top, (t * mi.get_aabb()).end.y)
	return top


## Árvore de animação:
##   locomotion (BlendSpace1D idle/walk/sprint) ─┐
##   jump (com TimeSeek para recomeçar) ─┐        ├─ air (Blend2) → saída
##   fall ───────────────────────── jumpfall ─────┘
func _setup_animation(model: Node3D) -> void:
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var player := players[0] as AnimationPlayer
	for anim_name in ["idle", "walk", "sprint", "fall", "holding-right"]:
		if player.has_animation(anim_name):
			player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	for anim_name in ["interact-right", "pick-up"]:
		if player.has_animation(anim_name):
			player.get_animation(anim_name).loop_mode = Animation.LOOP_NONE

	var locomotion := AnimationNodeBlendSpace1D.new()
	locomotion.min_space = 0.0
	locomotion.max_space = 2.0
	for point: Array in [["idle", 0.0], ["walk", 1.0], ["sprint", 2.0]]:
		locomotion.add_blend_point(_anim_node(point[0]), point[1], -1, StringName(point[0]))

	var tree := AnimationNodeBlendTree.new()
	tree.add_node("locomotion", locomotion, Vector2(0, 0))
	tree.add_node("jump", _anim_node("jump"), Vector2(0, 200))
	tree.add_node("jump_seek", AnimationNodeTimeSeek.new(), Vector2(200, 200))
	tree.add_node("fall", _anim_node("fall"), Vector2(0, 400))
	tree.add_node("jumpfall", AnimationNodeBlend2.new(), Vector2(400, 300))
	tree.add_node("air", AnimationNodeBlend2.new(), Vector2(600, 100))
	tree.connect_node("jump_seek", 0, "jump")
	tree.connect_node("jumpfall", 0, "jump_seek")
	tree.connect_node("jumpfall", 1, "fall")
	tree.connect_node("air", 0, "locomotion")
	tree.connect_node("air", 1, "jumpfall")
	# Ações (bater com a ferramenta, pegar do chão) tocam uma vez por cima de tudo.
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.08
	shot.fadeout_time = 0.15
	tree.add_node("action_anim", _anim_node("interact-right"), Vector2(600, 300))
	tree.add_node("action", shot, Vector2(800, 100))
	tree.connect_node("action", 0, "air")
	tree.connect_node("action", 1, "action_anim")
	# Pose do selfie (modo foto): braço esticado segurando a câmera, por cima de tudo.
	tree.add_node("pose_anim", _anim_node("holding-right"), Vector2(800, 300))
	tree.add_node("pose", AnimationNodeBlend2.new(), Vector2(1000, 100))
	tree.connect_node("pose", 0, "action")
	tree.connect_node("pose", 1, "pose_anim")
	tree.connect_node("output", 0, "pose")

	_anim_tree = AnimationTree.new()
	_anim_tree.tree_root = tree
	# Irmão do AnimationPlayer, para as trilhas resolverem a partir do mesmo nó raiz.
	player.get_parent().add_child(_anim_tree)
	_anim_tree.anim_player = _anim_tree.get_path_to(player)
	_anim_tree.active = true


static func _anim_node(anim_name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = anim_name
	return node


## Toca uma ação uma vez ("interact-right" para bater/sacudir, "pick-up" para pegar).
func play_action(anim_name: String) -> void:
	if _anim_tree == null:
		return
	var tree := _anim_tree.tree_root as AnimationNodeBlendTree
	(tree.get_node("action_anim") as AnimationNodeAnimation).animation = anim_name
	_anim_tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Pose do selfie ligada ou desligada (a mistura muda aos poucos).
func set_pose(on: bool) -> void:
	posing = on


## Mostra ou esconde o corpo (primeira pessoa no modo foto). A colisão continua.
func set_body_visible(on: bool) -> void:
	_visual.visible = on


func body_visible() -> bool:
	return _visual.visible


## Vira o personagem para um ponto do mundo.
func face(point: Vector3) -> void:
	var up := global_position.normalized()
	var f := _tangent(point - global_position, up)
	if f.length() > 0.01:
		facing = f.normalized()
		_align(up)


## Põe uma ferramenta na mão (mesh da ModelLibrary) ou tira (null).
func set_tool(mesh: Mesh) -> void:
	if _tool_holder:
		_tool_holder.queue_free()
		_tool_holder = null
	if mesh == null or _skeleton == null:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "arm-right"
	_skeleton.add_child(att)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	# O osso começa no ombro e o braço aponta para −X (pose em T): a ferramenta fica na
	# ponta da mão, com o cabo para a frente.
	mi.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)).scaled(Vector3.ONE * 0.7), Vector3(-0.21, -0.01, -0.07))
	att.add_child(mi)
	_tool_holder = att


## Leva o personagem para um ponto (já em cima do chão).
func teleport(pos: Vector3) -> void:
	var up := pos.normalized()
	global_position = pos + up * 0.4
	velocity = Vector3.ZERO
	_align(up)
	reset_physics_interpolation()
	var id := world.find_cell(global_position, cell_id)
	if id != cell_id:
		cell_id = id
		cell_changed.emit(cell_id)


func set_noclip(on: bool) -> void:
	noclip = on
	$CollisionShape3D.disabled = on
	velocity = Vector3.ZERO


## Coloca o personagem em pé sobre a célula `id`.
func spawn(w: WorldData, id: int) -> void:
	world = w
	var up := w.centers[id]
	global_position = up * (w.surface_radius(id) + 0.3)
	facing = _tangent(Vector3.UP, up)
	if facing.length() < 0.01:
		facing = _tangent(Vector3.FORWARD, up)
	facing = facing.normalized()
	_align(up)
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	cell_id = id
	visible = true
	set_physics_process(true)
	cell_changed.emit(cell_id)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump") and not input_blocked and not noclip:
		request_jump()


## Pede um pulo (vale por `jump_buffer` segundos, para o pulo responder mesmo se o
## Espaço vier um pouco antes de pousar).
func request_jump() -> void:
	_since_jump_pressed = 0.0


func _physics_process(delta: float) -> void:
	var up := global_position.normalized()
	up_direction = up
	if noclip:
		_fly(delta, up)
		return

	var vertical_speed := velocity.dot(up)
	var horizontal := velocity - up * vertical_speed
	vertical_speed -= gravity * delta

	# Coyote time e jump buffer.
	_since_jump_pressed += delta
	if is_on_floor():
		_since_floor = 0.0
		_jumping = false
	else:
		_since_floor += delta
	if _since_jump_pressed <= jump_buffer and _since_floor <= coyote_time and not _jumping:
		vertical_speed = sqrt(2.0 * gravity * jump_height)
		_jumping = true  # sem pulo duplo: só volta a valer depois de tocar o chão
		_since_jump_pressed = jump_buffer + 1.0
		_since_floor = coyote_time + 1.0
		jumps += 1
		if _anim_tree:
			_anim_tree.set("parameters/jump_seek/seek_request", 0.0)

	var wish := auto_wish.limit_length(1.0) if autopilot else _wish_direction(up)
	var running := auto_run if autopilot else (Input.is_action_pressed("run") and not input_blocked)
	var speed := walk_speed * (run_multiplier if running else 1.0)
	var accel := acceleration if is_on_floor() else air_acceleration
	horizontal = horizontal.lerp(wish * speed, clampf(accel * delta, 0.0, 1.0))
	horizontal = _block_ocean(horizontal, up, delta)
	horizontal = _block_border(horizontal, up, delta)
	_try_step_up(horizontal, up)

	velocity = horizontal + up * vertical_speed
	var before := global_position
	move_and_slide()
	# Rede de segurança: o desvio da fronteira, o degrau ou o deslize na colisão podem
	# levar o corpo para uma célula de oceano. Se isso acontecer, volta para a terra.
	if world.is_land(cell_id) and not world.is_land(world.find_cell(global_position, cell_id)):
		global_position = before
		velocity = up * minf(velocity.dot(up), 0.0)

	_update_animation(delta, up)

	var new_up := global_position.normalized()
	if wish.length() > 0.1:
		# Gira em volta do "para cima" (funciona até para dar meia-volta, onde um lerp travaria).
		var f := _tangent(facing, new_up).normalized()
		var angle := f.signed_angle_to(_tangent(wish, new_up).normalized(), new_up)
		facing = f.rotated(new_up, angle * (1.0 - exp(-turn_speed * delta)))
	_align(new_up)

	var id := world.find_cell(global_position, cell_id)
	if id != cell_id:
		cell_id = id
		cell_changed.emit(cell_id)


## Voo do modo dev: WASD no plano, Espaço sobe, Ctrl desce, Shift acelera. Sem colisão.
func _fly(delta: float, up: Vector3) -> void:
	var wish := _wish_direction(up)
	var vertical := 0.0
	if not input_blocked:
		vertical = (1.0 if Input.is_key_pressed(KEY_SPACE) else 0.0) - (1.0 if Input.is_key_pressed(KEY_CTRL) else 0.0)
	var speed := fly_speed * (4.0 if Input.is_action_pressed("run") and not input_blocked else 1.0)
	velocity = (wish + up * vertical) * speed
	global_position += velocity * delta
	if world and global_position.length() < world.radius - 2.0:
		global_position = global_position.normalized() * (world.radius - 2.0)
	var new_up := global_position.normalized()
	if wish.length() > 0.1:
		facing = _tangent(wish, new_up).normalized()
	_align(new_up)
	_update_animation(delta, new_up)
	var id := world.find_cell(global_position, cell_id)
	if id != cell_id:
		cell_id = id
		cell_changed.emit(cell_id)


## Fronteira sem passaporte: tira a parte do movimento que atravessaria a linha (o
## personagem desliza ao longo dela). Quem já está dentro do país anda livre.
func _block_border(horizontal: Vector3, up: Vector3, delta: float) -> Vector3:
	if not border_guard.is_valid() or horizontal.length_squared() < 0.0001:
		return horizontal
	# Confere de novo o que sobrou do movimento (perto de uma tríplice fronteira, deslizar
	# ao longo de uma linha pode levar a outra); na terceira, para.
	for attempt in 3:
		var probe := global_position + horizontal.normalized() * 0.45 + horizontal * delta
		var n: Vector3 = border_guard.call(global_position, probe)
		if n == Vector3.ZERO:
			return horizontal
		n = (n - up * n.dot(up)).normalized()
		var into := horizontal.dot(n)
		if into > 0.0:
			horizontal -= n * into
		if horizontal.length_squared() < 0.0001:
			return Vector3.ZERO
	return Vector3.ZERO


## Sobe degraus de até `step_height` andando: se algo bloqueia à frente e o mesmo
## movimento passa livre um degrau acima, levanta o corpo (o floor snap o assenta no degrau).
func _try_step_up(horizontal: Vector3, up: Vector3) -> void:
	if not is_on_floor() or horizontal.length_squared() < 0.04:
		return
	var motion := horizontal.normalized() * 0.3
	if not test_move(global_transform, motion):
		return
	var lift := up * step_height
	if test_move(global_transform, lift):
		return
	if test_move(global_transform.translated(lift), motion):
		return
	global_position += lift


## Animação: no chão, idle → walk → sprint pela velocidade; no ar, jump subindo e fall descendo.
func _update_animation(delta: float, up: Vector3) -> void:
	var v := get_real_velocity()
	var speed := (v - up * v.dot(up)).length()
	var target := 0.0
	if speed > walk_speed:
		target = 1.0 + clampf((speed - walk_speed) / (walk_speed * (run_multiplier - 1.0)), 0.0, 1.0)
	else:
		target = speed / walk_speed
	var k := clampf(10.0 * delta, 0.0, 1.0)
	anim_blend = lerpf(anim_blend, target, k)
	var airborne := not is_on_floor() and (_jumping or _since_floor > 0.15)
	air_blend = lerpf(air_blend, 1.0 if airborne else 0.0, clampf(14.0 * delta, 0.0, 1.0))
	var falling := clampf(-v.dot(up) / 4.0, 0.0, 1.0)
	pose_blend = move_toward(pose_blend, 1.0 if posing else 0.0, delta * 4.0)
	if _anim_tree:
		_anim_tree.set("parameters/pose/blend_amount", pose_blend)
		_anim_tree.set("parameters/locomotion/blend_position", anim_blend)
		_anim_tree.set("parameters/air/blend_amount", air_blend)
		_anim_tree.set("parameters/jumpfall/blend_amount", falling)


## Direção pedida pelo teclado, no plano tangente, relativa à câmera.
func _wish_direction(up: Vector3) -> Vector3:
	if input_blocked:
		return Vector3.ZERO
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO or camera == null:
		return Vector3.ZERO
	var basis := camera.global_basis
	var forward := _tangent(-basis.z, up)
	if forward.length() < 0.05:  # câmera olhando reto para baixo: usa o "para cima" da tela
		forward = _tangent(basis.y, up)
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	var wish := right * input.x - forward * input.y
	return wish.limit_length(1.0)


## Não deixa entrar em célula de oceano. Primeiro tenta deslizar pela costa (tira a parte
## da velocidade que aponta para a célula de oceano); se ainda assim cair no mar, para.
func _block_ocean(horizontal: Vector3, up: Vector3, delta: float) -> Vector3:
	if horizontal.length_squared() < 0.0001 or not world.is_land(cell_id):
		return horizontal  # parado, ou já no mar (aí deixamos sair)
	for attempt in 2:
		var probe := global_position + horizontal.normalized() * ocean_probe + horizontal * delta
		var id := world.find_cell(probe, cell_id)
		if world.is_land(id):
			return horizontal
		if attempt == 0:
			var toward := _tangent(world.centers[id] * world.radius - global_position, up).normalized()
			var into := horizontal.dot(toward)
			if into > 0.0:
				horizontal -= toward * into
			if horizontal.length_squared() < 0.0001:
				break
	return Vector3.ZERO


func _align(up: Vector3) -> void:
	var f := _tangent(facing, up)
	if f.length() < 0.01:
		f = _tangent(-global_basis.z, up)
	facing = f.normalized()
	global_basis = Basis.looking_at(facing, up)


static func _tangent(v: Vector3, up: Vector3) -> Vector3:
	return v - up * v.dot(up)
