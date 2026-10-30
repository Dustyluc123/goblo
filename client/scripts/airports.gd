class_name Airports
extends Node3D
## Aeroportos (fase 2.5, ADR 0035). A lista vem do servidor (GET /airports): um por país,
## no hexágono mais perto da capital, que fica só para o aeroporto. Países pequenos ganham
## só um ponto de chegada (balcão na beirada do hexágono).
##
## Praça central do país (fase 3.5, ADR 0042): no hexágono do aeroporto ficam o terminal
## com vidraça e o balcão (atendente), a torre de controle, a pista com faixas de cabeceira
## e luzinhas, a biruta, o portão de embarque, veículos de pátio do Car Kit, o avião parado
## (PlaneModel), a loja (lojista) e a fonte onde fica a guia. Nos países pequenos, o balcão
## é compartilhado: atendente e lojista lado a lado. Os NPCs abrem diálogos (E). Só as
## praças perto do personagem são montadas. Na visão afastada, um aviãozinho marca cada uma.

const BUILD_RADIUS := 130.0
const FREE_RADIUS := 170.0
const UPDATE_EVERY := 0.5
const COUNTER_REACH := 2.0
const COUNTER := "res://assets/kenney/fantasy-town-kit/stall-red.glb"
const SHOP := "res://assets/kenney/fantasy-town-kit/stall-green.glb"
const ROAD := "res://assets/kenney/fantasy-town-kit/road.glb"
const CART := "res://assets/kenney/fantasy-town-kit/cart.glb"
const LANTERN := "res://assets/kenney/fantasy-town-kit/lantern.glb"
const FOUNTAIN := "res://assets/kenney/fantasy-town-kit/fountain-round.glb"
const BENCH := "res://assets/kenney/graveyard-kit/bench.glb"
const BANNER := "res://assets/kenney/fantasy-town-kit/banner-green.glb"
const VAN := "res://assets/kenney/car-kit/van.glb"
const TRUCK := "res://assets/kenney/car-kit/truck-flat.glb"
const DELIVERY := "res://assets/kenney/car-kit/delivery.glb"
const CONE := "res://assets/kenney/car-kit/cone.glb"
## Peças que precisam estar carregadas antes do jogo começar.
const MODELS := [COUNTER, SHOP, ROAD, CART, LANTERN, FOUNTAIN, BENCH, BANNER, VAN, TRUCK, DELIVERY, CONE]
## Pontos da praça no plano do hexágono (o servidor usa os mesmos: game.ShopPoint).
const SHOP_POINT := Vector2(-6.0, 2.6)
const NPC_REACH := 2.4

var world: WorldData
var data: ChunkData
## [{country, country_name, name, city, cell, lat, lon, x, y, small}]
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
	return WorldData.frame_point(f, x, y - 1.6)


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

func _place(root: Node3D, f: Dictionary, model: String, x: float, y: float, rot: float, scale: float) -> MeshInstance3D:
	var lib := ModelLibrary.get_model(model)
	if lib.is_empty():
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = lib["mesh"]
	var aabb: AABB = lib["aabb"]
	var basis := WorldData.frame_basis(f, rot, scale)
	var offset := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	mi.transform = Transform3D(basis, WorldData.frame_point(f, x, y) - basis * offset)
	root.add_child(mi)
	return mi


func _box(body: StaticBody3D, f: Dictionary, x: float, y: float, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(WorldData.frame_basis(f, 0.0), WorldData.frame_point(f, x, y) + (f["center"] as Vector3) * size.y * 0.5)
	body.add_child(cs)


func _build(a: Dictionary) -> void:
	HitchLog.note("aeroporto montado: %s" % a.get("country", "?"))
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
	var small := bool(a.get("small", false))
	var npcs: Array = []
	# Balcão (barraquinha vermelha) virado para quem chega, com o atendente atrás.
	var face := Vector2(x, y).angle() + PI * 0.5 if small else 0.0
	_place(root, f, COUNTER, x, y, face, 1.5)
	_box(body, f, x, y, Vector3(1.4, 1.2, 1.0))
	_sign(root, f, x, y, 2.4, str(a["name"]))
	if small:
		# Balcão compartilhado: atendente e lojista lado a lado, atrás do balcão.
		var inward := -Vector2(x, y).normalized()
		var side := Vector2(-inward.y, inward.x)
		var back := Vector2(x, y) - inward * 0.8
		npcs.append(_npc(root, f, a, "attendant", back + side * 0.45, Vector2(x, y) + inward))
		npcs.append(_npc(root, f, a, "shopkeeper", back - side * 0.45, Vector2(x, y) + inward))
		_windsock(root, f, x + 1.6 * cos(face), y + 1.6 * sin(face), 1.4)
		root.set_meta("npcs", npcs.filter(func(n: Variant) -> bool: return n != null))
		return
	npcs.append(_npc(root, f, a, "attendant", Vector2(0.0, 2.25), Vector2(0.0, -1.0)))
	_terminal(root, body, f, str(a.get("city", "")))
	_tower(root, body, f, 6.6, 6.4)
	# Pista de pedra (leste-oeste): faixa no meio, faixas de cabeceira e luzinhas nas bordas.
	for i in 8:
		_place(root, f, ROAD, -7.0 + i * 2.0, -4.6, 0.0, 2.0)
	var white := _mat("white", Color("fffaf0"))
	var lamp := _mesh_lamp()
	for i in 7:
		var px := -6.0 + i * 2.0
		_flat(root, f, px, -4.6, Vector3(0.9, 0.02, 0.14), white, 0.03)
		for sd in [-1.0, 1.0]:
			var l := MeshInstance3D.new()
			l.mesh = lamp
			l.position = WorldData.frame_point(f, px, -4.6 + sd * 1.15) + (f["center"] as Vector3) * 0.08
			root.add_child(l)
	for end in [-7.4, 7.4]:
		for k in 4:
			_flat(root, f, end, -5.1 + k * 0.33, Vector3(0.6, 0.02, 0.16), white, 0.03)
	# Avião parado na cabeceira oeste, apontando para o leste.
	var plane := MeshInstance3D.new()
	plane.mesh = PlaneModel.mesh()
	plane.transform = Transform3D(WorldData.frame_basis(f, -PI * 0.5, 0.8), WorldData.frame_point(f, -3.6, -4.6) + (f["center"] as Vector3) * 0.42)
	root.add_child(plane)
	_box(body, f, -3.6, -4.6, Vector3(3.0, 1.2, 1.0))
	# Portão de embarque, entre o terminal e a pista.
	_gate(root, f, 3.4, 1.9)
	# Veículos de pátio do Car Kit, cones e o carrinho de malas.
	_place_len(root, f, VAN, 5.4, -2.2, 0.5, 1.7)
	_place_len(root, f, TRUCK, -6.4, -2.4, -0.4, 1.7)
	_place_len(root, f, DELIVERY, 7.6, 2.6, PI * 0.5, 2.0)
	for c in [Vector2(4.2, -2.9), Vector2(4.8, -3.1), Vector2(-5.2, -3.0)]:
		_place_len(root, f, CONE, c.x, c.y, 0.0, 0.35)
	_place(root, f, CART, -2.6, 1.0, 0.3, 1.2)
	_windsock(root, f, 7.6, -2.0, 2.2)
	# Loja da praça: barraca verde com bandeira, o lojista atrás, banquinhos na frente.
	_place(root, f, SHOP, SHOP_POINT.x, SHOP_POINT.y, 0.0, 1.5)
	_box(body, f, SHOP_POINT.x, SHOP_POINT.y, Vector3(1.6, 1.2, 1.2))
	_sign(root, f, SHOP_POINT.x, SHOP_POINT.y, 2.5, "Loja")
	_place(root, f, BANNER, SHOP_POINT.x - 1.4, SHOP_POINT.y + 0.3, 0.0, 1.5)
	npcs.append(_npc(root, f, a, "shopkeeper", SHOP_POINT + Vector2(0.0, 0.9), SHOP_POINT + Vector2(0.0, -2.0)))
	_place(root, f, BENCH, SHOP_POINT.x + 0.2, SHOP_POINT.y - 2.2, 0.0, 1.3)
	# Ponto de encontro: a fonte, com a guia ao lado e lampiões.
	_place(root, f, FOUNTAIN, 5.0, 1.8, 0.0, 1.0)
	_box(body, f, 5.0, 1.8, Vector3(2.4, 0.6, 2.4))
	npcs.append(_npc(root, f, a, "guide", Vector2(3.3, 0.9), Vector2(3.3, -2.0)))
	_place(root, f, LANTERN, 2.6, 0.6, 0.0, 1.2)
	_place(root, f, LANTERN, -3.6, 2.6, 0.0, 1.2)
	root.set_meta("npcs", npcs.filter(func(n: Variant) -> bool: return n != null))


## NPC de um papel num ponto da praça, olhando para `look`.
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


func _mat(key: String, c: Color, glass := false) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		if glass:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.08
			m.metallic_specular = 0.9
		_mats[key] = m
	return _mats[key]


## Caixa no plano da célula: centro (x, y), base `lift` acima do chão.
func _flat(root: Node3D, f: Dictionary, x: float, y: float, size: Vector3, m: Material, lift := 0.0) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = BorderLines._baked(b, m)
	mi.transform = Transform3D(WorldData.frame_basis(f, 0.0), WorldData.frame_point(f, x, y) + (f["center"] as Vector3) * (lift + size.y * 0.5))
	root.add_child(mi)
	return mi


func _mesh_lamp() -> Mesh:
	if not _mats.has("lamp_mesh"):
		var lamp := SphereMesh.new()
		lamp.radius = 0.08
		lamp.height = 0.16
		lamp.radial_segments = 8
		lamp.rings = 4
		var yellow := StandardMaterial3D.new()
		yellow.albedo_color = Color("ffd45a")
		yellow.emission_enabled = true
		yellow.emission = Color("ffb84a")
		yellow.emission_energy_multiplier = 0.6
		_mats["lamp_mesh"] = BorderLines._baked(lamp, yellow)
	return _mats["lamp_mesh"]


## Terminal: paredes creme, vidraça azulada na frente (para a pista), telhado rosado com
## beiral, letreiro. Fica transparente na frente da câmera (como as casas).
func _terminal(root: Node3D, body: StaticBody3D, f: Dictionary, city: String) -> void:
	var cream := _mat("cream", Color("f6ead2"))
	var glass := _mat("glass", Color(0.62, 0.84, 0.96, 0.45), true)
	var roof := _mat("roof", Color("e98aa8"))
	var trim := _mat("trim", Color("c99a6b"))
	var cx := 0.0
	var cy := 5.0
	var walls := _flat(root, f, cx, cy + 0.4, Vector3(7.0, 2.4, 2.2), cream)
	_flat(root, f, cx, cy - 0.85, Vector3(6.6, 2.1, 0.12), glass, 0.15)
	for k in 5:
		_flat(root, f, -3.2 + k * 1.6, cy - 0.9, Vector3(0.14, 2.3, 0.18), trim)
	_flat(root, f, cx, cy, Vector3(7.6, 0.25, 3.4), roof, 2.4)
	_flat(root, f, cx, cy - 0.95, Vector3(1.4, 0.12, 0.9), roof, 1.9)  # marquise da porta
	_sign(root, f, cx, cy - 1.2, 3.0, "Aeroporto" if city.is_empty() else "Aeroporto de " + city)
	_box(body, f, cx, cy, Vector3(7.0, 2.6, 3.0))
	var center := WorldData.frame_point(f, cx, cy) + (f["center"] as Vector3) * 1.5
	root.set_meta("occluders", [{"mi": walls, "xf": Transform3D(WorldData.frame_basis(f, 0.0), center), "half": Vector3(3.8, 1.6, 1.8)}])


## Torre de controle: base, haste, cabine de vidro octogonal, teto e antena com luz vermelha.
func _tower(root: Node3D, body: StaticBody3D, f: Dictionary, x: float, y: float) -> void:
	var up: Vector3 = f["center"]
	var base := WorldData.frame_point(f, x, y)
	var cream := _mat("cream", Color("f6ead2"))
	var glass := _mat("glass", Color(0.62, 0.84, 0.96, 0.45), true)
	var roof := _mat("roof", Color("e98aa8"))
	var red := _mat("red_light", Color("ff5a5a"))
	var parts := [
		[0.0, 1.0, 0.75, 0.9, cream], [1.0, 2.6, 0.38, 0.45, cream], [3.6, 0.15, 0.95, 0.95, cream],
		[3.75, 0.8, 0.9, 0.9, glass], [4.55, 0.35, 0.2, 1.05, roof], [4.9, 0.6, 0.03, 0.03, cream]]
	for p: Array in parts:
		var c := CylinderMesh.new()
		c.top_radius = p[2]
		c.bottom_radius = p[3]
		c.height = p[1]
		c.radial_segments = 8
		var mi := MeshInstance3D.new()
		mi.mesh = BorderLines._baked(c, p[4])
		mi.transform = Transform3D(WorldData.frame_basis(f, 0.0), base + up * (float(p[0]) + float(p[1]) * 0.5))
		root.add_child(mi)
	var light := SphereMesh.new()
	light.radius = 0.08
	light.height = 0.16
	var lm := MeshInstance3D.new()
	lm.mesh = BorderLines._baked(light, red)
	lm.position = base + up * 5.55
	root.add_child(lm)
	_box(body, f, x, y, Vector3(1.6, 4.6, 1.6))


## Portão de embarque: dois postes, uma viga com telhadinho e a plaquinha.
func _gate(root: Node3D, f: Dictionary, x: float, y: float) -> void:
	var trim := _mat("trim", Color("c99a6b"))
	var roof := _mat("roof", Color("e98aa8"))
	_flat(root, f, x - 0.7, y, Vector3(0.14, 1.9, 0.14), trim)
	_flat(root, f, x + 0.7, y, Vector3(0.14, 1.9, 0.14), trim)
	_flat(root, f, x, y, Vector3(1.8, 0.16, 0.5), roof, 1.9)
	_sign(root, f, x, y, 2.4, "Embarque")


## Modelo com `length` de comprimento (o maior lado no chão), para os veículos.
func _place_len(root: Node3D, f: Dictionary, model: String, x: float, y: float, rot: float, length: float) -> void:
	var lib := ModelLibrary.get_cached(model)
	if lib.is_empty():
		return
	var aabb: AABB = lib["aabb"]
	_place(root, f, model, x, y, rot, length / maxf(maxf(aabb.size.x, aabb.size.z), 0.01))


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
func _windsock(root: Node3D, f: Dictionary, x: float, y: float, height: float) -> void:
	var up: Vector3 = f["center"]
	var base := WorldData.frame_point(f, x, y)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.04
	pole.bottom_radius = 0.05
	pole.height = height
	pole.radial_segments = 8
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("f4f1ea")
	pole.material = pm
	var p := MeshInstance3D.new()
	p.mesh = pole
	p.transform = Transform3D(WorldData.frame_basis(f, 0.0), base + up * height * 0.5)
	root.add_child(p)
	var east: Vector3 = f["east"]
	for k in 3:
		var seg := CylinderMesh.new()
		seg.top_radius = 0.17 - k * 0.035
		seg.bottom_radius = 0.2 - k * 0.035
		seg.height = 0.32
		seg.radial_segments = 10
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("f08a3c") if k % 2 == 0 else Color("fffaf0")
		seg.material = m
		var s := MeshInstance3D.new()
		s.mesh = seg
		# Cilindro deitado na direção leste, um pouco caído (o eixo do cilindro é o Y local).
		var axis := east.rotated(f["north"], 0.25)
		var bx := up.cross(axis).normalized()
		var b := Basis(bx, axis, bx.cross(axis))
		s.transform = Transform3D(b, base + up * (height - 0.12) + axis * (0.2 + k * 0.32))
		root.add_child(s)


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
