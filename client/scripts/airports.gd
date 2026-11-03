class_name Airports
extends Node3D
## Aeroportos (fase 2.5, ADR 0035). A lista vem do servidor (GET /airports): um por país,
## no hexágono mais perto da capital, que fica só para o aeroporto. Países pequenos ganham
## só um ponto de chegada (balcão na beirada do hexágono).
##
## Praça central do país (fase 3.5, ADR 0042; escala nova na fase 3.6, ADR 0047). A praça é
## desenhada em (u, v): a pista corre ao longo de u, na diagonal do hexágono, do lado v < 0;
## o terminal (concreto, vidro azulado, branco e um toque de verde), a torre, o balcão com a
## atendente, a loja e o chafariz ficam do lado v > 0. O servidor manda o ângulo (`rot`) e a
## escala (`scale`, menor nos hexágonos pequenos) e confere o balcão e a loja nos mesmos
## pontos (game/plaza.go). O avião tem a porta da altura do personagem e a asa maior que
## uma casa grande; os carros do pátio cabem o personagem. Depois de montada, a praça vira
## uma malha por material (menos o terminal, que fica pontilhado na frente da câmera).
## Só as praças perto do personagem são montadas. Na visão afastada, um aviãozinho marca cada uma.

const BUILD_RADIUS := 130.0
const FREE_RADIUS := 170.0
const UPDATE_EVERY := 0.5
const COUNTER_REACH := 2.0
const COUNTER := "res://assets/kenney/fantasy-town-kit/stall-red.glb"
const SHOP := "res://assets/kenney/fantasy-town-kit/stall-green.glb"
const LANTERN := "res://assets/kenney/fantasy-town-kit/lantern.glb"
const FOUNTAIN := "res://assets/kenney/fantasy-town-kit/fountain-round.glb"
const BENCH := "res://assets/kenney/graveyard-kit/bench.glb"
const BANNER := "res://assets/kenney/fantasy-town-kit/banner-green.glb"
const VAN := "res://assets/kenney/car-kit/van.glb"
const TRUCK := "res://assets/kenney/car-kit/truck-flat.glb"
const DELIVERY := "res://assets/kenney/car-kit/delivery.glb"
const CONE := "res://assets/kenney/car-kit/cone.glb"
## Peças que precisam estar carregadas antes do jogo começar.
const MODELS := [COUNTER, SHOP, LANTERN, FOUNTAIN, BENCH, BANNER, VAN, TRUCK, DELIVERY, CONE]
## Pontos da praça em (u, v); o servidor usa os mesmos (game/plaza.go).
const COUNTER_UV := Vector2(0.0, 3.6)
const SHOP_UV := Vector2(-7.6, 3.4)
const NPC_REACH := 2.4
## Escala do avião parado (o modelo tem 4 de comprimento): porta de ~1,4 de altura, asa de
## ~11 de ponta a ponta (a casa grande tem ~5).
const PLANE_SCALE := 3.0
## Onde o avião fica na pista (u, v) e a pista (comprimento até a ponta, centro e largura).
const PLANE_UV := Vector2(-1.5, -4.6)
const RUNWAY_HALF := 8.5
const RUNWAY_V := -4.6
const RUNWAY_WIDTH := 4.6
## Altura do topo de cada piso acima do chão do hexágono. Nenhum fica no mesmo plano de
## outro onde se encostam (era o que piscava: faixas, pista e chão no mesmo plano).
const TOP_RUNWAY := 0.08
const TOP_MARKS := 0.11
const TOP_APRON := 0.05
const TOP_WALK := 0.03
## Altura (do personagem ~1) que os carros do pátio têm: a porta fica da altura dele.
const VAN_HEIGHT := 1.5
const DELIVERY_HEIGHT := 1.8

var world: WorldData
var data: ChunkData
## [{country, country_name, name, city, cell, lat, lon, x, y, rot, scale, shop_x, shop_y, small}]
var list: Array = []
var by_country := {}
var _built := {}  # célula → Node3D
## Papéis dos NPCs (npcs.json do servidor).
var npc_roles := {}
## Materiais compartilhados do cenário (cria uma vez).
var _mats := {}
var _timer := 0.0
## Aviõezinhos da visão afastada: um MultiMesh só (antes, um Sprite3D por aeroporto: 200
## draw calls a mais no globo).
var _markers: MultiMeshInstance3D
var _marker_mat: StandardMaterial3D
var _plane_tex: ImageTexture
## Praça sendo montada: ângulo e escala (ver _uv) e as peças a juntar
## ([parte, material, arrays, transformação], o formato de Neighborhood._merge_arrays).
var _rot := 0.0
var _sc := 1.0
var _jobs: Array = []
## Junções rodando numa thread: [{task, root, out, occluder}].
var _merges: Array = []
## Arrays das malhas já usadas (modelos, caixa, cilindros), para não pedir de novo.
var _arrays_cache := {}


func setup(w: WorldData, d: ChunkData, airports: Array, roles := {}) -> void:
	world = w
	data = d
	list = airports
	npc_roles = roles
	for a: Dictionary in list:
		a["cell"] = int(a["cell"])
		by_country[str(a["country"])] = a
	_make_markers()


## Aeroporto (o mais perto) cujo balcão está a até COUNTER_REACH do ponto; {} se nenhum.
func counter_near(pos: Vector3) -> Dictionary:
	for cell: int in _built:
		var a: Dictionary = (_built[cell] as Node3D).get_meta("airport")
		if counter_point(a).distance_to(pos) < COUNTER_REACH:
			return a
	return {}


## NPC (o mais perto) a até NPC_REACH do ponto; null se nenhum.
func npc_near(pos: Vector3) -> Npc:
	var best: Npc = null
	var best_d := NPC_REACH
	for cell: int in _built:
		for n in (_built[cell] as Node3D).get_meta("npcs", []):
			var npc := n as Npc
			if is_instance_valid(npc):
				var d := npc.global_position.distance_to(pos)
				if d < best_d:
					best_d = d
					best = npc
	return best


## Aeroporto de um país ({} se não houver).
func airport_of(country: String) -> Dictionary:
	return by_country.get(country, {})


## Ponto do balcão no mundo.
func counter_point(a: Dictionary) -> Vector3:
	return WorldData.frame_point(data.frame(int(a["cell"])), float(a["x"]), float(a["y"]))


## Onde o viajante aparece ao chegar: na frente do balcão (lado da pista).
func arrival_point(a: Dictionary) -> Vector3:
	var f := data.frame(int(a["cell"]))
	var x := float(a["x"])
	var y := float(a["y"])
	if bool(a.get("small", false)):
		var out := Vector2(x, y).normalized() * -1.4  # para dentro do hexágono
		return WorldData.frame_point(f, x + out.x, y + out.y)
	var front := Vector2(0.0, -1.6).rotated(float(a.get("rot", 0.0)))
	return WorldData.frame_point(f, x + front.x, y + front.y)


## Um cubinho com cada material da praça, para o pré-aquecimento de shaders.
func warm_nodes() -> Array[Node3D]:
	var mats: Array[Material] = [_mat("apron", Color("b4b8bc")), _mat("walk", Color("ddd6c8")),
		_mat("asphalt", Color("5d6269")), _mat("white", Color("f7f7f4")), _mat("lamp", Color("ffd45a"), false, true),
		_mat("stair", Color("eef0f2")), _mat("stair_side", Color("9aa1a8")), _mat("concrete", Color("b9bdc2")),
		_mat("concrete_dark", Color("8d939a")), _mat("glass", Color(0.55, 0.74, 0.9, 0.42), true),
		_mat("accent", Color("7cc49a")), _mat("red_light", Color("ff5a5a"), false, true), _mat("sock_orange", Color("f08a3c"))]
	var out: Array[Node3D] = []
	for m in mats:
		var mi := MeshInstance3D.new()
		mi.mesh = BorderLines._baked(BoxMesh.new(), m)
		mi.set_meta("warm_size", 0.5)
		out.append(mi)
	return out


## Ponto (u, v) da praça de um aeroporto grande, no mundo (capturas e testes).
func plaza_point(a: Dictionary, u: float, v: float) -> Vector3:
	var sc := float(a.get("scale", 1.0))
	var p := Vector2(u * sc, v * sc).rotated(float(a.get("rot", 0.0)))
	return WorldData.frame_point(data.frame(int(a["cell"])), p.x, p.y)


## Caixas dos terminais montados, para a transparência da câmera (CameraOcclusion).
func occluders() -> Array:
	var out: Array = []
	for cell: int in _built:
		var root: Node3D = _built[cell]
		if is_instance_valid(root) and root.has_meta("occluders"):
			out.append_array(root.get_meta("occluders"))
	return out


## Aeroporto do país do jogador ("" se não houver).
func of_country(code: String) -> Dictionary:
	return by_country.get(code, {})


func update(focus: Vector3, far_amount: float, delta: float) -> void:
	_poll_merges()
	var far_on := far_amount > 0.25
	if _markers:
		_markers.visible = far_on
		if far_on:
			_marker_mat.albedo_color.a = 0.85 * smoothstep(0.25, 0.6, far_amount)
	_timer -= delta
	if _timer > 0.0 or world == null:
		return
	_timer = UPDATE_EVERY
	var dir := focus.normalized()
	var nearest := {}
	var nearest_d := INF
	for a: Dictionary in list:
		var cell := int(a["cell"])
		var d := dir.angle_to(world.centers[cell]) * world.radius
		if d < BUILD_RADIUS and not _built.has(cell) and d < nearest_d:
			nearest = a
			nearest_d = d
		elif d > FREE_RADIUS and _built.has(cell):
			(_built[cell] as Node).queue_free()
			_built.erase(cell)
	# Um aeroporto por quadro, o mais perto primeiro (na Europa, uma dúzia ficava pronta
	# no mesmo quadro: 200 ms). Se faltar outro, volta no quadro seguinte.
	if not nearest.is_empty():
		_build(nearest)
		_timer = 0.0


# --- Cenário ------------------------------------------------------------------------------
#
# Nada de nó por peça: cada peça vira um pedido (arrays + transformação + material) e uma
# thread junta tudo numa malha por material (Neighborhood._merge_arrays). Na thread principal
# ficam só a colisão, os NPCs e as placas (ADR 0036: a praça custava ~25 ms num quadro).

## Ponto (u, v) da praça no plano da célula (gira `_rot` e escala `_sc`).
func _uv(u: float, v: float) -> Vector2:
	return Vector2(u * _sc, v * _sc).rotated(_rot)


## Arrays de todas as superfícies de uma malha (da cache).
func _arrays_of(mesh: Mesh) -> Array:
	if not _arrays_cache.has(mesh):
		var list: Array = []
		for si in mesh.get_surface_count():
			list.append(mesh.surface_get_arrays(si))
		_arrays_cache[mesh] = list
	return _arrays_cache[mesh]


## Arrays de uma forma simples (caixa 1 × 1 × 1, cilindros, esfera), da cache.
func _prim(key: String, make: Callable) -> Array:
	if not _arrays_cache.has(key):
		_arrays_cache[key] = (make.call() as PrimitiveMesh).get_mesh_arrays()
	return _arrays_cache[key]


func _unit_box() -> Array:
	return _prim("box", func() -> PrimitiveMesh: return BoxMesh.new())


func _cylinder(top: float, bottom: float, segments := 8) -> Array:
	return _prim("cyl %.3f %.3f %d" % [top, bottom, segments], func() -> PrimitiveMesh:
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = 1.0
		c.radial_segments = segments
		c.rings = 1
		return c)


func _sphere() -> Array:
	return _prim("sphere", func() -> PrimitiveMesh:
		var b := SphereMesh.new()
		b.radius = 0.5
		b.height = 1.0
		b.radial_segments = 8
		b.rings = 4
		return b)


func _job(mat: Material, arrays: Array, xf: Transform3D, part := "rest") -> void:
	_jobs.append([part, mat, arrays, xf])


func _place(f: Dictionary, model: String, x: float, y: float, rot: float, scale: float) -> void:
	var lib := ModelLibrary.get_model(model)
	if lib.is_empty():
		return
	var mesh: Mesh = lib["mesh"]
	var aabb: AABB = lib["aabb"]
	var basis := WorldData.frame_basis(f, rot, scale)
	var offset := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	var xf := Transform3D(basis, WorldData.frame_point(f, x, y) - basis * offset)
	var surfaces := _arrays_of(mesh)
	for si in surfaces.size():
		_job(mesh.surface_get_material(si), surfaces[si], xf)


## Modelo num ponto (u, v) da praça, girado `yaw` em relação à pista.
func _place_uv(f: Dictionary, model: String, u: float, v: float, yaw: float, scale: float) -> void:
	var p := _uv(u, v)
	_place(f, model, p.x, p.y, _rot + yaw, scale * _sc)


## Modelo com `height` de altura (veículos: a porta fica da altura do personagem).
func _place_height(f: Dictionary, model: String, u: float, v: float, yaw: float, height: float) -> void:
	var lib := ModelLibrary.get_model(model)
	if lib.is_empty():
		return
	var aabb: AABB = lib["aabb"]
	_place_uv(f, model, u, v, yaw, height / maxf(aabb.size.y, 0.01))


## Caixa de colisão: centro (x, y) no plano da célula, base `lift` acima do chão.
func _box(body: StaticBody3D, f: Dictionary, x: float, y: float, size: Vector3, yaw := 0.0, lift := 0.0) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(WorldData.frame_basis(f, yaw), WorldData.frame_point(f, x, y) + (f["center"] as Vector3) * (lift + size.y * 0.5))
	body.add_child(cs)


## Caixa de colisão em (u, v) da praça, alinhada à pista.
func _box_uv(body: StaticBody3D, f: Dictionary, u: float, v: float, size: Vector3, lift := 0.0) -> void:
	var p := _uv(u, v)
	_box(body, f, p.x, p.y, size * _sc, _rot, lift * _sc)


func _build(a: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var cell := int(a["cell"])
	var f := data.frame(cell)
	var root := Node3D.new()
	root.name = "Airport_%s" % a["country"]
	root.set_meta("airport", a)
	add_child(root)
	_built[cell] = root
	var body := StaticBody3D.new()
	root.add_child(body)
	var x := float(a["x"])
	var y := float(a["y"])
	var npcs: Array = []
	_jobs = []
	if bool(a.get("small", false)):
		# Balcão compartilhado: atendente e lojista lado a lado, atrás do balcão.
		var face := Vector2(x, y).angle() + PI * 0.5
		_place(f, COUNTER, x, y, face, 1.5)
		_box(body, f, x, y, Vector3(1.4, 1.2, 1.0))
		_sign(root, f, x, y, 2.4, str(a["name"]))
		var inward := -Vector2(x, y).normalized()
		var side := Vector2(-inward.y, inward.x)
		var back := Vector2(x, y) - inward * 0.8
		npcs.append(_npc(root, f, a, "attendant", back + side * 0.45, Vector2(x, y) + inward))
		npcs.append(_npc(root, f, a, "shopkeeper", back - side * 0.45, Vector2(x, y) + inward))
		_windsock(f, x + 1.6 * cos(face), y + 1.6 * sin(face), 1.4)
		root.set_meta("npcs", npcs.filter(func(n: Variant) -> bool: return n != null))
		_start_merge(root, {})
		HitchLog.note("aeroporto montado: %s" % a.get("country", "?"), (Time.get_ticks_usec() - t0) / 1000.0)
		return
	_rot = float(a.get("rot", 0.0))
	_sc = float(a.get("scale", 1.0))
	if _sc <= 0.0:
		_sc = 1.0
	_grounds(f)
	_runway(f)
	_plane(body, f)
	var occluder := _terminal(root, body, f, str(a.get("city", "")))
	npcs.append(_npc_uv(root, f, a, "attendant", COUNTER_UV + Vector2(0.0, 0.75), COUNTER_UV + Vector2(0.0, -1.0)))
	_tower(body, f, 6.6, 5.8)
	_gate(root, f, 5.4, 3.4)
	# Veículos de pátio do Car Kit, na escala do personagem, e cones.
	_place_height(f, VAN, 7.6, 0.8, PI * 0.5, VAN_HEIGHT)
	_box_uv(body, f, 7.6, 0.8, Vector3(3.0, 1.4, 1.6))
	_place_height(f, TRUCK, 4.6, -1.0, PI * 0.5, VAN_HEIGHT)
	_place_height(f, DELIVERY, -6.8, 6.6, PI * 0.5, DELIVERY_HEIGHT)
	_box_uv(body, f, -6.8, 6.6, Vector3(3.6, 1.7, 1.8))
	for c: Vector2 in [Vector2(6.3, -0.4), Vector2(8.9, -0.4), Vector2(2.9, -1.6)]:
		_place_height(f, CONE, c.x, c.y, 0.0, 0.45)
	var ws := _uv(7.0, -8.4)
	_windsock(f, ws.x, ws.y, 3.0 * _sc)
	# Loja da praça: barraca verde com bandeira, o lojista atrás, banco na frente.
	_place_uv(f, SHOP, SHOP_UV.x, SHOP_UV.y, 0.0, 1.5)
	_box_uv(body, f, SHOP_UV.x, SHOP_UV.y, Vector3(1.6, 1.2, 1.2))
	var sp := _uv(SHOP_UV.x, SHOP_UV.y)
	_sign(root, f, sp.x, sp.y, 2.5, "Loja")
	_place_uv(f, BANNER, SHOP_UV.x - 1.4, SHOP_UV.y + 0.3, 0.0, 1.5)
	npcs.append(_npc_uv(root, f, a, "shopkeeper", SHOP_UV + Vector2(0.0, 0.9), SHOP_UV + Vector2(0.0, -2.0)))
	_place_uv(f, BENCH, SHOP_UV.x + 2.2, SHOP_UV.y - 0.6, 0.0, 1.3)
	# Ponto de encontro: o chafariz, com a guia ao lado, bancos e lampiões.
	_place_uv(f, FOUNTAIN, -3.9, 3.2, 0.0, 1.0)
	_box_uv(body, f, -3.9, 3.2, Vector3(2.4, 0.6, 2.4))
	npcs.append(_npc_uv(root, f, a, "guide", Vector2(-2.2, 2.6), Vector2(-2.2, 0.0)))
	_place_uv(f, BENCH, -5.6, 4.6, PI, 1.3)
	for l: Vector2 in [Vector2(-1.9, 4.6), Vector2(2.0, 2.6), Vector2(-9.0, 2.6)]:
		_place_uv(f, LANTERN, l.x, l.y, 0.0, 1.2)
	root.set_meta("npcs", npcs.filter(func(n: Variant) -> bool: return n != null))
	_start_merge(root, occluder)
	HitchLog.note("aeroporto montado: %s" % a.get("country", "?"), (Time.get_ticks_usec() - t0) / 1000.0)


## Manda as peças pedidas para a thread juntar (uma malha por material; o terminal à parte).
func _start_merge(root: Node3D, occluder: Dictionary) -> void:
	var jobs := _jobs
	_jobs = []
	if jobs.is_empty():
		return
	var out := []
	var task := WorkerThreadPool.add_task(func() -> void: out.append(Neighborhood._merge_arrays(jobs)))
	_merges.append({"task": task, "root": root, "out": out, "occluder": occluder})


## Junções prontas viram as malhas da praça (uma por quadro).
func _poll_merges() -> void:
	for i in _merges.size():
		var m: Dictionary = _merges[i]
		if not WorkerThreadPool.is_task_completed(m["task"]):
			continue
		WorkerThreadPool.wait_for_task_completion(m["task"])
		_merges.remove_at(i)
		var t0 := Time.get_ticks_usec()
		_finish_merge(m)
		HitchLog.note("malhas da praça", (Time.get_ticks_usec() - t0) / 1000.0)
		return


func _finish_merge(m: Dictionary) -> void:
	# Sem tipo de propósito: a praça pode ter sido solta enquanto a thread rodava.
	var r: Variant = m["root"]
	if not is_instance_valid(r) or (r as Node).is_queued_for_deletion() or (m["out"] as Array).is_empty():
		return
	var root: Node3D = r
	var by_part: Dictionary = m["out"][0]
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
		mi.name = "Terminal" if part == "house" else "Plaza"
		mi.mesh = mesh
		root.add_child(mi)
		if part == "house" and not (m["occluder"] as Dictionary).is_empty():
			var occ: Dictionary = m["occluder"]
			occ["mi"] = mi
			root.set_meta("occluders", [occ])


func _exit_tree() -> void:
	for m: Dictionary in _merges:
		WorkerThreadPool.wait_for_task_completion(m["task"])
	_merges.clear()


## NPC de um papel num ponto (x, y) do plano da célula, olhando para `look`.
func _npc(root: Node3D, f: Dictionary, a: Dictionary, role: String, at: Vector2, look: Vector2) -> Npc:
	if not npc_roles.has(role):
		return null
	var names: Dictionary = a.get("npcs", {})
	var npc := Npc.create(role, npc_roles[role], str(names.get(role, role)), str(a.get("country", "")))
	root.add_child(npc)
	var p := WorldData.frame_point(f, at.x, at.y)
	npc.global_position = p
	npc.face(WorldData.frame_point(f, look.x, look.y))
	return npc


## NPC num ponto (u, v) da praça, olhando para `look` (u, v).
func _npc_uv(root: Node3D, f: Dictionary, a: Dictionary, role: String, at: Vector2, look: Vector2) -> Npc:
	return _npc(root, f, a, role, _uv(at.x, at.y), _uv(look.x, look.y))


func _mat(key: String, c: Color, glass := false, glow := false) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		if glass:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.08
			m.metallic_specular = 0.9
		if glow:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 0.6
		_mats[key] = m
	return _mats[key]


## Caixa em (u, v) da praça, alinhada à pista: `size` = (ao longo de u, altura, ao longo de v),
## base `lift` acima do chão. Tudo escala com a praça.
func _slab(f: Dictionary, u: float, v: float, size: Vector3, m: Material, lift := 0.0, part := "rest") -> void:
	var p := _uv(u, v)
	var b := WorldData.frame_basis(f, _rot)
	b = Basis(b.x * size.x * _sc, b.y * size.y * _sc, b.z * size.z * _sc)
	_job(m, _unit_box(), Transform3D(b, WorldData.frame_point(f, p.x, p.y) + (f["center"] as Vector3) * (lift + size.y * 0.5) * _sc), part)


## Cilindro em pé num ponto do mundo: base em `base`, `height` de altura.
func _cyl(f: Dictionary, base: Vector3, top_r: float, bottom_r: float, height: float, m: Material) -> void:
	var b := WorldData.frame_basis(f, _rot)
	b = Basis(b.x, b.y * height, b.z)
	_job(m, _cylinder(top_r, bottom_r), Transform3D(b, base + (f["center"] as Vector3) * height * 0.5))


## Piso com o topo em `top` acima do chão; desce 0,3 para dentro do chão (o topo do
## hexágono cai um pouco perto da borda, e o piso não pode ficar flutuando).
func _floor(f: Dictionary, u0: float, u1: float, v0: float, v1: float, top: float, m: Material) -> void:
	_slab(f, (u0 + u1) * 0.5, (v0 + v1) * 0.5, Vector3(u1 - u0, top + 0.3, v1 - v0), m, -0.3)


## Pátio de concreto (entre a pista e o terminal) e a calçada da praça.
func _grounds(f: Dictionary) -> void:
	_floor(f, -8.5, 9.4, RUNWAY_V + RUNWAY_WIDTH * 0.5 + 0.05, 2.2, TOP_APRON, _mat("apron", Color("b4b8bc")))
	_floor(f, -9.6, 8.2, 2.2, 5.4, TOP_WALK, _mat("walk", Color("ddd6c8")))


## Pista de asfalto com faixa do meio tracejada, faixas de cabeceira, linhas das bordas e
## luzinhas. As faixas ficam acima do asfalto (nada no mesmo plano).
func _runway(f: Dictionary) -> void:
	var asphalt := _mat("asphalt", Color("5d6269"))
	var white := _mat("white", Color("f7f7f4"))
	var v0 := RUNWAY_V - RUNWAY_WIDTH * 0.5
	var v1 := RUNWAY_V + RUNWAY_WIDTH * 0.5
	_floor(f, -RUNWAY_HALF, RUNWAY_HALF, v0, v1, TOP_RUNWAY, asphalt)
	var mark_h := TOP_MARKS - TOP_RUNWAY - 0.005
	var lift := TOP_RUNWAY + 0.005
	for i in 6:
		_slab(f, -5.0 + i * 2.0, RUNWAY_V, Vector3(1.1, mark_h, 0.16), white, lift)
	for side in [-1.0, 1.0]:
		_slab(f, 0.0, RUNWAY_V + side * (RUNWAY_WIDTH * 0.5 - 0.2), Vector3(RUNWAY_HALF * 2.0 - 0.6, mark_h, 0.1), white, lift)
		for k in 6:
			_slab(f, side * (RUNWAY_HALF - 1.0), v0 + 0.75 + k * 0.62, Vector3(1.2, mark_h, 0.26), white, lift)
	var lamp := _mat("lamp", Color("ffd45a"), false, true)
	var up: Vector3 = f["center"]
	for i in 9:
		for vv in [v0 - 0.15, v1 + 0.15]:
			var p := _uv(-8.0 + i * 2.0, vv)
			_job(lamp, _sphere(), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.16), WorldData.frame_point(f, p.x, p.y) + up * 0.12))


## Avião parado na pista, nariz para o leste da pista, e a escadinha encostada na porta.
func _plane(body: StaticBody3D, f: Dictionary) -> void:
	var s := PLANE_SCALE * _sc
	var mesh := PlaneModel.mesh()
	var p := _uv(PLANE_UV.x, PLANE_UV.y)
	var ground := TOP_RUNWAY * _sc - PlaneModel.GROUND * s
	var xf := Transform3D(WorldData.frame_basis(f, _rot - PI * 0.5, s), WorldData.frame_point(f, p.x, p.y) + (f["center"] as Vector3) * ground)
	var surfaces := _arrays_of(mesh)
	for si in surfaces.size():
		_job(mesh.surface_get_material(si), surfaces[si], xf)
	# Colisão só da fuselagem (dá para passar embaixo das asas e do avião).
	var bottom := (PlaneModel.GROUND + 0.42) * -1.0 * PLANE_SCALE
	_box_uv(body, f, PLANE_UV.x, PLANE_UV.y, Vector3(4.0 * PLANE_SCALE * 0.95, 1.1 * PLANE_SCALE, 1.1 * PLANE_SCALE), bottom + TOP_RUNWAY)
	# Escadinha: degraus do chão até a porta (do lado do terminal, v maior).
	var door := PlaneModel.DOOR_CENTER
	var du := PLANE_UV.x - door.z * PLANE_SCALE
	var dv := PLANE_UV.y - door.x * PLANE_SCALE
	var sill := (door.y - PlaneModel.DOOR_HEIGHT * 0.5 - PlaneModel.GROUND) * PLANE_SCALE
	var steps := 8
	var depth := 0.28
	var stair := _mat("stair", Color("eef0f2"))
	var side := _mat("stair_side", Color("9aa1a8"))
	for k in steps:
		var h := sill * float(k + 1) / steps
		var vv := dv + 0.2 + (steps - k - 0.5) * depth
		_slab(f, du, vv, Vector3(1.0, 0.08, depth), stair, TOP_RUNWAY + h - 0.08)
		_slab(f, du, vv, Vector3(0.9, h - 0.08, depth - 0.02), side, TOP_RUNWAY)


## Terminal com cara de aeroporto: bloco de concreto cinza, saguão de vidro azulado na frente
## (para a pista), laje branca com uma faixa verde (a cor do Goblo), marquise branca sobre o
## balcão e o letreiro. O bloco fica pontilhado na frente da câmera (como as casas): devolve
## a caixa dele para a CameraOcclusion (a malha entra quando a junção termina).
func _terminal(root: Node3D, body: StaticBody3D, f: Dictionary, city: String) -> Dictionary:
	var concrete := _mat("concrete", Color("b9bdc2"))
	var dark := _mat("concrete_dark", Color("8d939a"))
	var glass := _mat("glass", Color(0.55, 0.74, 0.9, 0.42), true)
	var white := _mat("white", Color("f7f7f4"))
	var accent := _mat("accent", Color("7cc49a"))
	# Bloco de trás (concreto) e o piso do saguão.
	_slab(f, 0.0, 7.5, Vector3(8.0, 3.2, 1.8), concrete, 0.0, "house")
	_slab(f, 0.0, 6.0, Vector3(8.2, 0.3, 1.4), dark)
	# Saguão: vidro na frente e nos lados, montantes brancos.
	_slab(f, 0.0, 5.45, Vector3(7.9, 2.9, 0.08), glass, 0.3)
	for sd in [-1.0, 1.0]:
		_slab(f, sd * 3.95, 6.05, Vector3(0.08, 2.9, 1.2), glass, 0.3)
	for k in 6:
		_slab(f, -4.0 + k * 1.6, 5.42, Vector3(0.12, 2.9, 0.16), white, 0.3)
	# Laje branca com a faixa verde em volta.
	_slab(f, 0.0, 6.9, Vector3(8.6, 0.3, 3.6), white, 3.2)
	_slab(f, 0.0, 6.9, Vector3(8.7, 0.16, 3.7), accent, 3.27)
	# Marquise do balcão, com dois pilares brancos, e o balcão de check-in.
	_slab(f, 0.0, 4.4, Vector3(3.2, 0.14, 2.4), white, 2.5)
	_slab(f, 0.0, 4.4, Vector3(3.26, 0.06, 2.46), accent, 2.46)
	for sd in [-1.0, 1.0]:
		_slab(f, sd * 1.45, 3.35, Vector3(0.14, 2.46, 0.14), white, TOP_WALK)
	_slab(f, COUNTER_UV.x, COUNTER_UV.y, Vector3(1.8, 0.95, 0.55), white, TOP_WALK)
	_slab(f, COUNTER_UV.x, COUNTER_UV.y - 0.29, Vector3(1.7, 0.6, 0.02), accent, TOP_WALK + 0.2)
	_box_uv(body, f, COUNTER_UV.x, COUNTER_UV.y, Vector3(1.8, 1.0, 0.6))
	var sp := _uv(0.0, 4.0)
	_sign(root, f, sp.x, sp.y, 3.3 * _sc, "Aeroporto" if city.is_empty() else "Aeroporto de " + city)
	_box_uv(body, f, 0.0, 6.9, Vector3(8.0, 3.4, 3.0))
	var c := _uv(0.0, 7.5)
	var center := WorldData.frame_point(f, c.x, c.y) + (f["center"] as Vector3) * 1.6 * _sc
	return {"mi": null, "xf": Transform3D(WorldData.frame_basis(f, _rot), center), "half": Vector3(4.2, 1.8, 1.1) * _sc}


## Torre de controle no mesmo estilo do terminal: base e haste de concreto, cabine de vidro
## azulado com piso e teto brancos, faixa verde, antena com luz vermelha.
func _tower(body: StaticBody3D, f: Dictionary, u: float, v: float) -> void:
	var up: Vector3 = f["center"]
	var p := _uv(u, v)
	var base := WorldData.frame_point(f, p.x, p.y)
	var concrete := _mat("concrete", Color("b9bdc2"))
	var glass := _mat("glass", Color(0.55, 0.74, 0.9, 0.42), true)
	var white := _mat("white", Color("f7f7f4"))
	var accent := _mat("accent", Color("7cc49a"))
	var parts := [
		[0.0, 1.0, 0.85, 0.95, concrete], [1.0, 4.4, 0.45, 0.5, concrete], [5.4, 0.2, 1.2, 1.1, white],
		[5.6, 1.1, 1.05, 1.05, glass], [6.7, 0.25, 1.25, 1.25, white], [6.75, 0.14, 1.28, 1.28, accent],
		[6.95, 0.8, 0.04, 0.04, white]]
	for q: Array in parts:
		_cyl(f, base + up * float(q[0]) * _sc, float(q[2]) * _sc, float(q[3]) * _sc, float(q[1]) * _sc, q[4])
	_job(_mat("red_light", Color("ff5a5a"), false, true), _sphere(), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.2), base + up * 7.8 * _sc))
	_box_uv(body, f, u, v, Vector3(1.9, 7.0, 1.9))


## Portão de embarque: dois postes brancos, viga verde e a plaquinha.
func _gate(root: Node3D, f: Dictionary, u: float, v: float) -> void:
	var white := _mat("white", Color("f7f7f4"))
	var accent := _mat("accent", Color("7cc49a"))
	_slab(f, u - 0.8, v, Vector3(0.14, 2.2, 0.14), white, TOP_WALK)
	_slab(f, u + 0.8, v, Vector3(0.14, 2.2, 0.14), white, TOP_WALK)
	_slab(f, u, v, Vector3(2.0, 0.18, 0.5), accent, 2.2)
	var p := _uv(u, v)
	_sign(root, f, p.x, p.y, 2.7 * _sc, "Embarque")


func _sign(root: Node3D, f: Dictionary, x: float, y: float, height: float, text: String) -> void:
	var sign := Label3D.new()
	sign.text = text
	sign.font_size = 40
	sign.pixel_size = 0.005
	sign.outline_size = 10
	sign.modulate = Color("5a4630")
	sign.outline_modulate = Color(1, 0.95, 0.8, 0.95)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = WorldData.frame_point(f, x, y) + (f["center"] as Vector3) * height
	sign.visibility_range_end = 40.0
	root.add_child(sign)


## Biruta: mastro branco e uma manga listrada (laranja e branca) apontando para o leste.
func _windsock(f: Dictionary, x: float, y: float, height: float) -> void:
	var up: Vector3 = f["center"]
	var base := WorldData.frame_point(f, x, y)
	var white := _mat("white", Color("f7f7f4"))
	_job(white, _cylinder(0.04, 0.05), Transform3D(Basis(f["east"], up * height, -(f["north"] as Vector3)), base + up * height * 0.5))
	var east: Vector3 = f["east"]
	for k in 3:
		# Cilindro deitado na direção leste, um pouco caído (o eixo do cilindro é o Y local).
		var axis := east.rotated(f["north"], 0.25)
		var bx := up.cross(axis).normalized()
		var b := Basis(bx, axis * 0.32, bx.cross(axis))
		var m := _mat("sock_orange", Color("f08a3c")) if k % 2 == 0 else white
		_job(m, _cylinder(0.17 - k * 0.035, 0.2 - k * 0.035, 10), Transform3D(b, base + up * (height - 0.12) + axis * (0.2 + k * 0.32)))


# --- Marcadores na visão afastada ---------------------------------------------------------

## Tamanho do aviãozinho no globo (unidades; o planeta tem raio 1000).
const MARKER_SIZE := 24.0


func _make_markers() -> void:
	if _markers:
		_markers.queue_free()
	if _plane_tex == null:
		_plane_tex = plane_texture()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * MARKER_SIZE
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.albedo_texture = _plane_tex
	_marker_mat.albedo_color = Color(1, 1, 1, 0.85)
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_marker_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BorderLines._baked(quad, _marker_mat)  # PrimitiveMesh no MultiMesh dá erro no headless
	# Só os aeroportos de verdade (os balcões dos países pequenos não entram).
	var real := list.filter(func(a: Dictionary) -> bool: return not bool(a.get("small", false)))
	mm.instance_count = real.size()
	for i in real.size():
		var cell := int(real[i]["cell"])
		mm.set_instance_transform(i, Transform3D(Basis(), world.centers[cell] * (world.surface_radius(cell) + 3.0)))
	_markers = MultiMeshInstance3D.new()
	_markers.multimesh = mm
	_markers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_markers.visible = false
	add_child(_markers)


## Aviãozinho fofo (usado no globo afastado e no mini mapa).
static func plane_texture() -> ImageTexture:
	var n := 48
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var poly := plane_polygon(Vector2(n * 0.5, n * 0.5), n * 0.9)
	for yy in n:
		for xx in n:
			var p := Vector2(xx + 0.5, yy + 0.5)
			if Geometry2D.is_point_in_polygon(p, poly):
				img.set_pixel(xx, yy, Color("ffffff"))
			else:
				for dx in [-2, 0, 2]:
					for dy in [-2, 0, 2]:
						if Geometry2D.is_point_in_polygon(p + Vector2(dx, dy), poly):
							img.set_pixel(xx, yy, Color("3a6ea5"))
	return ImageTexture.create_from_image(img)


## Silhueta do avião (nariz para cima) centrada em `c`, com `s` de altura.
static func plane_polygon(c: Vector2, s: float) -> PackedVector2Array:
	var pts := [
		[0.0, -0.5], [0.07, -0.4], [0.07, -0.1], [0.46, 0.08], [0.46, 0.16], [0.07, 0.06],
		[0.06, 0.32], [0.18, 0.42], [0.18, 0.48], [0.0, 0.43], [-0.18, 0.48], [-0.18, 0.42],
		[-0.06, 0.32], [-0.07, 0.06], [-0.46, 0.16], [-0.46, 0.08], [-0.07, -0.1], [-0.07, -0.4],
	]
	var out := PackedVector2Array()
	for p: Array in pts:
		out.append(c + Vector2(p[0], p[1]) * s)
	return out
