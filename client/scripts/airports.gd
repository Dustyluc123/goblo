class_name Airports
extends Node3D
## Aeroportos (fase 2.5, ADR 0035). A lista vem do servidor (GET /airports): um por país,
## no hexágono mais perto da capital, que fica só para o aeroporto. Países pequenos ganham
## só um ponto de chegada (balcão na beirada do hexágono).
##
## O cenário é montado com peças que o jogo já carrega (Fantasy Town Kit): a casa grande
## como terminal, a barraquinha vermelha como balcão (E abre as viagens), uma pista de
## pedra com luzinhas, carrinho de malas e uma biruta feita em código. Só os aeroportos
## perto do personagem são montados. Na visão afastada, um aviãozinho marca cada aeroporto.

const BUILD_RADIUS := 130.0
const FREE_RADIUS := 170.0
const UPDATE_EVERY := 0.5
const COUNTER_REACH := 2.0
const TERMINAL := "res://scenes/houses/house_level_3.tscn"
const COUNTER := "res://assets/kenney/fantasy-town-kit/stall-red.glb"
const ROAD := "res://assets/kenney/fantasy-town-kit/road.glb"
const CART := "res://assets/kenney/fantasy-town-kit/cart.glb"
const LANTERN := "res://assets/kenney/fantasy-town-kit/lantern.glb"
## Peças que precisam estar carregadas antes do jogo começar.
const MODELS := [TERMINAL, COUNTER, ROAD, CART, LANTERN]

var world: WorldData
var data: ChunkData
## [{country, country_name, name, city, cell, lat, lon, x, y, small}]
var list: Array = []
var by_country := {}
var _built := {}  # célula → Node3D
var _timer := 0.0
## Aviõezinhos da visão afastada: um MultiMesh só (antes, um Sprite3D por aeroporto: 200
## draw calls a mais no globo).
var _markers: MultiMeshInstance3D
var _marker_mat: StandardMaterial3D
var _plane_tex: ImageTexture


func setup(w: WorldData, d: ChunkData, airports: Array) -> void:
	world = w
	data = d
	list = airports
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
	# Balcão (barraquinha vermelha) virado para quem chega.
	var face := Vector2(x, y).angle() + PI * 0.5 if small else 0.0
	_place(root, f, COUNTER, x, y, face, 1.5)
	_box(body, f, x, y, Vector3(1.4, 1.2, 1.0))
	_sign(root, f, x, y, 2.4, str(a["name"]))
	if small:
		_windsock(root, f, x + 1.6 * cos(face), y + 1.6 * sin(face), 1.4)
		return
	# Terminal: a casa grande, com a porta para a pista (sul). Fica transparente quando
	# está entre a câmera e o personagem, como as casas dos lotes.
	var terminal := _place(root, f, TERMINAL, 0.0, 4.3, 0.0, 1.0)
	_box(body, f, 0.0, 4.3, Vector3(4.6, 3.2, 4.6))
	if terminal:
		var center := WorldData.frame_point(f, 0.0, 4.3) + (f["center"] as Vector3) * 2.2
		root.set_meta("occluders", [{"mi": terminal, "xf": Transform3D(WorldData.frame_basis(f, 0.0), center), "half": Vector3(2.7, 2.4, 2.7)}])
	# Pista de pedra (leste-oeste) com faixa no meio e luzinhas nas bordas.
	for i in 7:
		var px := -6.0 + i * 2.0
		_place(root, f, ROAD, px, -4.6, 0.0, 2.0)
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.9, 0.02, 0.14)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("fffaf0")
	stripe.material = white
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
	lamp.material = yellow
	for i in 7:
		var px := -6.0 + i * 2.0
		var s := MeshInstance3D.new()
		s.mesh = stripe
		s.transform = Transform3D(WorldData.frame_basis(f, 0.0), WorldData.frame_point(f, px, -4.6) + (f["center"] as Vector3) * 0.03)
		root.add_child(s)
		for side in [-1.0, 1.0]:
			var l := MeshInstance3D.new()
			l.mesh = lamp
			l.position = WorldData.frame_point(f, px, -4.6 + side * 1.15) + (f["center"] as Vector3) * 0.08
			root.add_child(l)
	_place(root, f, CART, -2.8, 1.3, 0.3, 1.2)
	_place(root, f, LANTERN, 3.0, 1.2, 0.0, 1.2)
	_place(root, f, LANTERN, -3.6, 2.6, 0.0, 1.2)
	_windsock(root, f, 6.2, -1.8, 2.2)


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
