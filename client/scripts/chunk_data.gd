class_name ChunkData
extends Node
## Dados do servidor por pedaço (chunk): objetos interativos (GET /objects) e lotes
## ocupados com casas e decoração (GET /lots). Busca os pedaços perto do personagem,
## guarda e solta os distantes. A vegetação e o bairro desenham a partir daqui.
##
## Cada objeto ganha campos calculados no cliente: "pos" (Vector3 no mundo), "basis",
## "hidden" (já colhido hoje por este jogador).

signal chunk_loaded(key: int)
signal chunk_unloaded(key: int)
## Um lote mudou (colocou/guardou objeto, obra, vizinho novo).
signal lot_changed(lot: Dictionary)
## O estado de um objeto mudou (sacudiu, colheu…).
signal object_changed(obj: Dictionary)
## O dia do jogo virou (5h locais): limites diários zerados, obras prontas.
signal day_changed

const MAX_REQUESTS := 4
const UPDATE_EVERY := 0.4
const RETRY_AFTER := 3.0

var world: WorldData
var api: Api
## Fronteiras exatas das células carregadas (GET /borders, junto com objetos e lotes).
var borders := BorderMap.new()
## Raio (unidades) em volta do personagem em que os dados ficam carregados.
var radius := 130.0
## Lado do lote em unidades (quadradinhos × tamanho do quadradinho, vem do /content).
var lot_size_units := 7.0
## Dia do jogo segundo o servidor (muda às 5h locais).
var day := -1
var next_rollover := 0

var _chunks := {}  # chave → {"objects": Array, "lots": Array}
var _objects := {}  # id → objeto
var _lots := {}  # id → lote
var _pending := {}  # chave → true
var _failed := {}  # chave → instante em que pode tentar de novo
var _frames := {}  # célula → frame
var _timer := 0.0
var _focus := Vector3.ZERO


func setup(w: WorldData, a: Api) -> void:
	world = w
	api = a


func frame(cell: int) -> Dictionary:
	if not _frames.has(cell):
		_frames[cell] = world.cell_frame(cell)
	return _frames[cell]


func lot_size() -> float:
	return lot_size_units


func is_loaded(key: int) -> bool:
	return _chunks.has(key)


func chunk(key: int) -> Dictionary:
	return _chunks.get(key, {})


func loaded_keys() -> Array:
	return _chunks.keys()


func lot(id: int) -> Dictionary:
	return _lots.get(id, {})


func object(id: int) -> Dictionary:
	return _objects.get(id, {})


## Carrega já (esperando) os pedaços a até `r` unidades do ponto. Usado no nascimento.
func load_now(point: Vector3, r: float) -> void:
	_focus = point
	var keys: Array = []
	for pair: Array in world.chunks_near_with_distance(point, r):
		if not _chunks.has(pair[0]):
			keys.append(pair[0])
	for key: int in keys:
		_pending[key] = true
		_fetch(key)
	# Espera todos (os pedidos já estão correndo em paralelo).
	for key: int in keys:
		while _pending.has(key):
			await get_tree().process_frame


## Chamado a cada quadro com a posição do personagem.
func update_focus(point: Vector3, delta: float) -> void:
	if world == null or api == null:
		return
	_focus = point
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = UPDATE_EVERY
	# Passou das 5h locais com o jogo aberto: recarrega tudo (árvores e flores voltam).
	if next_rollover > 0 and Time.get_unix_time_from_system() > next_rollover + 2:
		next_rollover = 0
		refresh_all()
		day_changed.emit()
		return
	var near := world.chunks_near_with_distance(point, radius)
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	var now := Time.get_ticks_msec() / 1000.0
	for pair: Array in near:
		var key: int = pair[0]
		if _chunks.has(key) or _pending.has(key) or float(_failed.get(key, 0.0)) > now:
			continue
		if _pending.size() >= MAX_REQUESTS:
			break
		_pending[key] = true
		_fetch(key)
	# Solta o que ficou longe (com folga).
	var dir := point.normalized()
	for key: int in _chunks.keys():
		var d: float = dir.angle_to(world.chunk_center[key]) * world.radius - float(world.chunk_radius[key])
		if d > radius * 1.35:
			_unload(key)


## Pede de novo os dados de um pedaço (ex.: depois de criar vizinhos falsos).
func refresh_all() -> void:
	for key: int in _chunks.keys():
		_unload(key)
	_timer = 0.0


func _land_cells(key: int) -> PackedStringArray:
	var out := PackedStringArray()
	for c in world.chunk_cells[key]:
		if world.land[c] == 1:
			out.append(str(c))
	return out


func _fetch(key: int) -> void:
	var cells := _land_cells(key)
	var objects: Array = []
	var lots: Array = []
	var r3 := {}
	if not cells.is_empty():
		var q := ",".join(cells)
		var r1 := await api.request("GET", "/objects?cells=" + q)
		var r2 := await api.request("GET", "/lots?cells=" + q)
		r3 = await api.request("GET", "/borders?cells=" + q)
		if not r1["ok"] or not r2["ok"] or not r3["ok"]:
			_pending.erase(key)
			_failed[key] = Time.get_ticks_msec() / 1000.0 + RETRY_AFTER
			return
		objects = r1["data"]["objects"]
		lots = r2["data"]["lots"]
		var d: Dictionary = r1["data"]["day"]
		day = int(d["index"])
		next_rollover = int(d["next_rollover"])
	_pending.erase(key)
	if not is_inside_tree():
		return
	# O personagem pode ter ido embora enquanto o pedido corria.
	if _focus.normalized().angle_to(world.chunk_center[key]) * world.radius - float(world.chunk_radius[key]) > radius * 1.35:
		return
	for o: Dictionary in objects:
		_prepare_object(o)
		_objects[int(o["id"])] = o
	for l: Dictionary in lots:
		_lots[int(l["id"])] = l
	if not cells.is_empty():
		borders.add_response(r3["data"])
	_chunks[key] = {"objects": objects, "lots": lots}
	chunk_loaded.emit(key)


func _prepare_object(o: Dictionary) -> void:
	var f := frame(int(o["cell"]))
	o["id"] = int(o["id"])
	o["cell"] = int(o["cell"])
	# Flores usam o modelo com as pétalas na cor do item (flower_red → "flower:red").
	if str(o["kind"]) == "flower" and str(o.get("item", "")).begins_with("flower_"):
		o["model"] = "flower:" + str(o["item"]).substr(7)
	o["pos"] = WorldData.frame_point(f, float(o["x"]), float(o["y"]))
	o["basis"] = WorldData.frame_basis(f, float(o["yaw"]), float(o["scale"]))
	o["up"] = f["center"]
	o["hidden"] = _is_hidden(o)


static func _is_hidden(o: Dictionary) -> bool:
	var st: Variant = o.get("state")
	if not (st is Dictionary):
		return false
	return str(o["kind"]) in ["flower", "pebble", "branch"] and int((st as Dictionary).get("pick", 0)) >= 1


func _unload(key: int) -> void:
	chunk_unloaded.emit(key)  # antes de apagar, para quem ouve ainda ver os objetos
	var c: Dictionary = _chunks.get(key, {})
	for o: Dictionary in c.get("objects", []):
		_objects.erase(o["id"])
	for l: Dictionary in c.get("lots", []):
		_lots.erase(int(l["id"]))
	for cell in world.chunk_cells[key]:
		borders.remove_cell(cell)
	_chunks.erase(key)


## Atualiza o estado de um objeto depois de uma interação.
func set_object_state(id: int, state: Dictionary) -> void:
	var o: Dictionary = _objects.get(id, {})
	if o.is_empty():
		return
	o["state"] = state
	o["hidden"] = _is_hidden(o)
	object_changed.emit(o)


## Atualiza um lote (resposta de /lot/place, /lot/remove, /lot/house ou /me).
func set_lot(l: Dictionary) -> void:
	var id := int(l["id"])
	var key := world.chunk_of_cell(int(l["cell"]))
	if _chunks.has(key):
		var lots: Array = _chunks[key]["lots"]
		var replaced := false
		for i in lots.size():
			if int(lots[i]["id"]) == id:
				lots[i] = l
				replaced = true
		if not replaced:
			lots.append(l)
	_lots[id] = l
	lot_changed.emit(l)


## Objetos (não escondidos) a até `r` unidades do ponto.
func objects_near(point: Vector3, r: float) -> Array:
	var out: Array = []
	for key: int in world.chunks_near(point, r):
		for o: Dictionary in _chunks.get(key, {}).get("objects", []):
			if not o["hidden"] and (o["pos"] as Vector3).distance_squared_to(point) <= r * r:
				out.append(o)
	return out


## Lotes carregados.
func all_lots() -> Array:
	return _lots.values()
