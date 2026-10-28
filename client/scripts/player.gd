class_name Player
extends CharacterBody3D
## Personagem que anda por cima da esfera.
##
## A gravidade aponta para o centro do planeta (a origem). A cada quadro, `up_direction`
## vira `position.normalized()` e o corpo é girado para ficar em pé na superfície.
## WASD move no plano tangente, relativo à câmera. O personagem não entra no oceano.

signal cell_changed(cell_id: int)

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


func _ready() -> void:
	floor_snap_length = 0.5
	floor_stop_on_slope = true
	floor_max_angle = deg_to_rad(50.0)
	visible = false
	set_physics_process(false)


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

	var new_up := global_position.normalized()
	if wish.length() > 0.1:
		facing = facing.lerp(wish.normalized(), clampf(turn_speed * delta, 0.0, 1.0))
	_align(new_up)

	var id := world.find_cell(global_position, cell_id)
	if id != cell_id:
		cell_id = id
		cell_changed.emit(cell_id)


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
