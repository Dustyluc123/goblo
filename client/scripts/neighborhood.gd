class_name Neighborhood
extends Node3D
## O bairro: desenha os lotes ocupados que o ChunkData trouxe (o do jogador e os dos
## vizinhos), com a borda no chão, a plaquinha com o apelido do dono, a casa (ou a obra)
## e os objetos colocados. Cada lote vira um nó; ele é refeito quando o lote muda.
##
## As casas são cenas montadas com o Fantasy Town Kit (scenes/houses/), juntadas numa
## malha só pela ModelLibrary (1 draw call por casa). Os lampiões acendem à noite; só os
## mais perto ganham luz de verdade, para não pesar.
##
## Desempenho: o lote de um vizinho (casa, decorações, plaquinha, obra) vira UMA malha por
## material (2 a 4 draw calls em vez de ~25). O lote do jogador fica peça por peça, porque
## o modo construção, a bancada e o destaque dos objetos que atrapalham precisam disso.
## Lotes além de `view_distance` (do preset de qualidade) não são desenhados.

const MAX_LIGHTS := 6
const SIGN_VISIBLE := 45.0

var world: WorldData
var data: ChunkData
var session: Session
## 0 = noite, 1 = dia (vem do DayNight), para os lampiões.
var daylight := 1.0

var _lots := {}  # id do lote → Node3D
var _lanterns: Array = []  # [OmniLight3D, MeshInstance3D]
var _light_timer := 0.0
var _border_mat: StandardMaterial3D
var _own_border_mat: StandardMaterial3D
## Materiais compartilhados (para as malhas dos lotes se juntarem).
var _wood_mat: StandardMaterial3D
var _paint_mat: StandardMaterial3D
var _own_paint_mat: StandardMaterial3D
var _scaffold_mat: StandardMaterial3D
## Até onde os lotes aparecem.
var view_distance := 120.0


func setup(w: WorldData, d: ChunkData, s: Session) -> void:
	world = w
	data = d
	session = s
	_border_mat = _line_material(Color(1, 1, 1, 0.22))
	_own_border_mat = _line_material(Color(1, 0.97, 0.75, 0.6))
	_wood_mat = _solid(Color("8a5a3b"))
	_paint_mat = _solid(Color("f3e3c3"))
	_own_paint_mat = _solid(Color("ffe9a8"))
	_scaffold_mat = _solid(Color("b98a5a"))
	data.chunk_loaded.connect(_on_chunk_loaded)
	data.chunk_unloaded.connect(_on_chunk_unloaded)
	data.lot_changed.connect(build_lot)


func _line_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _solid(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


## Distância máxima em que os lotes são desenhados (preset de qualidade).
func set_view_distance(d: float) -> void:
	view_distance = d
	for node: Node3D in _lots.values():
		_apply_range(node)


func _apply_range(root: Node) -> void:
	for c in root.find_children("*", "GeometryInstance3D", true, false):
		if c is Label3D:
			continue
		var gi := c as GeometryInstance3D
		gi.visibility_range_end = view_distance
		gi.visibility_range_end_margin = 8.0


func _on_chunk_loaded(key: int) -> void:
	for l: Dictionary in data.chunk(key).get("lots", []):
		build_lot(l)


func _on_chunk_unloaded(key: int) -> void:
	for l: Dictionary in data.chunk(key).get("lots", []):
		_remove_lot(int(l["id"]))


func _remove_lot(id: int) -> void:
	if _lots.has(id):
		(_lots[id] as Node).queue_free()
		_lots.erase(id)
	_lanterns = _lanterns.filter(func(pair: Array) -> bool: return is_instance_valid(pair[0]) and not (pair[0] as Node).is_queued_for_deletion())


## Nó do lote (para o modo construção achar os objetos).
## Pinta de vermelho os objetos `ids` do lote (os que atrapalham a obra). Vazio limpa.
func highlight_placements(lot_id: int, ids: Array) -> void:
	var node := lot_node(lot_id)
	if node == null:
		return
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(1.0, 0.25, 0.2, 0.55)
	red.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.no_depth_test = true
	for c in node.get_children():
		if c is MeshInstance3D and c.has_meta("placement"):
			var on := int((c.get_meta("placement") as Dictionary).get("id", -1)) in ids
			(c as MeshInstance3D).material_overlay = red if on else null


func lot_node(id: int) -> Node3D:
	return _lots.get(id)


## (Re)monta um lote.
func build_lot(l: Dictionary) -> void:
	var id := int(l["id"])
	_remove_lot(id)
	var root := Node3D.new()
	root.name = "Lot%d" % id
	root.set_meta("occluders", [])
	add_child(root)
	_lots[id] = root
	var f := data.frame(int(l["cell"]))
	var tile := session.tile_size
	var n := session.lot_tiles
	var own := int(l.get("owner_id", -1)) == int(session.me.get("id", -2))
	root.add_child(_border(f, l, tile, n, own))
	root.add_child(_sign(f, l, tile, n, str(l.get("owner", "?")), own))
	var body := StaticBody3D.new()
	root.add_child(body)

	var house: Variant = l.get("house")
	if house is Dictionary:
		_build_house(root, body, f, l, tile, house)
	for p: Dictionary in l.get("placements", []):
		_build_placement(root, body, f, l, tile, p)
	if not own:
		_merge(root)
	_apply_range(root)


## Junta as malhas do lote em duas ArrayMesh com uma superfície por material: a casa
## (meta "house") e o resto (decorações, placa, andaime). Separadas para a casa e as
## decorações ficarem transparentes na frente da câmera sem desbotar o lote inteiro; as
## caixas de `occluders` passam a apontar para a malha juntada certa.
## Fica de fora: borda (transparente), textos e luzes.
func _merge(root: Node3D) -> void:
	var by_part := {"house": {}, "rest": {}}  # parte → material → {v, n, uv, c, i}
	var part_of := {}  # malha original → parte
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.material_override == _border_mat or mi.material_override == _own_border_mat:
			continue
		var part := "house" if mi.has_meta("house") else "rest"
		part_of[mi] = part
		var groups: Dictionary = by_part[part]
		var xf := _local_to(mi, root)
		var nb := xf.basis.inverse().transposed()
		for si in mi.mesh.get_surface_count():
			var mat: Material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(si)
			var arrays := mi.mesh.surface_get_arrays(si)
			if not groups.has(mat):
				groups[mat] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
			var g: Dictionary = groups[mat]
			var gv: PackedVector3Array = g["v"]
			var gn: PackedVector3Array = g["n"]
			var guv: PackedVector2Array = g["uv"]
			var gc: PackedColorArray = g["c"]
			var gi: PackedInt32Array = g["i"]
			var base := gv.size()
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			for k in verts.size():
				gv.append(xf * verts[k])
				gn.append((nb * normals[k]).normalized() if k < normals.size() else Vector3.UP)
				guv.append(uvs[k] if k < uvs.size() else Vector2.ZERO)
				gc.append(cols[k] if k < cols.size() else Color.WHITE)
			if arrays[Mesh.ARRAY_INDEX] == null:
				for k in verts.size():
					gi.append(base + k)
			else:
				for k in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
					gi.append(base + k)
			g["v"] = gv
			g["n"] = gn
			g["uv"] = guv
			g["c"] = gc
			g["i"] = gi
		mi.get_parent().remove_child(mi)
	var merged := {}
	for part: String in by_part:
		var groups: Dictionary = by_part[part]
		if groups.is_empty():
			continue
		var mesh := ArrayMesh.new()
		for mat: Material in groups:
			var g: Dictionary = groups[mat]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = g["v"]
			arrays[Mesh.ARRAY_NORMAL] = g["n"]
			arrays[Mesh.ARRAY_TEX_UV] = g["uv"]
			arrays[Mesh.ARRAY_COLOR] = g["c"]
			arrays[Mesh.ARRAY_INDEX] = g["i"]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		var mi := MeshInstance3D.new()
		mi.name = "Merged" + part.capitalize()
		mi.mesh = mesh
		if part == "house":
			mi.set_meta("house", true)
		root.add_child(mi)
		merged[part] = mi
	for occ: Dictionary in root.get_meta("occluders", []):
		occ["mi"] = merged.get(part_of.get(occ["mi"], "rest"))
	for mi: MeshInstance3D in part_of:
		mi.queue_free()


static func _local_to(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _border(f: Dictionary, l: Dictionary, tile: float, n: int, own: bool) -> MeshInstance3D:
	var w := 0.06 if own else 0.04
	var verts := PackedVector3Array()
	var corners := [Vector2(0, 0), Vector2(n, 0), Vector2(n, n), Vector2(0, n)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x) * (w / tile)
		var p0 := LotGeom.point(f, l, tile, a.x, a.y, 0.03)
		var p1 := LotGeom.point(f, l, tile, b.x, b.y, 0.03)
		var p2 := LotGeom.point(f, l, tile, b.x + side.x, b.y + side.y, 0.03)
		var p3 := LotGeom.point(f, l, tile, a.x + side.x, a.y + side.y, 0.03)
		verts.append_array([p0, p1, p2, p0, p2, p3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _own_border_mat if own else _border_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _sign(f: Dictionary, l: Dictionary, tile: float, n: int, owner: String, own: bool) -> Node3D:
	var node := Node3D.new()
	var pos := LotGeom.point(f, l, tile, n * 0.5, -0.6)
	node.transform = Transform3D(WorldData.frame_basis(f, 0.0), pos)
	var post := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.7, 0.08)
	post.mesh = box
	post.position = Vector3(0, 0.35, 0)
	post.material_override = _wood_mat
	node.add_child(post)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.32, 0.05)
	board.mesh = bm
	board.position = Vector3(0, 0.78, 0)
	board.material_override = _own_paint_mat if own else _paint_mat
	node.add_child(board)
	var label := Label3D.new()
	label.text = owner
	label.font_size = 40
	label.pixel_size = 0.004
	label.outline_size = 8
	label.modulate = Color("4a3b2c")
	label.outline_modulate = Color(1, 1, 1, 0.7)
	label.position = Vector3(0, 0.78, 0.035)
	label.visibility_range_end = SIGN_VISIBLE
	node.add_child(label)
	var back := label.duplicate() as Label3D
	back.position = Vector3(0, 0.78, -0.035)
	back.rotation.y = PI
	node.add_child(back)
	return node


func _build_house(root: Node3D, body: StaticBody3D, f: Dictionary, l: Dictionary, tile: float, house: Dictionary) -> void:
	var level := int(house.get("level", 0))
	var pending := int(house.get("pending_level", 0))
	var x := int(house["x"])
	var y := int(house["y"])
	var rot := int(house.get("rot", 0))
	if level > 0:
		var h := session.house_level(level)
		var fp := Vector2i(int(h["footprint"][0]), int(h["footprint"][1]))
		var house_mi := _add_model(root, f, l, tile, str(h["scene"]), fp, x, y, rot, 1.0)
		var height := 2.6
		if house_mi:
			house_mi.set_meta("house", true)
			# Caixa da altura da casa com o telhado (colisão e transparência na câmera).
			height = maxf(height, house_mi.mesh.get_aabb().size.y)
			_add_occluder(root, house_mi, f, l, tile, fp, x, y, rot, height + 0.15)
		_add_box(body, f, l, tile, fp, x, y, rot, height)
	if pending > 0:
		# A obra pode ficar num lugar diferente da casa atual (a melhoria cresce).
		x = int(house.get("pending_x", x))
		y = int(house.get("pending_y", y))
		var hp := session.house_level(pending)
		var fp := Vector2i(int(hp["footprint"][0]), int(hp["footprint"][1]))
		var r := LotGeom.rotated(fp, rot)
		root.add_child(_scaffold(f, l, tile, r, x, y, 2.4 if level == 0 else 3.2))
		if level == 0:
			_add_box(body, f, l, tile, fp, x, y, rot, 1.5)
		var sign := Label3D.new()
		sign.text = "Em obras: %s\npronta amanhã às 5h" % str(hp.get("name", "casa"))
		sign.font_size = 36
		sign.pixel_size = 0.005
		sign.outline_size = 10
		sign.modulate = Color("5a4630")
		sign.outline_modulate = Color(1, 0.95, 0.8, 0.9)
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.position = LotGeom.point(f, l, tile, x + r.x * 0.5, y + r.y * 0.5, 3.4 if level > 0 else 2.2)
		sign.visibility_range_end = SIGN_VISIBLE
		root.add_child(sign)


func _build_placement(root: Node3D, body: StaticBody3D, f: Dictionary, l: Dictionary, tile: float, p: Dictionary) -> void:
	var item: Dictionary = session.items.get(str(p["item"]), {})
	if item.is_empty():
		return
	var fp := LotGeom.footprint_of(item)
	var x := int(p["x"])
	var y := int(p["y"])
	var rot := int(p.get("rot", 0))
	var mi := _add_model(root, f, l, tile, str(item["model"]), fp, x, y, rot, float(item.get("scale", 1.0)))
	if mi:
		mi.set_meta("placement", p)
	var h := float(item.get("height", 0.0))
	if h > 0.0:
		_add_box(body, f, l, tile, fp, x, y, rot, h, 0.8)
		if mi:
			_add_occluder(root, mi, f, l, tile, fp, x, y, rot, h + 0.1)
	if item.get("light", false) and mi:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.82, 0.55)
		light.omni_range = 5.0
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.visible = false
		# O nó do lote fica na origem, então posição local = posição no mundo.
		light.position = mi.position + (f["center"] as Vector3) * 1.75
		root.add_child(light)
		_lanterns.append([light, mi])


## Andaime de madeira em volta do footprint `r` (em quadradinhos), com `height` de altura.
func _scaffold(f: Dictionary, l: Dictionary, tile: float, r: Vector2i, x: int, y: int, height: float) -> Node3D:
	var node := Node3D.new()
	var center := LotGeom.point(f, l, tile, x + r.x * 0.5, y + r.y * 0.5)
	node.transform = Transform3D(WorldData.frame_basis(f, 0.0), center)
	var wood := _scaffold_mat
	var hx := r.x * tile * 0.5
	var hz := r.y * tile * 0.5
	var parts: Array = []  # [tamanho, posição, rotação em z]
	for cx in [-hx, hx]:
		for cz in [-hz, hz]:
			parts.append([Vector3(0.09, height, 0.09), Vector3(cx, height * 0.5, cz), 0.0])
	for hy in [height * 0.45, height * 0.9]:
		parts.append([Vector3(hx * 2.0, 0.07, 0.07), Vector3(0, hy, hz), 0.0])
		parts.append([Vector3(hx * 2.0, 0.07, 0.07), Vector3(0, hy, -hz), 0.0])
		parts.append([Vector3(0.07, 0.07, hz * 2.0), Vector3(hx, hy, 0), 0.0])
		parts.append([Vector3(0.07, 0.07, hz * 2.0), Vector3(-hx, hy, 0), 0.0])
	parts.append([Vector3(hx * 2.2, 0.06, 0.06), Vector3(0, height * 0.45, hz), atan2(height * 0.9, hx * 2.0)])
	parts.append([Vector3(hx * 1.2, 0.12, hz * 0.6), Vector3(0, 0.06, 0), 0.0])
	parts.append([Vector3(hx * 1.0, 0.12, hz * 0.5), Vector3(0.1, 0.18, 0.05), 0.0])
	for part: Array in parts:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		mi.mesh = box
		mi.material_override = wood
		mi.position = part[1]
		mi.rotation.z = part[2]
		node.add_child(mi)
	return node


## Coloca um modelo (ModelLibrary) no lote. Devolve o MeshInstance3D (ou null).
func _add_model(root: Node3D, f: Dictionary, l: Dictionary, tile: float, model: String, fp: Vector2i, x: int, y: int, rot: int, scale: float) -> MeshInstance3D:
	var lib := ModelLibrary.get_model(model)
	if lib.is_empty():
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = lib["mesh"]
	mi.transform = LotGeom.model_transform(f, l, tile, fp, x, y, rot, lib["aabb"], scale)
	root.add_child(mi)
	return mi


## Caixa orientada de algo que pode ficar entre a câmera e o personagem; `mi` é a malha
## que fica transparente (CameraOcclusion). Um pouco maior que o footprint (beiral).
func _add_occluder(root: Node3D, mi: MeshInstance3D, f: Dictionary, l: Dictionary, tile: float, fp: Vector2i, x: int, y: int, rot: int, height: float) -> void:
	var r := LotGeom.rotated(fp, rot)
	var center := LotGeom.point(f, l, tile, x + r.x * 0.5, y + r.y * 0.5, height * 0.5)
	var half := Vector3(r.x * tile * 0.5 + 0.1, height * 0.5, r.y * tile * 0.5 + 0.1)
	(root.get_meta("occluders") as Array).append({"mi": mi, "xf": Transform3D(WorldData.frame_basis(f, 0.0), center), "half": half})


## Caixas de quem pode ficar entre a câmera e o personagem no lote `id`.
func occluders(id: int) -> Array:
	var node := lot_node(id)
	return node.get_meta("occluders", []) if node else []


func _add_box(body: StaticBody3D, f: Dictionary, l: Dictionary, tile: float, fp: Vector2i, x: int, y: int, rot: int, height: float, shrink := 0.9) -> void:
	var r := LotGeom.rotated(fp, rot)
	var shape := BoxShape3D.new()
	shape.size = Vector3(r.x * tile * shrink, height, r.y * tile * shrink)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var center := LotGeom.point(f, l, tile, x + r.x * 0.5, y + r.y * 0.5, height * 0.5)
	# Base sem giro: x = leste, z = sul; o footprint girado já está em r.
	cs.transform = Transform3D(WorldData.frame_basis(f, 0.0), center)
	body.add_child(cs)


## Acende os lampiões mais perto do personagem à noite (chamado a cada quadro).
func update_lights(focus: Vector3, delta: float) -> void:
	_light_timer -= delta
	if _light_timer > 0.0:
		return
	_light_timer = 0.5
	_lanterns = _lanterns.filter(func(pair: Array) -> bool: return is_instance_valid(pair[0]))
	var night := daylight < 0.45
	var sorted := _lanterns.duplicate()
	sorted.sort_custom(func(a: Array, b: Array) -> bool:
		return (a[0] as Node3D).global_position.distance_squared_to(focus) < (b[0] as Node3D).global_position.distance_squared_to(focus))
	for i in sorted.size():
		var light: OmniLight3D = sorted[i][0]
		var on := night and i < MAX_LIGHTS and light.global_position.distance_to(focus) < 60.0
		light.visible = on
		light.light_energy = 1.4 if on else 0.0
