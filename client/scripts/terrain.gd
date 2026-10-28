class_name Terrain
extends Node3D
## Chão do globo: malhas de desenho agrupadas e colisão por pedaços perto do personagem.
##
## Desenho: os pedaços finos de WorldData (16×16 por face do cubo) são juntados em grupos
## de 4×4 → 96 grupos, cada um com uma malha de terra e uma de oceano. Poucos draw calls e
## o Godot ainda descarta os grupos fora da tela.
##
## Colisão: só os pedaços a até `collision_radius` do personagem têm ConcavePolygonShape3D.
## Assim a física não carrega o globo inteiro (centenas de milhares de triângulos).

const GROUP_SPLIT := 4  # pedaços finos por grupo, em cada direção

@export var collision_radius := 60.0

var world: WorldData
var _body: StaticBody3D
var _shapes: Dictionary = {}  # chave do pedaço → CollisionShape3D


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


## Liga a colisão dos pedaços perto do ponto e desliga a dos distantes.
func update_collision(point: Vector3) -> void:
	if world == null:
		return
	var wanted := {}
	for key in world.chunks_near(point, collision_radius):
		wanted[key] = true
		if not _shapes.has(key):
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(GlobeBuilder.collision_faces(world, world.chunk_cells[key]))
			var cs := CollisionShape3D.new()
			cs.shape = shape
			_body.add_child(cs)
			_shapes[key] = cs
	for key: int in _shapes.keys():
		if not wanted.has(key) and world.chunk_center[key].angle_to(point.normalized()) * world.radius \
				- float(world.chunk_radius[key]) > collision_radius * 1.3:
			(_shapes[key] as Node).queue_free()
			_shapes.erase(key)


func collision_chunk_count() -> int:
	return _shapes.size()
