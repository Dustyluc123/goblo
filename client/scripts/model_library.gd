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
##
## Nomes aceitos em `get_model`:
##   "CommonTree_1"           → Ultimate Nature Pack (client/assets/quaternius/ultimate-nature)
##   "res://…/fence.glb"      → qualquer cena
##   "flower:red"             → flor do Nature Pack com as pétalas recoloridas
##   "primitive:axe"          → modelos simples feitos aqui (machado, picareta, bancada, coco)

const NATURE_DIR := "res://assets/quaternius/ultimate-nature/"
const FLOWER_COLORS := {
	"red": Color("e0484f"), "yellow": Color("f4c542"), "white": Color("f5f2ea"), "purple": Color("9a6ad6"),
}
## Cor original das pétalas no Flowers.fbx (a que é trocada nas flores coloridas).
const PETAL_COLOR := Color("007b7c")

static var _cache := {}  # nome → {"mesh": ArrayMesh, "aabb": AABB}
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


## {"mesh": ArrayMesh, "aabb": AABB} do modelo (nulo se não existe). Fica em cache.
static func get_model(name: String) -> Dictionary:
	_mutex.lock()
	if _cache.has(name):
		var hit: Dictionary = _cache[name]
		_mutex.unlock()
		return hit
	_mutex.unlock()
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
	return _build(groups)


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

## Machado, picareta, bancada e coco, feitos de caixas e cilindros low-poly.
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
		"coconut":
			var s := SphereMesh.new()
			s.radius = 0.12
			s.height = 0.22
			s.radial_segments = 8
			s.rings = 4
			parts.append([s, Transform3D(Basis(), Vector3(0, 0.11, 0)), Color("6b4a2f")])
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


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
