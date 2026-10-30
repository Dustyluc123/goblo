class_name BorderLines
extends Node3D
## Fronteira viva (fases 2.5 e 3, ADR 0038), só onde dois países se encontram (a costa não
## ganha nada):
## - no chão, a faixa tracejada clarinha;
## - em cima dela, uma cortina de luz baixa e translúcida em tons pastel, ondulando, com
##   brilhinhos subindo;
## - marcos (postes baixos com bolinha) a cada poucos metros, com uma corda de bandeirolas
##   de festa entre eles e um cadeadinho em cima.
## O estado é por jogador: com os passaportes dos dois países do par, a fronteira está
## aberta (cortina baixa e quase transparente, em menta; corda erguida em arco; cadeado
## aberto). Sem um deles, fechada (rosa e lilás, corda baixa, cadeado fechado). Ao comprar
## um passaporte, as fronteiras perto abrem com uma animação; ao encostar numa fechada,
## sai uma onda a partir do ponto de contato.
##
## Montada por pedaço quando as fronteiras chegam do servidor (ChunkData.borders): as
## contas rodam numa thread e o nó entra no quadro seguinte. Cada par de países tem os
## próprios materiais (ShaderMaterial do border_curtain.gdshader), então abrir ou fechar
## só muda um parâmetro, sem remontar nada.
##
## Modo debug (painel F1): desenha também a costa e os segmentos com a cor de cada país.

const DASH_ON := 0.55
const DASH_OFF := 0.35
const WIDTH := 0.12
const STEP := 0.25
const LIFT := 0.035
## Marcos: onde a linha cruza a grade global de MARKER_GRID unidades (igual vista de
## qualquer pedaço), com pelo menos MARKER_MIN entre um e outro.
const MARKER_GRID := 6.0
const MARKER_MIN := 3.0
const HIDE_ABOVE_ZOOM := 0.3
## Bandeirolas: uma a cada FLAG_EVERY unidades, penduradas na corda.
const FLAG_EVERY := 0.32
const FLAG_COLORS := [Color("ff9fb8"), Color("ffd27f"), Color("9fe0c0"), Color("a9c8ff"), Color("d7b4ff")]
const CURTAIN_SHADER := preload("res://shaders/border_curtain.gdshader")
## Duração (s) da animação de abrir ou fechar e da onda ao encostar.
const OPEN_TIME := 1.6
const RIPPLE_TIME := 2.0

var world: WorldData
var data: ChunkData
var show_lines := true
var debug := false
## Diz se o jogador tem o passaporte de um país (GameMain liga a Session).
var has_passport := func(_code: String) -> bool: return false
## Visão forçada pelo modo dev: "" (pelos passaportes), "open" ou "closed".
var view_override := ""

var _chunks := {}  # chave → Node3D
var _tasks := {}  # chave → {"id": tarefa, "out": [resultado]}
var _line_mat: StandardMaterial3D
var _post_mesh: Mesh
var _cap_mesh: Mesh
var _icon_mesh: Mesh
var _atlas: ImageTexture
## Par de países ("BRA|PRY") → {"curtain", "ribbon", "icon": ShaderMaterial, "open": float,
## "target": float, "ripple": float (idade, < 0 = nenhuma)}.
var _pairs := {}


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
	var quad := QuadMesh.new()
	quad.size = Vector2(0.26, 0.26)
	_icon_mesh = _baked(quad, null)
	_atlas = icon_atlas()


## Malha primitiva convertida em ArrayMesh (o MultiMesh com PrimitiveMesh dá erro no
## renderizador falso dos testes headless).
static func _baked(prim: PrimitiveMesh, mat: Material) -> ArrayMesh:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, prim.get_mesh_arrays())
	if mat:
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


func _process(delta: float) -> void:
	_animate(delta)
	for key: int in _tasks.keys():
		var t: Dictionary = _tasks[key]
		if not WorkerThreadPool.is_task_completed(t["id"]):
			continue
		WorkerThreadPool.wait_for_task_completion(t["id"])
		_tasks.erase(key)
		if data.is_loaded(key) and not _chunks.has(key) and (show_lines or debug) and not (t["out"] as Array).is_empty():
			var t0 := Time.get_ticks_usec()
			_make_node(key, t["out"][0])
			HitchLog.note("fronteira do pedaço %d" % key, (Time.get_ticks_usec() - t0) / 1000.0)
		return  # um por quadro


func update_view(far_amount: float) -> void:
	visible = far_amount < HIDE_ABOVE_ZOOM


# --- Estado (aberta / fechada) ------------------------------------------------------------

## Chave do par de países, em ordem ("BRA|PRY").
static func pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


## A fronteira entre os dois países está aberta para este jogador?
func is_open(pair: String) -> bool:
	if view_override == "open":
		return true
	if view_override == "closed":
		return false
	for code: String in pair.split("|"):
		if not has_passport.call(code):
			return false
	return true


## Confere de novo o estado de todos os pares (passaporte comprado ou tirado, visão do
## modo dev). Com `animate`, a troca anima; sem, muda na hora.
func refresh_state(animate := true) -> void:
	for pair: String in _pairs:
		var e: Dictionary = _pairs[pair]
		e["target"] = 1.0 if is_open(pair) else 0.0
		if not animate:
			e["open"] = e["target"]
			_apply(e)


## Encostou numa fronteira fechada: onda a partir do ponto, na cortina daquele par.
func touch(pos: Vector3, country_a: String, country_b: String) -> void:
	var e: Dictionary = _pairs.get(pair_key(country_a, country_b), {})
	if e.is_empty():
		return
	(e["curtain"] as ShaderMaterial).set_shader_parameter("ripple_origin", pos)
	e["ripple"] = 0.0
	_apply(e)


## Quanto o par está aberto agora (0 a 1; testes).
func openness(pair: String) -> float:
	return float(_pairs.get(pair, {}).get("open", -1.0))


func _pair(pair: String) -> Dictionary:
	if not _pairs.has(pair):
		var e := {"open": 1.0 if is_open(pair) else 0.0, "ripple": -1.0}
		e["target"] = e["open"]
		for part: String in ["curtain", "ribbon", "icon"]:
			var m := ShaderMaterial.new()
			m.shader = CURTAIN_SHADER
			m.set_shader_parameter("part", ["curtain", "ribbon", "icon"].find(part))
			if part == "icon":
				m.set_shader_parameter("icon_atlas", _atlas)
			e[part] = m
		_pairs[pair] = e
		_apply(e)
	return _pairs[pair]


func _apply(e: Dictionary) -> void:
	for part: String in ["curtain", "ribbon", "icon"]:
		(e[part] as ShaderMaterial).set_shader_parameter("openness", float(e["open"]))
	(e["curtain"] as ShaderMaterial).set_shader_parameter("ripple_age", float(e["ripple"]))


func _animate(delta: float) -> void:
	for pair: String in _pairs:
		var e: Dictionary = _pairs[pair]
		var changed := false
		if not is_equal_approx(float(e["open"]), float(e["target"])):
			e["open"] = move_toward(float(e["open"]), float(e["target"]), delta / OPEN_TIME)
			changed = true
		if float(e["ripple"]) >= 0.0:
			e["ripple"] = float(e["ripple"]) + delta
			if float(e["ripple"]) > RIPPLE_TIME:
				e["ripple"] = -1.0
			changed = true
		if changed:
			_apply(e)


# --- Montagem por pedaço --------------------------------------------------------------------

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


## Contas (pode rodar numa thread: só lê o mundo). Junta os segmentos compartilhados em
## linhas contínuas por par de países e monta, para cada par: a faixa do chão, a cortina, as
## bandeirolas e a posição dos marcos.
func _compute(job: Dictionary, dbg: bool) -> Dictionary:
	var cells := {}
	for c in job["cells"]:
		cells[c] = true
	# 1. Segmentos sem repetição: chave → [a, b, célula perto, países dos dois lados].
	var segs := {}
	var coast: Array = []
	for pair_c: Array in job["segs"]:
		var c: int = pair_c[0]
		for s: Array in pair_c[1]:
			var a: Vector3 = s[0]
			var b: Vector3 = s[1]
			var k := _seg_key(a, b)
			if not bool(s[3]):
				if dbg and not segs.has(k):
					coast.append([a, b, c, str(s[2])])
					segs[k] = null
				continue
			if not segs.has(k) or segs[k] == null:
				segs[k] = [a, b, c, {}]
			(segs[k][3] as Dictionary)[str(s[2])] = true
	# 2. Por par de países, linhas contínuas (ligando pontas iguais).
	var by_pair := {}
	for k: String in segs:
		var sg: Variant = segs[k]
		if sg == null:
			continue
		var codes: Array = (sg[3] as Dictionary).keys()
		if codes.size() < 2:
			codes.append("?")
		codes.sort()
		var pk := pair_key(str(codes[0]), str(codes[1]))
		if not by_pair.has(pk):
			by_pair[pk] = []
		(by_pair[pk] as Array).append(sg)
	var out := {"pairs": {}, "debug": {}}
	for pk: String in by_pair:
		var lines := _chain(by_pair[pk])
		var r := {"line_v": PackedVector3Array(), "line_c": PackedColorArray(),
			"cur_v": PackedVector3Array(), "cur_n": PackedVector3Array(), "cur_uv": PackedVector2Array(),
			"rib_v": PackedVector3Array(), "rib_n": PackedVector3Array(), "rib_uv": PackedVector2Array(), "rib_c": PackedColorArray(),
			"markers": []}
		var col := _country_color(pk) if dbg else Color("fff3d6")
		for line: Dictionary in lines:
			_build_line(line, cells, col, r)
		out["pairs"][pk] = r
	if dbg:
		var d := {"line_v": PackedVector3Array(), "line_c": PackedColorArray()}
		for sg: Array in coast:
			_debug_segment(sg[0], sg[1], sg[2], cells, Color("ff4d6d"), d)
		out["debug"] = d
	return out


## Liga os segmentos em linhas: cada linha é uma lista de pontos (direções unitárias) e uma
## célula perto (pista para achar as células das amostras).
func _chain(list: Array) -> Array:
	var by_end := {}  # ponta → índices dos segmentos
	for i in list.size():
		for p: Vector3 in [list[i][0], list[i][1]]:
			var k := _pt_key(p)
			if not by_end.has(k):
				by_end[k] = []
			(by_end[k] as Array).append(i)
	var used := {}
	var lines: Array = []
	for i in list.size():
		if used.has(i):
			continue
		used[i] = true
		var pts: Array = [list[i][0], list[i][1]]
		# Cresce para os dois lados enquanto houver um segmento ligado ainda não usado.
		for side in 2:
			while true:
				var tip: Vector3 = pts[pts.size() - 1] if side == 0 else pts[0]
				var next := -1
				for j: int in by_end.get(_pt_key(tip), []):
					if not used.has(j):
						next = j
						break
				if next < 0:
					break
				used[next] = true
				var a: Vector3 = list[next][0]
				var b: Vector3 = list[next][1]
				var other := b if _pt_key(a) == _pt_key(tip) else a
				if side == 0:
					pts.append(other)
				else:
					pts.insert(0, other)
		lines.append({"pts": pts, "cell": list[i][2]})
	return lines


static func _pt_key(p: Vector3) -> String:
	return "%.5f,%.5f,%.5f" % [p.x, p.y, p.z]


static func _seg_key(a: Vector3, b: Vector3) -> String:
	var ka := _pt_key(a)
	var kb := _pt_key(b)
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


## Amostras de uma linha no chão: [ponto, célula, distância desde o começo da linha].
func _samples(line: Dictionary) -> Array:
	var pts: Array = line["pts"]
	var hint: int = line["cell"]
	var out: Array = []
	var dist := 0.0
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var length := a.angle_to(b) * world.radius
		var n := maxi(1, ceili(length / STEP))
		for k in range(0 if i == 0 else 1, n + 1):
			var t := float(k) / n
			var g := _ground(a.slerp(b, t).normalized(), hint)
			hint = g[1]
			out.append([g[0], g[1], dist + t * length])
		dist += length
	return out


## Faixa, cortina, marcos e bandeirolas de uma linha (só nas amostras das células do pedaço).
func _build_line(line: Dictionary, cells: Dictionary, col: Color, r: Dictionary) -> void:
	var smp := _samples(line)
	if smp.size() < 2:
		return
	# Marcos: onde a linha cruza a grade global (o mesmo lugar vindo de qualquer pedaço).
	var marks: Array[int] = []
	var last_mark := -INF
	for i in range(1, smp.size()):
		var p0: Vector3 = smp[i - 1][0]
		var p1: Vector3 = smp[i][0]
		var crossed := floori(p0.x / MARKER_GRID) != floori(p1.x / MARKER_GRID) \
			or floori(p0.y / MARKER_GRID) != floori(p1.y / MARKER_GRID) \
			or floori(p0.z / MARKER_GRID) != floori(p1.z / MARKER_GRID)
		if crossed and float(smp[i][2]) - last_mark >= MARKER_MIN:
			marks.append(i)
			last_mark = float(smp[i][2])
	var period := DASH_ON + DASH_OFF
	var flag_i := 0
	var next_flag := 0.0
	for i in range(1, smp.size()):
		var prev: Array = smp[i - 1]
		var cur: Array = smp[i]
		if not (cells.has(prev[1]) and cells.has(cur[1])):
			continue
		var p0: Vector3 = prev[0]
		var p1: Vector3 = cur[0]
		var mid: float = (float(prev[2]) + float(cur[2])) * 0.5
		if fmod(mid, period) < DASH_ON:
			_quad(p0, p1, col, r["line_v"], r["line_c"])
		_curtain_quad(p0, p1, float(prev[2]), float(cur[2]), r)
		# Bandeirolas entre o marco de antes e o de depois.
		var before := -1
		var after := -1
		for m in marks:
			if m <= i - 1:
				before = m
			elif m >= i and after < 0:
				after = m
		if before < 0 or after < 0:
			continue
		var d0 := float(smp[before][2])
		var d1 := float(smp[after][2])
		var span := maxf(d1 - d0, 0.01)
		_rope_quad(p0, p1, (float(prev[2]) - d0) / span, (float(cur[2]) - d0) / span, r)
		while next_flag <= float(cur[2]):
			if next_flag >= float(prev[2]) and next_flag > d0 + 0.15 and next_flag < d1 - 0.15:
				var k := (next_flag - float(prev[2])) / maxf(float(cur[2]) - float(prev[2]), 0.0001)
				_flag(p0.lerp(p1, k), (p1 - p0).normalized(), (next_flag - d0) / span, FLAG_COLORS[flag_i % FLAG_COLORS.size()], r)
				flag_i += 1
			next_flag += FLAG_EVERY
	for m in marks:
		if not cells.has(smp[m][1]):
			continue
		var p: Vector3 = smp[m][0]
		var up := p.normalized()
		var fwd := (p - (smp[m - 1][0] as Vector3)).normalized()
		var x := fwd.cross(up).normalized()
		(r["markers"] as Array).append(Transform3D(Basis(x, up, x.cross(up)), p + up * 0.25 - up * LIFT))


## Pedaço da cortina entre dois pontos do chão (o shader levanta pela UV.y).
func _curtain_quad(p0: Vector3, p1: Vector3, d0: float, d1: float, r: Dictionary) -> void:
	var up := p0.normalized()
	var side := (p1 - p0).cross(up).normalized()
	var v: PackedVector3Array = r["cur_v"]
	var n: PackedVector3Array = r["cur_n"]
	var uv: PackedVector2Array = r["cur_uv"]
	v.append_array([p0, p0, p1, p0, p1, p1])
	for k in 6:
		n.append(side)
	uv.append_array([Vector2(d0, 0), Vector2(d0, 1), Vector2(d1, 1), Vector2(d0, 0), Vector2(d1, 1), Vector2(d1, 0)])
	r["cur_v"] = v
	r["cur_n"] = n
	r["cur_uv"] = uv


## Pedaço da corda (fita fininha) entre dois pontos; t0, t1: posição entre os marcos.
func _rope_quad(p0: Vector3, p1: Vector3, t0: float, t1: float, r: Dictionary) -> void:
	var up := p0.normalized()
	var side := (p1 - p0).cross(up).normalized()
	var h := 0.025
	var v: PackedVector3Array = r["rib_v"]
	var n: PackedVector3Array = r["rib_n"]
	var uv: PackedVector2Array = r["rib_uv"]
	var c: PackedColorArray = r["rib_c"]
	v.append_array([p0, p0, p1, p0, p1, p1])
	uv.append_array([Vector2(t0, -h), Vector2(t0, h), Vector2(t1, h), Vector2(t0, -h), Vector2(t1, h), Vector2(t1, -h)])
	for k in 6:
		n.append(side)
		c.append(Color("fff8ee"))
	r["rib_v"] = v
	r["rib_n"] = n
	r["rib_uv"] = uv
	r["rib_c"] = c


## Uma bandeirola (triângulo pendurado na corda).
func _flag(p: Vector3, along: Vector3, t: float, col: Color, r: Dictionary) -> void:
	var up := p.normalized()
	var side := along.cross(up).normalized()
	var w := 0.09
	var v: PackedVector3Array = r["rib_v"]
	var n: PackedVector3Array = r["rib_n"]
	var uv: PackedVector2Array = r["rib_uv"]
	var c: PackedColorArray = r["rib_c"]
	v.append_array([p - along * w, p + along * w, p])
	uv.append_array([Vector2(t, 0.0), Vector2(t, 0.0), Vector2(t, -0.17)])
	for k in 3:
		n.append(side)
		c.append(col)
	r["rib_v"] = v
	r["rib_n"] = n
	r["rib_uv"] = uv
	r["rib_c"] = c


## Segmento solto (costa no modo debug): faixa contínua.
func _debug_segment(a: Vector3, b: Vector3, hint: int, cells: Dictionary, col: Color, d: Dictionary) -> void:
	var smp := _samples({"pts": [a, b], "cell": hint})
	for i in range(1, smp.size()):
		if cells.has(smp[i - 1][1]) and cells.has(smp[i][1]):
			_quad(smp[i - 1][0], smp[i][0], col, d["line_v"], d["line_c"])


func _quad(p0: Vector3, p1: Vector3, col: Color, verts: PackedVector3Array, colors: PackedColorArray) -> void:
	var up := p0.normalized()
	var side := (p1 - p0).cross(up).normalized() * (WIDTH * 0.5)
	verts.append_array([p0 - side, p0 + side, p1 + side, p0 - side, p1 + side, p1 - side])
	for k in 6:
		colors.append(col)


# --- Nós ----------------------------------------------------------------------------------

## Nó do pedaço (na thread principal): por par, a faixa, a cortina, as bandeirolas, os
## marcos e os cadeados.
func _make_node(key: int, res: Dictionary) -> void:
	var node := Node3D.new()
	for pk: String in res["pairs"]:
		var group := _build_group(pk, res["pairs"][pk])
		if group:
			node.add_child(group)
	var dbg: Dictionary = res.get("debug", {})
	if not dbg.is_empty():
		_add_mesh(node, {Mesh.ARRAY_VERTEX: dbg["line_v"], Mesh.ARRAY_COLOR: dbg["line_c"]}, _line_mat)
	if node.get_child_count() == 0:
		node.free()
		return
	add_child(node)
	_chunks[key] = node


## As peças de um par de países num pedaço (null se não houver nada).
func _build_group(pk: String, r: Dictionary) -> Node3D:
	var e := _pair(pk)
	var group := Node3D.new()
	group.name = pk.replace("|", "_")
	group.set_meta("pair", pk)
	_add_mesh(group, {Mesh.ARRAY_VERTEX: r["line_v"], Mesh.ARRAY_COLOR: r["line_c"]}, _line_mat)
	if not debug:
		_add_mesh(group, {Mesh.ARRAY_VERTEX: r["cur_v"], Mesh.ARRAY_NORMAL: r["cur_n"], Mesh.ARRAY_TEX_UV: r["cur_uv"]}, e["curtain"])
		_add_mesh(group, {Mesh.ARRAY_VERTEX: r["rib_v"], Mesh.ARRAY_NORMAL: r["rib_n"], Mesh.ARRAY_TEX_UV: r["rib_uv"], Mesh.ARRAY_COLOR: r["rib_c"]}, e["ribbon"])
	var markers: Array = r["markers"]
	if not markers.is_empty():
		var parts: Array = [[_post_mesh, Vector3.ZERO, null], [_cap_mesh, Vector3(0, 0.27, 0), null]]
		if not debug:
			parts.append([_icon_mesh, Vector3(0, 0.55, 0), e["icon"]])
		for part: Array in parts:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = markers.size()
			for i in markers.size():
				mm.set_instance_transform(i, (markers[i] as Transform3D).translated_local(part[1]))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if part[2] != null:
				mmi.material_override = part[2]
			group.add_child(mmi)
	if group.get_child_count() == 0:
		group.free()
		return null
	return group


## MeshInstance3D com uma superfície (nada se não houver vértices). Devolve se criou.
func _add_mesh(parent: Node3D, data_arrays: Dictionary, mat: Material) -> bool:
	var verts: PackedVector3Array = data_arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return false
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	for k: int in data_arrays:
		arrays[k] = data_arrays[k]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A malha fica no chão; o shader levanta a cortina e as bandeirolas.
	mi.extra_cull_margin = 2.0
	parent.add_child(mi)
	return true


## Pedaços de cada peça, para o pré-aquecimento dos shaders.
func warm_nodes() -> Array[Node3D]:
	var r := {"line_v": PackedVector3Array(), "line_c": PackedColorArray(),
		"cur_v": PackedVector3Array(), "cur_n": PackedVector3Array(), "cur_uv": PackedVector2Array(),
		"rib_v": PackedVector3Array(), "rib_n": PackedVector3Array(), "rib_uv": PackedVector2Array(), "rib_c": PackedColorArray(),
		"markers": []}
	var a := Vector3(0, 0, 1)
	var b := Vector3(0.5, 0, 1)
	_quad(a, b, Color("fff3d6"), r["line_v"], r["line_c"])
	_curtain_quad(a, b, 0.0, 0.5, r)
	_rope_quad(a, b, 0.0, 1.0, r)
	_flag(a, Vector3.RIGHT, 0.5, FLAG_COLORS[0], r)
	(r["markers"] as Array).append(Transform3D(Basis(), a))
	var group := _build_group("WARM|UP", r)
	_pairs.erase("WARM|UP")
	var out: Array[Node3D] = []
	for c in group.get_children():
		group.remove_child(c)
		out.append(c)
	group.free()
	return out


## Atlas dos ícones dos marcos: cadeado fechado (esquerda) e aberto (direita), num
## círculo branco, desenhados em código.
static func icon_atlas() -> ImageTexture:
	var s := 64
	var img := Image.create(s * 2, s, false, Image.FORMAT_RGBA8)
	for half in 2:
		var ox := half * s
		var body_c := Color("e98aa8") if half == 0 else Color("5dbb8f")
		for y in s:
			for x in s:
				var cx := x - s * 0.5 + 0.5
				var cy := y - s * 0.5 + 0.5
				var d := sqrt(cx * cx + cy * cy)
				var col := Color(0, 0, 0, 0)
				if d < s * 0.47:
					col = Color(1, 1, 1, 0.95)  # disquinho branco
				# Corpo do cadeado.
				if absf(cx) < 12 and cy > -2 and cy < 16:
					col = body_c
				# Furinho.
				if absf(cx) < 2.5 and cy > 4 and cy < 10:
					col = Color(1, 1, 1, 1)
				# Alça: um arco; aberto, deslocado para cima e para a direita.
				var ax := cx - (6.0 if half == 1 else 0.0)
				var ay := cy + (6.0 if half == 1 else 0.0)
				var ad := sqrt(ax * ax + (ay + 2) * (ay + 2))
				if ad > 6.5 and ad < 10.5 and ay < -1:
					col = body_c.darkened(0.15)
				if half == 1 and ax > 6.5 and ax < 10.5 and ay > -3 and ay < 2:
					col = Color(1, 1, 1, 0.95)  # aberto: a perna direita não entra
				img.set_pixel(ox + x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
