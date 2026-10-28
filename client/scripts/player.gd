class_name Player
extends CharacterBody3D
## Personagem que anda por cima da esfera.
##
## A gravidade aponta para o centro do planeta (a origem). A cada quadro, `up_direction`
## vira `position.normalized()` e o corpo é girado para ficar em pé na superfície.
## WASD move no plano tangente, relativo à câmera. O personagem não entra no oceano.
##
## O visual é um personagem do Mini Characters (Kenney), escolhido por `character` e
## escalado para `model_height`. As animações idle/walk/sprint são misturadas por um
## AnimationTree (BlendSpace1D) conforme a velocidade.

signal cell_changed(cell_id: int)

const CHARACTERS_DIR := "res://assets/kenney/mini-characters/"

## Qual dos 12 personagens do Mini Characters usar.
@export_enum(
	"character-female-a", "character-female-b", "character-female-c",
	"character-female-d", "character-female-e", "character-female-f",
	"character-male-a", "character-male-b", "character-male-c",
	"character-male-d", "character-male-e", "character-male-f"
) var character := "character-male-a"
## Altura do personagem em unidades do jogo (o planeta tem raio 100).
@export var model_height := 1.0

@export var walk_speed := 4.5
@export var run_multiplier := 1.8
@export var acceleration := 12.0
@export var turn_speed := 10.0
@export var gravity := 25.0
## Distância à frente usada para "olhar" a célula seguinte antes de pisar nela.
@export var ocean_probe := 0.6

var world: WorldData
var camera: Camera3D
var cell_id := -1
var facing := Vector3.FORWARD
## Mistura atual da animação: 0 = idle, 1 = walk, 2 = sprint.
var anim_blend := 0.0

var _anim_tree: AnimationTree

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


func _setup_animation(model: Node3D) -> void:
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var player := players[0] as AnimationPlayer
	for anim_name in ["idle", "walk", "sprint"]:
		if player.has_animation(anim_name):
			player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	var blend := AnimationNodeBlendSpace1D.new()
	blend.min_space = 0.0
	blend.max_space = 2.0
	for point: Array in [["idle", 0.0], ["walk", 1.0], ["sprint", 2.0]]:
		var node := AnimationNodeAnimation.new()
		node.animation = point[0]
		blend.add_blend_point(node, point[1])
	_anim_tree = AnimationTree.new()
	_anim_tree.tree_root = blend
	# Irmão do AnimationPlayer, para as trilhas resolverem a partir do mesmo nó raiz.
	player.get_parent().add_child(_anim_tree)
	_anim_tree.anim_player = _anim_tree.get_path_to(player)
	_anim_tree.active = true


## Coloca o personagem em pé sobre a célula `id`.
func spawn(w: WorldData, id: int, surface_height: float) -> void:
	world = w
	var up := w.centers[id]
	global_position = up * (surface_height + 0.3)
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


func _physics_process(delta: float) -> void:
	var up := global_position.normalized()
	up_direction = up

	var vertical := up * velocity.dot(up)
	var horizontal := velocity - vertical
	vertical -= up * gravity * delta

	var wish := _wish_direction(up)
	var speed := walk_speed * (run_multiplier if Input.is_action_pressed("run") else 1.0)
	horizontal = horizontal.lerp(wish * speed, clampf(acceleration * delta, 0.0, 1.0))
	horizontal = _block_ocean(horizontal, up, delta)

	velocity = horizontal + vertical
	move_and_slide()

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


## Idle → walk → sprint conforme a velocidade real no plano tangente, com transição suave.
func _update_animation(delta: float, up: Vector3) -> void:
	var v := get_real_velocity()
	var speed := (v - up * v.dot(up)).length()
	var target := 0.0
	if speed > walk_speed:
		target = 1.0 + clampf((speed - walk_speed) / (walk_speed * (run_multiplier - 1.0)), 0.0, 1.0)
	else:
		target = speed / walk_speed
	anim_blend = lerpf(anim_blend, target, clampf(10.0 * delta, 0.0, 1.0))
	if _anim_tree:
		_anim_tree.set("parameters/blend_position", anim_blend)


## Direção pedida pelo teclado, no plano tangente, relativa à câmera.
func _wish_direction(up: Vector3) -> Vector3:
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
