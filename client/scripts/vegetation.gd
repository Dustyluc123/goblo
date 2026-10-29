class_name Vegetation
extends Node3D
## Árvores, pedras, flores e enfeites por cima do chão, só perto do jogador.
##
## Três camadas por pedaço (chunk de WorldData):
## - "big": os objetos do SERVIDOR (árvores, pedras grandes, flores, arbustos, pedrinhas,
##   galhos, enfeites grandes), vindos do ChunkData. Um MultiMeshInstance3D por modelo.
##   Objetos colhidos hoje ficam escondidos (escala zero na instância).
## - "small": grama e plantinhas espalhadas pelo CLIENTE (data/decoracao.json), com
##   semente no id da célula. Sorteadas em threads; não nascem dentro de lotes ocupados.
## - "body": colisão das árvores, pedras e enfeites sólidos, só bem perto, direto no
##   PhysicsServer3D (sem um nó por árvore).
## Árvores interativas e decorativas não se sobrepõem porque todas as árvores vêm do
## servidor (ADR 0020). No zoom afastado, nada aparece.

const DECOR_FILE := "res://data/decoracao.json"
const INSET := 0.8  # grama só no topo plano da célula, longe da borda
const UPDATE_EVERY := 0.3
const HIDE_ABOVE_ZOOM := 0.25
const MAX_TASKS := 3
const MAX_BUILDS_PER_FRAME := 1
const LOT_MARGIN := 0.3

var world: WorldData
var data: ChunkData
## Quantos objetos estão desenhados agora (para o painel F2).
var instance_count := 0

var _decor := {}  # bioma (int) → Array de entradas
var _object_tint := {}  # bioma (int) → Color
## chave → {"big": Node3D, "small": Node3D, "body": RID}
var _chunks := {}
## id do objeto → [MultiMesh, índice da instância, Transform3D]
var _instances := {}
var _queue: Array = []  # [chave, camada, distância]
var _tasks := {}  # "chave:camada" → tarefa
var _shapes := {}  # "tipo:escala" → RID de forma compartilhada
var _timer := 0.0
var _focus := Vector3.ZERO
var _generation := 0


func setup(w: WorldData, d: ChunkData) -> void:
	world = w
	data = d
	_load_decor()
	data.chunk_unloaded.connect(_on_chunk_unloaded)
	data.chunk_loaded.connect(func(_k: int) -> void: _timer = 0.0)
	data.object_changed.connect(_on_object_changed)
	data.lot_changed.connect(_on_lot_changed)
	Quality.emitter.changed.connect(clear)


func _exit_tree() -> void:
	for t: String in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[t]["id"])
	clear()
	for rid: RID in _shapes.values():
		PhysicsServer3D.free_rid(rid)
	_shapes.clear()


func _load_decor() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DECOR_FILE))
	if not (parsed is Dictionary):
		push_error("decoracao.json inválido")
		return
	for i in world.biome_names.size():
		var name := world.biome_names[i]
		var entries: Array = []
		for e: Dictionary in parsed["biomes"].get(name, []):
			var t: Array = e.get("tint", [1, 1, 1])
			entries.append({"models": e["models"], "per_cell": float(e["per_cell"]),
				"scale": e["scale"], "tint": Color(t[0], t[1], t[2])})
			for m: String in e["models"]:
				ModelLibrary.get_model(m)  # carrega já (no thread principal)
		_decor[i] = entries
		var ot: Array = parsed.get("object_tint", {}).get(name, [1, 1, 1])
		_object_tint[i] = Color(ot[0], ot[1], ot[2])


## Apaga tudo (ex.: mudou a qualidade); o próximo update recarrega.
func clear() -> void:
	_generation += 1
	for key: int in _chunks.keys():
		_free_chunk(key)
	_chunks.clear()
	_queue.clear()
	_instances.clear()
	instance_count = 0
	_timer = 0.0


## Monta na hora o que já está carregado em volta do ponto (usado no nascimento).
func load_now(point: Vector3) -> void:
	_focus = point
	_refresh()
	for item: Array in _queue:
		_build_layer(item[0], item[1], true)
	_queue.clear()


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
	var built := 0
	while not _queue.is_empty() and built < MAX_BUILDS_PER_FRAME and _tasks.size() < MAX_TASKS:
		var item: Array = _queue.pop_front()
		if _build_layer(item[0], item[1], false):
			built += 1


func _radii() -> Dictionary:
	var q := Quality.current()
	return {"body": q["collider_radius"], "big": q["big_radius"], "small": q["small_radius"]}


func _refresh() -> void:
	var radii := _radii()
	var near := world.chunks_near_with_distance(_focus, float(radii["big"]) * 1.2)
	var items: Array = []
	for pair: Array in near:
		var key: int = pair[0]
		if not data.is_loaded(key):
			continue
		var d: float = pair[1]
		var chunk: Dictionary = _chunks.get(key, {})
		for layer: String in radii:
			if d <= radii[layer] and not chunk.has(layer) and not _tasks.has(_task_key(key, layer)):
				items.append([key, layer, d])
	var order := {"body": 0, "big": 1, "small": 2}
	items.sort_custom(func(a: Array, b: Array) -> bool:
		return (a[2] < b[2]) if a[1] == b[1] else order[a[1]] < order[b[1]])
	_queue = items
	# Solta o que ficou longe (com folga, para não ficar carregando e descarregando).
	var dir := _focus.normalized()
	for key: int in _chunks.keys():
		var chunk: Dictionary = _chunks[key]
		var d: float = dir.angle_to(world.chunk_center[key]) * world.radius - float(world.chunk_radius[key])
		for layer: String in radii:
			if chunk.has(layer) and d > float(radii[layer]) * 1.25:
				_free_layer(key, layer)
		if chunk.is_empty():
			_chunks.erase(key)


static func _task_key(key: int, layer: String) -> String:
	return "%d:%s" % [key, layer]


## Monta uma camada. "small" vai para uma thread (a não ser que `now`).
func _build_layer(key: int, layer: String, now: bool) -> bool:
	if not data.is_loaded(key):
		return false
	if not _chunks.has(key):
		_chunks[key] = {}
	if (_chunks[key] as Dictionary).has(layer):
		return false
	match layer:
		"big":
			_chunks[key]["big"] = _build_objects(key)
		"body":
			_chunks[key]["body"] = _build_colliders(key)
		"small":
			var lots := _lot_rects(key)
			var density := float(Quality.current()["small_density"])
			if now:
				_apply_small(key, _generate_small(key, density, lots))
			else:
				var holder := []
				var id := WorkerThreadPool.add_task(func() -> void: holder.append(_generate_small(key, density, lots)))
				_tasks[_task_key(key, layer)] = {"id": id, "result": holder, "key": key, "gen": _generation}
	return true


func _collect_finished() -> void:
	for name: String in _tasks.keys():
		var t: Dictionary = _tasks[name]
		if not WorkerThreadPool.is_task_completed(t["id"]):
			continue
		WorkerThreadPool.wait_for_task_completion(t["id"])
		_tasks.erase(name)
		if t["gen"] != _generation or (t["result"] as Array).is_empty() or not data.is_loaded(t["key"]):
			continue
		_apply_small(t["key"], t["result"][0])


# --- Objetos do servidor ------------------------------------------------------------------

func _build_objects(key: int) -> Node3D:
	var node := Node3D.new()
	node.set_meta("layer", "big")
	add_child(node)
	var by_model := {}  # modelo → Array de objetos
	for o: Dictionary in data.chunk(key).get("objects", []):
		if not by_model.has(o["model"]):
			by_model[o["model"]] = []
		(by_model[o["model"]] as Array).append(o)
	var shadows: bool = Quality.current()["big_shadows"]
	var count := 0
	for model: String in by_model:
		var lib := ModelLibrary.get_model(model)
		if lib.is_empty():
			continue
		var list: Array = by_model[model]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = lib["mesh"]
		mm.instance_count = list.size()
		var buf := PackedFloat32Array()
		buf.resize(list.size() * 16)
		for i in list.size():
			var o: Dictionary = list[i]
			var t := Transform3D(o["basis"], o["pos"])
			_instances[o["id"]] = [mm, i, t]
			if o["hidden"]:
				t = _hidden_transform(t)
			var c: Color = _object_tint.get(int(world.biomes[o["cell"]]), Color.WHITE)
			var b := t.basis
			var k := i * 16
			buf[k] = b.x.x; buf[k + 1] = b.y.x; buf[k + 2] = b.z.x; buf[k + 3] = t.origin.x
			buf[k + 4] = b.x.y; buf[k + 5] = b.y.y; buf[k + 6] = b.z.y; buf[k + 7] = t.origin.y
			buf[k + 8] = b.x.z; buf[k + 9] = b.y.z; buf[k + 10] = b.z.z; buf[k + 11] = t.origin.z
			buf[k + 12] = c.r; buf[k + 13] = c.g; buf[k + 14] = c.b; buf[k + 15] = c.a
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if ModelLibrary.is_baked(lib):
			mmi.material_override = ModelLibrary.foliage_material(_wind_kind(list[0]))
		node.add_child(mmi)
		count += list.size()
	node.set_meta("count", count)
	instance_count += count
	return node


## Tipo de vento de um objeto do servidor: árvores balançam a copa, flores e arbustos um
## pouco, pedras e galhos no chão ficam parados.
static func _wind_kind(o: Dictionary) -> String:
	match str(o["kind"]):
		"tree":
			return "tree"
		"flower", "bush":
			return "plant"
	return "still"


static func _hidden_transform(t: Transform3D) -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ONE * 0.0001), t.origin)


## Página da Goblopédia de uma árvore pela estação ("tree_autumn", "tree_snow" ou "").
func season_entry(_o: Dictionary) -> String:
	return ""


func _on_object_changed(o: Dictionary) -> void:
	set_object_visible(o["id"], not o["hidden"])


## Mostra ou esconde a instância de um objeto (colheu a flor, ou a árvore está balançando).
func set_object_visible(id: int, on: bool) -> void:
	var inst: Array = _instances.get(id, [])
	if inst.is_empty():
		return
	var mm: MultiMesh = inst[0]
	if not is_instance_valid(mm):
		return
	var t: Transform3D = inst[2]
	mm.set_instance_transform(inst[1], t if on else _hidden_transform(t))


# --- Grama do cliente ---------------------------------------------------------------------

## Retângulos dos lotes ocupados do pedaço, por célula: célula → [Rect2, ...].
func _lot_rects(key: int) -> Dictionary:
	var out := {}
	var size := data.lot_size()
	for l: Dictionary in data.chunk(key).get("lots", []):
		var cell := int(l["cell"])
		if not out.has(cell):
			out[cell] = []
		(out[cell] as Array).append(Rect2(float(l["x0"]) - LOT_MARGIN, float(l["y0"]) - LOT_MARGIN, size + 2 * LOT_MARGIN, size + 2 * LOT_MARGIN))
	return out


func _on_lot_changed(l: Dictionary) -> void:
	# Lote novo ou mudado: a grama daquele pedaço é sorteada de novo, sem o lote.
	var key := world.chunk_of_cell(int(l["cell"]))
	if _chunks.has(key) and (_chunks[key] as Dictionary).has("small"):
		_free_layer(key, "small")
		_timer = 0.0


## Sorteia a grama de um pedaço (roda em thread: só lê o mundo, não mexe na cena).
func _generate_small(key: int, density: float, lots: Dictionary) -> Dictionary:
	var lists := {}  # modelo → Array de [Transform3D, Color]
	for cell in world.chunk_cells[key]:
		if world.land[cell] == 1:
			_cell_decor(cell, density, lots.get(cell, []), lists)
	var buffers := {}
	var counts := {}
	for name: String in lists:
		var list: Array = lists[name]
		var buf := PackedFloat32Array()
		buf.resize(list.size() * 16)
		var o := 0
		for inst: Array in list:
			var t: Transform3D = inst[0]
			var c: Color = inst[1]
			var b := t.basis
			buf[o] = b.x.x; buf[o + 1] = b.y.x; buf[o + 2] = b.z.x; buf[o + 3] = t.origin.x
			buf[o + 4] = b.x.y; buf[o + 5] = b.y.y; buf[o + 6] = b.z.y; buf[o + 7] = t.origin.y
			buf[o + 8] = b.x.z; buf[o + 9] = b.y.z; buf[o + 10] = b.z.z; buf[o + 11] = t.origin.z
			buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = c.a
			o += 16
		buffers[name] = buf
		counts[name] = list.size()
	return {"buffers": buffers, "counts": counts}


## Grama de uma célula. A ordem de sorteio é fixa: a densidade só decide se cada tufo
## aparece, então qualidades menores mostram um subconjunto das maiores.
func _cell_decor(cell: int, density: float, lots: Array, lists: Dictionary) -> void:
	var entries: Array = _decor.get(int(world.biomes[cell]), [])
	if entries.is_empty():
		return
	var f := world.cell_frame(cell)
	var c: Vector3 = f["center"]
	var h: float = f["top"]
	var poly := world.vertices[cell]
	var n := poly.size()
	var center := c * h
	var inner := PackedVector3Array()
	for corner in poly:
		var d := c.lerp(corner, INSET).normalized()
		inner.append(d * (h / d.dot(c)) - center)
	for e_i in entries.size():
		var e: Dictionary = entries[e_i]
		var models: Array = e["models"]
		var rng := DecorRng.new(cell * 16 + e_i)
		var expected: float = e["per_cell"]
		var count := int(expected) + (1 if rng.next_float() < expected - floorf(expected) else 0)
		for j in count:
			var tri := rng.next_u32() % n
			var u := rng.next_float()
			var v := rng.next_float()
			var yaw := rng.next_float() * TAU
			var s := lerpf(e["scale"][0], e["scale"][1], rng.next_float())
			var model: String = models[rng.next_u32() % models.size()]
			var keep := rng.next_float()
			if keep >= density:
				continue
			if u + v > 1.0:
				u = 1.0 - u
				v = 1.0 - v
			var p := center + inner[tri] * u + inner[(tri + 1) % n] * v
			if not lots.is_empty():
				var q := WorldData.frame_coords(f, p)
				var blocked := false
				for r: Rect2 in lots:
					if r.has_point(q):
						blocked = true
						break
				if blocked:
					continue
			if not lists.has(model):
				lists[model] = []
			(lists[model] as Array).append([Transform3D(WorldData.frame_basis(f, yaw, s), p), e["tint"]])


func _apply_small(key: int, result: Dictionary) -> void:
	if not _chunks.has(key):
		_chunks[key] = {}
	if (_chunks[key] as Dictionary).has("small"):
		return
	var node := Node3D.new()
	node.set_meta("layer", "small")
	add_child(node)
	var count := 0
	for name: String in result["buffers"]:
		var lib := ModelLibrary.get_model(name)
		if lib.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = lib["mesh"]
		mm.instance_count = result["counts"][name]
		mm.buffer = result["buffers"][name]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if ModelLibrary.is_baked(lib):
			mmi.material_override = ModelLibrary.foliage_material("grass")
		node.add_child(mmi)
		count += int(result["counts"][name])
	node.set_meta("count", count)
	instance_count += count
	_chunks[key]["small"] = node


# --- Colisão ------------------------------------------------------------------------------

## Colisão simples dos objetos sólidos de um pedaço, direto no servidor de física.
func _build_colliders(key: int) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, get_world_3d().space)
	for o: Dictionary in data.chunk(key).get("objects", []):
		var kind := str(o["kind"])
		if not (kind == "tree" or kind == "rock" or (kind == "decor" and o.get("solid", false))):
			continue
		var lib := ModelLibrary.get_model(o["model"])
		if lib.is_empty():
			continue
		var aabb: AABB = lib["aabb"]
		var s := float(o["scale"])
		var basis: Basis = (o["basis"] as Basis).orthonormalized()
		var up: Vector3 = o["up"]
		var shape_key: String
		var xf: Transform3D
		if kind == "tree":
			var h := minf(aabb.size.y * s, 3.0)
			shape_key = "tree:%.1f" % snappedf(s, 0.1)
			if not _shapes.has(shape_key):
				var rid := PhysicsServer3D.cylinder_shape_create()
				PhysicsServer3D.shape_set_data(rid, {"radius": 0.14 * maxf(s, 1.0), "height": h})
				_shapes[shape_key] = rid
			xf = Transform3D(basis, o["pos"] + up * h * 0.5)
		else:
			shape_key = "%s:%.1f" % [o["model"], snappedf(s, 0.1)]
			if not _shapes.has(shape_key):
				var rid := PhysicsServer3D.box_shape_create()
				PhysicsServer3D.shape_set_data(rid, aabb.size * s * 0.8 * 0.5)
				_shapes[shape_key] = rid
			xf = Transform3D(basis, (o["pos"] as Vector3) + (o["basis"] as Basis) * aabb.get_center())
		PhysicsServer3D.body_add_shape(body, _shapes[shape_key], xf)
	return body


func _on_chunk_unloaded(key: int) -> void:
	if _chunks.has(key):
		_free_chunk(key)
		_chunks.erase(key)


func _free_chunk(key: int) -> void:
	for layer in ["big", "small", "body"]:
		if (_chunks[key] as Dictionary).has(layer):
			_free_layer(key, layer)


func _free_layer(key: int, layer: String) -> void:
	var chunk: Dictionary = _chunks[key]
	if layer == "body":
		PhysicsServer3D.free_rid(chunk["body"])
	else:
		var node: Node = chunk[layer]
		instance_count -= int(node.get_meta("count", 0))
		node.queue_free()
		if layer == "big":
			for o: Dictionary in data.chunk(key).get("objects", []):
				_instances.erase(o["id"])
	chunk.erase(layer)
