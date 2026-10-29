class_name BorderLines
extends Node3D
## Linha de fronteira no chão: uma faixa tracejada clarinha com marquinhos (postes baixos
## com uma bolinha laranja) a cada poucos metros, só onde dois países se encontram (a costa
## não ganha linha). Montada por pedaço, quando as fronteiras do pedaço chegam do servidor
## (ChunkData.borders), e solta junto com ele.
##
## Modo debug (painel F1): desenha também a costa e os segmentos de todos os países, com
## a cor de cada país, para conferir os polígonos.
##
## As contas (amostrar cada segmento no chão) rodam numa thread; o nó entra no quadro
## seguinte, um pedaço por quadro (fase 2.6: um pedaço com fronteira travava o jogo).

const DASH_ON := 0.55
const DASH_OFF := 0.35
const WIDTH := 0.12
const STEP := 0.25
const LIFT := 0.035
const MARKER_EVERY := 7.0
const HIDE_ABOVE_ZOOM := 0.3

var world: WorldData
var data: ChunkData
var show_lines := true
var debug := false

var _chunks := {}  # chave → Node3D
var _tasks := {}  # chave → {"id": tarefa, "out": [resultado]}
var _line_mat: StandardMaterial3D
var _post_mesh: Mesh
var _cap_mesh: Mesh


func setup(w: WorldData, d: ChunkData) -> void:
	world = w
	data = d
	data.chunk_loaded.connect(_on_chunk_loaded)
	data.chunk_unloaded.connect(_on_chunk_unloaded)
	_line_mat = StandardMaterial3D.new()
	_line_mat.albedo_color = Color("fff3d6")
	_line_mat.roughness = 1.0
	_line_mat.vertex_color_use_as_albedo = true
	_line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var post := CylinderMesh.new()
	post.top_radius = 0.045
	post.bottom_radius = 0.065
	post.height = 0.5
	post.radial_segments = 8
	post.rings = 1
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("fffaf0")
	pm.roughness = 0.9
	_post_mesh = _baked(post, pm)
	var cap := SphereMesh.new()
	cap.radius = 0.085
	cap.height = 0.17
	cap.radial_segments = 10
	cap.rings = 5
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color("f2a65a")
	cm.roughness = 0.7
	_cap_mesh = _baked(cap, cm)


## Malha primitiva convertida em ArrayMesh (o MultiMesh com PrimitiveMesh dá erro no
## renderizador falso dos testes headless).
static func _baked(prim: PrimitiveMesh, mat: Material) -> ArrayMesh:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, prim.get_mesh_arrays())
	am.surface_set_material(0, mat)
	return am


## O que mostrar (painel dev): linhas e/ou polígonos de debug. Remonta o que está carregado
## (na hora: é uma ferramenta de conferência).
func set_mode(lines: bool, show_debug: bool) -> void:
	show_lines = lines
	debug = show_debug
	for key: int in _chunks.keys():
		_on_chunk_unloaded(key)
	_wait_tasks()
	if not (show_lines or debug):
		return
	for key: int in data.loaded_keys():
		_make_node(key, _compute(_gather(key), debug))


func _wait_tasks() -> void:
	for key: int in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key]["id"])
	_tasks.clear()


func _exit_tree() -> void:
	_wait_tasks()


func _process(_delta: float) -> void:
	for key: int in _tasks.keys():
		var t: Dictionary = _tasks[key]
		if not WorkerThreadPool.is_task_completed(t["id"]):
			continue
		WorkerThreadPool.wait_for_task_completion(t["id"])
		_tasks.erase(key)
		if data.is_loaded(key) and not _chunks.has(key) and (show_lines or debug) and not (t["out"] as Array).is_empty():
			var t0 := Time.get_ticks_usec()
			_make_node(key, t["out"][0])
			HitchLog.note("linhas de fronteira do pedaço %d" % key, (Time.get_ticks_usec() - t0) / 1000.0)
		return  # um por quadro


func update_view(far_amount: float) -> void:
	visible = far_amount < HIDE_ABOVE_ZOOM


func _on_chunk_unloaded(key: int) -> void:
	if _chunks.has(key):
		(_chunks[key] as Node).queue_free()
		_chunks.erase(key)


func _on_chunk_loaded(key: int) -> void:
	if _chunks.has(key) or _tasks.has(key) or not (show_lines or debug):
		return
	var job := _gather(key)
	if job["segs"].is_empty():
		return  # longe de qualquer fronteira: nada a desenhar
	var out := []
	var dbg := debug
	var id := WorkerThreadPool.add_task(func() -> void: out.append(_compute(job, dbg)))
	_tasks[key] = {"id": id, "out": out}


## O que a thread precisa: as células do pedaço e os segmentos de cada uma (cópia das
## listas, que o mapa de fronteiras pode trocar enquanto a thread roda).
func _gather(key: int) -> Dictionary:
	var segs := []
	for c in world.chunk_cells[key]:
		var list := data.borders.segments(c)
		if not list.is_empty():
			segs.append([c, list.duplicate()])
	return {"cells": world.chunk_cells[key], "segs": segs}


## Contas da faixa e dos marquinhos (pode rodar numa thread: só lê o mundo).
func _compute(job: Dictionary, dbg: bool) -> Dictionary:
	var cells := {}
	for c in job["cells"]:
		cells[c] = true
	var seen := {}
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var markers: Array[Transform3D] = []
	var scratch: Array[Transform3D] = []  # marquinhos da costa (modo debug): descartados
	for pair: Array in job["segs"]:
		var c: int = pair[0]
		for s: Array in pair[1]:
			var shared: bool = s[3]
			if not shared and not dbg:
				continue
			var a: Vector3 = s[0]
			var b: Vector3 = s[1]
			# A fronteira compartilhada vem duas vezes (uma por país): desenha uma só.
			var k := _seg_key(a, b)
			if seen.has(k):
				continue
			seen[k] = true
			var col := Color("fff3d6")
			if dbg:
				col = _country_color(str(s[2])) if shared else Color("ff4d6d")
			_add_segment(a, b, c, cells, col, dbg and not shared, verts, colors, markers if shared else scratch)
	return {"verts": verts, "colors": colors, "markers": markers}


## Nó do pedaço (na thread principal).
func _make_node(key: int, r: Dictionary) -> void:
	var verts: PackedVector3Array = r["verts"]
	var colors: PackedColorArray = r["colors"]
	var markers: Array[Transform3D] = r["markers"]
	if verts.is_empty() and markers.is_empty():
		return
	var node := Node3D.new()
	add_child(node)
	_chunks[key] = node
	if not verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _line_mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
	if not markers.is_empty():
		for mesh: Mesh in [_post_mesh, _cap_mesh]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = markers.size()
			for i in markers.size():
				var t := markers[i]
				if mesh == _cap_mesh:
					t = t.translated_local(Vector3(0, 0.27, 0))
				mm.set_instance_transform(i, t)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			node.add_child(mmi)


## Um pedacinho de faixa e um marquinho, para o pré-aquecimento dos shaders.
func warm_nodes() -> Array[Node3D]:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	_quad(Vector3(0, 0, 0), Vector3(0, 0, 1), Color("fff3d6"), verts, colors)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var line := ArrayMesh.new()
	line.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	line.surface_set_material(0, _line_mat)
	var out: Array[Node3D] = []
	for mesh: Mesh in [line, _post_mesh, _cap_mesh]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = 1
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		out.append(mmi)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		out.append(mi)
	return out


static func _seg_key(a: Vector3, b: Vector3) -> String:
	var ka := "%.5f,%.5f,%.5f" % [a.x, a.y, a.z]
	var kb := "%.5f,%.5f,%.5f" % [b.x, b.y, b.z]
	return ka + "|" + kb if ka < kb else kb + "|" + ka


static func _country_color(code: String) -> Color:
	var h := float(hash(code) % 1000) / 1000.0
	return Color.from_hsv(h, 0.55, 0.95)


## Ponto no chão (topo plano da célula) na direção `dir`.
func _ground(dir: Vector3, hint: int) -> Array:
	var cell := world.find_cell(dir, hint)
	var c := world.centers[cell]
	var top := world.surface_radius(cell)
	var p := dir * (top / maxf(dir.dot(c), 0.5)) + c * LIFT
	return [p, cell]


## Faixa tracejada ao longo do arco a→b, só nas amostras que caem nas células do pedaço.
## `near_cell` é uma célula perto do segmento: a busca da célula de cada amostra começa
## dali (sem pista, a busca varre o mundo inteiro e um pedaço levava 300 ms).
func _add_segment(a: Vector3, b: Vector3, near_cell: int, cells: Dictionary, col: Color, solid: bool,
		verts: PackedVector3Array, colors: PackedColorArray, markers: Array[Transform3D]) -> void:
	var angle := a.angle_to(b)
	var length := angle * world.radius
	if length <= 0.0001:
		return
	var n := maxi(1, ceili(length / STEP))
	var hint := near_cell
	var prev: Array = []
	var period := DASH_ON + DASH_OFF
	for i in n + 1:
		var t := float(i) / n
		var dir := a.slerp(b, t).normalized()
		var g := _ground(dir, hint)
		hint = g[1]
		var cur := [g[0], g[1], t * length]
		if not prev.is_empty() and cells.has(prev[1]) and cells.has(cur[1]):
			var mid: float = (float(prev[2]) + float(cur[2])) * 0.5
			if solid or fmod(mid, period) < DASH_ON:
				_quad(prev[0], cur[0], col, verts, colors)
		# Marquinho a cada MARKER_EVERY unidades (a contar do começo do segmento).
		if i > 0 and cells.has(cur[1]) and floorf(float(cur[2]) / MARKER_EVERY) > floorf(float(prev[2]) / MARKER_EVERY):
			var up: Vector3 = (cur[0] as Vector3).normalized()
			var fwd := ((cur[0] as Vector3) - (prev[0] as Vector3)).normalized()
			var x := fwd.cross(up).normalized()
			markers.append(Transform3D(Basis(x, up, x.cross(up)), (cur[0] as Vector3) + up * 0.25 - up * LIFT))
		prev = cur


func _quad(p0: Vector3, p1: Vector3, col: Color, verts: PackedVector3Array, colors: PackedColorArray) -> void:
	var up := p0.normalized()
	var side := (p1 - p0).cross(up).normalized() * (WIDTH * 0.5)
	verts.append_array([p0 - side, p0 + side, p1 + side, p0 - side, p1 + side, p1 - side])
	for k in 6:
		colors.append(col)
