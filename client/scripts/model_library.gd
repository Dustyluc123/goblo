class_name ModelLibrary
extends RefCounted
## Carrega modelos e junta cada um numa malha só, pronta para MultiMesh e para os lotes.
##
## - Modelos sem textura (Ultimate Nature Pack): as cores dos materiais viram cor por
##   vértice e tudo vira UMA superfície com um material compartilhado. Uma árvore que tinha
##   3 materiais passa a custar 1 draw call, e a cor por instância (tom do bioma) ainda
##   multiplica por cima.
## - Modelos com textura (Kenney, colormap): as superfícies com o mesmo material são
##   juntadas, mantendo a textura.
## - Os níveis de detalhe (LOD) são gerados de novo para a malha juntada.
## - Oclusão de ambiente barata ("AO nos vértices"): a cor por vértice escurece perto da
##   base do modelo, como se o chão sombreasse o pé das árvores, pedras e paredes. O
##   renderizador Mobile não tem SSAO; isto vale em todas as qualidades e não custa nada.
##
## Nomes aceitos em `get_model`:
##   "CommonTree_1"           → Ultimate Nature Pack (client/assets/quaternius/ultimate-nature)
##   "res://…/fence.glb"      → qualquer cena
##   "flower:red"             → flor do Nature Pack com as pétalas recoloridas
##   "primitive:axe"          → modelos simples feitos aqui (machado, picareta, bancada, coco)

const NATURE_DIR := "res://assets/quaternius/ultimate-nature/"
const FLOWER_COLORS := {
	"red": Color("e0484f"), "yellow": Color("f4c542"), "white": Color("f5f2ea"), "purple": Color("9a6ad6"),
	"blue": Color("4aa8f0"),  # flor rara (Goblopédia)
}
## Cor original das pétalas no Flowers.fbx (a que é trocada nas flores coloridas).
const PETAL_COLOR := Color("007b7c")
## Neve dos modelos de inverno: o pacote usa um cinza-lilás (0,67; 0,63; 0,68) que, com a
## luz da tarde, parece rosa. Trocado por um branco levemente azulado.
const SNOW_COLOR := Color(0.9, 0.93, 0.98)

static var _cache := {}  # nome → {"mesh": ArrayMesh, "aabb": AABB}
## Materiais de folhagem (vento + variação), por tipo: "tree", "grass", "plant", "still".
static var _foliage := {}
const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")
## Vento por tipo: [deslocamento no topo, altura do balanço máximo] em unidades do modelo.
const WIND := {"tree": [0.09, 4.0], "plant": [0.07, 1.0], "grass": [0.12, 0.6], "still": [0.0, 1.0]}
static var _baked_material: StandardMaterial3D
## Protege o cache: os modelos são pré-carregados em várias threads (preload_all).
static var _mutex := Mutex.new()


## Material único dos modelos com cor por vértice.
static func baked_material() -> StandardMaterial3D:
	if _baked_material == null:  # criado no thread principal antes do pré-carregamento
		_baked_material = StandardMaterial3D.new()
		_baked_material.vertex_color_use_as_albedo = true
		_baked_material.roughness = 0.95
	return _baked_material


## Material de folhagem para MultiMesh de modelos sem textura (`material_override`).
## `kind`: "tree", "plant" (arbustos, flores), "grass" ou "still" (pedras: sem vento).
static func foliage_material(kind: String) -> ShaderMaterial:
	if not _foliage.has(kind):
		var m := ShaderMaterial.new()
		m.shader = FOLIAGE_SHADER
		var w: Array = WIND.get(kind, WIND["still"])
		m.set_shader_parameter("wind_strength", w[0])
		m.set_shader_parameter("wind_height", w[1])
		_foliage[kind] = m
	return _foliage[kind]


## O modelo usa só o material de cor por vértice (pode trocar pelo de folhagem)?
static func is_baked(lib: Dictionary) -> bool:
	var mesh: Mesh = lib.get("mesh")
	return mesh != null and mesh.get_surface_count() == 1 and mesh.surface_get_material(0) == _baked_material


## {"mesh": ArrayMesh, "aabb": AABB} do modelo (nulo se não existe). Fica em cache.
static func get_model(name: String) -> Dictionary:
	_mutex.lock()
	if _cache.has(name):
		var hit: Dictionary = _cache[name]
		_mutex.unlock()
		return hit
	_mutex.unlock()
	HitchLog.note("modelo carregado na hora: %s" % name)
	var out := {}
	if name.begins_with("primitive:"):
		out = _primitive(name.substr(10))
	elif name.begins_with("flower:"):
		out = _load_scene(NATURE_DIR + "Flowers.fbx", FLOWER_COLORS.get(name.substr(7), Color.WHITE))
	elif name.begins_with("res://"):
		out = _load_scene(name)
	else:
		out = _load_scene(NATURE_DIR + name + ".fbx")
	_mutex.lock()
	_cache[name] = out
	_mutex.unlock()
	return out


## Nomes de todos os modelos já carregados (pré-aquecimento dos shaders).
static func cached_names() -> Array:
	_mutex.lock()
	var out := _cache.keys()
	_mutex.unlock()
	return out


## O modelo, só se já estiver carregado ({} se não): para trocar pela versão da estação sem
## carregar nada no meio do jogo.
static func get_cached(name: String) -> Dictionary:
	_mutex.lock()
	var hit: Dictionary = _cache.get(name, {})
	_mutex.unlock()
	return hit


## Carrega vários modelos em paralelo (WorkerThreadPool), sem travar a tela: espera
## quadro a quadro até terminar. Usado na entrada do jogo, para não haver travadas depois.
##
## Em duas fases: primeiro os modelos soltos (.glb, .fbx, primitivos), depois as cenas
## (.tscn das casas). As cenas usam as mesmas peças (cerca, lampião); carregar a mesma
## peça em duas threads ao mesmo tempo fazia o Godot dizer que ela "não existe" e a casa
## grande saía sem a sacada.
static func preload_all(names: Array, tree: SceneTree) -> void:
	baked_material()  # cria antes, no thread principal
	var models: Array = []
	var scenes: Array = []
	for n: String in names:
		var target := scenes if n.ends_with(".tscn") else models
		if not target.has(n):
			target.append(n)
	for list: Array in [models, scenes]:
		if list.is_empty():
			continue
		if DisplayServer.get_name() == "headless":
			# Testes: o renderizador falso não aguenta várias threads criando malhas ao mesmo
			# tempo (erros de RID); carrega em sequência, alguns por quadro.
			for i in list.size():
				get_model(list[i])
				if i % 8 == 7:
					await tree.process_frame
			continue
		var id := WorkerThreadPool.add_group_task(func(i: int) -> void: get_model(list[i]), list.size())
		while not WorkerThreadPool.is_group_task_completed(id):
			await tree.process_frame
		WorkerThreadPool.wait_for_group_task_completion(id)


static func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.03 and absf(a.g - b.g) < 0.03 and absf(a.b - b.b) < 0.03


static func nature_path(name: String) -> String:
	return NATURE_DIR + name + ".fbx"


## Carrega a cena e junta as malhas. `petal` != null troca a cor das pétalas das flores.
static func _load_scene(path: String, petal: Variant = null) -> Dictionary:
	if not ResourceLoader.exists(path):
		push_error("Modelo não encontrado: " + path)
		return {}
	var scene := load(path) as PackedScene
	if scene == null:
		return {}
	var root := scene.instantiate() as Node3D
	var groups := {}  # material (ou "baked") → {verts, normals, uvs, colors, indices, material}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := _transform_to_root(mi, root)
		var nbasis := xf.basis.inverse().transposed()
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var mat := mi.get_active_material(s)
			var baked := mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture == null
			var key: Variant = "baked" if baked else mat
			if not groups.has(key):
				groups[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
					"c": PackedColorArray(), "i": PackedInt32Array(), "mat": mat}
			var g: Dictionary = groups[key]
			var color := Color.WHITE
			if baked:
				color = (mat as StandardMaterial3D).albedo_color
				if petal != null and _close(color, PETAL_COLOR):
					color = petal
				elif mat.resource_name == "Snow":
					color = SNOW_COLOR
				color = color.srgb_to_linear()
			var base: int = (g["v"] as PackedVector3Array).size()
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var vcolors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var gv: PackedVector3Array = g["v"]
			var gn: PackedVector3Array = g["n"]
			var guv: PackedVector2Array = g["uv"]
			var gc: PackedColorArray = g["c"]
			for k in verts.size():
				gv.append(xf * verts[k])
				gn.append((nbasis * normals[k]).normalized() if k < normals.size() else Vector3.UP)
				guv.append(uvs[k] if k < uvs.size() else Vector2.ZERO)
				gc.append(color * (vcolors[k] if k < vcolors.size() else Color.WHITE))
			var gi: PackedInt32Array = g["i"]
			var idx = arrays[Mesh.ARRAY_INDEX]
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
			g["i"] = gi
	root.free()
	_bake_ao(groups)
	return _build(groups)


## Escurece a cor por vértice perto da base do modelo (AO nos vértices).
const AO_DARK := 0.62
const AO_MAX_HEIGHT := 0.8


static func _bake_ao(groups: Dictionary) -> void:
	var min_y := INF
	var max_y := -INF
	for g: Dictionary in groups.values():
		for v in (g["v"] as PackedVector3Array):
			min_y = minf(min_y, v.y)
			max_y = maxf(max_y, v.y)
	if min_y == INF:
		return
	var reach := clampf((max_y - min_y) * 0.3, 0.05, AO_MAX_HEIGHT)
	for g: Dictionary in groups.values():
		var verts: PackedVector3Array = g["v"]
		var cols: PackedColorArray = g["c"]
		for k in verts.size():
			var t := clampf((verts[k].y - min_y) / reach, 0.0, 1.0)
			var ao := lerpf(AO_DARK, 1.0, t * t * (3.0 - 2.0 * t))
			var c := cols[k]
			cols[k] = Color(c.r * ao, c.g * ao, c.b * ao, c.a)
		g["c"] = cols


## Junta os grupos numa ArrayMesh com LODs. A ordem é estável: o grupo "baked" primeiro.
static func _build(groups: Dictionary) -> Dictionary:
	var im := ImporterMesh.new()
	var keys := groups.keys()
	keys.sort_custom(func(a, b) -> bool: return str(a) == "baked" and str(b) != "baked")
	for key in keys:
		var g: Dictionary = groups[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g["v"]
		arrays[Mesh.ARRAY_NORMAL] = g["n"]
		arrays[Mesh.ARRAY_TEX_UV] = g["uv"]
		arrays[Mesh.ARRAY_COLOR] = g["c"]
		arrays[Mesh.ARRAY_INDEX] = g["i"]
		var mat: Material = baked_material() if str(key) == "baked" else _textured(g["mat"])
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mat)
	if im.get_surface_count() == 0:
		return {}
	im.generate_lods(25.0, 60.0, [])
	var mesh := im.get_mesh()
	return {"mesh": mesh, "aabb": mesh.get_aabb()}


static var _textured_cache := {}


## Cópia do material com textura que também aceita cor por vértice e por instância.
static func _textured(mat: Material) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	_mutex.lock()
	if not _textured_cache.has(mat):
		var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.vertex_color_use_as_albedo = true
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		_textured_cache[mat] = m
	var out: Material = _textured_cache[mat]
	_mutex.unlock()
	return out


static func _transform_to_root(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return root.transform * t


# --- Modelos primitivos (o que não existe nos pacotes) -------------------------------------

## Machado, picareta, bancada, coco, caixa de vendas e câmera, feitos de caixas e cilindros
## low-poly.
static func _primitive(kind: String) -> Dictionary:
	var parts: Array = []  # [Mesh, Transform3D, Color]
	var wood := Color("a8754a")
	var dark_wood := Color("7a5233")
	var metal := Color("b8c0c8")
	match kind:
		"axe":
			parts.append([_box(Vector3(0.05, 0.5, 0.05)), Transform3D(Basis(), Vector3(0, 0.25, 0)), wood])
			parts.append([_box(Vector3(0.18, 0.12, 0.03)), Transform3D(Basis(), Vector3(0.07, 0.44, 0)), metal])
		"pickaxe":
			parts.append([_box(Vector3(0.05, 0.5, 0.05)), Transform3D(Basis(), Vector3(0, 0.25, 0)), wood])
			parts.append([_box(Vector3(0.36, 0.05, 0.04)), Transform3D(Basis(Vector3.FORWARD, 0.18), Vector3(0, 0.47, 0)), metal])
		"workbench":
			parts.append([_box(Vector3(0.95, 0.1, 0.7)), Transform3D(Basis(), Vector3(0, 0.62, 0)), wood])
			for x in [-0.4, 0.4]:
				for z in [-0.28, 0.28]:
					parts.append([_box(Vector3(0.09, 0.57, 0.09)), Transform3D(Basis(), Vector3(x, 0.285, z)), dark_wood])
			parts.append([_box(Vector3(0.8, 0.06, 0.55)), Transform3D(Basis(), Vector3(0, 0.18, 0)), dark_wood])
			parts.append([_box(Vector3(0.3, 0.04, 0.12)), Transform3D(Basis(Vector3.UP, 0.4), Vector3(-0.15, 0.69, 0.05)), metal])
			parts.append([_box(Vector3(0.05, 0.25, 0.05)), Transform3D(Basis(Vector3.FORWARD, 1.3), Vector3(0.2, 0.7, -0.1)), wood])
		"sell_box":
			# Caixote de madeira com tampa, frestinha e um gobolar dourado na frente.
			parts.append([_box(Vector3(0.78, 0.5, 0.62)), Transform3D(Basis(), Vector3(0, 0.25, 0)), wood])
			for y in [0.1, 0.4]:
				parts.append([_box(Vector3(0.8, 0.06, 0.64)), Transform3D(Basis(), Vector3(0, y, 0)), dark_wood])
			parts.append([_box(Vector3(0.84, 0.08, 0.68)), Transform3D(Basis(), Vector3(0, 0.54, 0)), dark_wood])
			parts.append([_box(Vector3(0.3, 0.02, 0.05)), Transform3D(Basis(), Vector3(0, 0.585, 0)), Color("3d2a1a")])
			var coin := CylinderMesh.new()
			coin.top_radius = 0.11
			coin.bottom_radius = 0.11
			coin.height = 0.03
			coin.radial_segments = 14
			coin.rings = 1
			parts.append([coin, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.27, 0.32)), Color("f6c94b")])
		"camera":
			# Câmera fotográfica: corpo, lente, botão e visor.
			parts.append([_box(Vector3(0.26, 0.16, 0.1)), Transform3D(Basis(), Vector3(0, 0.08, 0)), Color("4a4f5c")])
			var lens := CylinderMesh.new()
			lens.top_radius = 0.055
			lens.bottom_radius = 0.065
			lens.height = 0.08
			lens.radial_segments = 12
			lens.rings = 1
			parts.append([lens, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.08, 0.08)), Color("2e3138")])
			parts.append([_box(Vector3(0.05, 0.03, 0.05)), Transform3D(Basis(), Vector3(0.08, 0.175, 0)), Color("e8665a")])
			parts.append([_box(Vector3(0.07, 0.05, 0.04)), Transform3D(Basis(), Vector3(-0.07, 0.18, 0)), Color("4a4f5c")])
		"coconut":
			var s := SphereMesh.new()
			s.radius = 0.12
			s.height = 0.22
			s.radial_segments = 8
			s.rings = 4
			parts.append([s, Transform3D(Basis(), Vector3(0, 0.11, 0)), Color("6b4a2f")])
		_:
			parts.append_array(_primitive_40(kind))
	if parts.is_empty():
		# Nunca uma malha vazia: um cubinho neutro.
		parts.append([_box(Vector3(0.2, 0.2, 0.2)), Transform3D(Basis(), Vector3(0, 0.1, 0)), Color("c8b8a0")])
	var groups := {"baked": {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
		"c": PackedColorArray(), "i": PackedInt32Array(), "mat": null}}
	var g: Dictionary = groups["baked"]
	for p: Array in parts:
		var arrays := (p[0] as PrimitiveMesh).get_mesh_arrays()
		var xf: Transform3D = p[1]
		var color: Color = (p[2] as Color).srgb_to_linear()
		var base: int = (g["v"] as PackedVector3Array).size()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var gv: PackedVector3Array = g["v"]
		var gn: PackedVector3Array = g["n"]
		var guv: PackedVector2Array = g["uv"]
		var gc: PackedColorArray = g["c"]
		var gi: PackedInt32Array = g["i"]
		for k in verts.size():
			gv.append(xf * verts[k])
			gn.append((xf.basis * normals[k]).normalized())
			guv.append(Vector2.ZERO)
			gc.append(color)
		for k in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
			gi.append(base + k)
		g["v"] = gv
		g["n"] = gn
		g["uv"] = guv
		g["c"] = gc
		g["i"] = gi
	return _build(groups)


# --- Modelos da fase 4.0 (flores, ingredientes, fogueira, poço, espelho, comidas, roupas) ---

static func _cy(top: float, bottom: float, h: float, seg := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _sp(r: float, h: float, seg := 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h
	s.radial_segments = seg
	s.rings = 4
	return s


static func _at(x: float, y: float, z: float, basis := Basis()) -> Transform3D:
	return Transform3D(basis, Vector3(x, y, z))


## Haste verde de altura h.
static func _stem(parts: Array, h: float, x := 0.0, z := 0.0, lean := 0.0) -> void:
	parts.append([_cy(0.012, 0.016, h, 5), _at(x, h * 0.5, z, Basis(Vector3.FORWARD, lean)), Color("5f9e4b")])


## Pétalas em volta de um centro: n caixinhas achatadas inclinadas.
static func _petals(parts: Array, center: Vector3, n: int, length: float, width: float, tilt: float, col: Color) -> void:
	for k in n:
		var a := TAU * k / n
		var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, tilt)
		parts.append([_box(Vector3(width, 0.012, length)), Transform3D(b, center + b * Vector3(0, 0, length * 0.5)), col])


static func _primitive_40(kind: String) -> Array:
	var parts: Array = []
	match kind:
		"flower_sunflower":
			_stem(parts, 0.55)
			parts.append([_cy(0.13, 0.13, 0.03, 12), _at(0, 0.58, 0.02, Basis(Vector3.RIGHT, 1.2)), Color("f5c518")])
			parts.append([_cy(0.07, 0.07, 0.04, 10), _at(0, 0.585, 0.04, Basis(Vector3.RIGHT, 1.2)), Color("6b4226")])
			parts.append([_box(Vector3(0.1, 0.01, 0.05)), _at(0.04, 0.25, 0, Basis(Vector3.FORWARD, 0.5)), Color("6fb04f")])
		"flower_lavender":
			for k in 4:
				var x := (k - 1.5) * 0.04
				_stem(parts, 0.32, x, (k % 2) * 0.03, x * 1.5)
				parts.append([_cy(0.018, 0.022, 0.12, 5), _at(x * 1.5, 0.38, (k % 2) * 0.03), Color("9b7fd4")])
		"flower_poppy":
			_stem(parts, 0.32)
			parts.append([_cy(0.08, 0.035, 0.07, 8), _at(0, 0.36, 0), Color("e8453c")])
			parts.append([_sp(0.025, 0.04), _at(0, 0.39, 0), Color("2b2b2b")])
		"flower_daisy":
			_stem(parts, 0.26)
			_petals(parts, Vector3(0, 0.27, 0), 10, 0.06, 0.022, -0.2, Color("fbfbf2"))
			parts.append([_sp(0.025, 0.03), _at(0, 0.28, 0), Color("f5c518")])
		"flower_tulip":
			_stem(parts, 0.28)
			parts.append([_cy(0.055, 0.035, 0.09, 6), _at(0, 0.32, 0), Color("f07aa8")])
			parts.append([_box(Vector3(0.03, 0.14, 0.012)), _at(0.03, 0.1, 0, Basis(Vector3.FORWARD, -0.3)), Color("6fb04f")])
		"flower_bluebell":
			_stem(parts, 0.3, 0, 0, 0.25)
			for k in 3:
				parts.append([_cy(0.012, 0.03, 0.045, 6), _at(-0.05 - k * 0.02, 0.28 - k * 0.06, 0, Basis(Vector3.RIGHT, PI)), Color("6d8fe8")])
		"flower_snowdrop":
			_stem(parts, 0.2, 0, 0, 0.3)
			parts.append([_cy(0.01, 0.03, 0.05, 6), _at(-0.05, 0.19, 0, Basis(Vector3.RIGHT, PI)), Color("f2f6ff")])
		"flower_heather":
			for k in 5:
				var a := TAU * k / 5.0
				parts.append([_sp(0.05, 0.12, 6), _at(cos(a) * 0.05, 0.08, sin(a) * 0.05), Color("c46fb3")])
			parts.append([_sp(0.07, 0.08, 6), _at(0, 0.03, 0), Color("5f8a4b")])
		"flower_gentian":
			_stem(parts, 0.12)
			parts.append([_cy(0.045, 0.015, 0.08, 6), _at(0, 0.16, 0), Color("3c62d6")])
		"flower_edelweiss":
			_stem(parts, 0.1)
			_petals(parts, Vector3(0, 0.11, 0), 7, 0.05, 0.025, -0.1, Color("f4f1e4"))
			parts.append([_sp(0.02, 0.025), _at(0, 0.12, 0), Color("e8e2c8")])
		"flower_cactus_flower":
			parts.append([_cy(0.06, 0.07, 0.3, 8), _at(0, 0.15, 0), Color("5f9e4b")])
			parts.append([_sp(0.06, 0.06, 8), _at(0, 0.3, 0), Color("5f9e4b")])
			_petals(parts, Vector3(0, 0.33, 0), 6, 0.05, 0.03, -0.5, Color("ff6fa3"))
		"flower_hibiscus":
			_stem(parts, 0.3)
			_petals(parts, Vector3(0, 0.31, 0), 5, 0.09, 0.07, -0.35, Color("ff4d6d"))
			parts.append([_cy(0.006, 0.006, 0.08, 4), _at(0, 0.35, 0.02, Basis(Vector3.RIGHT, 0.5)), Color("ffd23f")])
		"flower_orchid":
			_stem(parts, 0.32, 0, 0, 0.2)
			_petals(parts, Vector3(-0.05, 0.33, 0.02), 5, 0.06, 0.045, -1.2, Color("d68fe8"))
			parts.append([_sp(0.02, 0.03), _at(-0.05, 0.33, 0.04), Color("f7e14a")])
		"flower_ipe":
			# Arvorezinha florida: tronco e copa amarela.
			parts.append([_cy(0.05, 0.08, 1.2, 6), _at(0, 0.6, 0), Color("7a5233")])
			for k in 4:
				var a := TAU * k / 4.0
				parts.append([_sp(0.38, 0.5, 8), _at(cos(a) * 0.22, 1.35 + (k % 2) * 0.15, sin(a) * 0.22), Color("ffd23f")])
			parts.append([_sp(0.42, 0.55, 8), _at(0, 1.55, 0), Color("ffcf2e")])
		"flower_lotus":
			parts.append([_cy(0.16, 0.16, 0.015, 10), _at(0, 0.01, 0), Color("4f9a60")])
			_petals(parts, Vector3(0, 0.03, 0), 8, 0.07, 0.04, -0.7, Color("ffb3c8"))
			parts.append([_sp(0.03, 0.03), _at(0, 0.06, 0), Color("ffd23f")])
		"mushroom":
			for k in 2:
				var x := k * 0.07 - 0.03
				parts.append([_cy(0.02, 0.025, 0.08 - k * 0.02, 6), _at(x, 0.04, k * 0.04), Color("f2e8d5")])
				parts.append([_sp(0.06 - k * 0.015, 0.06, 8), _at(x, 0.09 - k * 0.02, k * 0.04), Color("d9583b")])
		"herbs":
			for k in 6:
				var a := TAU * k / 6.0
				parts.append([_box(Vector3(0.03, 0.16, 0.012)), _at(cos(a) * 0.03, 0.08, sin(a) * 0.03, Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.35)), Color("7cbf5a")])
		"grain":
			for k in 5:
				var x := (k - 2) * 0.03
				_stem(parts, 0.32, x, (k % 2) * 0.02, x)
				parts.append([_cy(0.012, 0.02, 0.09, 5), _at(x * 1.4, 0.36, (k % 2) * 0.02), Color("e9c46a")])
		"canteen", "canteen_0", "canteen_1", "canteen_2":
			# Cantil (fase 4.1): na frente, uma janelinha com a água azulada; cada risco é um
			# gole que ainda resta (0, 1 ou 2).
			var sips := int(kind.substr(8)) if kind.length() > 8 else 0
			parts.append([_cy(0.1, 0.1, 0.06, 12), _at(0, 0.11, 0, Basis(Vector3.RIGHT, PI / 2)), Color("8a9bb0")])
			parts.append([_cy(0.025, 0.025, 0.05, 6), _at(0, 0.23, 0), Color("7a5233")])
			parts.append([_box(Vector3(0.02, 0.2, 0.065)), _at(0.1, 0.13, 0), Color("a8754a")])
			parts.append([_box(Vector3(0.07, 0.13, 0.01)), _at(0, 0.11, 0.032), Color("3b4250")])
			for k in 2:
				var full := k < sips
				parts.append([_box(Vector3(0.056, 0.05, 0.012)), _at(0, 0.075 + k * 0.064, 0.034), Color("6ec6f5") if full else Color("59606e")])
		"campfire":
			for k in 7:
				var a := TAU * k / 7.0
				parts.append([_sp(0.07, 0.07, 6), _at(cos(a) * 0.28, 0.03, sin(a) * 0.28), Color("9a9a9a")])
			for k in 3:
				parts.append([_cy(0.03, 0.03, 0.42, 6), _at(0, 0.12, 0, Basis(Vector3.UP, k * PI / 3) * Basis(Vector3.RIGHT, 1.2)), Color("7a5233")])
			parts.append([_cy(0.0, 0.11, 0.26, 6), _at(0, 0.2, 0), Color("ff9a3c")])
			parts.append([_cy(0.0, 0.06, 0.18, 6), _at(0, 0.2, 0), Color("ffd45a")])
		"well":
			parts.append([_cy(0.55, 0.6, 0.55, 12), _at(0, 0.27, 0), Color("a7a39b")])
			parts.append([_cy(0.45, 0.45, 0.02, 12), _at(0, 0.5, 0), Color("4d8fe8")])
			for x in [-0.5, 0.5]:
				parts.append([_box(Vector3(0.07, 1.0, 0.07)), _at(x, 0.95, 0), Color("7a5233")])
			parts.append([_box(Vector3(1.3, 0.06, 0.8)), _at(0, 1.5, 0, Basis(Vector3.FORWARD, 0.0)), Color("c0645a")])
			parts.append([_cy(0.04, 0.04, 1.0, 6), _at(0, 1.2, 0, Basis(Vector3.FORWARD, PI / 2)), Color("a8754a")])
			parts.append([_cy(0.1, 0.08, 0.14, 8), _at(0.1, 0.85, 0), Color("a8754a")])
		"mirror":
			parts.append([_box(Vector3(0.62, 1.12, 0.06)), _at(0, 0.66, 0), Color("a8754a")])
			parts.append([_box(Vector3(0.5, 1.0, 0.02)), _at(0, 0.66, 0.035), Color("cfe8f3")])
			parts.append([_box(Vector3(0.7, 0.08, 0.3)), _at(0, 0.04, 0), Color("7a5233")])
		"roasted_berries":
			parts.append([_cy(0.008, 0.008, 0.3, 4), _at(0, 0.15, 0, Basis(Vector3.FORWARD, 0.3)), Color("a8754a")])
			for k in 3:
				parts.append([_sp(0.035, 0.07, 6), _at(-0.02 - k * 0.025, 0.12 + k * 0.06, 0), Color("8b2d4a")])
		"mushroom_skewer":
			parts.append([_cy(0.008, 0.008, 0.32, 4), _at(0, 0.16, 0), Color("a8754a")])
			for k in 3:
				parts.append([_sp(0.04, 0.04, 6), _at(0, 0.12 + k * 0.07, 0), Color("c47a4a")])
		"herb_soup", "berry_juice", "herb_tea":
			var col: Color = {"herb_soup": Color("c9a24a"), "berry_juice": Color("c2185b"), "herb_tea": Color("8bc34a")}[kind]
			if kind == "herb_soup":
				parts.append([_cy(0.12, 0.08, 0.08, 10), _at(0, 0.04, 0), Color("f4f1e4")])
				parts.append([_cy(0.112, 0.112, 0.012, 10), _at(0, 0.079, 0), col])
			else:
				# Copo cheio (fase 4.1): o líquido colorido é o corpo do copo; o vidro só aparece
				# no fundo, na borda e num reflexo (os modelos não têm transparência).
				var glass := Color(0.88, 0.94, 1.0)
				parts.append([_cy(0.052, 0.05, 0.02, 10), _at(0, 0.01, 0), glass])
				parts.append([_cy(0.056, 0.05, 0.11, 10), _at(0, 0.075, 0), col])
				parts.append([_ring(0.062, 0.012), _at(0, 0.136, 0), glass])
				parts.append([_cy(0.055, 0.055, 0.006, 10), _at(0, 0.133, 0), col.lightened(0.15)])
				parts.append([_box(Vector3(0.012, 0.075, 0.006)), _at(-0.03, 0.08, 0.047, Basis(Vector3.UP, -0.5)), Color(1, 1, 1)])
		"grain_bread":
			parts.append([_sp(0.11, 0.12, 8), _at(0, 0.05, 0, Basis().scaled(Vector3(1.3, 1, 1))), Color("d9a05b")])
		"cloth":
			for k in 3:
				parts.append([_box(Vector3(0.26, 0.03, 0.2)), _at(0, 0.02 + k * 0.032, 0, Basis(Vector3.UP, k * 0.2)), [Color("e86a6a"), Color("f4f1e4"), Color("6d8fe8")][k]])
		"paint":
			parts.append_array(_paint_pot(Color("e86a6a")))
		_:
			if kind.begins_with("wear_"):
				parts.append_array(_wear_icon(kind.substr(5)))
			elif kind.begins_with("paint_"):
				parts.append_array(_paint_pot(Color(kind.substr(6))))
	return parts


## Pote de tinta (fase 4.1): cheio da cor da tinta até a borda, com rótulo creme e um
## pingo escorrendo (primitive:paint_RRGGBB).
## Anel (borda de pote e de copo) de raio externo r e espessura t.
static func _ring(r: float, t: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.outer_radius = r
	m.inner_radius = r - t
	m.rings = 12
	m.ring_segments = 4
	return m


static func _paint_pot(col: Color) -> Array:
	var parts: Array = []
	parts.append([_cy(0.07, 0.066, 0.1, 10), _at(0, 0.05, 0), col.darkened(0.12)])
	parts.append([_cy(0.073, 0.072, 0.032, 10), _at(0, 0.042, 0), Color("f4f1e4")])
	parts.append([_cy(0.066, 0.066, 0.008, 10), _at(0, 0.102, 0), col])
	parts.append([_ring(0.074, 0.012), _at(0, 0.102, 0), Color("cfc6b4")])
	parts.append([_box(Vector3(0.018, 0.04, 0.008)), _at(0.02, 0.085, 0.071), col])
	parts.append([_sp(0.012, 0.016, 6), _at(0.02, 0.064, 0.072), col])
	return parts


## Peça de roupa para o ícone e para quando ela está no chão.
static func _wear_icon(item: String) -> Array:
	var parts: Array = []
	var col := {"beanie": "e86a6a", "straw_hat": "e9c46a", "cap": "6d8fe8", "scarf": "e86a6a", "coat": "6d8fe8",
		"tank_top": "f4f1e4", "pants": "5b6f8c", "shorts": "e9c46a", "boots": "7a5233", "sandals": "c99a6b",
		"poncho": "c0392b", "sun_hat": "f4f1e4", "fur_hat": "8d6e63", "flag_cape": "f4f1e4"}
	var c := Color(str(col.get(item, "c8b8a0")))
	match item:
		"beanie", "fur_hat":
			var h := SphereMesh.new()
			h.radius = 0.16
			h.height = 0.16
			h.is_hemisphere = true
			parts.append([h, _at(0, 0.0, 0), c])
		"straw_hat", "sun_hat":
			parts.append([_cy(0.24 if item == "straw_hat" else 0.3, 0.24 if item == "straw_hat" else 0.3, 0.02, 12), _at(0, 0.01, 0), c])
			parts.append([_cy(0.11, 0.12, 0.1, 10), _at(0, 0.07, 0), c])
		"cap":
			var h := SphereMesh.new()
			h.radius = 0.14
			h.height = 0.14
			h.is_hemisphere = true
			parts.append([h, _at(0, 0.0, 0), c])
			parts.append([_box(Vector3(0.18, 0.02, 0.12)), _at(0, 0.01, 0.15), c])
		"scarf":
			var t := TorusMesh.new()
			t.inner_radius = 0.09
			t.outer_radius = 0.14
			parts.append([t, _at(0, 0.03, 0), c])
		"coat", "tank_top", "poncho", "flag_cape":
			parts.append([_box(Vector3(0.3, 0.34, 0.08)), _at(0, 0.17, 0), c])
			if item == "coat":
				for x in [-0.2, 0.2]:
					parts.append([_box(Vector3(0.09, 0.28, 0.08)), _at(x, 0.19, 0), c])
		"pants", "shorts":
			var h := 0.32 if item == "pants" else 0.18
			for x in [-0.07, 0.07]:
				parts.append([_box(Vector3(0.11, h, 0.09)), _at(x, h * 0.5, 0), c])
			parts.append([_box(Vector3(0.26, 0.06, 0.1)), _at(0, h, 0), c])
		"boots", "sandals":
			for x in [-0.08, 0.08]:
				parts.append([_box(Vector3(0.11, 0.16 if item == "boots" else 0.03, 0.18)), _at(x, 0.08 if item == "boots" else 0.015, 0), c])
	return parts


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
