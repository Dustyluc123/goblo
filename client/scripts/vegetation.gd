class_name Vegetation
extends Node3D
## Decoração 3D (árvores, pedras, grama) espalhada por cima do chão, só perto do jogador.
##
## - Espalhamento determinístico: posição, rotação e escala de cada objeto vêm de um
##   DecorRng com semente no id da célula, então todos veem as mesmas árvores.
## - Por pedaços (os chunks de WorldData): duas camadas por pedaço, "big" (árvores e pedras
##   grandes, aparecem mais longe) e "small" (grama, plantas, pedrinhas, somem antes).
##   Cada camada vira um MultiMeshInstance3D por modelo.
## - Árvores e pedras grandes ganham colisão simples (cilindro ou caixa) só bem perto.
## - No zoom afastado, nada aparece e nada é carregado.
## A qualidade gráfica (Quality) define distâncias, densidade da camada small e sombras.

const INSET := 0.8  # decoração só no topo plano da célula, longe da borda
const UPDATE_EVERY := 0.3
const HIDE_ABOVE_ZOOM := 0.25
const FRAME_BUDGET_MS := 4.0

var world: WorldData
## Quantos objetos estão carregados agora (para o painel F2).
var instance_count := 0

var _models := {}  # nome → {mesh, local, material, aabb, info}
var _chunks := {}  # chave → {"big": Node3D, "small": Node3D, "body": StaticBody3D, "big_list": Array}
var _queue: Array = []  # [chave, camada]
var _queued := {}
var _timer := 0.0
var _focus := Vector3.ZERO


func setup(w: WorldData) -> void:
	world = w
	_load_models()
	Quality.emitter.changed.connect(clear)


func _load_models() -> void:
	for name: String in BiomeStyle.MODELS:
		var info: Dictionary = BiomeStyle.MODELS[name]
		var scene := load(info["path"]) as PackedScene
		if scene == null:
			push_error("Modelo não encontrado: %s" % info["path"])
			continue
		var root := scene.instantiate() as Node3D
		var mis := root.find_children("*", "MeshInstance3D", true, false)
		if mis.is_empty():
			root.free()
			continue
		var mi := mis[0] as MeshInstance3D
		var local := Transform3D.IDENTITY
		var n: Node = mi
		while n != root:
			local = (n as Node3D).transform * local
			n = n.get_parent()
		local = root.transform * local
		var mat := (mi.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		mat.vertex_color_use_as_albedo = true  # cor por instância (tom do bioma)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		_models[name] = {"mesh": mi.mesh, "local": local, "material": mat, "aabb": mi.get_aabb(), "info": info}
		root.free()


## Apaga tudo (ex.: mudou a qualidade); o próximo update recarrega.
func clear() -> void:
	for key: int in _chunks:
		_free_chunk(key)
	_chunks.clear()
	_queue.clear()
	_queued.clear()
	instance_count = 0
	_timer = 0.0


## Carrega na hora tudo o que precisa estar em volta do ponto (usado no nascimento).
func load_now(point: Vector3) -> void:
	_focus = point
	_refresh()
	while not _queue.is_empty():
		_process_item(_queue.pop_front())
	_queued.clear()


## Chamado a cada quadro com a posição do personagem e o zoom da câmera.
func update_focus(point: Vector3, far_amount: float, delta: float) -> void:
	if world == null:
		return
	visible = far_amount < HIDE_ABOVE_ZOOM
	if not visible:
		return
	_focus = point
	_timer -= delta
	if _timer <= 0.0:
		_timer = UPDATE_EVERY
		_refresh()
	var start := Time.get_ticks_usec()
	while not _queue.is_empty() and (Time.get_ticks_usec() - start) < FRAME_BUDGET_MS * 1000.0:
		var item: Array = _queue.pop_front()
		_queued.erase(_item_key(item))
		_process_item(item)


func _refresh() -> void:
	var q := Quality.current()
	var want := {
		"big": world.chunks_near(_focus, q["big_radius"]),
		"small": world.chunks_near(_focus, q["small_radius"]),
		"body": world.chunks_near(_focus, q["collider_radius"]),
	}
	var dir := _focus.normalized()
	var items: Array = []
	for layer: String in want:
		for key: int in want[layer]:
			var chunk: Dictionary = _chunks.get(key, {})
			if not chunk.has(layer) and not _queued.has(_item_key([key, layer])):
				items.append([key, layer, dir.angle_to(world.chunk_center[key])])
	items.sort_custom(func(a: Array, b: Array) -> bool:
		return (a[2] < b[2]) if a[1] == b[1] else (a[1] == "body" or (a[1] == "big" and b[1] == "small")))
	for it: Array in items:
		var item := [it[0], it[1]]
		_queue.append(item)
		_queued[_item_key(item)] = true
	# Descarrega o que ficou longe (com folga, para não ficar carregando e descarregando).
	var limits := {"big": q["big_radius"] * 1.25, "small": q["small_radius"] * 1.25, "body": q["collider_radius"] * 1.5}
	for key: int in _chunks.keys():
		var chunk: Dictionary = _chunks[key]
		var d: float = dir.angle_to(world.chunk_center[key]) * world.radius - float(world.chunk_radius[key])
		for layer: String in limits:
			if chunk.has(layer) and d > limits[layer]:
				_free_layer(chunk, layer)
		if not (chunk.has("big") or chunk.has("small") or chunk.has("body")):
			_chunks.erase(key)


static func _item_key(item: Array) -> String:
	return "%d:%s" % [item[0], item[1]]


func _process_item(item: Array) -> void:
	var key: int = item[0]
	var layer: String = item[1]
	if not _chunks.has(key):
		_chunks[key] = {}
	var chunk: Dictionary = _chunks[key]
	if chunk.has(layer):
		return
	match layer:
		"big":
			chunk["big_list"] = _chunk_instances(key, true)
			chunk["big"] = _build_layer(chunk["big_list"], Quality.current()["big_shadows"])
		"small":
			chunk["small"] = _build_layer(_chunk_instances(key, false), false)
		"body":
			if not chunk.has("big_list"):
				chunk["big_list"] = _chunk_instances(key, true)
			chunk["body"] = _build_colliders(chunk["big_list"])


## Lista [modelo, Transform3D, cor] de uma camada em todas as células do pedaço.
func _chunk_instances(key: int, big: bool) -> Array:
	var out: Array = []
	var density: float = 1.0 if big else Quality.current()["small_density"]
	for cell in world.chunk_cells[key]:
		if world.land[cell] == 1:
			_cell_instances(cell, big, density, out)
	return out


## Sorteia a decoração de uma célula. A ordem de sorteio é fixa: a densidade só decide se
## cada objeto pequeno aparece, então qualidades menores mostram um subconjunto das maiores.
func _cell_instances(cell: int, big: bool, density: float, out: Array) -> void:
	var entries: Array = BiomeStyle.DECOR.get(int(world.biomes[cell]), [])
	if entries.is_empty():
		return
	var c := world.centers[cell]
	var h := world.surface_radius(cell)
	var poly := world.vertices[cell]
	var n := poly.size()
	var center := c * h
	var inner := PackedVector3Array()
	for corner in poly:
		var d := c.lerp(corner, INSET).normalized()
		inner.append(d * (h / d.dot(c)))
	var tangent := c.cross(Vector3.UP)
	if tangent.length() < 0.01:
		tangent = c.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	for e_i in entries.size():
		var e: Array = entries[e_i]
		if bool(e[5]) != big:
			continue
		var rng := DecorRng.new(cell * 16 + e_i)
		var expected: float = e[1]
		var count := int(expected) + (1 if rng.next_float() < expected - floorf(expected) else 0)
		for j in count:
			var tri := rng.next_u32() % n
			var u := rng.next_float()
			var v := rng.next_float()
			var yaw := rng.next_float() * TAU
			var s := lerpf(e[2], e[3], rng.next_float())
			var keep := rng.next_float()
			if keep >= density:
				continue
			if u + v > 1.0:
				u = 1.0 - u
				v = 1.0 - v
			var p := center + (inner[tri] - center) * u + (inner[(tri + 1) % n] - center) * v
			var x := tangent.rotated(c, yaw)
			var z := x.cross(c)
			out.append([e[0], Transform3D(Basis(x * s, c * s, z * s), p), e[4]])


func _build_layer(instances: Array, shadows: bool) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	var by_model := {}
	for inst: Array in instances:
		if not by_model.has(inst[0]):
			by_model[inst[0]] = []
		(by_model[inst[0]] as Array).append(inst)
	for name: String in by_model:
		if not _models.has(name):
			continue
		var model: Dictionary = _models[name]
		var list: Array = by_model[name]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = model["mesh"]
		mm.instance_count = list.size()
		var local: Transform3D = model["local"]
		for i in list.size():
			mm.set_instance_transform(i, (list[i][1] as Transform3D) * local)
			mm.set_instance_color(i, list[i][2])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = model["material"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)
		instance_count += list.size()
	node.set_meta("count", instances.size())
	return node


func _build_colliders(instances: Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	add_child(body)
	for inst: Array in instances:
		if not _models.has(inst[0]):
			continue
		var model: Dictionary = _models[inst[0]]
		var info: Dictionary = model["info"]
		var t: Transform3D = inst[1]
		var s := t.basis.get_scale().x
		var up := t.basis.y.normalized()
		var cs := CollisionShape3D.new()
		if info.get("collider", "") == "cylinder":
			var shape := CylinderShape3D.new()
			shape.radius = float(info["r"]) * s
			shape.height = float(info["h"]) * s
			cs.shape = shape
			cs.transform = Transform3D(t.basis.orthonormalized(), t.origin + up * shape.height * 0.5)
		elif info.get("collider", "") == "box":
			var aabb: AABB = model["aabb"]
			var shape := BoxShape3D.new()
			shape.size = aabb.size * s * 0.85
			cs.shape = shape
			var local: Transform3D = model["local"]
			cs.transform = Transform3D(t.basis.orthonormalized(), t * (local * aabb.get_center()))
		else:
			continue
		body.add_child(cs)
	return body


func _free_layer(chunk: Dictionary, layer: String) -> void:
	var node: Node = chunk[layer]
	if layer != "body":
		instance_count -= int(node.get_meta("count", 0))
	node.queue_free()
	chunk.erase(layer)
	if layer == "big":
		chunk.erase("big_list")


func _free_chunk(key: int) -> void:
	var chunk: Dictionary = _chunks[key]
	for layer in ["big", "small", "body"]:
		if chunk.has(layer):
			(chunk[layer] as Node).queue_free()
