class_name Vegetation
extends Node3D
## Decoração 3D (árvores, pedras, grama) espalhada por cima do chão, só perto do jogador.
##
## - Espalhamento determinístico: posição, rotação e escala de cada objeto vêm de um
##   DecorRng com semente no id da célula, então todos veem as mesmas árvores.
## - Por pedaços (os chunks de WorldData): duas camadas por pedaço, "big" (árvores e pedras
##   grandes, aparecem mais longe) e "small" (grama, plantas, pedrinhas, somem antes).
##   Cada camada vira um MultiMeshInstance3D por modelo.
## - O sorteio roda em threads (WorkerThreadPool) e já devolve o buffer do MultiMesh; o
##   thread principal só entrega o buffer à GPU. Assim andar não dá travadas.
## - Árvores e pedras grandes ganham colisão simples (cilindro ou caixa) só bem perto,
##   criada direto no PhysicsServer3D (sem um nó por árvore).
## - No zoom afastado, nada aparece e nada é carregado.
## A qualidade gráfica (Quality) define distâncias, densidade da camada small e sombras.

const INSET := 0.8  # decoração só no topo plano da célula, longe da borda
const UPDATE_EVERY := 0.3
const HIDE_ABOVE_ZOOM := 0.25
const MAX_TASKS := 3
const MAX_BUILDS_PER_FRAME := 2

var world: WorldData
## Quantos objetos estão carregados agora (para o painel F2).
var instance_count := 0

var _models := {}  # nome → {mesh, local, material, aabb, info}
## chave → {"big": Node3D, "small": Node3D, "body": RID, "colliders": Array}
var _chunks := {}
var _queue: Array = []  # [chave, camada, distância]
var _queued := {}
var _tasks := {}  # "chave:camada" → {"id": int, "result": Array}
var _shapes := {}  # "modelo:escala" → RID de forma compartilhada
var _timer := 0.0
var _focus := Vector3.ZERO
var _generation := 0  # muda quando tudo é apagado, para descartar tarefas antigas


func setup(w: WorldData) -> void:
	world = w
	_load_models()
	Quality.emitter.changed.connect(clear)


func _exit_tree() -> void:
	for t: String in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[t]["id"])
	clear()
	for rid: RID in _shapes.values():
		PhysicsServer3D.free_rid(rid)
	_shapes.clear()


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
	_generation += 1
	for key: int in _chunks:
		var chunk: Dictionary = _chunks[key]
		for layer in ["big", "small", "body"]:
			if chunk.has(layer):
				_free_layer(chunk, layer)
	_chunks.clear()
	_queue.clear()
	_queued.clear()
	instance_count = 0
	_timer = 0.0


## Carrega na hora tudo o que precisa estar em volta do ponto (usado no nascimento).
func load_now(point: Vector3) -> void:
	_focus = point
	_refresh()
	for item: Array in _queue:
		var key: int = item[0]
		var layer: String = item[1]
		if layer == "body":
			_apply(key, layer, _generate(key, true, 1.0))
		else:
			_apply(key, layer, _generate(key, layer == "big", _density(layer)))
	_queue.clear()
	_queued.clear()


## Chamado a cada quadro com a posição do personagem e o zoom da câmera.
func update_focus(point: Vector3, far_amount: float, delta: float) -> void:
	if world == null:
		return
	visible = far_amount < HIDE_ABOVE_ZOOM
	_collect_finished()
	if not visible:
		return
	_focus = point
	_timer -= delta
	if _timer <= 0.0:
		_timer = UPDATE_EVERY
		_refresh()
	while not _queue.is_empty() and _tasks.size() < MAX_TASKS:
		var item: Array = _queue.pop_front()
		_queued.erase(_item_key(item[0], item[1]))
		_start_task(item[0], item[1])


func _density(layer: String) -> float:
	return 1.0 if layer != "small" else float(Quality.current()["small_density"])


func _refresh() -> void:
	var q := Quality.current()
	var radii := {"body": q["collider_radius"], "big": q["big_radius"], "small": q["small_radius"]}
	var dir := _focus.normalized()
	var near := world.chunks_near_with_distance(_focus, q["big_radius"] * 1.3)
	var items: Array = []
	for pair: Array in near:
		var key: int = pair[0]
		var d: float = pair[1]
		var chunk: Dictionary = _chunks.get(key, {})
		for layer: String in radii:
			if d <= radii[layer] and not chunk.has(layer) and not _queued.has(_item_key(key, layer)) \
					and not _tasks.has(_item_key(key, layer)):
				items.append([key, layer, d])
	# Colisão primeiro, depois árvores, depois grama; dentro de cada uma, mais perto primeiro.
	var order := {"body": 0, "big": 1, "small": 2}
	items.sort_custom(func(a: Array, b: Array) -> bool:
		return (a[2] < b[2]) if a[1] == b[1] else order[a[1]] < order[b[1]])
	_queue = items
	_queued.clear()
	for it: Array in items:
		_queued[_item_key(it[0], it[1])] = true
	# Descarrega o que ficou longe (com folga, para não ficar carregando e descarregando).
	for key: int in _chunks.keys():
		var chunk: Dictionary = _chunks[key]
		var d: float = dir.angle_to(world.chunk_center[key]) * world.radius - float(world.chunk_radius[key])
		for layer: String in radii:
			if chunk.has(layer) and d > float(radii[layer]) * 1.25:
				_free_layer(chunk, layer)
		if not (chunk.has("big") or chunk.has("small") or chunk.has("body")):
			_chunks.erase(key)


static func _item_key(key: int, layer: String) -> String:
	return "%d:%s" % [key, layer]


func _start_task(key: int, layer: String) -> void:
	var holder := []
	var big := layer != "small"
	var density := _density(layer)
	var id := WorkerThreadPool.add_task(func() -> void: holder.append(_generate(key, big, density)))
	_tasks[_item_key(key, layer)] = {"id": id, "result": holder, "key": key, "layer": layer, "gen": _generation}


func _collect_finished() -> void:
	var built := 0
	for name: String in _tasks.keys():
		if built >= MAX_BUILDS_PER_FRAME:
			break
		var t: Dictionary = _tasks[name]
		if not WorkerThreadPool.is_task_completed(t["id"]):
			continue
		WorkerThreadPool.wait_for_task_completion(t["id"])
		_tasks.erase(name)
		if t["gen"] != _generation or (t["result"] as Array).is_empty():
			continue
		_apply(t["key"], t["layer"], t["result"][0])
		built += 1


## Entrega o resultado de um sorteio: cria os MultiMesh (ou a colisão) do pedaço.
func _apply(key: int, layer: String, data: Dictionary) -> void:
	if not _chunks.has(key):
		_chunks[key] = {}
	var chunk: Dictionary = _chunks[key]
	if chunk.has(layer):
		return
	if layer == "body":
		chunk["body"] = _build_colliders(data["colliders"])
		return
	var node := Node3D.new()
	add_child(node)
	var shadows: bool = layer == "big" and Quality.current()["big_shadows"]
	var count := 0
	for name: String in data["buffers"]:
		var model: Dictionary = _models[name]
		var n: int = data["counts"][name]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = model["mesh"]
		mm.instance_count = n
		mm.buffer = data["buffers"][name]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = model["material"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)
		count += n
	node.set_meta("count", count)
	instance_count += count
	chunk[layer] = node


## Sorteia a decoração de um pedaço (roda em thread: só lê o mundo, não mexe na cena).
## Devolve {"buffers": {modelo: PackedFloat32Array}, "counts": {modelo: int},
## "colliders": [[modelo, Transform3D], ...]} (colisores só na camada grande).
func _generate(key: int, big: bool, density: float) -> Dictionary:
	var lists := {}  # modelo → Array de [Transform3D, Color]
	var colliders: Array = []
	for cell in world.chunk_cells[key]:
		if world.land[cell] == 1:
			_cell_instances(cell, big, density, lists)
	var buffers := {}
	var counts := {}
	for name: String in lists:
		if not _models.has(name):
			continue
		var local: Transform3D = _models[name]["local"]
		var list: Array = lists[name]
		var buf := PackedFloat32Array()
		buf.resize(list.size() * 16)
		var o := 0
		for inst: Array in list:
			var t: Transform3D = inst[0]
			var c: Color = inst[1]
			if big and _models[name]["info"].has("collider"):
				colliders.append([name, t])
			t = t * local
			var b := t.basis
			buf[o] = b.x.x; buf[o + 1] = b.y.x; buf[o + 2] = b.z.x; buf[o + 3] = t.origin.x
			buf[o + 4] = b.x.y; buf[o + 5] = b.y.y; buf[o + 6] = b.z.y; buf[o + 7] = t.origin.y
			buf[o + 8] = b.x.z; buf[o + 9] = b.y.z; buf[o + 10] = b.z.z; buf[o + 11] = t.origin.z
			buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = c.a
			o += 16
		buffers[name] = buf
		counts[name] = list.size()
	return {"buffers": buffers, "counts": counts, "colliders": colliders}


## Sorteia a decoração de uma célula. A ordem de sorteio é fixa: a densidade só decide se
## cada objeto pequeno aparece, então qualidades menores mostram um subconjunto das maiores.
func _cell_instances(cell: int, big: bool, density: float, lists: Dictionary) -> void:
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
		inner.append(d * (h / d.dot(c)) - center)
	var tangent := c.cross(Vector3.UP)
	if tangent.length() < 0.01:
		tangent = c.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	for e_i in entries.size():
		var e: Array = entries[e_i]
		if bool(e[5]) != big:
			continue
		var name: String = e[0]
		if not lists.has(name):
			lists[name] = []
		var list: Array = lists[name]
		var color: Color = e[4]
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
			var p := center + inner[tri] * u + inner[(tri + 1) % n] * v
			var x := tangent.rotated(c, yaw)
			var z := x.cross(c)
			list.append([Transform3D(Basis(x * s, c * s, z * s), p), color])


## Colisão simples das árvores e pedras grandes de um pedaço, direto no servidor de física.
func _build_colliders(colliders: Array) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, get_world_3d().space)
	for item: Array in colliders:
		var name: String = item[0]
		var t: Transform3D = item[1]
		var model: Dictionary = _models[name]
		var info: Dictionary = model["info"]
		var s := t.basis.get_scale().x
		var qs := snappedf(s, 0.1)
		var basis := t.basis.orthonormalized()
		var shape_key := "%s:%.1f" % [name, qs]
		if not _shapes.has(shape_key):
			_shapes[shape_key] = _make_shape(model, qs)
		var xf: Transform3D
		if info["collider"] == "cylinder":
			xf = Transform3D(basis, t.origin + basis.y * float(info["h"]) * qs * 0.5)
		else:
			var local: Transform3D = model["local"]
			xf = Transform3D(basis, t * (local * (model["aabb"] as AABB).get_center()))
		PhysicsServer3D.body_add_shape(body, _shapes[shape_key], xf)
	return body


func _make_shape(model: Dictionary, s: float) -> RID:
	var info: Dictionary = model["info"]
	if info["collider"] == "cylinder":
		var rid := PhysicsServer3D.cylinder_shape_create()
		PhysicsServer3D.shape_set_data(rid, {"radius": float(info["r"]) * s, "height": float(info["h"]) * s})
		return rid
	var rid := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(rid, (model["aabb"] as AABB).size * s * 0.85 * 0.5)
	return rid


func _free_layer(chunk: Dictionary, layer: String) -> void:
	if layer == "body":
		PhysicsServer3D.free_rid(chunk["body"])
	else:
		var node: Node = chunk[layer]
		instance_count -= int(node.get_meta("count", 0))
		node.queue_free()
	chunk.erase(layer)
