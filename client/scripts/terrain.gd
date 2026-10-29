class_name Terrain
extends Node3D
## Chão do globo: malhas de desenho agrupadas e colisão por pedaços perto do personagem.
##
## Desenho: os pedaços finos de WorldData (16×16 por face do cubo) são juntados em grupos
## de 4×4 → 96 grupos, cada um com uma malha de terra e uma de oceano. Poucos draw calls e
## o Godot ainda descarta os grupos fora da tela.
##
## Colisão: só os pedaços a até `collision_radius` do personagem têm ConcavePolygonShape3D.
## Assim a física não carrega o globo inteiro (centenas de milhares de triângulos). Os
## triângulos de um pedaço novo são montados numa thread e a forma entra no quadro
## seguinte (um por quadro), para andar não travar (fase 2.6).

const GROUP_SPLIT := 4  # pedaços finos por grupo, em cada direção

@export var collision_radius := 60.0

var world: WorldData
var _body: StaticBody3D
var _shapes: Dictionary = {}  # chave do pedaço → CollisionShape3D
var _tasks: Dictionary = {}  # chave do pedaço → {"id": tarefa, "faces": [PackedVector3Array]}


func build(w: WorldData) -> void:
	world = w
	for child in get_children():
		child.queue_free()
	_shapes.clear()
	var groups := {}
	for key: int in w.chunk_cells:
		var g := _group_of(key)
		if not groups.has(g):
			groups[g] = []  # Array é referência; PackedInt32Array seria copiado
		(groups[g] as Array).append_array(Array(w.chunk_cells[key]))
	for g: int in groups:
		var meshes := GlobeBuilder.build_meshes(w, PackedInt32Array(groups[g]))
		for m in meshes:
			if m == null:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = m
			add_child(mi)
	_body = StaticBody3D.new()
	_body.name = "Collision"
	add_child(_body)


static func _group_of(key: int) -> int:
	var g := WorldData.CHUNK_GRID
	var face := key / (g * g)
	var iv := (key / g) % g
	var iu := key % g
	var s := g / GROUP_SPLIT
	return (face * s + iv / GROUP_SPLIT) * s + iu / GROUP_SPLIT


## Liga a colisão dos pedaços perto do ponto e desliga a dos distantes. `max_new` limita
## quantos pedaços novos são montados por chamada (cada um custa ~4 ms); -1 = todos.
func update_collision(point: Vector3, max_new := 2) -> void:
	if world == null:
		return
	var wanted := {}
	var built := 0
	var near := world.chunks_near_with_distance(point, collision_radius)
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	for pair: Array in near:
		var key: int = pair[0]
		wanted[key] = true
		if _shapes.has(key):
			continue
		if max_new < 0:
			# Teleporte e nascimento: precisa do chão já (espera a thread, se houver).
			if _tasks.has(key):
				WorkerThreadPool.wait_for_task_completion(_tasks[key]["id"])
				_add_shape(key, _tasks[key]["faces"][0])
				_tasks.erase(key)
			else:
				_add_shape(key, GlobeBuilder.collision_faces(world, world.chunk_cells[key]))
		elif not _tasks.has(key) and built < max_new:
			built += 1
			var holder := []
			var w := world
			var cells: PackedInt32Array = world.chunk_cells[key]
			var id := WorkerThreadPool.add_task(func() -> void: holder.append(GlobeBuilder.collision_faces(w, cells)))
			_tasks[key] = {"id": id, "faces": holder}
	for key: int in _shapes.keys():
		if not wanted.has(key) and world.chunk_center[key].angle_to(point.normalized()) * world.radius \
				- float(world.chunk_radius[key]) > collision_radius * 1.3:
			(_shapes[key] as Node).queue_free()
			_shapes.erase(key)


func _process(_delta: float) -> void:
	# Uma forma pronta por quadro.
	for key: int in _tasks.keys():
		var t: Dictionary = _tasks[key]
		if not WorkerThreadPool.is_task_completed(t["id"]):
			continue
		WorkerThreadPool.wait_for_task_completion(t["id"])
		_tasks.erase(key)
		if not _shapes.has(key):
			var t0 := Time.get_ticks_usec()
			_add_shape(key, t["faces"][0])
			HitchLog.note("colisão do chão do pedaço %d" % key, (Time.get_ticks_usec() - t0) / 1000.0)
		return


func _add_shape(key: int, faces: PackedVector3Array) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_body.add_child(cs)
	_shapes[key] = cs


func _exit_tree() -> void:
	for key: int in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key]["id"])
	_tasks.clear()


func collision_chunk_count() -> int:
	return _shapes.size()
