class_name CaveWorld
extends Node3D
## Uma caverna desenhada (fase 4.5, ADR 0056). O servidor manda o desenho (salões, túneis,
## alturas, minérios, enfeites); aqui o chão vira uma grade de quadradinhos (cada um plano na
## altura do lugar, com degraus de pé quando a altura muda e paredes onde a caverna acaba),
## com os cantos tremidos de leve pela posição (cara de pedra, igual para todos). Malha e
## colisão são montadas numa thread.
##
## O nó fica no sistema de coordenadas da caverna: x = East, y = Up, z = −North (a caverna
## usa North para o "z"; o Godot quer uma base com o mesmo sentido de giro).

signal built

const ROCK := Color("5d5751")
const ROCK_LIGHT := Color("766f68")
const WALL := Color("4a4540")
const WALL_TOP := Color("2c2926")
const GLOW_SHADER := preload("res://shaders/cave_glow.gdshader")

var layout := {}
var ores := {}  # id → {"node", "ore": {...}}
var glows: Array = []  # {"kind", "pos"}
var exit_point := Vector3.ZERO
var start_point := Vector3.ZERO
var furnace_point := Vector3.ZERO
var boss_point := Vector3.ZERO
var boss_room := {}
var boss: Node3D
var boss_ap: AnimationPlayer
var lights: Array = []  # OmniLight3D dos salões, da saída e da fornalha
var _task := -1
var _out := {}
static var _glow_mat: ShaderMaterial
static var _rock_mat: StandardMaterial3D


static func glow_material() -> ShaderMaterial:
	if _glow_mat == null:
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = GLOW_SHADER
	return _glow_mat


static func rock_material() -> StandardMaterial3D:
	if _rock_mat == null:
		_rock_mat = StandardMaterial3D.new()
		_rock_mat.vertex_color_use_as_albedo = true
		_rock_mat.roughness = 1.0
		_rock_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_rock_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _rock_mat


## Ponto da caverna (x, altura, z do servidor) no espaço deste nó.
static func local(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, -z)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Monta a caverna (espera a thread). `l` é o layout do servidor.
func build(l: Dictionary) -> void:
	layout = l
	var fr: Dictionary = l["frame"]
	var east := _v(fr["east"])
	var up := _v(fr["up"])
	var north := _v(fr["north"])
	transform = Transform3D(Basis(east, up, -north), _v(fr["origin"]))
	var job := {"layout": l}
	_task = WorkerThreadPool.add_task(func() -> void: _out = _mesh(job))
	while not WorkerThreadPool.is_task_completed(_task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var t0 := Time.get_ticks_usec()
	var mi := MeshInstance3D.new()
	mi.mesh = _out["mesh"]
	mi.material_override = rock_material()
	add_child(mi)
	var body := StaticBody3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(_out["faces"])
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	HitchLog.note("caverna: malha e colisão", (Time.get_ticks_usec() - t0) / 1000.0)
	_place_things(l)
	built.emit()


static func _v(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


# --- Chão e paredes (thread) ----------------------------------------------------------------

## Altura do chão em (x, z) do servidor (a mesma conta de CaveLayout.FloorAt no Go).
static func floor_at(l: Dictionary, x: float, z: float) -> Variant:
	var best := -INF
	var inside := false
	for rm: Dictionary in l["rooms"]:
		if Vector2(x - float(rm["x"]), z - float(rm["z"])).length() <= float(rm["r"]):
			best = maxf(best, float(rm["y"]))
			inside = true
	if inside:
		return best
	for t: Dictionary in l["tunnels"]:
		var a: Dictionary = l["rooms"][int(t["a"])]
		var b: Dictionary = l["rooms"][int(t["b"])]
		var pa := Vector2(float(a["x"]), float(a["z"]))
		var pb := Vector2(float(b["x"]), float(b["z"]))
		var p := Vector2(x, z)
		var d := pb - pa
		var ln := d.length()
		var tt := clampf((p - pa).dot(d) / (ln * ln), 0.0, 1.0)
		if p.distance_to(pa + d * tt) > float(t["w"]) * 0.5:
			continue
		var tr := (p - pa).dot(d) / (ln * ln)
		var ta := float(a["r"]) / ln
		var tb := 1.0 - float(b["r"]) / ln
		var u := clampf((tr - ta) / maxf(1e-6, tb - ta), 0.0, 1.0)
		var y := lerpf(float(a["y"]), float(b["y"]), u)
		if bool(t.get("ledge", false)):
			y = float(a["y"]) if u < 0.5 else float(b["y"])
		best = maxf(best, y)
		inside = true
	return best if inside else null


## Tremido determinístico de um canto da grade (cara de pedra).
static func _jitter(i: int, j: int) -> Vector2:
	var h := hash(Vector2i(i, j))
	return Vector2(float(h & 1023) / 1023.0 - 0.5, float((h >> 10) & 1023) / 1023.0 - 0.5) * 0.5


static func _mesh(job: Dictionary) -> Dictionary:
	var l: Dictionary = job["layout"]
	var g := float(l["grid"])
	var b: Array = l["bounds"]
	var x0 := float(b[0])
	var z0 := float(b[1])
	var nx := int(ceil((float(b[2]) - x0) / g))
	var nz := int(ceil((float(b[3]) - z0) / g))
	var wall_h := float(l["wall"])
	# Altura de cada quadradinho (centro) ou nulo fora da caverna.
	var h := []
	h.resize(nx * nz)
	for i in nx:
		for j in nz:
			h[i * nz + j] = floor_at(l, x0 + (i + 0.5) * g, z0 + (j + 0.5) * g)
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var faces := PackedVector3Array()
	var corner := func(i: int, j: int, y: float) -> Vector3:
		var jt := _jitter(i, j)
		return local(x0 + (i + jt.x) * g, y, z0 + (j + jt.y) * g)
	# Quadrilátero a, b, c, d em volta, com a normal dada (o material desenha os dois lados).
	var quad := func(a: Vector3, bq: Vector3, cq: Vector3, d: Vector3, col: Color, col_top: Color, nn: Vector3) -> void:
		for tri: Array in [[a, bq, cq], [a, cq, d]]:
			for q: Vector3 in tri:
				v.append(q)
				n.append(nn)
				c.append(col_top if q.y > minf(a.y, cq.y) + 0.01 and col_top != col else col)
				faces.append(q)
	for i in nx:
		for j in nz:
			var hv: Variant = h[i * nz + j]
			if hv == null:
				continue
			var y: float = hv
			# Chão: cor de pedra com um pouco de variação.
			var k := float(hash(Vector2i(i * 7, j * 13)) & 255) / 255.0
			var col := ROCK.lerp(ROCK_LIGHT, k * 0.6)
			quad.call(corner.call(i, j, y), corner.call(i + 1, j, y), corner.call(i + 1, j + 1, y), corner.call(i, j + 1, y), col, col, Vector3.UP)
			# Os quatro lados: parede (fora da caverna) ou degrau (vizinho mais baixo).
			for side in 4:
				var di: int = [1, 0, -1, 0][side]
				var dj: int = [0, 1, 0, -1][side]
				var ni: int = i + di
				var nj: int = j + dj
				var other: Variant = null
				if ni >= 0 and nj >= 0 and ni < nx and nj < nz:
					other = h[ni * nz + nj]
				# Os dois cantos da aresta, em ordem.
				var ca: Vector2i
				var cb: Vector2i
				match side:
					0:
						ca = Vector2i(i + 1, j + 1)
						cb = Vector2i(i + 1, j)
					1:
						ca = Vector2i(i, j + 1)
						cb = Vector2i(i + 1, j + 1)
					2:
						ca = Vector2i(i, j)
						cb = Vector2i(i, j + 1)
					3:
						ca = Vector2i(i + 1, j)
						cb = Vector2i(i, j)
				if other == null:
					var top := y + wall_h
					quad.call(corner.call(ca.x, ca.y, y - 0.3), corner.call(cb.x, cb.y, y - 0.3),
						corner.call(cb.x, cb.y, top), corner.call(ca.x, ca.y, top), WALL, WALL_TOP, Vector3(-di, 0, dj))
				elif float(other) < y - 0.01:
					var low := float(other)
					quad.call(corner.call(ca.x, ca.y, low), corner.call(cb.x, cb.y, low),
						corner.call(cb.x, cb.y, y), corner.call(ca.x, ca.y, y), WALL.lerp(ROCK, 0.5), ROCK, Vector3(di, 0, -dj))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return {"mesh": mesh, "faces": faces}


# --- Coisas da caverna ----------------------------------------------------------------------

func _place_things(l: Dictionary) -> void:
	var st: Array = l["start"]
	var ex: Array = l["exit"]
	var fu: Array = l["furnace"]
	var bo: Array = l["boss"]
	start_point = to_global(local(float(st[0]), float(st[1]), float(st[2])))
	exit_point = to_global(local(float(ex[0]), float(ex[1]), float(ex[2])))
	furnace_point = to_global(local(float(fu[0]), float(fu[1]), float(fu[2])))
	boss_point = to_global(local(float(bo[0]), float(bo[1]), float(bo[2])))
	# Minérios.
	for o: Dictionary in l["ores"]:
		var node := Node3D.new()
		add_child(node)
		node.position = local(float(o["x"]), float(o["y"]), float(o["z"]))
		node.rotation.y = float(o["yaw"])
		var mi := MeshInstance3D.new()
		mi.mesh = ModelLibrary.get_model("primitive:ore_" + str(o["ore"]))["mesh"]
		node.add_child(mi)
		if bool(o.get("glow", false)):
			var cr := MeshInstance3D.new()
			cr.mesh = ModelLibrary.get_model("primitive:" + str(o["item"]))["mesh"]
			cr.material_override = glow_material()
			cr.scale = Vector3.ONE * 2.6
			cr.position = Vector3(0, 0.55, 0)
			node.add_child(cr)
		ores[int(o["id"])] = {"node": node, "ore": o}
	# Cogumelos e cristais que brilham.
	for gl: Dictionary in l["glow"]:
		var mi := MeshInstance3D.new()
		mi.mesh = ModelLibrary.get_model("primitive:" + str(gl["kind"]))["mesh"]
		mi.material_override = glow_material()
		mi.position = local(float(gl["x"]), float(gl["y"]), float(gl["z"]))
		mi.rotation.y = float(gl["yaw"])
		mi.scale = Vector3.ONE * float(gl["scale"]) * (2.2 if str(gl["kind"]) == "cave_mushroom" else 1.6)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		glows.append({"kind": str(gl["kind"]), "pos": mi.global_position})
	# Saída: arco de pedra com luz do dia entrando.
	var arch := MeshInstance3D.new()
	arch.mesh = ModelLibrary.get_model("primitive:cave_mouth")["mesh"]
	arch.scale = Vector3.ONE * 0.75
	add_child(arch)
	var first: Dictionary = l["rooms"][0]
	var center := to_global(local(float(first["x"]), float(first["y"]), float(first["z"])))
	# O arco fica embutido na parede, com a abertura para dentro do salão.
	var out := exit_point - center
	arch.global_position = center + out.normalized() * (float(first["r"]) + 0.6)
	_face(arch, center)
	_light(exit_point + global_basis.y * 2.0, Color("fff1d0"), 9.0, 1.4)
	# Fornalha antiga.
	var fn := MeshInstance3D.new()
	fn.mesh = ModelLibrary.get_model("primitive:furnace")["mesh"]
	fn.scale = Vector3.ONE * 1.3
	add_child(fn)
	fn.global_position = furnace_point
	_face(fn, center)
	_light(furnace_point + global_basis.y * 1.0, Color("ff9a4a"), 6.0, 1.2)
	# Luz suave em cada salão (só as mais perto ficam acesas: CaveGame).
	for rm: Dictionary in l["rooms"]:
		var p := to_global(local(float(rm["x"]), float(rm["y"]) + 4.0, float(rm["z"])))
		var col := Color("8fa7ff") if float(rm["depth"]) > 0.5 else Color("a8c4ff")
		if bool(rm.get("boss", false)):
			col = Color("ffb8dc")
			boss_room = rm
		_light(p, col, float(rm["r"]) * 1.4, 0.55)
	# O golem.
	boss = CreatureModels.instance("cave_golem")
	var h := maxf(Player._model_height(boss), 0.01)
	boss.scale = Vector3.ONE * (3.4 / h)
	add_child(boss)
	boss.global_position = boss_point
	_face(boss, start_point)
	boss_ap = boss.find_child("AnimationPlayer") as AnimationPlayer
	if boss_ap:
		boss_ap.play("Sleep")


func _face(n: Node3D, target: Vector3) -> void:
	var up := global_basis.y.normalized()
	var to := target - n.global_position
	to -= up * to.dot(up)
	if to.length() < 0.01:
		return
	n.global_basis = Basis.looking_at(-to.normalized(), up).scaled(n.scale)


func _light(at: Vector3, col: Color, rng: float, energy: float) -> OmniLight3D:
	var li := OmniLight3D.new()
	li.light_color = col
	li.omni_range = rng
	li.light_energy = energy
	li.shadow_enabled = false
	add_child(li)
	li.global_position = at
	lights.append(li)
	return li


## Esconde o minério quebrado hoje (ou mostra de novo).
func set_ore_mined(id: int, mined: bool) -> void:
	if not ores.has(id):
		return
	var node: Node3D = ores[id]["node"]
	node.visible = not mined
