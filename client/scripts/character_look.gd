class_name CharacterLook
extends Node
## Visual do personagem (fase 4.0, ADR 0051): editor e roupas numa malha só por personagem.
##
## Os 12 personagens do Mini Characters têm o mesmo esqueleto (root, pernas, tronco, braços e
## cabeça, na mesma ordem) e duas malhas: "body-mesh" (tronco, braços e pernas) e
## "head-mesh" (cabeça com o cabelo). Dá para misturar: a cabeça de um, o tronco de outro e as
## pernas de um terceiro (os triângulos do corpo são separados pelo osso que mais pesa).
##
## Por cima, o que não existe no pacote é montado aqui, no mesmo estilo:
## - roupas de corpo e pernas: "cascas" um pouco maiores que o corpo, copiadas dos triângulos
##   do tronco, dos braços ou das pernas, com a cor da peça; elas usam os mesmos pesos dos
##   ossos e acompanham as animações;
## - chapéus, cachecol, sandálias, penteados extras e a capa: formas simples presas a um osso;
## - óculos do pacote, presos à cabeça.
## Tudo vira UMA malha (uma superfície; duas com a capa, que usa o atlas de bandeiras), com
## um material só para todos os personagens: pele e cabelo trocam de cor por parâmetro de
## instância (sem material por jogador). A malha é montada numa thread e fica em cache pela
## combinação (partes + roupas + cores das roupas): jogadores iguais dividem a mesma malha.
##
## Cor do vértice: rgb = cor da peça; alfa = modo (0 textura, 0,25 pele, 0,5 cabelo,
## 0,75 cabelo extra, 1 cor do vértice). Ver shaders/character_look.gdshader.

const DIR := "res://assets/kenney/mini-characters/"
const SHADER := preload("res://shaders/character_look.gdshader")
const CAPE_SHADER := preload("res://shaders/character_cape.gdshader")
const B_ROOT := 0
const B_LEG_L := 1
const B_LEG_R := 2
const B_TORSO := 3
const B_ARM_L := 4
const B_ARM_R := 5
const B_HEAD := 6
const MODE_TEX := 0.0
const MODE_SKIN := 0.25
const MODE_HAIR := 0.5
const MODE_HAIR_EXTRA := 0.75
const MODE_COLOR := 1.0
## Quantas montagens de malha podem rodar ao mesmo tempo (threads).
const MAX_TASKS := 2

static var instance: CharacterLook
## Parte ("female-a") → {head: arrays, body: arrays, skin_head: Color, skin_body: Color,
## hair: Color, top: float, front: float, height: float}
static var _parts := {}
static var _prims := {}  # nome → arrays de uma forma unitária (thread principal)
static var _accessories := {}  # nome → arrays no espaço do personagem
static var _palette: Image
static var _material: ShaderMaterial
static var _cape_mats := {}  # países da capa → material com a textura das bandeiras
static var _meshes := {}  # chave → ArrayMesh pronta
static var _pending := {}  # chave → {"task", "out", "waiting": [Callable]}
static var _queue: Array = []  # chaves esperando thread

## Cores: hex → Color linear (para a cor do vértice e os parâmetros de instância).
static func lin(hex: String) -> Color:
	return Color(hex).srgb_to_linear() if not hex.is_empty() else Color(0, 0, 0, 0)


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	for k: String in _pending:
		WorkerThreadPool.wait_for_task_completion(_pending[k]["task"])
	_pending.clear()
	if instance == self:
		instance = null


## Carrega as partes dos 12 personagens e as formas (na entrada do jogo).
static func prepare(parts: Array) -> void:
	if _palette == null:
		var tex: Texture2D = load(DIR + "Textures/colormap.png")
		_palette = tex.get_image()
		if _palette.is_compressed():
			_palette.decompress()
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("colormap", tex)
	for part: String in parts:
		if _parts.has(part):
			continue
		var scene := load(DIR + "character-" + part + ".glb") as PackedScene
		if scene == null:
			continue
		var root := scene.instantiate()
		var head: MeshInstance3D = root.find_child("head-mesh", true, false)
		var body: MeshInstance3D = root.find_child("body-mesh", true, false)
		if head == null or body == null:
			root.free()
			continue
		var ha := head.mesh.surface_get_arrays(0)
		var ba := body.mesh.surface_get_arrays(0)
		_parts[part] = _measure(ha, ba)
		root.free()
	_make_prims()
	for acc in ["aid-glasses", "aid-sunglasses"]:
		if _accessories.has(acc):
			continue
		var sc := load(DIR + acc + ".glb") as PackedScene
		if sc == null:
			continue
		var root := sc.instantiate() as Node3D
		var merged := []
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			var xf := Transform3D.IDENTITY
			var n: Node = mi
			while n != root and n is Node3D:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			for si in mi.mesh.get_surface_count():
				merged.append([mi.mesh.surface_get_arrays(si), xf])
		_accessories[acc] = merged
		root.free()


## Mede uma parte. A paleta do Mini Characters é uma grade de 4 × 4 quadrados, cada um um
## degradê de uma cor: a pele e o cabelo são reconhecidos pelo quadrado (não pela cor exata,
## que muda com o sombreado). Pele da cabeça: o quadrado mais usado no rosto (vértices de
## frente); cabelo: o mais usado no alto da cabeça (fora a pele); pele do corpo: o das mãos.
static func _measure(ha: Array, ba: Array) -> Dictionary:
	var hv: PackedVector3Array = ha[Mesh.ARRAY_VERTEX]
	var hn: PackedVector3Array = ha[Mesh.ARRAY_NORMAL]
	var huv: PackedVector2Array = ha[Mesh.ARRAY_TEX_UV]
	var top := -INF
	var front := -INF
	var mid_y := 0.0
	for i in hv.size():
		mid_y += hv[i].y
		top = maxf(top, hv[i].y)
		front = maxf(front, hv[i].z)
	mid_y /= maxf(hv.size(), 1)
	var face := {}
	for i in hv.size():
		_vote(face, _cell(huv[i]), _sample(huv[i]))
	var crown := {}
	var hmin := INF
	for v in hv:
		hmin = minf(hmin, v.y)
	for i in hv.size():
		if hv[i].y > top - (top - hmin) * 0.2:
			_vote(crown, _cell(huv[i]), _sample(huv[i]))
	var hair := _winner(crown, Vector2i(-1, -1))
	var skin_head := _skin_cells(face, hair)
	var bv: PackedVector3Array = ba[Mesh.ARRAY_VERTEX]
	var buv: PackedVector2Array = ba[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = ba[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = ba[Mesh.ARRAY_WEIGHTS]
	var arm_low := INF
	var arm_high := -INF
	var torso_top := -INF
	var torso_back := INF
	var torso_w := 0.0
	var foot := INF
	var leg_top := -INF
	for i in bv.size():
		var b := _dominant(bones, weights, i)
		if b == B_ARM_L or b == B_ARM_R:
			arm_low = minf(arm_low, bv[i].y)
			arm_high = maxf(arm_high, bv[i].y)
		if b == B_TORSO:
			torso_top = maxf(torso_top, bv[i].y)
			torso_back = minf(torso_back, bv[i].z)
			torso_w = maxf(torso_w, absf(bv[i].x))
		if b == B_LEG_L or b == B_LEG_R:
			foot = minf(foot, bv[i].y)
			leg_top = maxf(leg_top, bv[i].y)
	var hands := {}
	for i in bv.size():
		var b := _dominant(bones, weights, i)
		if (b == B_ARM_L or b == B_ARM_R) and bv[i].y < arm_low + (arm_high - arm_low) * 0.25:
			_vote(hands, _cell(buv[i]), _sample(buv[i]))
	var skin_body := _skin_cells(hands, Vector2i(-1, -1))
	return {"head": ha, "body": ba, "skin_head": skin_head, "skin_body": skin_body, "hair": hair,
		"hair_ref": _ref(crown, hair), "hmin": hmin,
		"top": top, "front": front, "mid": mid_y, "torso_top": torso_top,
		"torso_back": torso_back, "torso_w": torso_w, "foot": foot, "leg_top": leg_top, "height": top}


static func _cell(uv: Vector2) -> Vector2i:
	return Vector2i(clampi(int(uv.x * 4.0), 0, 3), clampi(int(uv.y * 4.0), 0, 3))


static func _vote(votes: Dictionary, cell: Vector2i, c: Color) -> void:
	if not votes.has(cell):
		votes[cell] = {"n": 0, "lum": 0.0}
	votes[cell]["n"] += 1
	votes[cell]["lum"] += _lum(c)


## Os quadrados com cara de pele (tom quente, saturação e brilho médios) usados pelo menos
## 20% do mais usado, menos o do cabelo: {quadrado: brilho de referência}. Sem nenhum, o
## mais usado.
static func _skin_cells(votes: Dictionary, hair: Vector2i) -> Dictionary:
	var cand := {}
	var most := 0
	for cell: Vector2i in votes:
		if cell == hair:
			continue
		var c := _palette.get_pixel(clampi(cell.x * 128 + 64, 0, 511), clampi(cell.y * 128 + 64, 0, 511))
		var hue := c.h * 360.0
		if hue >= 8.0 and hue <= 42.0 and c.s >= 0.18 and c.s <= 0.72 and c.v >= 0.3:
			cand[cell] = int(votes[cell]["n"])
			most = maxi(most, cand[cell])
	var out := {}
	for cell: Vector2i in cand:
		if cand[cell] >= most * 0.2:
			out[cell] = _ref(votes, cell)
	if out.is_empty():
		var w := _winner(votes, hair)
		if w.x >= 0:
			out[w] = _ref(votes, w)
	return out


static func _winner(votes: Dictionary, skip: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var n := 0
	for cell: Vector2i in votes:
		if cell != skip and int(votes[cell]["n"]) > n:
			n = votes[cell]["n"]
			best = cell
	return best


## Brilho médio (linear) do quadrado escolhido: a cor nova é multiplicada pela razão entre o
## brilho de cada vértice e este, para manter o sombreado do degradê.
static func _ref(votes: Dictionary, cell: Vector2i) -> float:
	if not votes.has(cell):
		return 1.0
	return maxf(float(votes[cell]["lum"]) / float(votes[cell]["n"]), 0.001)


static func _lum(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


static func _sample(uv: Vector2) -> Color:
	var x := clampi(int(uv.x * _palette.get_width()), 0, _palette.get_width() - 1)
	var y := clampi(int(uv.y * _palette.get_height()), 0, _palette.get_height() - 1)
	return _palette.get_pixel(x, y)


static func _dominant(bones: PackedInt32Array, weights: PackedFloat32Array, v: int) -> int:
	var best := 0
	var bw := -1.0
	for k in 4:
		if weights[v * 4 + k] > bw:
			bw = weights[v * 4 + k]
			best = bones[v * 4 + k]
	return best


static func _make_prims() -> void:
	if not _prims.is_empty():
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 10
	cyl.rings = 1
	_prims["cyl"] = cyl.get_mesh_arrays()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 1
	_prims["cone"] = cone.get_mesh_arrays()
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	sph.radial_segments = 10
	sph.rings = 5
	_prims["sphere"] = sph.get_mesh_arrays()
	var hemi := SphereMesh.new()
	hemi.radius = 0.5
	hemi.height = 0.5
	hemi.is_hemisphere = true
	hemi.radial_segments = 10
	hemi.rings = 4
	_prims["hemi"] = hemi.get_mesh_arrays()
	var box := BoxMesh.new()
	_prims["box"] = box.get_mesh_arrays()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.38
	torus.outer_radius = 0.5
	torus.rings = 12
	torus.ring_segments = 6
	_prims["torus"] = torus.get_mesh_arrays()


# --- Pedidos -------------------------------------------------------------------------------

## Chave da malha: partes, penteado, acessório e roupas (com as cores). Pele e cabelo não
## entram (são parâmetros de instância).
static func key_of(look: Dictionary, wear: Dictionary) -> String:
	var parts := [str(look.get("head", "")), str(look.get("body", "")), str(look.get("legs", "")),
		str(look.get("hairstyle", "none")), str(look.get("accessory", "none"))]
	var slots := wear.keys()
	slots.sort()
	for s: String in slots:
		var w: Dictionary = wear[s]
		parts.append("%s:%s:%s" % [s, w.get("item", ""), w.get("color", "")])
	return "|".join(parts)


## Pede a malha; `done(mesh)` é chamado quando ficar pronta (na hora, se já estiver em cache).
static func request(look: Dictionary, wear: Dictionary, done: Callable) -> void:
	var key := key_of(look, wear)
	if _meshes.has(key):
		done.call(_meshes[key])
		return
	if not _parts.has(str(look.get("head", ""))) or not _parts.has(str(look.get("body", ""))) or not _parts.has(str(look.get("legs", ""))):
		return
	if _pending.has(key):
		(_pending[key]["waiting"] as Array).append(done)
		return
	_pending[key] = {"task": -1, "out": [], "waiting": [done], "job": _job(look, wear)}
	_queue.append(key)


## Pronta agora mesmo (sem thread): para o espelho e o editor, que mostram na hora.
static func build_now(look: Dictionary, wear: Dictionary) -> ArrayMesh:
	var key := key_of(look, wear)
	if not _meshes.has(key):
		_meshes[key] = _finish(_build(_job(look, wear)))
	return _meshes[key]


func _process(_delta: float) -> void:
	# Começa as montagens da fila (no máximo MAX_TASKS de uma vez) e entrega as prontas.
	var running := 0
	for key: String in _pending:
		if int(_pending[key]["task"]) >= 0:
			running += 1
	while running < MAX_TASKS and not _queue.is_empty():
		var key: String = _queue.pop_front()
		var p: Dictionary = _pending[key]
		var job: Dictionary = p["job"]
		var out: Array = p["out"]
		p["task"] = WorkerThreadPool.add_task(func() -> void: out.append(CharacterLook._build(job)))
		running += 1
	for key: String in _pending.keys():
		var p: Dictionary = _pending[key]
		if int(p["task"]) < 0 or not WorkerThreadPool.is_task_completed(p["task"]):
			continue
		WorkerThreadPool.wait_for_task_completion(p["task"])
		_pending.erase(key)
		var t0 := Time.get_ticks_usec()
		var mesh := _finish(p["out"][0])
		HitchLog.note("visual de personagem", (Time.get_ticks_usec() - t0) / 1000.0)
		_meshes[key] = mesh
		for cb: Callable in p["waiting"]:
			if cb.is_valid():
				cb.call(mesh)
		return  # uma por quadro


## O que a thread precisa (cópias das referências; os arrays não mudam).
static func _job(look: Dictionary, wear: Dictionary) -> Dictionary:
	var w := {}
	for slot: String in wear:
		var d: Dictionary = wear[slot]
		w[slot] = {"item": str(d.get("item", "")), "color": lin(str(d.get("color", "#ffffff")))}
	return {"head": _parts[str(look["head"])], "body": _parts[str(look["body"])], "legs": _parts[str(look["legs"])],
		"hairstyle": str(look.get("hairstyle", "none")), "accessory": _accessories.get(str(look.get("accessory", "none")), []),
		"wear": w, "prims": _prims}


# --- Montagem (pode rodar numa thread: só mexe em arrays) ------------------------------------

## Junta tudo em arrays: [superfície do corpo, superfície da capa (ou vazia)].
static func _build(job: Dictionary) -> Array:
	var g := _group()
	var cape := _group()
	var head: Dictionary = job["head"]
	var body: Dictionary = job["body"]
	var legs: Dictionary = job["legs"]
	var h := float(head["height"])
	# Pele: cada parte marca a cor de pele dela (para o tom escolhido trocar tudo junto).
	# Cabelo só fora do rosto (os olhos usam o mesmo quadrado escuro do cabelo).
	var hair_ok := func(v: Vector3, n: Vector3) -> bool: return n.z < 0.6 or v.y > float(head["mid"]) + (float(head["top"]) - float(head["mid"])) * 0.45
	_add_skinned(g, head["head"], func(_b: int, _y: float) -> bool: return true, [head["skin_head"], head["hair"], head["hair_ref"], hair_ok], 0.0, Color(0, 0, 0, 0))
	_add_skinned(g, body["body"], func(b: int, _y: float) -> bool: return b != B_LEG_L and b != B_LEG_R, [body["skin_body"], Vector2i(-1, -1), 1.0, Callable()], 0.0, Color(0, 0, 0, 0))
	_add_skinned(g, legs["body"], func(b: int, _y: float) -> bool: return b == B_LEG_L or b == B_LEG_R, [legs["skin_body"], Vector2i(-1, -1), 1.0, Callable()], 0.0, Color(0, 0, 0, 0))
	var wear: Dictionary = job["wear"]
	var t := 0.016 * h  # espessura da casca da roupa
	var foot := float(legs["foot"])
	var leg_top := float(legs["leg_top"])
	for slot: String in wear:
		var item: String = wear[slot]["item"]
		var col: Color = wear[slot]["color"]
		col.a = MODE_COLOR
		match item:
			"coat":
				_add_skinned(g, body["body"], func(b: int, _y: float) -> bool: return b == B_TORSO or b == B_ARM_L or b == B_ARM_R, [], t * 1.4, col)
			"tank_top":
				_add_skinned(g, body["body"], func(b: int, _y: float) -> bool: return b == B_TORSO, [], t, col)
			"poncho":
				_add_skinned(g, body["body"], func(b: int, _y: float) -> bool: return b == B_TORSO or b == B_ARM_L or b == B_ARM_R, [], t * 2.4, col)
			"pants":
				_add_skinned(g, legs["body"], func(b: int, y: float) -> bool: return (b == B_LEG_L or b == B_LEG_R) and y > foot + (leg_top - foot) * 0.18, [], t, col)
			"shorts":
				_add_skinned(g, legs["body"], func(b: int, y: float) -> bool: return (b == B_LEG_L or b == B_LEG_R) and y > foot + (leg_top - foot) * 0.55, [], t, col)
			"boots":
				_add_skinned(g, legs["body"], func(b: int, y: float) -> bool: return (b == B_LEG_L or b == B_LEG_R) and y < foot + (leg_top - foot) * 0.3, [], t * 1.3, col)
			"sandals":
				for side in [-1.0, 1.0]:
					_add_rigid(g, job["prims"]["box"], Transform3D(Basis().scaled(Vector3(0.09, 0.02, 0.15) * h), Vector3(side * 0.085 * h, foot + 0.01 * h, 0.01 * h)), B_LEG_L if side < 0.0 else B_LEG_R, col)
			"scarf":
				var neck := float(body["torso_top"])
				_add_rigid(g, job["prims"]["torus"], Transform3D(Basis().scaled(Vector3(0.36, 0.5, 0.33) * h), Vector3(0, neck - 0.01 * h, 0)), B_TORSO, col)
				_add_rigid(g, job["prims"]["box"], Transform3D(Basis(Vector3.RIGHT, 0.2).scaled(Vector3(0.06, 0.16, 0.025) * h), Vector3(0.07 * h, neck - 0.09 * h, float(body["torso_w"]) * 0.0 + 0.11 * h)), B_TORSO, col)
			_:
				_add_hat(g, job["prims"], item, head, col)
		if item == "flag_cape":
			_add_cape(cape, body, h)
	_add_hairstyle(g, job["prims"], job["hairstyle"], head)
	for part: Array in job["accessory"]:
		_add_arrays(g, part[0], part[1], B_HEAD, Color(1, 1, 1, MODE_TEX), 0.0)
	return [g, cape]


## Arrays vazios de uma superfície.
static func _group() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "c": PackedColorArray(),
		"b": PackedInt32Array(), "w": PackedFloat32Array(), "i": PackedInt32Array()}


## Triângulos de uma malha com pele (filtro pelo osso dominante e pela altura do triângulo).
## marks: [{quadrado da pele: brilho}, quadrado do cabelo, brilho, filtro do cabelo (vértice,
## normal)] (vazio = não marca). shell > 0 = casca de roupa, empurrada pela normal, com a cor `col`.
static func _add_skinned(g: Dictionary, arrays: Array, keep: Callable, marks: Array, shell: float, col: Color) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var gv: PackedVector3Array = g["v"]
	var gn: PackedVector3Array = g["n"]
	var guv: PackedVector2Array = g["uv"]
	var gc: PackedColorArray = g["c"]
	var gb: PackedInt32Array = g["b"]
	var gw: PackedFloat32Array = g["w"]
	var gi: PackedInt32Array = g["i"]
	var remap := {}
	for t in range(0, idx.size(), 3):
		# Osso do triângulo: o que mais aparece entre os três vértices; altura: a média.
		var counts := {}
		var y := 0.0
		for k in 3:
			var b := _dominant(bones, weights, idx[t + k])
			counts[b] = int(counts.get(b, 0)) + 1
			y += verts[idx[t + k]].y
		var bone := -1
		var best := 0
		for b: int in counts:
			if counts[b] > best:
				best = counts[b]
				bone = b
		if not keep.call(bone, y / 3.0):
			continue
		for k in 3:
			var v := idx[t + k]
			if not remap.has(v):
				remap[v] = gv.size()
				var n := normals[v]
				gv.append(verts[v] + n * shell)
				gn.append(n)
				guv.append(uvs[v])
				if shell > 0.0:
					gc.append(col)
				else:
					# Pele e cabelo: modo e, no vermelho, o brilho do vértice em relação ao do
					# quadrado (÷ 2, para caber em 0–1).
					var c := Color(1, 1, 1, MODE_TEX)
					if not marks.is_empty():
						var cell := _cell(uvs[v])
						var skins: Dictionary = marks[0]
						if skins.has(cell):
							c = Color(clampf(_lum(_sample(uvs[v])) / float(skins[cell]) * 0.5, 0.0, 1.0), 0, 0, MODE_SKIN)
						elif cell == marks[1] and (not (marks[3] as Callable).is_valid() or (marks[3] as Callable).call(verts[v], normals[v])):
							c = Color(clampf(_lum(_sample(uvs[v])) / float(marks[2]) * 0.5, 0.0, 1.0), 0, 0, MODE_HAIR)
					gc.append(c)
				for j in 4:
					gb.append(bones[v * 4 + j])
					gw.append(weights[v * 4 + j])
			gi.append(remap[v])
	g["v"] = gv
	g["n"] = gn
	g["uv"] = guv
	g["c"] = gc
	g["b"] = gb
	g["w"] = gw
	g["i"] = gi


## Forma presa a um osso (peso 1), transformada por `xf` (espaço do personagem).
static func _add_rigid(g: Dictionary, arrays: Array, xf: Transform3D, bone: int, col: Color) -> void:
	_add_arrays(g, arrays, xf, bone, col, 0.0)


static func _add_arrays(g: Dictionary, arrays: Array, xf: Transform3D, bone: int, col: Color, _shell: float) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
	var idx: Variant = arrays[Mesh.ARRAY_INDEX]
	var nb := xf.basis.inverse().transposed()
	var gv: PackedVector3Array = g["v"]
	var gn: PackedVector3Array = g["n"]
	var guv: PackedVector2Array = g["uv"]
	var gc: PackedColorArray = g["c"]
	var gb: PackedInt32Array = g["b"]
	var gw: PackedFloat32Array = g["w"]
	var gi: PackedInt32Array = g["i"]
	var base := gv.size()
	for k in verts.size():
		gv.append(xf * verts[k])
		gn.append((nb * normals[k]).normalized())
		guv.append((uvs as PackedVector2Array)[k] if uvs != null else Vector2.ZERO)
		gc.append(col)
		gb.append_array([bone, 0, 0, 0])
		gw.append_array([1.0, 0.0, 0.0, 0.0])
	if idx == null:
		for k in verts.size():
			gi.append(base + k)
	else:
		for k in (idx as PackedInt32Array):
			gi.append(base + k)
	g["v"] = gv
	g["n"] = gn
	g["uv"] = guv
	g["c"] = gc
	g["b"] = gb
	g["w"] = gw
	g["i"] = gi


## Chapéus (cabeça), em cima do topo da cabeça.
static func _add_hat(g: Dictionary, prims: Dictionary, item: String, head: Dictionary, col: Color) -> void:
	var h := float(head["height"])
	var top := float(head["top"])
	var r := 0.27 * h
	match item:
		"beanie":
			_add_rigid(g, prims["hemi"], Transform3D(Basis().scaled(Vector3(r * 2.05, r * 2.4, r * 2.05)), Vector3(0, top - 0.11 * h, 0)), B_HEAD, col)
			_add_rigid(g, prims["sphere"], Transform3D(Basis().scaled(Vector3.ONE * 0.08 * h), Vector3(0, top + 0.07 * h, 0)), B_HEAD, Color(1, 1, 1, MODE_COLOR))
		"fur_hat":
			_add_rigid(g, prims["cyl"], Transform3D(Basis().scaled(Vector3(r * 2.1, 0.14 * h, r * 2.1)), Vector3(0, top - 0.01 * h, 0)), B_HEAD, col)
			_add_rigid(g, prims["hemi"], Transform3D(Basis().scaled(Vector3(r * 2.0, r * 1.2, r * 2.0)), Vector3(0, top + 0.05 * h, 0)), B_HEAD, col.darkened(0.1))
		"straw_hat", "sun_hat":
			var brim := 0.42 * h if item == "straw_hat" else 0.55 * h
			_add_rigid(g, prims["cyl"], Transform3D(Basis().scaled(Vector3(brim * 2.0, 0.02 * h, brim * 2.0)), Vector3(0, top - 0.04 * h, 0)), B_HEAD, col)
			_add_rigid(g, prims["cyl"], Transform3D(Basis().scaled(Vector3(r * 1.7, 0.12 * h, r * 1.7)), Vector3(0, top + 0.02 * h, 0)), B_HEAD, col)
			var band := Color(0.55, 0.18, 0.15, MODE_COLOR)
			_add_rigid(g, prims["cyl"], Transform3D(Basis().scaled(Vector3(r * 1.74, 0.03 * h, r * 1.74)), Vector3(0, top - 0.01 * h, 0)), B_HEAD, band)
		"cap":
			_add_rigid(g, prims["hemi"], Transform3D(Basis().scaled(Vector3(r * 2.0, r * 1.6, r * 2.0)), Vector3(0, top - 0.06 * h, 0)), B_HEAD, col)
			_add_rigid(g, prims["box"], Transform3D(Basis().scaled(Vector3(0.3 * h, 0.02 * h, 0.2 * h)), Vector3(0, top - 0.05 * h, float(head["front"]) + 0.05 * h)), B_HEAD, col)


## Penteados extras (por cima do cabelo do personagem), na cor do cabelo.
static func _add_hairstyle(g: Dictionary, prims: Dictionary, style: String, head: Dictionary) -> void:
	var h := float(head["height"])
	var top := float(head["top"])
	var hc: Vector2i = head["hair"]
	var hair := _palette.get_pixel(clampi(hc.x * 128 + 64, 0, 511), clampi(hc.y * 128 + 64, 0, 511)) if hc.x >= 0 else Color("3f3f46")
	var c := Color(hair.srgb_to_linear().r, hair.srgb_to_linear().g, hair.srgb_to_linear().b, MODE_HAIR_EXTRA)
	match style:
		"bun":
			_add_rigid(g, prims["sphere"], Transform3D(Basis().scaled(Vector3.ONE * 0.16 * h), Vector3(0, top - 0.02 * h, -0.12 * h)), B_HEAD, c)
		"ponytail":
			_add_rigid(g, prims["sphere"], Transform3D(Basis().scaled(Vector3(0.1, 0.1, 0.1) * h), Vector3(0, top - 0.1 * h, -0.22 * h)), B_HEAD, c)
			_add_rigid(g, prims["cone"], Transform3D(Basis(Vector3.RIGHT, PI * 0.85).scaled(Vector3(0.1, 0.24, 0.1) * h), Vector3(0, top - 0.22 * h, -0.27 * h)), B_HEAD, c)
		"curls":
			for k in 7:
				var a := TAU * k / 7.0
				_add_rigid(g, prims["sphere"], Transform3D(Basis().scaled(Vector3.ONE * 0.11 * h), Vector3(cos(a) * 0.17 * h, top - 0.03 * h, sin(a) * 0.17 * h)), B_HEAD, c)
		"spiky":
			for k in 5:
				var x := (k - 2) * 0.07 * h
				_add_rigid(g, prims["cone"], Transform3D(Basis(Vector3.FORWARD, x * 2.0).scaled(Vector3(0.07, 0.14, 0.07) * h), Vector3(x, top + 0.04 * h, -0.02 * h)), B_HEAD, c)


## Capa: um pano atrás das costas (preso ao tronco), com UV para a textura das bandeiras.
static func _add_cape(g: Dictionary, body: Dictionary, h: float) -> void:
	var top := float(body["torso_top"]) - 0.02 * h
	var bottom := float(body["foot"]) + 0.22 * h
	var half := float(body["torso_w"]) * 1.05
	var z := float(body["torso_back"]) - 0.025 * h
	var cols := 4
	var rows := 6
	var gv: PackedVector3Array = g["v"]
	var gn: PackedVector3Array = g["n"]
	var guv: PackedVector2Array = g["uv"]
	var gc: PackedColorArray = g["c"]
	var gb: PackedInt32Array = g["b"]
	var gw: PackedFloat32Array = g["w"]
	var gi: PackedInt32Array = g["i"]
	for r in rows + 1:
		for c in cols + 1:
			var u := float(c) / cols
			var v := float(r) / rows
			# Mais larga embaixo e um tico afastada das costas.
			var w := half * (1.0 + 0.35 * v)
			gv.append(Vector3(lerpf(-w, w, u), lerpf(top, bottom, v), z - 0.05 * h * v))
			gn.append(Vector3(0, 0, -1))
			guv.append(Vector2(1.0 - u, v))
			gc.append(Color(1, 1, 1, v))  # alfa = quanto balança
			gb.append_array([B_TORSO, 0, 0, 0])
			gw.append_array([1.0, 0.0, 0.0, 0.0])
	for r in rows:
		for c in cols:
			var a := r * (cols + 1) + c
			var b := a + 1
			var d := a + cols + 1
			var e := d + 1
			gi.append_array([a, b, d, b, e, d])
	g["v"] = gv
	g["n"] = gn
	g["uv"] = guv
	g["c"] = gc
	g["b"] = gb
	g["w"] = gw
	g["i"] = gi


## Arrays → ArrayMesh (thread principal).
static func _finish(groups: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		if (g["i"] as PackedInt32Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g["v"]
		arrays[Mesh.ARRAY_NORMAL] = g["n"]
		arrays[Mesh.ARRAY_TEX_UV] = g["uv"]
		arrays[Mesh.ARRAY_COLOR] = g["c"]
		arrays[Mesh.ARRAY_BONES] = g["b"]
		arrays[Mesh.ARRAY_WEIGHTS] = g["w"]
		arrays[Mesh.ARRAY_INDEX] = g["i"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material if gi == 0 else null)
		mesh.surface_set_name(mesh.get_surface_count() - 1, "corpo" if gi == 0 else "capa")
	return mesh


# --- Aplicar num modelo --------------------------------------------------------------------

## Troca as duas malhas do personagem pela malha do visual. `cape` = países visitados (a
## textura dos retalhos). Devolve o MeshInstance3D novo (ou null).
static func apply(model: Node3D, mesh: ArrayMesh, look: Dictionary, cape: Array) -> MeshInstance3D:
	if model == null or mesh == null:
		return null
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return null
	var sk := sks[0] as Skeleton3D
	var skin: Skin = null
	for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", false, false):
		if mi.name in ["body-mesh", "head-mesh"]:
			skin = mi.skin
			mi.visible = false
		elif mi.name == "Look":
			mi.free()
	var out := MeshInstance3D.new()
	out.name = "Look"
	out.mesh = mesh
	out.skin = skin
	sk.add_child(out)
	out.skeleton = out.get_path_to(sk)
	set_colors(out, look)
	if mesh.get_surface_count() > 1:
		out.set_surface_override_material(1, cape_material(cape))
	return out


## Pele e cabelo por parâmetro de instância (o material é o mesmo para todos).
static func set_colors(mi: MeshInstance3D, look: Dictionary) -> void:
	var skin := lin(str(look.get("skin", "")))
	var hair := lin(str(look.get("hair", "")))
	mi.set_instance_shader_parameter("skin_color", skin)
	mi.set_instance_shader_parameter("hair_color", hair)


## Material da capa com os retalhos das bandeiras (cache por lista de países).
static func cape_material(countries: Array) -> ShaderMaterial:
	var key := ",".join(countries)
	if _cape_mats.has(key):
		return _cape_mats[key]
	var m := ShaderMaterial.new()
	m.shader = CAPE_SHADER
	m.set_shader_parameter("flags", cape_texture(countries))
	_cape_mats[key] = m
	return m


## Textura dos retalhos: até 12 bandeiras (3 × 4), na ordem das viagens; sem viagens, um
## pano creme com a faixa verde.
static func cape_texture(countries: Array) -> ImageTexture:
	var cols := 3
	var rows := 4
	var tw := 32
	var th := 24
	var img := Image.create(cols * tw, rows * th, false, Image.FORMAT_RGBA8)
	img.fill(Color("fff6e4"))
	img.fill_rect(Rect2i(0, 0, cols * tw, 6), Color("7cc49a"))
	var atlas := FlagAtlas.texture().get_image()
	if atlas.is_compressed():
		atlas.decompress()
	atlas.convert(Image.FORMAT_RGBA8)
	var list := countries.slice(maxi(0, countries.size() - cols * rows))
	for i in list.size():
		var r := FlagAtlas.uv_rect(str(list[i]))
		var src := Rect2i(int(r.position.x * atlas.get_width()), int(r.position.y * atlas.get_height()),
			int(r.size.x * atlas.get_width()), int(r.size.y * atlas.get_height()))
		var tile := atlas.get_region(src)
		tile.resize(tw - 2, th - 2, Image.INTERPOLATE_BILINEAR)
		img.blit_rect(tile, Rect2i(0, 0, tw - 2, th - 2), Vector2i((i % cols) * tw + 1, (i / cols) * th + 1))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
